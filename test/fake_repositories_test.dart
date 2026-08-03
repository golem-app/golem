import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/fake_benchmark_repository.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/core/repositories/fake_model_management_repository.dart';

Future<String> _fixtureAsset(String key) async =>
    '[{"role": "user", "content": "${'x' * 400}"}]';

void main() {
  test(
    'fake inference streams reasoning, answer, metrics, then completion',
    () async {
      final repository = FakeInferenceRepository(eventDelay: Duration.zero);
      final events = await repository
          .generate(
            context: const [
              {'role': 'user', 'content': 'Hello'},
            ],
            reasoningEnabled: true,
          )
          .toList();
      expect(events.first, isA<ReasoningDelta>());
      expect(events.whereType<AnswerDelta>(), isNotEmpty);
      expect(events.whereType<MetricsEvent>(), isNotEmpty);
      expect(events.last, isA<CompletedEvent>());
    },
  );

  test('fake inference supports cancellation and injected failure', () async {
    final repository = FakeInferenceRepository(
      eventDelay: const Duration(milliseconds: 20),
    );
    final seen = <InferenceEvent>[];
    late StreamSubscription<InferenceEvent> subscription;
    subscription = repository
        .generate(
          context: const [
            {'role': 'user', 'content': 'cancel'},
          ],
          reasoningEnabled: true,
        )
        .listen((event) {
          seen.add(event);
          subscription.cancel();
        });
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(seen, hasLength(1));
    expect(
      repository
          .generate(
            context: const [
              {'role': 'user', 'content': '[fail]'},
            ],
            reasoningEnabled: false,
          )
          .toList(),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'model download pauses, resumes, verifies, imports, guards, and persists',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'golem-model-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/model.json');
      final repository = FakeModelManagementRepository(
        file,
        stepDelay: const Duration(milliseconds: 2),
      );
      await repository.load();
      final selected = await repository.selectBackend(BackendId.mlx);
      expect(selected.runtime, RuntimePhase.unloaded);
      final subscription = repository.downloadMlx().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final paused = await repository.pauseMlx();
      await subscription.cancel();
      expect(paused.mlxPhase, DownloadPhase.paused);
      final completed = await repository.downloadMlx().last;
      expect(completed.mlxPhase, DownloadPhase.installed);
      expect((await repository.loadRuntime()).runtime, RuntimePhase.loaded);
      expect((await repository.unloadRuntime()).runtime, RuntimePhase.unloaded);
      final imported = await repository.importTurboFieldfare().last;
      expect(imported.turboInstalled, isTrue);
      final reloaded = await FakeModelManagementRepository(file).load();
      expect(reloaded.mlxPhase, DownloadPhase.installed);
    },
  );

  test('benchmark result and export are unambiguously simulated', () async {
    final directory = await Directory.systemTemp.createTemp(
      'golem-benchmark-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = FakeBenchmarkRepository(
      directory,
      readAsset: _fixtureAsset,
      delay: Duration.zero,
    );
    final record = await repository.run(
      'short-explanation',
      BenchmarkPhase.measured,
    );
    final path = await repository.export(record);
    final json =
        jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
    expect(json['simulated'], isTrue);
    expect(json['validation'], contains('not hardware validated'));
  });
}
