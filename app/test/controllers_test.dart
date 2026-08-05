import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_benchmark_repository.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_settings_repository.dart';

Future<String> _fixtureAsset(String key) async =>
    '[{"role": "user", "content": "${'x' * 400}"}]';

final class _RecordingInferenceRepository implements InferenceRepository {
  SamplingOverrides? lastOverrides;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> unload() async {}

  @override
  Future<void> cancel() async {}

  @override
  Stream<InferenceEvent> generate({
    required List<Map<String, String>> context,
    required bool reasoningEnabled,
    SamplingOverrides? overrides,
  }) async* {
    lastOverrides = overrides;
    yield const AnswerDelta('ok');
    yield const CompletedEvent();
  }
}

void main() {
  ProviderContainer containerWith({Duration delay = Duration.zero}) {
    final directory = Directory.systemTemp.createTempSync(
      'golem-controller-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    return ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(
          FakeInferenceRepository(eventDelay: delay),
        ),
        benchmarkRepositoryProvider.overrideWithValue(
          FakeBenchmarkRepository(
            directory,
            readAsset: _fixtureAsset,
            delay: delay,
          ),
        ),
      ],
    );
  }

  test(
    'send, replacement, edit truncation, and persistence invariants',
    () async {
      final container = containerWith();
      addTearDown(container.dispose);
      await container.read(chatControllerProvider.future);
      final controller = container.read(chatControllerProvider.notifier);
      await controller.send('  First   prompt ');
      var state = container.read(chatControllerProvider).requireValue;
      expect(state.active!.title, 'First prompt');
      expect(state.active!.messages.map((item) => item.role), [
        MessageRole.user,
        MessageRole.assistant,
      ]);
      final userId = state.active!.messages.first.id;
      await controller.regenerate();
      state = container.read(chatControllerProvider).requireValue;
      expect(
        state.active!.messages.where(
          (item) => item.role == MessageRole.assistant,
        ),
        hasLength(1),
      );
      await controller.editAndTruncate(userId, 'Edited prompt');
      state = container.read(chatControllerProvider).requireValue;
      expect(state.active!.messages.first.text, 'Edited prompt');
      expect(state.active!.messages, hasLength(2));
    },
  );

  test('stop and new chat prevent stale generation completion', () async {
    final container = containerWith(delay: const Duration(milliseconds: 30));
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.future);
    final controller = container.read(chatControllerProvider.notifier);
    final send = controller.send('Slow prompt');
    await Future<void>.delayed(const Duration(milliseconds: 45));
    await controller.newChat();
    await send;
    final state = container.read(chatControllerProvider).requireValue;
    expect(state.active!.messages, isEmpty);
    expect(state.generation, GenerationPhase.idle);
  });

  test('failure supports discard and lifecycle cancellation', () async {
    final container = containerWith(delay: const Duration(milliseconds: 2));
    await container.read(chatControllerProvider.future);
    final controller = container.read(chatControllerProvider.notifier);
    await controller.send('[fail]');
    expect(
      container.read(chatControllerProvider).requireValue.failure,
      isNotNull,
    );
    await controller.discardFailure();
    expect(container.read(chatControllerProvider).requireValue.failure, isNull);
    unawaited(controller.send('dispose while streaming'));
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('benchmark controller cancellation prevents stale result', () async {
    final container = containerWith(delay: const Duration(milliseconds: 30));
    addTearDown(container.dispose);
    final controller = container.read(benchmarkControllerProvider.notifier);
    unawaited(controller.run());
    await Future<void>.delayed(const Duration(milliseconds: 3));
    controller.stop();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(container.read(benchmarkControllerProvider).result, isNull);
  });

  test('chat generation passes the active profile overrides', () async {
    final inference = _RecordingInferenceRepository();
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(inference),
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(
            const GenerationSettings().withModel(
              // The default backend signal's profile key.
              'gemma4',
              const SamplingOverrides(maxTokens: 64, temperature: 1.4),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.future);
    await container.read(chatControllerProvider.notifier).send('Hello');
    expect(inference.lastOverrides?.maxTokens, 64);
    expect(inference.lastOverrides?.temperature, 1.4);
  });

  test(
    'settings controller persists updates and reset drops the entry',
    () async {
      final repository = InMemorySettingsRepository();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);

      await controller.updateModel(
        'gemma4',
        const SamplingOverrides(maxTokens: 64, temperature: 1.4),
      );
      // Optimistic state and the persisted snapshot agree.
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .overridesFor('gemma4')
            .maxTokens,
        64,
      );
      expect(repository.settings.overridesFor('gemma4').temperature, 1.4);
      expect(repository.saves, 1);

      await controller.resetModel('gemma4');
      expect(repository.settings.models, isEmpty);
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .overridesFor('gemma4')
            .isEmpty,
        isTrue,
      );
    },
  );
}
