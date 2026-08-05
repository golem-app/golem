import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_benchmark_repository.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/core/repositories/fake_model_management_repository.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_settings_repository.dart';

Future<String> _fixtureAsset(String key) async =>
    '[{"role": "user", "content": "${'x' * 400}"}]';

final class _RecordingInferenceRepository implements InferenceRepository {
  _RecordingInferenceRepository({
    this.failPrepare = false,
    this.failUnload = false,
  });

  final bool failPrepare;
  final bool failUnload;
  SamplingOverrides? lastOverrides;
  int prepares = 0;
  int unloads = 0;

  @override
  Future<void> prepare() async {
    prepares++;
    if (failPrepare) throw StateError('injected prepare failure');
  }

  @override
  Future<void> unload() async {
    unloads++;
    if (failUnload) throw StateError('injected unload failure');
  }

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
        // A non-default profile key, so this test can only pass if the
        // controller looks the profile up through the backend signal —
        // seeding the fake default's gemma4 would pass with a hardcoded
        // key. Fake kind keeps the lazy-load reflection out of scope here.
        inferenceBackendProvider.overrideWithValue(
          const InferenceBackendConfig(
            kind: InferenceBackendKind.fake,
            profileKey: 'qwen35',
          ),
        ),
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(
            const GenerationSettings()
                .withModel(
                  'qwen35',
                  const SamplingOverrides(maxTokens: 64, temperature: 1.4),
                )
                .withModel('gemma4', const SamplingOverrides(maxTokens: 999)),
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

  FakeModelManagementRepository fakeModels(Directory directory) =>
      FakeModelManagementRepository(
        File('${directory.path}/model.json'),
        catalog: const [
          ModelCatalogEntry(
            key: 'test-mlx',
            displayName: 'Test MLX',
            engine: ModelEngine.mlx,
            quantization: '4-bit',
            repository: 'example/test-mlx',
            revision: '0123456789abcdef',
            files: [
              ModelArtifactFile(
                path: 'model.safetensors',
                bytes: 12,
                sha256: 'a',
              ),
            ],
          ),
        ],
        activeArtifactKey: 'test-mlx',
        stepDelay: Duration.zero,
      );

  /// Installs the fake active artifact through the simulated download.
  Future<void> installActiveModel(ProviderContainer container) async {
    await container.read(modelControllerProvider.future);
    await container.read(modelControllerProvider.notifier).download('test-mlx');
    expect(
      container
          .read(modelControllerProvider)
          .requireValue
          .statusOf('test-mlx')
          .phase,
      ArtifactPhase.installed,
    );
  }

  test('a real backend without its model fails fast into the CTA', () async {
    final directory = Directory.systemTemp.createTempSync('golem-cta-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final inference = _RecordingInferenceRepository();
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(inference),
        inferenceBackendProvider.overrideWithValue(
          const InferenceBackendConfig(
            kind: InferenceBackendKind.llama,
            profileKey: 'gemma4',
            artifactKey: 'test-mlx',
            modelPath: 'documents:models/test-mlx',
            modelPathFromCatalog: true,
          ),
        ),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.future);
    await container.read(chatControllerProvider.notifier).send('Hello');

    final state = container.read(chatControllerProvider).requireValue;
    expect(state.generation, GenerationPhase.failed);
    expect(state.missingModelArtifactKey, 'test-mlx');
    expect(state.failure, contains('not downloaded'));
    // The engine was never touched: no hang-like prepare, no cryptic error.
    expect(inference.prepares, 0);
    // Discard clears the typed marker with the failure.
    await container.read(chatControllerProvider.notifier).discardFailure();
    expect(
      container
          .read(chatControllerProvider)
          .requireValue
          .missingModelArtifactKey,
      isNull,
    );
  });

  test('runtime toggle drives real engine load and unload', () async {
    final directory = Directory.systemTemp.createTempSync('golem-toggle-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final inference = _RecordingInferenceRepository();
    final container = ProviderContainer(
      overrides: [
        inferenceRepositoryProvider.overrideWithValue(inference),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
      ],
    );
    addTearDown(container.dispose);
    await installActiveModel(container);
    final controller = container.read(modelControllerProvider.notifier);

    await controller.toggleRuntime();
    expect(inference.prepares, 1, reason: 'loaded means the engine loaded');
    expect(
      container.read(modelControllerProvider).requireValue.runtime,
      RuntimePhase.loaded,
    );

    await controller.toggleRuntime();
    expect(inference.unloads, 1, reason: 'unloaded means the engine freed');
    expect(
      container.read(modelControllerProvider).requireValue.runtime,
      RuntimePhase.unloaded,
    );
  });

  test('an engine load failure surfaces without persisting loaded', () async {
    final directory = Directory.systemTemp.createTempSync('golem-fail-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [
        inferenceRepositoryProvider.overrideWithValue(
          _RecordingInferenceRepository(failPrepare: true),
        ),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
      ],
    );
    addTearDown(container.dispose);
    await installActiveModel(container);
    await container.read(modelControllerProvider.notifier).toggleRuntime();

    final state = container.read(modelControllerProvider).requireValue;
    expect(state.runtime, RuntimePhase.failed);
    expect(state.failure, contains('prepare failure'));
    // The failure stays in-memory: a relaunch reconciles to unloaded, and
    // loaded was never recorded for an engine that holds nothing.
    final relaunched = await fakeModels(directory).load();
    expect(relaunched.runtime, RuntimePhase.unloaded);
  });

  test('deleting the active artifact unloads the engine first', () async {
    final directory = Directory.systemTemp.createTempSync('golem-delete-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final inference = _RecordingInferenceRepository();
    final container = ProviderContainer(
      overrides: [
        inferenceRepositoryProvider.overrideWithValue(inference),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
      ],
    );
    addTearDown(container.dispose);
    await installActiveModel(container);
    await container.read(modelControllerProvider.notifier).delete('test-mlx');

    expect(inference.unloads, 1);
    expect(
      container
          .read(modelControllerProvider)
          .requireValue
          .statusOf('test-mlx')
          .phase,
      ArtifactPhase.notDownloaded,
    );
  });

  test('an operator-supplied model path is never install-gated', () async {
    final directory = Directory.systemTemp.createTempSync('golem-side-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final inference = _RecordingInferenceRepository();
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(inference),
        // Explicit GOLEM_MODEL_PATH composition: artifact key present for
        // the Settings ACTIVE badge, but the path is the operator's.
        inferenceBackendProvider.overrideWithValue(
          const InferenceBackendConfig(
            kind: InferenceBackendKind.llama,
            profileKey: 'gemma4',
            artifactKey: 'test-mlx',
            modelPath: '/sideloaded/model.gguf',
          ),
        ),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.future);
    await container.read(chatControllerProvider.notifier).send('Hello');
    final state = container.read(chatControllerProvider).requireValue;
    // The send reached the engine (the probe/sideload contract) instead of
    // dead-ending on a download it never asked for.
    expect(inference.prepares, 1);
    expect(state.missingModelArtifactKey, isNull);
    expect(state.generation, GenerationPhase.idle);
  });

  test('lazy engine load reflects into the persisted runtime phase', () async {
    final directory = Directory.systemTemp.createTempSync('golem-lazy-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final inference = _RecordingInferenceRepository();
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(inference),
        inferenceBackendProvider.overrideWithValue(
          const InferenceBackendConfig(
            kind: InferenceBackendKind.llama,
            profileKey: 'gemma4',
            artifactKey: 'test-mlx',
            modelPath: 'documents:models/test-mlx',
            modelPathFromCatalog: true,
          ),
        ),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
      ],
    );
    addTearDown(container.dispose);
    await installActiveModel(container);
    await container.read(chatControllerProvider.future);
    await container.read(chatControllerProvider.notifier).send('Hello');
    // Settings may not claim "Unloaded" while the engine holds weights:
    // the lazy prepare() records the loaded phase like the toggle does.
    expect(inference.prepares, 1);
    expect(
      container.read(modelControllerProvider).requireValue.runtime,
      RuntimePhase.loaded,
    );
  });

  test('runtime toggle refuses without the model, engine untouched', () async {
    final directory = Directory.systemTemp.createTempSync('golem-refuse-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final inference = _RecordingInferenceRepository();
    final container = ProviderContainer(
      overrides: [
        inferenceRepositoryProvider.overrideWithValue(inference),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(modelControllerProvider.future);
    await container.read(modelControllerProvider.notifier).toggleRuntime();

    final state = container.read(modelControllerProvider).requireValue;
    expect(state.runtime, RuntimePhase.failed);
    expect(state.failure, isNotNull);
    expect(inference.prepares, 0, reason: 'the engine is never touched');
  });

  test('an unload failure surfaces and keeps loaded truthful', () async {
    final directory = Directory.systemTemp.createTempSync('golem-unfail-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final inference = _RecordingInferenceRepository(failUnload: true);
    final container = ProviderContainer(
      overrides: [
        inferenceRepositoryProvider.overrideWithValue(inference),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
      ],
    );
    addTearDown(container.dispose);
    await installActiveModel(container);
    final controller = container.read(modelControllerProvider.notifier);
    await controller.toggleRuntime();
    expect(
      container.read(modelControllerProvider).requireValue.runtime,
      RuntimePhase.loaded,
    );

    await controller.toggleRuntime();
    final state = container.read(modelControllerProvider).requireValue;
    expect(state.runtime, RuntimePhase.failed);
    expect(state.failure, contains('unload failure'));
    // unloaded was never recorded for an engine still holding weights.
    final relaunched = await fakeModels(directory).load();
    expect(relaunched.runtime, isNot(RuntimePhase.unloaded));
  });

  test('a failed unload aborts deleting the active artifact', () async {
    final directory = Directory.systemTemp.createTempSync('golem-abort-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final inference = _RecordingInferenceRepository(failUnload: true);
    final container = ProviderContainer(
      overrides: [
        inferenceRepositoryProvider.overrideWithValue(inference),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
      ],
    );
    addTearDown(container.dispose);
    await installActiveModel(container);
    await container.read(modelControllerProvider.notifier).delete('test-mlx');

    final state = container.read(modelControllerProvider).requireValue;
    expect(inference.unloads, 1);
    // Never delete a file the engine may still have mapped: the artifact
    // survives and the failure lands on its card.
    expect(state.statusOf('test-mlx').phase, ArtifactPhase.failed);
    expect(state.statusOf('test-mlx').failure, contains('unload failure'));
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
