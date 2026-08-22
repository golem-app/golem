import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../domain/byte_format.dart';
import '../domain/model_catalog.dart';
import '../domain/models.dart';
import '../services/artifact_downloader.dart';
import '../services/device_storage.dart';
import 'contracts.dart';
import 'persistence_io.dart';

/// Real Hugging Face downloads: pinned repository + revision URLs, per-file
/// SHA-256 verification as one phase after every file has arrived,
/// skip-if-valid, disk-space preflight. Artifacts install
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
    this.diskSpaceMargin = modelDownloadFreeSpaceMargin,
    this.verifyProgressStride = 8 << 20,
    this.verifyEmitInterval = const Duration(milliseconds: 250),
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

  /// Bytes hashed between two verification snapshots, each an in-memory
  /// emit; tests pass a few bytes to watch every step. See [_hashProgress]
  /// for why 8 MiB.
  final int verifyProgressStride;

  /// The least time between two verification emits; the stride is the
  /// isolate's reporting granularity, this is the UI's.
  final Duration verifyEmitInterval;

  late ModelState _state;
  final Set<String> _stopRequested = {};

  /// Artifacts a [download] generator is currently sequencing. Reconciliation
  /// leaves these alone: it cannot see inside a hash or between two files, and
  /// the generator is the more recent authority on both.
  final Set<String> _active = {};
  Future<void> _writes = Future.value();

  /// Whether the state file has been read and the engine claim normalized.
  /// Reconciliation runs again on every resume, and neither of those is
  /// repeatable: re-reading would discard newer in-memory state, and demoting
  /// the runtime a second time would unload a model that is legitimately live.
  bool _hydrated = false;

  Future<void> _reconciles = Future.value();

  /// Serializes read-modify-write of [_state]. [_persist] serializes the writes
  /// themselves, but reconciliation reads state, awaits a series of platform
  /// probes, then writes a whole map — a window long enough for a download that
  /// finishes in between to be overwritten by a snapshot taken before it did.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _reconciles.then((_) => action());
    _reconciles = result.then((_) {}, onError: (_) {});
    return result;
  }

  String _rootFor(ModelCatalogEntry entry) =>
      '$documentsDirectory/${entry.installDirectory}';

  /// Publishes [value] without a durable write, for ticks whose only change
  /// is a field the store never holds.
  ModelState _emit(ModelState value) => _state = value;

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

  /// Convergence, and safe to re-run: the composition root calls it at startup
  /// and again whenever the app returns to the foreground, which is the only
  /// moment a transfer the OS moved on without telling anyone can be noticed.
  @override
  Future<ModelState> load() => _exclusive(_converge);

  Future<ModelState> _converge() async {
    if (!_hydrated) {
      _hydrated = true;
      if (await stateFile.exists()) {
        final loaded = await loadStore(
          stateFile,
          what: 'model state',
          decode: (raw) => ModelState.fromJson(
            Map<String, Object?>.from(jsonDecode(raw) as Map),
          ),
          orElse: () => const ModelState(),
        );
        _state = loaded.stamp(
          activeArtifactKey: activeArtifactKey,
          simulated: false,
        );
      }
      // Since #19 the loaded phase is a claim about the engine, and no engine
      // survives its process. Failed stays — still accurate across a relaunch.
      // First hydration only: on a later pass the engine may genuinely be
      // loaded, and demoting it again would describe a live model as unloaded.
      if (_state.runtime == RuntimePhase.loading ||
          _state.runtime == RuntimePhase.loaded) {
        _state = _state.copyWith(runtime: RuntimePhase.unloaded);
      }
    }
    // Disk and platform together. Disk alone cannot tell a transfer the OS is
    // still running from one it silently dropped, so demoting every
    // interrupted download to Paused made a live one look stopped — and the
    // Resume it invited started a second writer on the same file.
    final before = {
      for (final entry in catalog) entry.key: _state.statusOf(entry.key),
    };
    final artifacts = <String, ArtifactStatus>{};
    for (final entry in catalog) {
      final status = before[entry.key]!;
      artifacts[entry.key] = switch (status.phase) {
        // A generator already owns this artifact and is mid-sequence — very
        // possibly inside a multi-minute hash, during which no transfer is
        // live. Reconciling it would flip a verifying card to Paused behind a
        // Resume button that cannot act while the download holds the guard.
        _ when _active.contains(entry.key) => status,
        ArtifactPhase.installed when !await _installVerified(entry) =>
          const ArtifactStatus(),
        // Disk decides in both directions. Without this the store only ever
        // demotes, so a state that had to be reset — a schema move, a corrupt
        // file — reports weights sitting verified on disk as never downloaded,
        // and offers a multi-gigabyte re-download as the only way back (#130).
        // Receipts are revision-scoped and written only by a completed
        // hash-verified transfer, so this cannot claim a hand-provisioned
        // directory; addModel already promotes on the same evidence.
        // A delete whose sweep failed leaves both behind and is therefore
        // re-reported as installed: disk decides, and weights that are still
        // there are better named than hidden behind an offer to re-fetch them.
        ArtifactPhase.notDownloaded when await _installVerified(entry) =>
          ArtifactStatus(
            phase: ArtifactPhase.installed,
            downloadedBytes: entry.totalBytes,
          ),
        ArtifactPhase.downloading ||
        ArtifactPhase.verifying ||
        ArtifactPhase.paused => await _reconcileTransfer(entry),
        _ => status,
      };
      if (artifacts[entry.key]!.phase == ArtifactPhase.notDownloaded) {
        artifacts[entry.key] = const ArtifactStatus();
      }
    }
    // Applied only where nothing moved underneath. Hashing and probing an
    // artifact takes long enough for a download running alongside to install
    // it, and writing this pass's whole map would revert that install to the
    // phase it held before the pass began.
    final merged = {..._state.artifacts};
    artifacts.forEach((key, reconciled) {
      if (_state.statusOf(key) == before[key]) merged[key] = reconciled;
    });
    _state = _state.copyWith(artifacts: merged);
    return _persist(_state);
  }

  /// What one artifact's transfer really is: bytes already on disk, plus
  /// whatever the platform still holds for the files that are not.
  Future<ArtifactStatus> _reconcileTransfer(ModelCatalogEntry entry) async {
    var present = 0;
    var live = false;
    for (final spec in entry.files) {
      if (await _sizeMatches(entry, spec)) {
        present += spec.bytes;
        continue;
      }
      final snapshot = await downloader.inspect(_refFor(entry, spec));
      if (snapshot.presence == ArtifactTransferPresence.running ||
          snapshot.presence == ArtifactTransferPresence.waitingToRetry) {
        live = true;
      }
      // Partial data lives in the plugin's staging file, never at the
      // destination — both platforms move the file into place only once it is
      // whole — so without this a resumed card reports a false regression.
      present += snapshot.receivedBytes ?? 0;
    }
    return ArtifactStatus(
      phase: live ? ArtifactPhase.downloading : ArtifactPhase.paused,
      downloadedBytes: present,
    );
  }

  Future<bool> _installVerified(ModelCatalogEntry entry) async {
    // No files is no evidence. Vacuously true was harmless while this only
    // guarded a demotion; the promotion arm would read it as an install.
    if (entry.files.isEmpty) return false;
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
    _active.add(artifactKey);
    try {
      yield* _download(artifactKey);
    } finally {
      _active.remove(artifactKey);
    }
  }

  Stream<ModelState> _download(String artifactKey) async* {
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
    // Bytes already staged by an in-flight transfer likewise occupy the disk
    // already: without this, re-attaching to a nearly-finished 4 GB download
    // asks for another 4 GB and fails the artifact on every foreground return,
    // while the transfer it just condemned keeps running unwatched.
    var staged = 0;
    for (final spec in pending) {
      if (await _sizeMatches(entry, spec)) continue;
      staged +=
          (await downloader.inspect(_refFor(entry, spec))).receivedBytes ?? 0;
    }
    final remaining =
        entry.totalBytes - verifiedBytes - presentUnverifiedBytes - staged;
    final free = await _freeBytesSafely();
    if (free != null && free < remaining + diskSpaceMargin) {
      yield await _persist(
        _state.withArtifact(
          artifactKey,
          ArtifactStatus(
            phase: ArtifactPhase.failed,
            downloadedBytes: verifiedBytes,
            failure:
                'Needs ${gigabytes(remaining + diskSpaceMargin)} free; '
                '${gigabytes(free)} available.',
            failureReason: ArtifactFailure(
              ArtifactFailureKind.insufficientStorage,
              requiredBytes: remaining + diskSpaceMargin,
              availableBytes: free,
            ),
          ),
        ),
      );
      return;
    }

    // Bytes on disk at their pinned size. Every transfer moves this once and
    // verification reads its own counter, so the bar climbs to the total
    // exactly once (#143); a size-matching unreceipted file counts here the
    // way reconciliation already counts it.
    var onDisk = verifiedBytes + presentUnverifiedBytes;
    // Bytes the verify counter has already walked through this pass: the
    // receipted files plus every file hashed so far, passed or failed. A
    // failed file keeps its bytes in the count — dropping them stepped the
    // bar back mid-phase and reset the ETA window.
    var counted = verifiedBytes;
    ArtifactStatus downloading(int received) => ArtifactStatus(
      phase: ArtifactPhase.downloading,
      downloadedBytes: onDisk + received,
    );
    ArtifactStatus verifying(int hashed) => ArtifactStatus(
      phase: ArtifactPhase.verifying,
      downloadedBytes: onDisk,
      verifiedBytes: counted + hashed,
    );

    yield await _persist(_state.withArtifact(artifactKey, downloading(0)));

    // Files fetched in this attempt. A size-matching file that fails its hash
    // is a sideload or a right-length forgery: deleted and fetched in a second
    // round. One fetched here that still fails is a transfer fault and fails
    // the artifact, so the loop ends within two rounds.
    final fetched = <ModelArtifactFile>{};
    // Files that vanished under the hash once: a second disappearance is a
    // fault to report, not a loop to run.
    final vanishedOnce = <ModelArtifactFile>{};
    while (pending.isNotEmpty) {
      // Transfer first: every file arrives before any is hashed.
      for (final spec in pending) {
        // The install directory is keyed by artifact, not by commit, so a
        // re-pin mid-download would land this commit's bytes under the new
        // revision's name and let the engine map weights the catalog no
        // longer describes.
        if (_repinned(entry)) return;
        if (await _sizeMatches(entry, spec)) continue;
        fetched.add(spec);

        ArtifactFileEvent fileOutcome = const ArtifactFileComplete();
        var lastReceived = 0;
        await for (final event in downloader.download(_refFor(entry, spec))) {
          if (event is ArtifactFileProgress) {
            if (_stopRequested.contains(artifactKey)) continue;
            lastReceived = event.bytesReceived;
            yield await _persist(
              _state.withArtifact(
                artifactKey,
                downloading(event.bytesReceived),
              ),
            );
          } else {
            fileOutcome = event;
          }
        }
        switch (fileOutcome) {
          case ArtifactFilePaused(:final userInitiated, :final resumable):
            // A user pause already persisted out of band; an uncommanded one
            // (network loss, OS timeout) must be persisted here or the card
            // freezes on "downloading".
            if (!userInitiated && !_stopRequested.contains(artifactKey)) {
              yield await _persist(
                _state.withArtifact(
                  artifactKey,
                  ArtifactStatus(
                    phase: ArtifactPhase.paused,
                    // Streamed bytes count only while they can still be
                    // resumed from. Crediting a partial the platform discarded
                    // shows a card at 60% whose Resume restarts from zero, and
                    // a bar that jumps backwards reads as lost work.
                    downloadedBytes: resumable ? onDisk + lastReceived : onDisk,
                  ),
                ),
              );
            }
            return;
          case ArtifactFileCanceled(:final userInitiated):
            if (!userInitiated && !_stopRequested.contains(artifactKey)) {
              // The OS discarded the partial; pause at what is on disk.
              yield await _persist(
                _state.withArtifact(
                  artifactKey,
                  ArtifactStatus(
                    phase: ArtifactPhase.paused,
                    downloadedBytes: onDisk,
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
                  downloadedBytes: onDisk,
                  failure: message,
                  failureReason: const ArtifactFailure(
                    ArtifactFailureKind.transfer,
                  ),
                ),
              ),
            );
            return;
          case ArtifactFileProgress() || ArtifactFileComplete():
            break;
        }

        if (!await _sizeMatches(entry, spec)) {
          final file = File('${_rootFor(entry)}/${spec.path}');
          if (await file.exists()) {
            await file.delete();
          }
          yield await _persist(
            _state.withArtifact(
              artifactKey,
              ArtifactStatus(
                phase: ArtifactPhase.failed,
                downloadedBytes: onDisk,
                failure: '${spec.path} did not arrive at its expected size.',
                failureReason: ArtifactFailure(
                  ArtifactFailureKind.unexpectedSize,
                  fileName: spec.path,
                ),
              ),
            ),
          );
          return;
        }
        onDisk += spec.bytes;
        if (_stopRequested.contains(artifactKey)) return;
      }

      // Then verify: one phase over the whole artifact with its own counter.
      // The hash loop yields between chunks, so a cancel lands before the next
      // emit instead of after a multi-gigabyte read — and never after
      // _discard has already emptied the directory.
      if (_repinned(entry) || _stopRequested.contains(artifactKey)) return;
      counted = verifiedBytes;
      yield await _persist(_state.withArtifact(artifactKey, verifying(0)));
      final refetch = <ModelArtifactFile>[];
      // Emits are paced by the clock, not the byte stride: at real hash
      // speed the stride alone fired ~15 state rebuilds a second.
      var lastEmit = DateTime.now();
      for (final spec in pending) {
        final file = File('${_rootFor(entry)}/${spec.path}');
        String? actual;
        var vanished = false;
        try {
          await for (final step in _hashProgress(file)) {
            if (_stopRequested.contains(artifactKey)) return;
            if (step.digest case final digest?) {
              actual = digest.toString();
            } else if (DateTime.now().difference(lastEmit) >=
                verifyEmitInterval) {
              lastEmit = DateTime.now();
              // In memory only: verifiedBytes is not serialized, so a
              // durable write here would fsync the same bytes every stride.
              yield _emit(
                _state.withArtifact(artifactKey, verifying(step.hashed)),
              );
            }
          }
        } on FileSystemException {
          // A file that vanished under the hash — a cancel racing the read,
          // or an external deletion — is unproven and fetched again below,
          // once. Any other read fault is the device's, not the bytes': the
          // file stays, and the attempt fails the way every thrown fault
          // does rather than as a hash mismatch.
          if (await file.exists()) rethrow;
          vanished = true;
        }
        if (_stopRequested.contains(artifactKey)) return;

        final expected = spec.sha256;
        if (vanished) {
          onDisk -= spec.bytes;
          counted += spec.bytes;
          if (vanishedOnce.add(spec)) {
            refetch.add(spec);
            continue;
          }
          yield await _persist(
            _state.withArtifact(
              artifactKey,
              ArtifactStatus(
                phase: ArtifactPhase.failed,
                downloadedBytes: onDisk,
                failure:
                    '${spec.path} disappeared before it could be verified.',
                failureReason: const ArtifactFailure(
                  ArtifactFailureKind.transfer,
                ),
              ),
            ),
          );
          return;
        }
        if (actual == null || (expected != null && actual != expected)) {
          if (await file.exists()) {
            await file.delete();
          }
          onDisk -= spec.bytes;
          counted += spec.bytes;
          if (fetched.contains(spec)) {
            yield await _persist(
              _state.withArtifact(
                artifactKey,
                ArtifactStatus(
                  phase: ArtifactPhase.failed,
                  downloadedBytes: onDisk,
                  failure: '${spec.path} failed SHA-256 verification.',
                  failureReason: ArtifactFailure(
                    ArtifactFailureKind.hashVerification,
                    fileName: spec.path,
                  ),
                ),
              ),
            );
            return;
          }
          refetch.add(spec);
          continue;
        }
        await _recordVerified(entry, spec, actual);
        verifiedBytes += spec.bytes;
        counted += spec.bytes;
      }
      pending
        ..clear()
        ..addAll(refetch);
    }

    if (_repinned(entry) || _stopRequested.contains(artifactKey)) return;
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

  /// Whether the catalog moved to a different commit for this key since the
  /// download started. [addModel] swaps the entry in place and cannot stop a
  /// generator already running against the old one.
  bool _repinned(ModelCatalogEntry entry) {
    for (final current in catalog) {
      if (current.key == entry.key) return current.revision != entry.revision;
    }
    // The entry left the catalog entirely; nothing may still be installed
    // under its name.
    return true;
  }

  /// Derived, never remembered: an out-of-band pause or cancel arriving in a
  /// fresh process must address the same transfer the previous process
  /// started, and the catalog is the only thing both share.
  ArtifactFileRef _refFor(ModelCatalogEntry entry, ModelArtifactFile spec) =>
      ArtifactFileRef(
        artifactKey: entry.key,
        sourceUrl: entry.resolveUrlFor(spec).toString(),
        directory: _directoryFor(entry, spec),
        filename: _filenameFor(spec),
        expectedBytes: spec.bytes,
      );

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

  /// Hashes [file] in chunks, reporting the running byte count every
  /// [verifyProgressStride] bytes and the digest last. A digest rather than a
  /// verdict so an unhashed file is receipted by content. The stride is the
  /// pace estimator's only sample of a hash; past its 4 s window between
  /// samples the ETA never appears, so 8 MiB keeps it alive down to 2 MB/s.
  /// The hash runs on its own isolate: pure-Dart SHA-256 over gigabytes is
  /// ~30 s of uninterruptible CPU on a laptop core and longer on a phone,
  /// and on the UI isolate every frame of the determinate bar paid for it.
  /// Messages are hashed-byte counts, then the hex digest, then done; a read
  /// fault crosses back as a FileSystemException so the caller's handling
  /// is the same as for an inline read.
  Stream<({int hashed, Digest? digest})> _hashProgress(File file) async* {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(_hashFile, (
      path: file.path,
      stride: verifyProgressStride,
      port: port.sendPort,
    ), onError: port.sendPort);
    try {
      await for (final message in port) {
        switch (message) {
          case final int hashed:
            yield (hashed: hashed, digest: null);
          case final String hex:
            yield (hashed: 0, digest: Digest(_hexBytes(hex)));
          case (final String path, final String detail):
            throw FileSystemException(detail, path);
          case final List<Object?> error:
            throw StateError('${error.first}');
          case _:
            return;
        }
      }
    } finally {
      isolate.kill(priority: Isolate.immediate);
      port.close();
    }
  }

  static Future<void> _hashFile(
    ({String path, int stride, SendPort port}) job,
  ) async {
    final sink = _DigestCatch();
    final input = sha256.startChunkedConversion(sink);
    var hashed = 0;
    var reported = 0;
    try {
      await for (final chunk in File(job.path).openRead()) {
        input.add(chunk);
        hashed += chunk.length;
        if (hashed - reported >= job.stride) {
          reported = hashed;
          job.port.send(hashed);
        }
      }
    } on FileSystemException catch (error) {
      job.port.send((job.path, error.message));
      job.port.send(null);
      return;
    }
    input.close();
    job.port.send(sink.value!.toString());
    job.port.send(null);
  }

  static List<int> _hexBytes(String hex) => [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];

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

  /// An out-of-band stop names only the artifact, so every file of the entry is
  /// addressed; the platform holds at most one transfer per destination and
  /// answers for the rest immediately.
  Future<bool> _pauseTransfers(ModelCatalogEntry entry) async {
    var paused = false;
    for (final spec in entry.files) {
      if (await downloader.pause(_refFor(entry, spec))) paused = true;
    }
    return paused;
  }

  /// True only when the platform holds nothing for any file — the precondition
  /// for deleting the directory those transfers write into.
  Future<bool> _cancelTransfers(ModelCatalogEntry entry) async {
    var cleared = true;
    for (final spec in entry.files) {
      if (!await downloader.cancel(_refFor(entry, spec))) cleared = false;
    }
    return cleared;
  }

  @override
  Future<ModelState> pause(String artifactKey) async {
    final entry = _entry(artifactKey);
    // Confirmed first: a transfer the platform would not pause is still
    // moving bytes, and a card reading "Paused" over a live writer is a lie
    // the user acts on. Reconciliation converges it either way.
    if (!await _pauseTransfers(entry)) return _state;
    _stopRequested.add(artifactKey);
    return _persist(
      _state.withArtifact(
        artifactKey,
        _state.statusOf(artifactKey).copyWith(phase: ArtifactPhase.paused),
      ),
    );
  }

  @override
  Future<ModelState> cancel(String artifactKey) => _discard(artifactKey);

  @override
  Future<ModelState> delete(String artifactKey) => _discard(artifactKey);

  /// Cancel and delete differ only in what the user was looking at; both stop
  /// every transfer, prove it stopped, and remove the install.
  Future<ModelState> _discard(String artifactKey) async {
    final entry = _entry(artifactKey);
    _stopRequested.add(artifactKey);
    // The answer decides whether one sweep is enough. A transfer the platform
    // could not confirm stopping may still land its staging file on the
    // destination after the directory is gone, recreating it with weights that
    // carry no receipt — bytes the UI then calls "not downloaded" and no user
    // action can reach.
    final cleared = await _cancelTransfers(entry);
    await _deleteArtifactFiles(entry, sweepTwice: !cleared);
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

  /// [sweepTwice] only when a transfer could not be confirmed stopped: both
  /// platforms write the destination at completion from a staging file,
  /// recreating the directory on the way, so a task already inside that move
  /// can resurrect what was just deleted. A confirmed-clear delete pays no
  /// second pass and no delay.
  Future<void> _deleteArtifactFiles(
    ModelCatalogEntry entry, {
    bool sweepTwice = false,
  }) async {
    Future<void> sweep() async {
      final root = Directory(_rootFor(entry));
      if (!await root.exists()) return;
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    }

    await sweep();
    if (!sweepTwice) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await sweep();
  }

  @override
  Future<ModelState> recordRuntime(
    RuntimePhase phase, {
    RuntimeFailureKind? failure,
  }) => _persist(
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

/// `crypto` keeps its own `DigestSink` private to the package.
final class _DigestCatch implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
