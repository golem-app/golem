import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../domain/model_catalog.dart';
import '../domain/models.dart';
import 'contracts.dart';
import 'persistence_io.dart';

final class FakeModelManagementRepository implements ModelManagementRepository {
  FakeModelManagementRepository(
    this.file, {
    required List<ModelCatalogEntry> catalog,
    this.stepDelay = const Duration(milliseconds: 90),
    this.activeArtifactKey = 'gemma4-mlx',
    this.failKeys = const {},
  }) : catalog = List.of(catalog) {
    _state = ModelState(activeArtifactKey: activeArtifactKey, simulated: true);
  }

  final File file;

  /// Growable: [addModel] registers custom repositories at runtime; the
  /// composition root re-merges persisted specs into the injected catalog
  /// on the next launch.
  final List<ModelCatalogEntry> catalog;
  final Duration stepDelay;
  final String activeArtifactKey;

  /// Keys whose simulated download fails deterministically at the halfway
  /// point — the test hook for the failed phase.
  final Set<String> failKeys;

  late ModelState _state;
  final Set<String> _stopRequested = {};
  Future<void> _writes = Future.value();

  Future<ModelState> _persist(ModelState value) async {
    _state = value;
    // Serialized atomic writes, mirroring FileChatHistoryRepository: a kill
    // mid-write must never leave a truncated file behind.
    final write = _writes.then(
      (_) => writeStore(file, jsonEncode(value.toJson()), what: 'model state'),
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
    if (await file.exists()) {
      final loaded = await loadStore(
        file,
        what: 'model state',
        decode: (raw) => ModelState.fromJson(
          Map<String, Object?>.from(jsonDecode(raw) as Map),
        ),
        orElse: () => const ModelState(),
      );
      _state = loaded.stamp(
        activeArtifactKey: activeArtifactKey,
        simulated: true,
      );
      if (_state.runtime == RuntimePhase.loading) {
        _state = _state.copyWith(runtime: RuntimePhase.unloaded);
      }
      // The catalog is authoritative: drop keys it no longer contains, and
      // normalize live phases — nothing drives a persisted "downloading" or
      // "verifying" after a relaunch, so they become paused at the saved
      // byte count instead of staring at a stuck live state.
      final known = {for (final entry in catalog) entry.key};
      _state = _state.copyWith(
        artifacts: {
          for (final MapEntry(:key, :value) in _state.artifacts.entries)
            if (known.contains(key))
              key: switch (value.phase) {
                ArtifactPhase.downloading || ArtifactPhase.verifying =>
                  value.copyWith(phase: ArtifactPhase.paused),
                _ => value,
              },
        },
      );
    }
    return _state;
  }

  @override
  Stream<ModelState> download(String artifactKey) async* {
    final entry = _entry(artifactKey);
    _stopRequested.remove(artifactKey);
    var bytes = _state.statusOf(artifactKey).downloadedBytes;
    final step = max(entry.totalBytes ~/ 12, 1);
    final failAt = failKeys.contains(artifactKey) ? entry.totalBytes ~/ 2 : -1;
    while (bytes < entry.totalBytes) {
      await Future<void>.delayed(stepDelay);
      // Re-check after the delay: a pause or cancel that arrived mid-delay
      // must not be overwritten by one more downloading step, or the
      // repository would disagree with the state the UI already shows.
      if (_stopRequested.contains(artifactKey)) return;
      bytes = min(bytes + step, entry.totalBytes);
      if (failAt >= 0 && bytes >= failAt) {
        yield await _persist(
          _state.withArtifact(
            artifactKey,
            ArtifactStatus(
              phase: ArtifactPhase.failed,
              downloadedBytes: bytes,
              failure: 'Simulated download failure.',
              failureReason: const ArtifactFailure(
                ArtifactFailureKind.transfer,
              ),
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
            downloadedBytes: bytes,
          ),
        ),
      );
    }
    // Verification as the real repository reports it: one phase after every
    // byte has arrived, with its own counter climbing to the total.
    const verifySteps = 4;
    for (var step = 0; step <= verifySteps; step++) {
      if (step > 0) await Future<void>.delayed(stepDelay);
      if (_stopRequested.contains(artifactKey)) return;
      yield await _persist(
        _state.withArtifact(
          artifactKey,
          ArtifactStatus(
            phase: ArtifactPhase.verifying,
            downloadedBytes: bytes,
            verifiedBytes: entry.totalBytes * step ~/ verifySteps,
          ),
        ),
      );
    }
    if (_stopRequested.contains(artifactKey)) return;
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

  @override
  Future<ModelState> pause(String artifactKey) async {
    _entry(artifactKey);
    _stopRequested.add(artifactKey);
    return _persist(
      _state.withArtifact(
        artifactKey,
        _state.statusOf(artifactKey).copyWith(phase: ArtifactPhase.paused),
      ),
    );
  }

  @override
  Future<ModelState> cancel(String artifactKey) async {
    _entry(artifactKey);
    _stopRequested.add(artifactKey);
    return _persist(
      _withoutArtifact(
        artifactKey,
      ).withArtifact(artifactKey, const ArtifactStatus()),
    );
  }

  @override
  Future<ModelState> delete(String artifactKey) async {
    _entry(artifactKey);
    _stopRequested.add(artifactKey);
    return _persist(
      _withoutArtifact(
        artifactKey,
      ).withArtifact(artifactKey, const ArtifactStatus()),
    );
  }

  /// Removing the active artifact invalidates a loaded simulated runtime.
  ModelState _withoutArtifact(String artifactKey) =>
      artifactKey == activeArtifactKey &&
          _state.runtime != RuntimePhase.unloaded
      ? _state.copyWith(runtime: RuntimePhase.unloaded, clearFailure: true)
      : _state;

  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async {
    // Re-adding an existing key refreshes the entry (a repaste with a new
    // revision) without disturbing its download state.
    catalog.removeWhere((item) => item.key == entry.key);
    catalog.add(entry);
    if (_state.statusOf(entry.key).phase == ArtifactPhase.notDownloaded) {
      return _persist(_state.withArtifact(entry.key, const ArtifactStatus()));
    }
    return _state;
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
}
