import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/app/launch_composition.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/features/models/application/download_note_providers.dart';
import 'package:golem_flutter/features/models/application/download_pace_providers.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';

import 'support/harness.dart';

/// A repository whose download stream is driven by the test, so byte counts
/// and phase transitions arrive exactly when the scripted clock says they do.
final class _ScriptedModels implements ModelManagementRepository {
  final ModelState initial = const ModelState(simulated: true);
  StreamController<ModelState>? _downloads;

  void emit(ModelState state) => _downloads!.add(state);

  @override
  Future<ModelState> load() async => initial;

  @override
  Stream<ModelState> download(String artifactKey) {
    final controller = StreamController<ModelState>();
    _downloads = controller;
    return controller.stream;
  }

  @override
  Future<ModelState> pause(String artifactKey) async => initial;
  @override
  Future<ModelState> cancel(String artifactKey) async => initial;
  @override
  Future<ModelState> delete(String artifactKey) async => initial;
  @override
  Future<ModelState> recordRuntime(RuntimePhase phase, {String? failure}) =>
      Future.value(initial);
  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => initial;
}

ModelState _downloading(String key, int bytes) => ModelState(
  simulated: true,
  artifacts: {
    key: ArtifactStatus(
      phase: ArtifactPhase.downloading,
      downloadedBytes: bytes,
    ),
  },
);

ModelState _phase(String key, ArtifactPhase phase, int bytes) => ModelState(
  simulated: true,
  artifacts: {key: ArtifactStatus(phase: phase, downloadedBytes: bytes)},
);

void main() {
  const key = 'gemma4-mlx';

  late _ScriptedModels repository;
  late DateTime now;
  late ProviderContainer container;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    repository = _ScriptedModels();
    now = DateTime(2026, 8, 13, 12);
    container = ProviderContainer(
      overrides: [
        ...launchOverrides(launchDependenciesWith(models: repository)),
        paceClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    await container.read(modelControllerProvider.future);
  });

  Future<void> startDownload() async {
    unawaited(container.read(modelControllerProvider.notifier).download(key));
    await settle();
  }

  Future<void> tick(Duration advance, ModelState state) async {
    now = now.add(advance);
    repository.emit(state);
    await settle();
  }

  group('downloadPace', () {
    test('publishes a rate only once the window is honest', () async {
      container.listen(downloadPaceProvider, (_, _) {});
      await startDownload();
      await tick(Duration.zero, _downloading(key, 0));
      expect(container.read(downloadPaceProvider), isNull);
      await tick(const Duration(seconds: 1), _downloading(key, 44000000));
      final snapshot = container.read(downloadPaceProvider);
      expect(snapshot, isNotNull);
      expect(snapshot!.artifactKey, key);
      expect(snapshot.mbPerSecond, closeTo(44.0, 0.001));
      expect(snapshot.eta, isNotNull, reason: 'pinned catalog knows the size');
    });

    test('leaving the downloading phase clears the snapshot', () async {
      container.listen(downloadPaceProvider, (_, _) {});
      await startDownload();
      await tick(Duration.zero, _downloading(key, 0));
      await tick(const Duration(seconds: 1), _downloading(key, 44000000));
      expect(container.read(downloadPaceProvider), isNotNull);
      await tick(
        const Duration(seconds: 1),
        _phase(key, ArtifactPhase.paused, 44000000),
      );
      expect(container.read(downloadPaceProvider), isNull);
    });

    test(
      'a resume starts a fresh window instead of averaging the pause',
      () async {
        container.listen(downloadPaceProvider, (_, _) {});
        await startDownload();
        await tick(Duration.zero, _downloading(key, 0));
        await tick(const Duration(seconds: 1), _downloading(key, 44000000));
        await tick(Duration.zero, _phase(key, ArtifactPhase.paused, 44000000));
        // A long pause, then resumption at a slower link.
        await tick(const Duration(minutes: 10), _downloading(key, 44000000));
        expect(
          container.read(downloadPaceProvider),
          isNull,
          reason: 'one post-resume sample is not a rate',
        );
        await tick(const Duration(seconds: 1), _downloading(key, 49000000));
        final snapshot = container.read(downloadPaceProvider);
        expect(snapshot!.mbPerSecond, closeTo(5.0, 0.001));
      },
    );

    test('per-file verifying flips do not restart the warm-up', () async {
      container.listen(downloadPaceProvider, (_, _) {});
      await startDownload();
      await tick(Duration.zero, _downloading(key, 0));
      await tick(const Duration(seconds: 1), _downloading(key, 44000000));
      expect(container.read(downloadPaceProvider), isNotNull);
      // A finished file verifies, then the next file starts transferring.
      await tick(
        const Duration(seconds: 1),
        _phase(key, ArtifactPhase.verifying, 44000000),
      );
      expect(container.read(downloadPaceProvider), isNull);
      await tick(const Duration(seconds: 1), _downloading(key, 88000000));
      expect(
        container.read(downloadPaceProvider),
        isNotNull,
        reason: 'the window survives the file boundary',
      );
    });

    test('verification and completion clear the snapshot', () async {
      container.listen(downloadPaceProvider, (_, _) {});
      await startDownload();
      await tick(Duration.zero, _downloading(key, 0));
      await tick(const Duration(seconds: 1), _downloading(key, 44000000));
      await tick(
        const Duration(seconds: 1),
        _phase(key, ArtifactPhase.verifying, 88000000),
      );
      expect(container.read(downloadPaceProvider), isNull);
    });
  });

  group('downloadNoteDismissal', () {
    test('visibility is downloading and not dismissed, per artifact', () async {
      container.listen(downloadNoteVisibleProvider(key), (_, _) {});
      expect(container.read(downloadNoteVisibleProvider(key)), isFalse);
      await startDownload();
      await tick(Duration.zero, _downloading(key, 0));
      expect(container.read(downloadNoteVisibleProvider(key)), isTrue);

      container.read(downloadNoteDismissalProvider.notifier).dismiss(key);
      expect(container.read(downloadNoteVisibleProvider(key)), isFalse);
      expect(
        container.read(downloadNoteVisibleProvider('qwen35-gguf')),
        isFalse,
        reason: 'another artifact is simply not downloading',
      );
    });

    test('a dismissal survives ticks but not a new attempt', () async {
      container.listen(downloadNoteVisibleProvider(key), (_, _) {});
      await startDownload();
      await tick(Duration.zero, _downloading(key, 0));
      container.read(downloadNoteDismissalProvider.notifier).dismiss(key);

      await tick(const Duration(seconds: 1), _downloading(key, 44000000));
      expect(
        container.read(downloadNoteVisibleProvider(key)),
        isFalse,
        reason: 'progress ticks are the same attempt',
      );

      await tick(
        const Duration(seconds: 1),
        _phase(key, ArtifactPhase.paused, 44000000),
      );
      expect(container.read(downloadNoteVisibleProvider(key)), isFalse);

      // Resume re-enters downloading: the trade-off is live again.
      await tick(const Duration(seconds: 5), _downloading(key, 44000000));
      expect(container.read(downloadNoteVisibleProvider(key)), isTrue);
    });

    test('a dismissal survives per-file verifying flips', () async {
      container.listen(downloadNoteVisibleProvider(key), (_, _) {});
      await startDownload();
      await tick(Duration.zero, _downloading(key, 0));
      container.read(downloadNoteDismissalProvider.notifier).dismiss(key);

      // Multi-file artifact: each finished file verifies before the next
      // file re-enters downloading. Same attempt — the note stays away.
      for (var i = 1; i <= 3; i++) {
        await tick(
          const Duration(seconds: 1),
          _phase(key, ArtifactPhase.verifying, 44000000 * i),
        );
        await tick(
          const Duration(seconds: 1),
          _downloading(key, 44000000 * (i + 1)),
        );
        expect(
          container.read(downloadNoteVisibleProvider(key)),
          isFalse,
          reason: 'file boundary $i is not a new attempt',
        );
      }
    });

    test(
      'note figures freeze at attempt start and refreeze on resume',
      () async {
        container.listen(downloadNoteFiguresProvider, (_, _) {});
        await startDownload();
        await tick(Duration.zero, _downloading(key, 5000000));
        expect(container.read(downloadNoteFiguresProvider)[key], 5000000);

        // Progress ticks and file-boundary verify flips leave the figure alone.
        await tick(const Duration(seconds: 1), _downloading(key, 44000000));
        await tick(
          const Duration(seconds: 1),
          _phase(key, ArtifactPhase.verifying, 44000000),
        );
        await tick(const Duration(seconds: 1), _downloading(key, 50000000));
        expect(container.read(downloadNoteFiguresProvider)[key], 5000000);

        // A pause ends the attempt; resuming freezes a fresh figure.
        await tick(
          const Duration(seconds: 1),
          _phase(key, ArtifactPhase.paused, 60000000),
        );
        await tick(const Duration(seconds: 1), _downloading(key, 60000000));
        expect(container.read(downloadNoteFiguresProvider)[key], 60000000);
      },
    );

    test('dismissals are independent per artifact key', () async {
      container.listen(downloadNoteVisibleProvider(key), (_, _) {});
      await startDownload();
      await tick(Duration.zero, _downloading(key, 0));
      container
          .read(downloadNoteDismissalProvider.notifier)
          .dismiss('qwen35-gguf');
      expect(container.read(downloadNoteVisibleProvider(key)), isTrue);
    });
  });
}
