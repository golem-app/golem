import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_benchmark_repository.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/core/repositories/fake_model_management_repository.dart';

Future<String> _fixtureAsset(String key) async =>
    '[{"role": "user", "content": "${'x' * 400}"}]';

const _catalog = [
  ModelCatalogEntry(
    key: 'test-mlx',
    displayName: 'Test MLX',
    engine: ModelEngine.mlx,
    quantization: '4-bit',
    repository: 'example/test-mlx',
    revision: '0123456789abcdef',
    profileKey: 'gemma4',
    files: [
      ModelArtifactFile(path: 'model.safetensors', bytes: 1200, sha256: 'aa'),
    ],
  ),
  ModelCatalogEntry(
    key: 'test-gguf',
    displayName: 'Test GGUF',
    engine: ModelEngine.gguf,
    quantization: 'Q4_0',
    repository: 'example/test-gguf',
    revision: 'fedcba9876543210',
    profileKey: 'gemma4',
    files: [ModelArtifactFile(path: 'model.gguf', bytes: 600, sha256: 'bb')],
  ),
];

void main() {
  test(
    'fake inference streams reasoning, answer, metrics, then completion',
    () async {
      final repository = FakeInferenceRepository(eventDelay: Duration.zero);
      final events = await repository
          .generate(
            context: [PromptMessage.text('user', 'Hello')],
            reasoningEnabled: true,
          )
          .toList();
      expect(events.first, isA<ReasoningDelta>());
      expect(events.whereType<AnswerDelta>(), isNotEmpty);
      expect(events.whereType<MetricsEvent>(), isNotEmpty);
      expect(events.last, isA<CompletedEvent>());
    },
  );

  test('the simulation names the artifact it was given', () async {
    // `startsWith('qwen35')` made every Qwen key answer as the 4B and be
    // charged its slower rate, so QA claimed the smaller model was the
    // slower one under a header reading 2B (#118).
    Future<({String opening, double rate})> turnFor(String modelKey) async {
      final events =
          await FakeInferenceRepository(
                eventDelay: Duration.zero,
                catalog: () => modelCatalog,
              )
              .generate(
                context: [PromptMessage.text('user', 'Hello')],
                reasoningEnabled: false,
                modelKey: modelKey,
              )
              .toList();
      return (
        opening: events.whereType<AnswerDelta>().first.text,
        rate: events
            .whereType<MetricsEvent>()
            .first
            .metrics
            .decodeTokensPerSecond,
      );
    }

    final small = await turnFor('qwen35-2b-mlx');
    final large = await turnFor('qwen35-mlx');
    final gemma = await turnFor('gemma4-gguf');

    expect(small.opening, startsWith('Simulated Qwen 3.5 2B here.'));
    expect(large.opening, startsWith('Simulated Qwen 3.5 4B here.'));
    expect(gemma.opening, startsWith('Simulated Gemma 4 E2B here.'));
    // Distinct identities, and the smaller artifact is no longer the slower.
    expect(small.rate, isNot(large.rate));
    expect(small.rate, greaterThan(large.rate));
  });

  test(
    'the system-prompt note never precedes reasoning or a failure',
    () async {
      final repository = FakeInferenceRepository(eventDelay: Duration.zero);
      // With reasoning on, answer text arriving early would end the
      // reasoning card's live state — the note must follow the whole
      // reasoning stream.
      final events = await repository
          .generate(
            context: [PromptMessage.text('user', 'Hello')],
            reasoningEnabled: true,
            systemPrompt: 'Answer briefly.',
          )
          .toList();
      final firstAnswer = events.indexWhere((event) => event is AnswerDelta);
      final lastReasoning = events.lastIndexWhere(
        (event) => event is ReasoningDelta,
      );
      expect(firstAnswer, greaterThan(lastReasoning));
      expect(
        (events[firstAnswer] as AnswerDelta).text,
        contains('system prompt is applied'),
      );

      // The failure injections stay pristine: no note ahead of the throw.
      final failed = <InferenceEvent>[];
      await expectLater(
        repository
            .generate(
              context: [PromptMessage.text('user', '[fail]')],
              reasoningEnabled: false,
              systemPrompt: 'Answer briefly.',
            )
            .forEach(failed.add),
        throwsA(isA<InferenceException>()),
      );
      expect(
        failed.whereType<AnswerDelta>().map((event) => event.text).join(),
        isNot(contains('system prompt')),
      );
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
          context: [PromptMessage.text('user', 'cancel')],
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
            context: [PromptMessage.text('user', '[fail]')],
            reasoningEnabled: false,
          )
          .toList(),
      throwsA(isA<InferenceException>()),
    );
  });

  test(
    'model download pauses, resumes, verifies, guards, and persists',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'golem-model-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/model.json');
      final repository = FakeModelManagementRepository(
        file,
        catalog: _catalog,
        activeArtifactKey: 'test-mlx',
        stepDelay: const Duration(milliseconds: 2),
      );
      final initial = await repository.load();
      expect(initial.simulated, isTrue);
      expect(initial.activeArtifactKey, 'test-mlx');
      // A refused load records a failed phase with its kind (the refusal
      // decision itself lives in ModelController since #42).
      final refused = await repository.recordRuntime(
        RuntimePhase.failed,
        failure: RuntimeFailureKind.notInstalled,
      );
      expect(refused.runtime, RuntimePhase.failed);
      expect(refused.failure, RuntimeFailureKind.notInstalled);
      final subscription = repository.download('test-mlx').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final paused = await repository.pause('test-mlx');
      await subscription.cancel();
      expect(paused.statusOf('test-mlx').phase, ArtifactPhase.paused);
      final resumedFrom = paused.statusOf('test-mlx').downloadedBytes;
      expect(resumedFrom, greaterThan(0));
      expect(resumedFrom, lessThan(1200));
      final completed = await repository.download('test-mlx').last;
      expect(completed.statusOf('test-mlx').phase, ArtifactPhase.installed);
      expect(completed.statusOf('test-mlx').downloadedBytes, 1200);
      expect(
        (await repository.recordRuntime(RuntimePhase.loaded)).runtime,
        RuntimePhase.loaded,
      );
      expect(
        (await repository.recordRuntime(RuntimePhase.unloaded)).runtime,
        RuntimePhase.unloaded,
      );
      final reloaded = await FakeModelManagementRepository(
        file,
        catalog: _catalog,
        activeArtifactKey: 'test-mlx',
      ).load();
      expect(reloaded.statusOf('test-mlx').phase, ArtifactPhase.installed);
      expect(reloaded.simulated, isTrue);
    },
  );

  test('model cancel discards progress and delete uninstalls', () async {
    final directory = await Directory.systemTemp.createTemp(
      'golem-model-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/model.json');
    final repository = FakeModelManagementRepository(
      file,
      catalog: _catalog,
      stepDelay: const Duration(milliseconds: 2),
    );
    await repository.load();
    final subscription = repository.download('test-gguf').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final cancelled = await repository.cancel('test-gguf');
    await subscription.cancel();
    expect(cancelled.statusOf('test-gguf').phase, ArtifactPhase.notDownloaded);
    expect(cancelled.statusOf('test-gguf').downloadedBytes, 0);
    final installed = await repository.download('test-gguf').last;
    expect(installed.statusOf('test-gguf').phase, ArtifactPhase.installed);
    final deleted = await repository.delete('test-gguf');
    expect(deleted.statusOf('test-gguf').phase, ArtifactPhase.notDownloaded);
    expect(deleted.statusOf('test-gguf').downloadedBytes, 0);
    expect(
      () => repository.download('unknown').first,
      throwsA(isA<ArgumentError>()),
    );
  });

  test('deleting the active simulated model unloads the runtime', () async {
    final directory = await Directory.systemTemp.createTemp(
      'golem-model-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = FakeModelManagementRepository(
      File('${directory.path}/model.json'),
      catalog: _catalog,
      activeArtifactKey: 'test-mlx',
      stepDelay: Duration.zero,
    );
    await repository.load();
    await repository.download('test-mlx').drain<void>();
    expect(
      (await repository.recordRuntime(RuntimePhase.loaded)).runtime,
      RuntimePhase.loaded,
    );
    final deleted = await repository.delete('test-mlx');
    expect(deleted.statusOf('test-mlx').phase, ArtifactPhase.notDownloaded);
    expect(deleted.runtime, RuntimePhase.unloaded);
  });

  test('a fail-keyed artifact fails deterministically and can retry', () async {
    final directory = await Directory.systemTemp.createTemp(
      'golem-model-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = FakeModelManagementRepository(
      File('${directory.path}/model.json'),
      catalog: _catalog,
      stepDelay: const Duration(milliseconds: 2),
      failKeys: const {'test-gguf'},
    );
    await repository.load();
    final failed = await repository.download('test-gguf').last;
    final status = failed.statusOf('test-gguf');
    expect(status.phase, ArtifactPhase.failed);
    expect(status.failure, contains('Simulated'));
    expect(status.downloadedBytes, greaterThan(0));
  });

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
