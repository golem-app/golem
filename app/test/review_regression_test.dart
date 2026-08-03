import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/fake_benchmark_repository.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/core/repositories/fake_model_management_repository.dart';
import 'package:golem_flutter/core/repositories/file_chat_history_repository.dart';
import 'package:golem_flutter/core/theme/golem_theme.dart';

import 'support/in_memory_chat_history_repository.dart';

Future<String> _fixtureAsset(String key) async =>
    '[{"role": "user", "content": "${'x' * 400}"}]';

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

  test('model failure survives relaunch; unknown schema recovers', () async {
    final file = File('${tempDir().path}/model.json');
    final first = FakeModelManagementRepository(file, stepDelay: Duration.zero);
    await first.load();
    await first.selectBackend(BackendId.mlx);
    final failed = await first.loadRuntime();
    expect(failed.runtime, RuntimePhase.failed);
    expect(failed.failure, isNotNull);

    final second = FakeModelManagementRepository(
      file,
      stepDelay: Duration.zero,
    );
    final reloaded = await second.load();
    expect(reloaded.runtime, RuntimePhase.failed);
    expect(reloaded.failure, failed.failure);

    await file.writeAsString('{"schemaVersion": 2}');
    final third = FakeModelManagementRepository(file, stepDelay: Duration.zero);
    final fresh = await third.load();
    expect(fresh.backend, BackendId.turboFieldfare);
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
          FakeModelManagementRepository(
            File('${tempDir().path}/model.json'),
            stepDelay: const Duration(milliseconds: 5),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(modelControllerProvider.future);
    final controller = container.read(modelControllerProvider.notifier);
    await controller.selectBackend(BackendId.mlx);

    final download = controller.downloadOrResumeMlx();
    await Future<void>.delayed(const Duration(milliseconds: 12));
    await controller.pauseMlx();
    await download;
    final state = container.read(modelControllerProvider).requireValue;
    expect(state.mlxPhase, DownloadPhase.paused);
    expect(state.mlxProgress, greaterThan(0));
    expect(state.mlxProgress, lessThan(1));
  });

  test('interrupted download relaunches as paused, not downloading', () async {
    final file = File('${tempDir().path}/model.json');
    await file.writeAsString(
      '{"schemaVersion": 1, "backend": "mlx", "mlxPhase": "downloading", '
      '"mlxProgress": 0.4, "turboInstalled": true, "runtime": "unloaded"}',
    );
    final repository = FakeModelManagementRepository(
      file,
      stepDelay: Duration.zero,
    );
    final state = await repository.load();
    expect(state.mlxPhase, DownloadPhase.paused);
    expect(state.mlxProgress, 0.4);
  });

  test('runtime toggle publishes the loading phase', () async {
    final container = ProviderContainer(
      overrides: [
        modelManagementRepositoryProvider.overrideWithValue(
          FakeModelManagementRepository(
            File('${tempDir().path}/model.json'),
            stepDelay: const Duration(milliseconds: 5),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(modelControllerProvider.future);
    final controller = container.read(modelControllerProvider.notifier);

    final phases = <RuntimePhase>[];
    final subscription = container.listen(modelControllerProvider, (
      previous,
      next,
    ) {
      if (next.hasValue) phases.add(next.requireValue.runtime);
    });
    addTearDown(subscription.close);

    await controller.toggleRuntime(); // loaded -> unloaded
    await controller.toggleRuntime(); // unloaded -> loading -> loaded
    expect(phases, [
      RuntimePhase.unloaded,
      RuntimePhase.loading,
      RuntimePhase.loaded,
    ]);
  });

  test('busy model controller ignores overlapping operations', () async {
    final container = ProviderContainer(
      overrides: [
        modelManagementRepositoryProvider.overrideWithValue(
          FakeModelManagementRepository(
            File('${tempDir().path}/model.json'),
            stepDelay: const Duration(milliseconds: 5),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(modelControllerProvider.future);
    final controller = container.read(modelControllerProvider.notifier);
    await controller.selectBackend(BackendId.mlx);

    final download = controller.downloadOrResumeMlx();
    await Future<void>.delayed(const Duration(milliseconds: 8));
    await controller.toggleRuntime();
    final during = container.read(modelControllerProvider).requireValue;
    expect(during.runtime, isNot(RuntimePhase.loading));
    await controller.pauseMlx();
    await download;
    final after = container.read(modelControllerProvider).requireValue;
    expect(after.mlxPhase, DownloadPhase.paused);
  });

  test('pause mid-delay is not overwritten by a late download step', () async {
    final repository = FakeModelManagementRepository(
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
    await controller.selectBackend(BackendId.mlx);

    final download = controller.downloadOrResumeMlx();
    // Land the pause inside a step delay, not at a loop boundary.
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await controller.pauseMlx();
    await download;
    // Give any late repository write a chance to land before checking.
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // A subsequent repository operation must not resurrect "downloading".
    final after = await repository.selectBackend(BackendId.mlx);
    expect(after.mlxPhase, DownloadPhase.paused);
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
