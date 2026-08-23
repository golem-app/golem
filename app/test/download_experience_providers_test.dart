import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/app/launch_composition.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
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
  Future<ModelState> recordRuntime(
    RuntimePhase phase, {
    RuntimeFailureKind? failure,
  }) => Future.value(initial);
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

/// Every byte has arrived; [hashed] of the pinned total are verified.
ModelState _verifying(String key, int hashed) => ModelState(
  simulated: true,
  artifacts: {
    key: ArtifactStatus(
      phase: ArtifactPhase.verifying,
      downloadedBytes: 3583086498,
      verifiedBytes: hashed,
    ),
  },
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
      expect(snapshot.eta, isNull, reason: 'a rate this young is not a time');
    });

    test('publishes a time left once two ticks agree on it', () async {
      container.listen(downloadPaceProvider, (_, _) {});
      await startDownload();
      await tick(Duration.zero, _downloading(key, 0));
      for (var second = 1; second <= 3; second++) {
        await tick(
          const Duration(seconds: 1),
          _downloading(key, 44000000 * second),
        );
      }
      expect(
        container.read(downloadPaceProvider)!.eta,
        isNull,
        reason: 'the first estimate is unconfirmed',
      );
      await tick(const Duration(seconds: 1), _downloading(key, 176000000));
      // 3.58 GB pinned, 176 MB in, 44 MB/s.
      expect(
        container.read(downloadPaceProvider)!.eta!.inSeconds,
        closeTo(77, 2),
      );
    });

    test(
      'a slow first stride never reaches a surface as a time left',
      () async {
        // The reported defect: the opening reading of a transfer divided into
        // the whole artifact printed "About 2173 minutes left" (#146).
        final published = <Duration>[];
        container.listen(downloadPaceProvider, (_, next) {
          if (next?.eta case final eta?) published.add(eta);
        });
        await startDownload();
        await tick(Duration.zero, _downloading(key, 0));
        await tick(const Duration(seconds: 1), _downloading(key, 300000));
        for (var second = 2; second <= 4; second++) {
          await tick(
            const Duration(seconds: 1),
            _downloading(key, 300000 + 44000000 * (second - 1)),
          );
        }
        expect(published, isNotEmpty, reason: 'the settled figure still lands');
        expect(
          published,
          everyElement(lessThan(const Duration(minutes: 5))),
          reason: 'nothing derived from the 0.3 MB/s opening stride',
        );
      },
    );

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

    test('verification opens a fresh window over hashed bytes', () async {
      container.listen(downloadPaceProvider, (_, _) {});
      await startDownload();
      await tick(Duration.zero, _downloading(key, 0));
      await tick(const Duration(seconds: 1), _downloading(key, 44000000));
      expect(container.read(downloadPaceProvider), isNotNull);
      // Every byte has arrived; the hash starts with its own counter, and
      // the network window is not averaged into it.
      await tick(const Duration(seconds: 1), _verifying(key, 0));
      expect(container.read(downloadPaceProvider), isNull);
      await tick(const Duration(seconds: 1), _verifying(key, 150000000));
      final snapshot = container.read(downloadPaceProvider);
      expect(snapshot, isNotNull);
      expect(snapshot!.phase, ArtifactPhase.verifying);
      expect(snapshot.mbPerSecond, closeTo(150.0, 0.001));
      expect(snapshot.eta, isNull, reason: 'the hash window is a tick old');
      for (var second = 2; second <= 4; second++) {
        await tick(
          const Duration(seconds: 1),
          _verifying(key, 150000000 * second),
        );
      }
      expect(
        container.read(downloadPaceProvider)!.eta,
        isNotNull,
        reason: 'the catalog knows the size',
      );
    });

    test('completion clears the snapshot', () async {
      container.listen(downloadPaceProvider, (_, _) {});
      await startDownload();
      await tick(Duration.zero, _verifying(key, 0));
      await tick(const Duration(seconds: 1), _verifying(key, 150000000));
      expect(container.read(downloadPaceProvider), isNotNull);
      await tick(
        const Duration(seconds: 1),
        _phase(key, ArtifactPhase.installed, 3583086498),
      );
      expect(container.read(downloadPaceProvider), isNull);
    });
  });
}
