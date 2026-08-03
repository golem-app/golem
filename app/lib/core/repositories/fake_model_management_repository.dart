import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';
import 'contracts.dart';

final class FakeModelManagementRepository implements ModelManagementRepository {
  FakeModelManagementRepository(
    this.file, {
    this.stepDelay = const Duration(milliseconds: 90),
  });
  final File file;
  final Duration stepDelay;
  ModelState _state = const ModelState();
  bool _pauseRequested = false;
  Future<void> _writes = Future.value();

  Future<ModelState> _persist(ModelState value) async {
    _state = value;
    // Serialized atomic writes, mirroring FileChatHistoryRepository: a kill
    // mid-write must never leave a truncated file behind.
    final write = _writes.then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(value.toJson()), flush: true);
      await temporary.rename(file.path);
    });
    _writes = write.catchError((_) {});
    await write;
    return value;
  }

  @override
  Future<ModelState> load() async {
    if (await file.exists()) {
      try {
        _state = ModelState.fromJson(
          Map<String, Object?>.from(
            jsonDecode(await file.readAsString()) as Map,
          ),
        );
      } catch (_) {
        // Preserve an unreadable or unknown-schema file and fall back to the
        // default simulated state rather than failing startup.
        await file.rename('${file.path}.corrupt');
        _state = const ModelState();
      }
      if (_state.runtime == RuntimePhase.loading) {
        _state = _state.copyWith(runtime: RuntimePhase.unloaded);
      }
      // Nothing drives a persisted "downloading"/"verifying" phase after a
      // relaunch; normalize it to paused so the user resumes from the saved
      // progress instead of staring at a stuck live state.
      if (_state.mlxPhase == DownloadPhase.downloading ||
          _state.mlxPhase == DownloadPhase.verifying) {
        _state = _state.copyWith(mlxPhase: DownloadPhase.paused);
      }
    }
    return _state;
  }

  @override
  Future<ModelState> selectBackend(BackendId backend) => _persist(
    _state.copyWith(backend: backend, runtime: RuntimePhase.unloaded),
  );

  @override
  Stream<ModelState> downloadMlx() async* {
    _pauseRequested = false;
    var progress = _state.mlxProgress;
    while (progress < 1 && !_pauseRequested) {
      await Future<void>.delayed(stepDelay);
      // Re-check after the delay: a pause that arrived mid-delay must not be
      // overwritten by one more downloading step, or the repository would
      // disagree with the paused state the UI already shows.
      if (_pauseRequested) break;
      progress = (progress + 0.08).clamp(0, 1);
      yield await _persist(
        _state.copyWith(
          mlxPhase: DownloadPhase.downloading,
          mlxProgress: progress,
        ),
      );
    }
    if (_pauseRequested) {
      yield await _persist(_state.copyWith(mlxPhase: DownloadPhase.paused));
      return;
    }
    yield await _persist(_state.copyWith(mlxPhase: DownloadPhase.verifying));
    await Future<void>.delayed(stepDelay * 2);
    yield await _persist(
      _state.copyWith(mlxPhase: DownloadPhase.installed, mlxProgress: 1),
    );
  }

  @override
  Future<ModelState> pauseMlx() async {
    _pauseRequested = true;
    return _persist(_state.copyWith(mlxPhase: DownloadPhase.paused));
  }

  @override
  Stream<ModelState> importTurboFieldfare() async* {
    for (var step = 1; step <= 10; step++) {
      await Future<void>.delayed(stepDelay);
      yield await _persist(
        _state.copyWith(importProgress: step / 10, turboInstalled: step == 10),
      );
    }
  }

  @override
  Future<ModelState> loadRuntime() async {
    if (!_state.activeModelInstalled) {
      return _persist(
        _state.copyWith(
          runtime: RuntimePhase.failed,
          failure: 'Install the selected simulated model first.',
        ),
      );
    }
    await _persist(
      _state.copyWith(runtime: RuntimePhase.loading, clearFailure: true),
    );
    await Future<void>.delayed(stepDelay * 3);
    return _persist(_state.copyWith(runtime: RuntimePhase.loaded));
  }

  @override
  Future<ModelState> unloadRuntime() =>
      _persist(_state.copyWith(runtime: RuntimePhase.unloaded));
}
