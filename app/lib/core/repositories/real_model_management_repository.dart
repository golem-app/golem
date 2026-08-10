import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/model_catalog.dart';
import '../domain/models.dart';
import '../services/artifact_downloader.dart';
import '../services/device_storage.dart';
import 'contracts.dart';
import 'persistence_io.dart';

/// Real Hugging Face downloads: pinned repository + revision URLs, per-file
/// SHA-256 verification, skip-if-valid, disk-space preflight. Artifacts install
/// under `<documents>/models/<key>/` so the `documents:` model-path flow loads
/// them unchanged. Verification is receipt-backed: a file that passes its
/// SHA-256 gets an entry in a `.golem-verified.json` beside the install, and
/// only size + receipt count as verified on a fast path — a size-matching file
/// without one (sideload, interrupted verify) is hashed before it is trusted.
final class RealModelManagementRepository implements ModelManagementRepository {
  RealModelManagementRepository({
    required this.stateFile,
    required this.documentsDirectory,
    required List<ModelCatalogEntry> catalog,
    required this.downloader,
    required this.diskSpace,
    required this.backupExclusion,
    this.activeArtifactKey,
    this.diskSpaceMargin = 500 * 1024 * 1024,
  }) : catalog = [...catalog] {
    _state = ModelState(activeArtifactKey: activeArtifactKey);
  }

  final File stateFile;
  final String documentsDirectory;

  /// The composition root passes the pinned `modelCatalog`, a shared top-level
  /// list also handed to `modelCatalogEntriesProvider`; growing it in place
  /// would leak custom entries into the pinned set, so [addModel] copies it.
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
    // Serialized atomic writes: a kill mid-write must not truncate the file.
    final write = _writes.then(
      (_) => writeStore(
        stateFile,
        jsonEncode(value.toJson()),
        what: 'model state',
      ),
    );
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
    final raw = await readStore(stateFile, what: 'model state');
    if (raw != null) {
      var loaded = const ModelState();
      try {
        loaded = ModelState.fromJson(
          Map<String, Object?>.from(jsonDecode(raw) as Map),
        );
      } catch (_) {
        // Only pure decode/parse can throw here — corruption by definition.
        await quarantineStore(stateFile, what: 'model state');
      }
      _state = loaded.stamp(
        activeArtifactKey: activeArtifactKey,
        simulated: false,
      );
    }
    // Since #19 the loaded phase is a claim about the engine, and no engine
    // survives its process. Failed stays — still accurate across a relaunch.
    if (_state.runtime == RuntimePhase.loading ||
        _state.runtime == RuntimePhase.loaded) {
      _state = _state.copyWith(runtime: RuntimePhase.unloaded);
    }
    // Disk is truth: persisted phases are reconciled against the files present,
    // so a kill mid-download resumes from real bytes and an externally removed
    // install stops claiming to exist. "Installed" also needs the receipt to
    // cover every file — size alone never re-earns it.
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

  /// Present by size — a progress hint for the paused card, not a verdict.
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
      if (!_receiptCovers(receipt, spec) || !await _sizeMatches(entry, spec)) {
        return false;
      }
    }
    return true;
  }

  /// Whether [receipt] already accounts for [spec] — the only fast path that
  /// counts as verified without re-hashing gigabytes on every launch. A pinned
  /// file must match the publisher's hash; one published without a hash is
  /// covered by *any* recorded digest, since the receipt is scoped to the
  /// entry's revision. Absent means unverified — not the same as a recorded
  /// null, which an equality check would conflate.
  bool _receiptCovers(Map<String, String> receipt, ModelArtifactFile spec) {
    final recorded = receipt[spec.path];
    if (recorded == null) return false;
    final expected = spec.sha256;
    return expected == null || recorded == expected;
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
      if (sized && _receiptCovers(receipt, spec)) {
        verifiedBytes += spec.bytes;
      } else {
        if (sized) presentUnverifiedBytes += spec.bytes;
        pending.add(spec);
      }
    }

    // Size-matching unreceipted files will most likely verify in place, so they
    // do not count against free space; a corrupt one fails cleanly later.
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
      // Local content first: a size-matching file without a receipt entry is
      // hashed before any network use, then verifies in place or is re-fetched.
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
        final digest = await _acceptableDigest(entry, spec);
        if (digest != null) {
          await _recordVerified(entry, spec, digest);
          verifiedBytes += spec.bytes;
          if (_stopRequested.contains(artifactKey)) return;
          continue;
        }
        await File('${_rootFor(entry)}/${spec.path}').delete();
      }

      final url = entry.resolveUrlFor(spec).toString();
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
          // A user pause already persisted out of band; an uncommanded one
          // (network loss, OS timeout) must be persisted here or the card
          // freezes on "downloading".
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
            // The OS discarded the partial; pause at the verified bytes.
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
      final sized = await _sizeMatches(entry, spec);
      final digest = sized ? await _acceptableDigest(entry, spec) : null;
      if (digest == null) {
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
              // A wrong length and wrong content are different facts, and a
              // file published without a hash can only fail the first.
              failure: sized
                  ? '${spec.path} failed SHA-256 verification.'
                  : '${spec.path} did not arrive at its expected size.',
            ),
          ),
        );
        return;
      }
      await _recordVerified(entry, spec, digest);
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

  /// Null when a pinned hash was published and these bytes do not match it. A
  /// digest rather than a bool so an unhashed file is receipted by content.
  Future<String?> _acceptableDigest(
    ModelCatalogEntry entry,
    ModelArtifactFile spec,
  ) async {
    final file = File('${_rootFor(entry)}/${spec.path}');
    final digest = (await sha256.bind(file.openRead()).first).toString();
    final expected = spec.sha256;
    if (expected != null && digest != expected) return null;
    return digest;
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
    String digest,
  ) async {
    final receipt = await _readReceipt(entry);
    receipt[spec.path] = digest;
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
    // A probe failure must not block downloads; the downloader fails cleanly if
    // the disk actually fills.
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
    // Stop the download first, or bytes land in the directory just removed.
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
    ModelCatalogEntry? previous;
    for (final item in catalog) {
      if (item.key == entry.key) previous = item;
    }
    catalog.removeWhere((item) => item.key == entry.key);
    catalog.add(entry);

    // Re-pasting the same artifact keeps its progress and partial download.
    if (previous != null && previous.revision == entry.revision) {
      return _state;
    }

    // Otherwise the entry is new or now pins a different commit, so its phase
    // is reconciled against disk as load() does — receipts are scoped by
    // revision, and the same bytes under a new commit are unproven.
    if (await _installVerified(entry)) {
      return _persist(
        _state.withArtifact(
          entry.key,
          ArtifactStatus(
            phase: ArtifactPhase.installed,
            downloadedBytes: entry.totalBytes,
          ),
        ),
      );
    }
    return _persist(_state.withArtifact(entry.key, const ArtifactStatus()));
  }
}

String _gigabytes(int bytes) => '${(bytes / 1000000000).toStringAsFixed(2)} GB';
