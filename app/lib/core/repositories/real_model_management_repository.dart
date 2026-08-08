import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/model_catalog.dart';
import '../domain/models.dart';
import '../services/artifact_downloader.dart';
import '../services/device_storage.dart';
import 'contracts.dart';

/// Real Hugging Face downloads with the fetch-tool discipline: pinned
/// repository + revision URLs, per-file SHA-256 verification, skip-if-valid,
/// and disk-space preflight. Artifacts install under
/// `<documents>/models/<key>/` so the `documents:` model-path flow loads
/// them unchanged. Operational failures surface as failed-phase snapshots,
/// never as thrown errors.
///
/// Verification is receipt-backed: every file that passes its SHA-256 gets
/// an entry in a `.golem-verified.json` receipt beside the install, and only
/// size + receipt together count as verified on any fast path. A
/// size-matching file without a receipt entry (a cable-push sideload, or a
/// download whose verify was interrupted) is hashed before it is trusted.
final class RealModelManagementRepository implements ModelManagementRepository {
  RealModelManagementRepository({
    required this.stateFile,
    required this.documentsDirectory,
    required this.catalog,
    required this.downloader,
    required this.diskSpace,
    required this.backupExclusion,
    this.activeArtifactKey,
    this.diskSpaceMargin = 500 * 1024 * 1024,
  }) {
    _state = ModelState(activeArtifactKey: activeArtifactKey);
  }

  final File stateFile;
  final String documentsDirectory;
  final List<ModelCatalogEntry> catalog;
  final ArtifactFileDownloader downloader;
  final DiskSpaceProbe diskSpace;
  final BackupExclusion backupExclusion;
  final String? activeArtifactKey;

  /// Free bytes that must remain after a download completes.
  final int diskSpaceMargin;

  late ModelState _state;
  final Set<String> _stopRequested = {};
  Future<void> _writes = Future.value();

  String _rootFor(ModelCatalogEntry entry) =>
      '$documentsDirectory/${entry.installDirectory}';

  Future<ModelState> _persist(ModelState value) async {
    _state = value;
    // Serialized atomic writes, mirroring the fake repository: a kill
    // mid-write must never leave a truncated file behind.
    final write = _writes.then((_) async {
      await stateFile.parent.create(recursive: true);
      final temporary = File('${stateFile.path}.tmp');
      await temporary.writeAsString(jsonEncode(value.toJson()), flush: true);
      await temporary.rename(stateFile.path);
    });
    _writes = write.catchError((_) {});
    await write;
    return value;
  }

  ModelCatalogEntry _entry(String artifactKey) => catalog.firstWhere(
    (entry) => entry.key == artifactKey,
    orElse: () => throw ArgumentError.value(
      artifactKey,
      'artifactKey',
      'Unknown catalog entry',
    ),
  );

  @override
  Future<ModelState> load() async {
    if (await stateFile.exists()) {
      var loaded = const ModelState();
      try {
        loaded = ModelState.fromJson(
          Map<String, Object?>.from(
            jsonDecode(await stateFile.readAsString()) as Map,
          ),
        );
      } catch (_) {
        await stateFile.rename('${stateFile.path}.corrupt');
      }
      _state = loaded.stamp(
        activeArtifactKey: activeArtifactKey,
        simulated: false,
      );
    }
    // Since #19 the loaded phase is a claim about the engine, and no
    // engine survives its process: a fresh load() always starts unloaded,
    // whatever the previous run persisted. Failed stays — the last
    // attempt's outcome remains accurate across a relaunch.
    if (_state.runtime == RuntimePhase.loading ||
        _state.runtime == RuntimePhase.loaded) {
      _state = _state.copyWith(runtime: RuntimePhase.unloaded);
    }
    // Disk is truth: persisted phases are reconciled against the files
    // actually present, so a kill mid-download resumes from real bytes and
    // an externally removed install stops claiming to exist. "Installed"
    // additionally requires the verification receipt to cover every file —
    // size alone never re-earns the verified label.
    final artifacts = <String, ArtifactStatus>{};
    for (final entry in catalog) {
      final status = _state.statusOf(entry.key);
      artifacts[entry.key] = switch (status.phase) {
        ArtifactPhase.installed when !await _installVerified(entry) =>
          const ArtifactStatus(),
        ArtifactPhase.downloading ||
        ArtifactPhase.verifying ||
        ArtifactPhase.paused => ArtifactStatus(
          phase: ArtifactPhase.paused,
          downloadedBytes: await _presentBytes(entry),
        ),
        _ => status,
      };
      if (artifacts[entry.key]!.phase == ArtifactPhase.notDownloaded) {
        artifacts[entry.key] = const ArtifactStatus();
      }
    }
    _state = _state.copyWith(artifacts: artifacts);
    return _persist(_state);
  }

  /// Bytes of this artifact's files that are fully present on disk by size —
  /// a progress hint for the paused card, not a verification verdict.
  Future<int> _presentBytes(ModelCatalogEntry entry) async {
    var bytes = 0;
    for (final spec in entry.files) {
      if (await _sizeMatches(entry, spec)) {
        bytes += spec.bytes;
      }
    }
    return bytes;
  }

  Future<bool> _installVerified(ModelCatalogEntry entry) async {
    final receipt = await _readReceipt(entry);
    for (final spec in entry.files) {
      if (receipt[spec.path] != spec.sha256 ||
          !await _sizeMatches(entry, spec)) {
        return false;
      }
    }
    return true;
  }

  @override
  Stream<ModelState> download(String artifactKey) async* {
    final entry = _entry(artifactKey);
    _stopRequested.remove(artifactKey);
    final root = Directory(_rootFor(entry));
    await root.create(recursive: true);
    // Idempotent; re-fetchable artifacts must never reach iCloud backups.
    await backupExclusion.exclude('$documentsDirectory/models');

    final receipt = await _readReceipt(entry);
    var verifiedBytes = 0;
    var presentUnverifiedBytes = 0;
    final pending = <ModelArtifactFile>[];
    for (final spec in entry.files) {
      final sized = await _sizeMatches(entry, spec);
      if (sized && receipt[spec.path] == spec.sha256) {
        verifiedBytes += spec.bytes;
      } else {
        if (sized) presentUnverifiedBytes += spec.bytes;
        pending.add(spec);
      }
    }

    // Size-matching unreceipted files will most likely verify in place, so
    // they do not count against free space; if one turns out corrupt on a
    // genuinely full disk, the re-download fails cleanly on its own.
    final remaining = entry.totalBytes - verifiedBytes - presentUnverifiedBytes;
    final free = await _freeBytesSafely();
    if (free != null && free < remaining + diskSpaceMargin) {
      yield await _persist(
        _state.withArtifact(
          artifactKey,
          ArtifactStatus(
            phase: ArtifactPhase.failed,
            downloadedBytes: verifiedBytes,
            failure:
                'Needs ${_gigabytes(remaining + diskSpaceMargin)} free; '
                '${_gigabytes(free)} available.',
          ),
        ),
      );
      return;
    }

    yield await _persist(
      _state.withArtifact(
        artifactKey,
        ArtifactStatus(
          phase: ArtifactPhase.downloading,
          downloadedBytes: verifiedBytes,
        ),
      ),
    );

    for (final spec in pending) {
      // Local content first: a size-matching file without a receipt entry
      // (sideload, or an interrupted verify) is hashed before any network
      // use — it either verifies in place or is deleted and re-fetched.
      if (await _sizeMatches(entry, spec)) {
        yield await _persist(
          _state.withArtifact(
            artifactKey,
            ArtifactStatus(
              phase: ArtifactPhase.verifying,
              downloadedBytes: verifiedBytes + spec.bytes,
            ),
          ),
        );
        if (await _hashMatches(entry, spec)) {
          await _recordVerified(entry, spec);
          verifiedBytes += spec.bytes;
          if (_stopRequested.contains(artifactKey)) return;
          continue;
        }
        await File('${_rootFor(entry)}/${spec.path}').delete();
      }

      final url =
          'https://huggingface.co/${entry.repository}'
          '/resolve/${entry.revision}/${spec.path}';
      ArtifactFileEvent fileOutcome = const ArtifactFileComplete();
      var lastReceived = 0;
      await for (final event in downloader.download(
        url: url,
        directory: _directoryFor(entry, spec),
        filename: _filenameFor(spec),
        expectedBytes: spec.bytes,
      )) {
        if (event is ArtifactFileProgress) {
          if (_stopRequested.contains(artifactKey)) continue;
          lastReceived = event.bytesReceived;
          yield await _persist(
            _state.withArtifact(
              artifactKey,
              ArtifactStatus(
                phase: ArtifactPhase.downloading,
                downloadedBytes: verifiedBytes + event.bytesReceived,
              ),
            ),
          );
        } else {
          fileOutcome = event;
        }
      }
      switch (fileOutcome) {
        case ArtifactFilePaused(:final userInitiated):
          // A user pause already persisted its state out of band; an
          // uncommanded one (network loss, OS timeout the plugin gave up
          // on) must be persisted here or the card freezes on
          // "downloading" forever.
          if (!userInitiated && !_stopRequested.contains(artifactKey)) {
            yield await _persist(
              _state.withArtifact(
                artifactKey,
                ArtifactStatus(
                  phase: ArtifactPhase.paused,
                  downloadedBytes: verifiedBytes + lastReceived,
                ),
              ),
            );
          }
          return;
        case ArtifactFileCanceled(:final userInitiated):
          if (!userInitiated && !_stopRequested.contains(artifactKey)) {
            // The OS discarded the partial; surface a resumable pause at
            // the bytes that remain verified on disk.
            yield await _persist(
              _state.withArtifact(
                artifactKey,
                ArtifactStatus(
                  phase: ArtifactPhase.paused,
                  downloadedBytes: verifiedBytes,
                ),
              ),
            );
          }
          return;
        case ArtifactFileFailed(:final message):
          yield await _persist(
            _state.withArtifact(
              artifactKey,
              ArtifactStatus(
                phase: ArtifactPhase.failed,
                downloadedBytes: verifiedBytes,
                failure: message,
              ),
            ),
          );
          return;
        case ArtifactFileProgress() || ArtifactFileComplete():
          break;
      }

      yield await _persist(
        _state.withArtifact(
          artifactKey,
          ArtifactStatus(
            phase: ArtifactPhase.verifying,
            downloadedBytes: verifiedBytes + spec.bytes,
          ),
        ),
      );
      if (!await _sizeMatches(entry, spec) ||
          !await _hashMatches(entry, spec)) {
        final file = File('${_rootFor(entry)}/${spec.path}');
        if (await file.exists()) {
          await file.delete();
        }
        yield await _persist(
          _state.withArtifact(
            artifactKey,
            ArtifactStatus(
              phase: ArtifactPhase.failed,
              downloadedBytes: verifiedBytes,
              failure: '${spec.path} failed SHA-256 verification.',
            ),
          ),
        );
        return;
      }
      await _recordVerified(entry, spec);
      verifiedBytes += spec.bytes;
      if (_stopRequested.contains(artifactKey)) return;
    }

    yield await _persist(
      _state.withArtifact(
        artifactKey,
        ArtifactStatus(
          phase: ArtifactPhase.installed,
          downloadedBytes: entry.totalBytes,
        ),
      ),
    );
  }

  String _directoryFor(ModelCatalogEntry entry, ModelArtifactFile spec) {
    final segments = spec.path.split('/');
    return [
      entry.installDirectory,
      ...segments.sublist(0, segments.length - 1),
    ].join('/');
  }

  String _filenameFor(ModelArtifactFile spec) => spec.path.split('/').last;

  Future<bool> _sizeMatches(
    ModelCatalogEntry entry,
    ModelArtifactFile spec,
  ) async {
    final file = File('${_rootFor(entry)}/${spec.path}');
    return await file.exists() && await file.length() == spec.bytes;
  }

  Future<bool> _hashMatches(
    ModelCatalogEntry entry,
    ModelArtifactFile spec,
  ) async {
    final file = File('${_rootFor(entry)}/${spec.path}');
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == spec.sha256;
  }

  static const _receiptName = '.golem-verified.json';

  File _receiptFile(ModelCatalogEntry entry) =>
      File('${_rootFor(entry)}/$_receiptName');

  /// path → sha256 of files this repository has hash-verified, empty when
  /// absent, unreadable, or written for a different revision.
  Future<Map<String, String>> _readReceipt(ModelCatalogEntry entry) async {
    try {
      final file = _receiptFile(entry);
      if (!await file.exists()) return {};
      final json = Map<String, Object?>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      if (json['revision'] != entry.revision) return {};
      return Map<String, String>.from(json['files'] as Map? ?? {});
    } catch (_) {
      return {};
    }
  }

  Future<void> _recordVerified(
    ModelCatalogEntry entry,
    ModelArtifactFile spec,
  ) async {
    final receipt = await _readReceipt(entry);
    receipt[spec.path] = spec.sha256;
    final file = _receiptFile(entry);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'revision': entry.revision, 'files': receipt}),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<int?> _freeBytesSafely() async {
    // A probe failure must not block downloads; the downloader itself fails
    // cleanly when the disk actually fills.
    try {
      return await diskSpace.freeBytes(documentsDirectory);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ModelState> pause(String artifactKey) async {
    _entry(artifactKey);
    _stopRequested.add(artifactKey);
    await downloader.pause();
    return _persist(
      _state.withArtifact(
        artifactKey,
        _state.statusOf(artifactKey).copyWith(phase: ArtifactPhase.paused),
      ),
    );
  }

  @override
  Future<ModelState> cancel(String artifactKey) async {
    final entry = _entry(artifactKey);
    _stopRequested.add(artifactKey);
    await downloader.cancel();
    await _deleteArtifactFiles(entry);
    return _persist(
      _withoutArtifact(
        artifactKey,
      ).withArtifact(artifactKey, const ArtifactStatus()),
    );
  }

  @override
  Future<ModelState> delete(String artifactKey) async {
    final entry = _entry(artifactKey);
    // Stop any in-flight download first, or bytes keep landing in the
    // directory that was just removed.
    _stopRequested.add(artifactKey);
    await downloader.cancel();
    await _deleteArtifactFiles(entry);
    return _persist(
      _withoutArtifact(
        artifactKey,
      ).withArtifact(artifactKey, const ArtifactStatus()),
    );
  }

  /// Removing the active artifact's weights invalidates a loaded runtime.
  ModelState _withoutArtifact(String artifactKey) =>
      artifactKey == activeArtifactKey &&
          _state.runtime != RuntimePhase.unloaded
      ? _state.copyWith(runtime: RuntimePhase.unloaded, clearFailure: true)
      : _state;

  Future<void> _deleteArtifactFiles(ModelCatalogEntry entry) async {
    final root = Directory(_rootFor(entry));
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }

  @override
  Future<ModelState> recordRuntime(RuntimePhase phase, {String? failure}) =>
      _persist(
        failure == null
            ? _state.copyWith(runtime: phase, clearFailure: true)
            : _state.copyWith(runtime: phase, failure: failure),
      );

  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async {
    // Arbitrary-repository downloads need real manifest/verification wiring
    // (#20); until then the UI keeps Add disabled on this backend and this
    // deliberately records nothing.
    return _state;
  }
}

String _gigabytes(int bytes) => '${(bytes / 1000000000).toStringAsFixed(2)} GB';
