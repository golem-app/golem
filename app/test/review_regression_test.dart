import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/features/benchmark/application/benchmark_providers.dart';
import 'package:golem_flutter/core/repositories/fake_benchmark_repository.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/core/repositories/fake_model_management_repository.dart';
import 'package:golem_flutter/core/repositories/file_chat_history_repository.dart';
import 'package:golem_flutter/core/repositories/file_settings_repository.dart';
import 'package:golem_flutter/core/theme/golem_theme.dart';

import 'support/in_memory_chat_history_repository.dart';

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

FakeModelManagementRepository _fakeModels(
  File file, {
  Duration stepDelay = Duration.zero,
}) => FakeModelManagementRepository(
  file,
  catalog: _catalog,
  activeArtifactKey: 'test-mlx',
  stepDelay: stepDelay,
);

void main() {
  Directory tempDir() {
    final directory = Directory.systemTemp.createTempSync('golem-review-');
    addTearDown(() => directory.deleteSync(recursive: true));
    return directory;
  }

  test('corrupt chat history is preserved aside and load recovers', () async {
    final file = File('${tempDir().path}/chat.json');
    await file.writeAsString('{"schemaVersion": 99, "conversations": ');
    final snapshot = await FileChatHistoryRepository(file).load();
    expect(snapshot.conversations, isEmpty);
    expect(File('${file.path}.corrupt').existsSync(), isTrue);
    expect(file.existsSync(), isFalse);
  });

  test('concurrent chat saves serialize; the last snapshot wins', () async {
    final file = File('${tempDir().path}/chat.json');
    final repository = FileChatHistoryRepository(file);
    await Future.wait([
      for (var i = 0; i < 12; i++)
        repository.save(
          ChatHistorySnapshot(
            conversations: [
              ChatConversation(
                id: 'c$i',
                title: 'Chat $i',
                messages: const [],
                updatedAt: DateTime(2026),
              ),
            ],
          ),
        ),
    ]);
    final loaded = await repository.load();
    expect(loaded.conversations.single.id, 'c11');
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('concurrent settings saves serialize; the last snapshot wins', () async {
    final file = File('${tempDir().path}/prefs.json');
    final repository = FileSettingsRepository(file);
    await Future.wait([
      for (var i = 1; i <= 12; i++)
        repository.save(
          const GenerationSettings().withModel(
            'gemma4',
            SamplingOverrides(maxTokens: i * 32),
          ),
        ),
    ]);
    final loaded = await repository.load();
    expect(loaded.overridesFor('gemma4').maxTokens, 12 * 32);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('model failure survives relaunch; unknown schema recovers', () async {
    final file = File('${tempDir().path}/model.json');
    final first = _fakeModels(file);
    await first.load();
    final failed = await first.recordRuntime(
      RuntimePhase.failed,
      failure: 'Install the selected simulated model first.',
    );
    expect(failed.runtime, RuntimePhase.failed);
    expect(failed.failure, isNotNull);

    final reloaded = await _fakeModels(file).load();
    expect(reloaded.runtime, RuntimePhase.failed);
    expect(reloaded.failure, failed.failure);

    await file.writeAsString('{"schemaVersion": 99}');
    final fresh = await _fakeModels(file).load();
    expect(fresh.artifacts, isEmpty);
    expect(fresh.runtime, RuntimePhase.unloaded);
    expect(File('${file.path}.corrupt').existsSync(), isTrue);
  });

  test('benchmark metrics derive from the prompt fixture', () async {
    final repository = FakeBenchmarkRepository(
      tempDir(),
      readAsset: _fixtureAsset,
      delay: Duration.zero,
    );
    final record = await repository.run(
      'medium-review',
      BenchmarkPhase.measured,
    );
    // The stub prompt is 400 characters, estimated at 4 characters per token.
    expect(record.output, contains('100 estimated prompt tokens'));
    expect(record.metrics.elapsedSeconds, closeTo(100 / 144 + 128 / 21.4, 0.1));
  });

  test('select, rename, toggle reasoning, and delete round-trip', () async {
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(
          FakeInferenceRepository(eventDelay: Duration.zero),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.future);
    final controller = container.read(chatControllerProvider.notifier);

    await controller.send('First conversation');
    await controller.newChat();
    await controller.send('Second conversation');
    var state = container.read(chatControllerProvider).requireValue;
    expect(state.conversations.length, 2);

    final firstId = state.conversations
        .firstWhere((item) => item.title == 'First conversation')
        .id;
    await controller.selectConversation(firstId);
    state = container.read(chatControllerProvider).requireValue;
    expect(state.activeId, firstId);

    await controller.toggleReasoning();
    state = container.read(chatControllerProvider).requireValue;
    expect(state.active!.reasoningEnabled, isTrue);

    await controller.renameConversation(firstId, '  Renamed   chat  ');
    state = container.read(chatControllerProvider).requireValue;
    expect(
      state.conversations.firstWhere((item) => item.id == firstId).title,
      'Renamed chat',
    );

    await controller.deleteConversation(firstId);
    state = container.read(chatControllerProvider).requireValue;
    expect(state.conversations.length, 1);
    expect(state.activeId, isNot(firstId));
  });

  test('pause interrupts a simulated download mid-stream', () async {
    final container = ProviderContainer(
      overrides: [
        modelManagementRepositoryProvider.overrideWithValue(
          _fakeModels(
            File('${tempDir().path}/model.json'),
            stepDelay: const Duration(milliseconds: 5),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(modelControllerProvider.future);
    final controller = container.read(modelControllerProvider.notifier);

    final download = controller.download('test-mlx');
    await Future<void>.delayed(const Duration(milliseconds: 12));
    await controller.pause('test-mlx');
    await download;
    final status = container
        .read(modelControllerProvider)
        .requireValue
        .statusOf('test-mlx');
    expect(status.phase, ArtifactPhase.paused);
    expect(status.downloadedBytes, greaterThan(0));
    expect(status.downloadedBytes, lessThan(1200));
  });

  test('interrupted download relaunches as paused, not downloading', () async {
    final file = File('${tempDir().path}/model.json');
    await file.writeAsString(
      '{"schemaVersion": 2, "runtime": "unloaded", "failure": null, '
      '"artifacts": {'
      '"test-mlx": {"phase": "downloading", "downloadedBytes": 480}, '
      '"removed-model": {"phase": "installed", "downloadedBytes": 9}}}',
    );
    final state = await _fakeModels(file).load();
    expect(state.statusOf('test-mlx').phase, ArtifactPhase.paused);
    expect(state.statusOf('test-mlx').downloadedBytes, 480);
    // The catalog is authoritative; state for entries it no longer contains
    // is dropped on load.
    expect(state.artifacts.containsKey('removed-model'), isFalse);
  });

  test('runtime toggle publishes the loading phase', () async {
    final container = ProviderContainer(
      overrides: [
        modelManagementRepositoryProvider.overrideWithValue(
          _fakeModels(
            File('${tempDir().path}/model.json'),
            stepDelay: const Duration(milliseconds: 5),
          ),
        ),
        // The toggle now drives the engine for real (prepare/unload), so
        // the container must supply an inference repository.
        inferenceRepositoryProvider.overrideWithValue(
          FakeInferenceRepository(eventDelay: Duration.zero),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(modelControllerProvider.future);
    final controller = container.read(modelControllerProvider.notifier);
    // The runtime only loads once the active artifact is installed.
    await controller.download('test-mlx');

    final phases = <RuntimePhase>[];
    final subscription = container.listen(modelControllerProvider, (
      previous,
      next,
    ) {
      if (next.hasValue) phases.add(next.requireValue.runtime);
    });
    addTearDown(subscription.close);

    await controller.toggleRuntime(); // unloaded -> loading -> loaded
    await controller.toggleRuntime(); // loaded -> unloaded
    expect(phases, [
      RuntimePhase.loading,
      RuntimePhase.loaded,
      RuntimePhase.unloaded,
    ]);
  });

  test('busy model controller ignores overlapping operations', () async {
    final container = ProviderContainer(
      overrides: [
        modelManagementRepositoryProvider.overrideWithValue(
          _fakeModels(
            File('${tempDir().path}/model.json'),
            stepDelay: const Duration(milliseconds: 5),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(modelControllerProvider.future);
    final controller = container.read(modelControllerProvider.notifier);

    final download = controller.download('test-mlx');
    await Future<void>.delayed(const Duration(milliseconds: 8));
    await controller.toggleRuntime();
    final during = container.read(modelControllerProvider).requireValue;
    expect(during.runtime, isNot(RuntimePhase.loading));
    await controller.download('test-gguf');
    expect(
      container
          .read(modelControllerProvider)
          .requireValue
          .statusOf('test-gguf')
          .phase,
      ArtifactPhase.notDownloaded,
    );
    await controller.pause('test-mlx');
    await download;
    final after = container.read(modelControllerProvider).requireValue;
    expect(after.statusOf('test-mlx').phase, ArtifactPhase.paused);
  });

  test('pause mid-delay is not overwritten by a late download step', () async {
    final repository = _fakeModels(
      File('${tempDir().path}/model.json'),
      stepDelay: const Duration(milliseconds: 10),
    );
    final container = ProviderContainer(
      overrides: [
        modelManagementRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(modelControllerProvider.future);
    final controller = container.read(modelControllerProvider.notifier);

    final download = controller.download('test-mlx');
    // Land the pause inside a step delay, not at a loop boundary.
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await controller.pause('test-mlx');
    await download;
    // Give any late repository write a chance to land before checking.
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // A subsequent repository operation must not resurrect "downloading".
    final after = await repository.recordRuntime(RuntimePhase.unloaded);
    expect(after.statusOf('test-mlx').phase, ArtifactPhase.paused);
  });

  test('benchmark selection and reruns clear stale results', () async {
    final container = ProviderContainer(
      overrides: [
        benchmarkRepositoryProvider.overrideWithValue(
          FakeBenchmarkRepository(
            tempDir(),
            readAsset: _fixtureAsset,
            delay: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(benchmarkControllerProvider.notifier);

    await controller.run();
    expect(container.read(benchmarkControllerProvider).result, isNotNull);

    controller.selectCase('long-synthesis');
    expect(container.read(benchmarkControllerProvider).result, isNull);

    await controller.run();
    expect(container.read(benchmarkControllerProvider).result, isNotNull);

    controller.selectPhase(BenchmarkPhase.measured);
    expect(container.read(benchmarkControllerProvider).result, isNull);

    final running = controller.run();
    expect(container.read(benchmarkControllerProvider).result, isNull);
    expect(container.read(benchmarkControllerProvider).isRunning, isTrue);
    await running;
    expect(container.read(benchmarkControllerProvider).result, isNotNull);
  });

  test('navigation bar background stays dynamic for dark mode', () {
    final bar = GolemTheme.theme(Brightness.dark).barBackgroundColor;
    expect(bar, isA<CupertinoDynamicColor>());
    final dynamicBar = bar as CupertinoDynamicColor;
    expect(dynamicBar.darkColor, isNot(dynamicBar.color));
    expect(dynamicBar.darkColor.a, closeTo(0.84, 0.01));
  });

  test('startup retry replays the ready sequence to completion', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // `.future` resolves with the first intermediate emission, so poll until
    // the sequence reaches its terminal state.
    await container.read(startupControllerProvider.future);
    while (container.read(startupControllerProvider).requireValue.phase !=
        StartupPhase.complete) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final states = <StartupState>[];
    final subscription = container.listen(startupControllerProvider, (
      previous,
      next,
    ) {
      if (next.hasValue) states.add(next.requireValue);
    });
    addTearDown(subscription.close);

    await container.read(startupControllerProvider.notifier).retry();
    expect(states.first.progress, 0.2);
    expect(states.last.phase, StartupPhase.complete);
    expect(states.last.progress, 1);
  });
}
