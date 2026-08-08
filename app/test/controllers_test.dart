import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_benchmark_repository.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/core/repositories/fake_model_management_repository.dart';
import 'package:golem_flutter/core/services/cache_probe.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_preferences_repository.dart';
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
  String? lastModelKey;
  String? lastPrepareModelKey;
  String? lastSystemPrompt;
  int prepares = 0;
  int unloads = 0;
  final ValueNotifier<String?> _residentKey = ValueNotifier<String?>(null);

  @override
  ValueListenable<String?> get residentModelKey => _residentKey;

  @override
  Future<void> prepare({String? modelKey}) async {
    prepares++;
    lastPrepareModelKey = modelKey;
    if (failPrepare) throw StateError('injected prepare failure');
    if (modelKey != null) _residentKey.value = modelKey;
  }

  @override
  Future<void> unload() async {
    unloads++;
    if (failUnload) throw StateError('injected unload failure');
  }

  @override
  Future<void> cancel() async {}

  /// When set, generate parks mid-stream until completed — for tests that
  /// need a deterministically in-flight generation.
  Completer<void>? generateGate;

  @override
  Stream<InferenceEvent> generate({
    required List<Map<String, String>> context,
    required bool reasoningEnabled,
    SamplingOverrides? overrides,
    String? modelKey,
    String? systemPrompt,
  }) async* {
    lastOverrides = overrides;
    lastModelKey = modelKey;
    lastSystemPrompt = systemPrompt;
    yield const AnswerDelta('ok');
    final gate = generateGate;
    if (gate != null) await gate.future;
    yield const CompletedEvent();
  }
}

final class _CountingCacheProbe implements CacheProbe {
  int calls = 0;

  @override
  Future<int> sizeBytes() async {
    calls++;
    return 500;
  }

  @override
  Future<void> clear() async {}
}

final class _StaticState implements ModelManagementRepository {
  const _StaticState(this.state);
  final ModelState state;

  @override
  Future<ModelState> load() async => state;
  @override
  Future<ModelState> recordRuntime(RuntimePhase phase, {String? failure}) =>
      Future.value(state);
  @override
  Stream<ModelState> download(String artifactKey) => Stream.value(state);
  @override
  Future<ModelState> pause(String artifactKey) async => state;
  @override
  Future<ModelState> cancel(String artifactKey) async => state;
  @override
  Future<ModelState> delete(String artifactKey) async => state;
  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => state;
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

  test(
    'the response style layers under manual overrides at generate',
    () async {
      final inference = _RecordingInferenceRepository();
      final container = ProviderContainer(
        overrides: [
          chatHistoryRepositoryProvider.overrideWithValue(
            InMemoryChatHistoryRepository(),
          ),
          inferenceRepositoryProvider.overrideWithValue(inference),
          inferenceBackendProvider.overrideWithValue(
            const InferenceBackendConfig(
              kind: InferenceBackendKind.fake,
              profileKey: 'gemma4',
            ),
          ),
          // Precise style (temp 0.3, topP 0.9) with a hand-set temperature:
          // the manual knob must win, the untouched one must follow the
          // style, and the system prompt must ride along.
          preferencesRepositoryProvider.overrideWithValue(
            InMemoryPreferencesRepository(
              const AppPreferences(
                systemPrompt: 'Answer briefly.',
              ).withStyle('gemma4', ResponseStyle.precise),
            ),
          ),
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const GenerationSettings().withModel(
                'gemma4',
                const SamplingOverrides(temperature: 0.55),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(chatControllerProvider.future);
      await container.read(chatControllerProvider.notifier).send('Hello');
      expect(inference.lastOverrides?.temperature, 0.55);
      expect(inference.lastOverrides?.topP, 0.9);
      expect(inference.lastSystemPrompt, 'Answer briefly.');
    },
  );

  test(
    'history off stops persisting, wipes disk, and re-saves on enable',
    () async {
      final history = InMemoryChatHistoryRepository();
      final container = ProviderContainer(
        overrides: [
          chatHistoryRepositoryProvider.overrideWithValue(history),
          inferenceRepositoryProvider.overrideWithValue(
            FakeInferenceRepository(eventDelay: Duration.zero),
          ),
          preferencesRepositoryProvider.overrideWithValue(
            InMemoryPreferencesRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(chatControllerProvider.future);
      await container.read(preferencesControllerProvider.future);
      final chat = container.read(chatControllerProvider.notifier);
      final preferences = container.read(
        preferencesControllerProvider.notifier,
      );

      await chat.send('Keep this one');
      expect(history.snapshot.conversations, hasLength(1));

      // Off: the disk copy empties immediately, and later sends stay
      // memory-only.
      await preferences.setSaveHistory(false);
      expect(history.snapshot.conversations, isEmpty);
      await chat.newChat();
      await chat.send('Memory only');
      expect(history.snapshot.conversations, isEmpty);
      expect(
        container.read(chatControllerProvider).requireValue.conversations,
        hasLength(2),
        reason: 'in-memory chats survive the session',
      );

      // Back on: whatever is in memory re-saves at once.
      await preferences.setSaveHistory(true);
      expect(history.snapshot.conversations, hasLength(2));
    },
  );

  test('delete-all wipes memory and disk even with history off', () async {
    final history = InMemoryChatHistoryRepository();
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(history),
        inferenceRepositoryProvider.overrideWithValue(
          FakeInferenceRepository(eventDelay: Duration.zero),
        ),
        preferencesRepositoryProvider.overrideWithValue(
          InMemoryPreferencesRepository(
            const AppPreferences(saveHistory: false),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.future);
    final chat = container.read(chatControllerProvider.notifier);
    await chat.send('Doomed');
    final exported = chat.exportAllChats();
    expect(exported, contains('Doomed'));
    expect(exported, contains('"schemaVersion"'));

    await chat.deleteAllChats();
    expect(
      container.read(chatControllerProvider).requireValue.conversations,
      isEmpty,
    );
    expect(history.snapshot.conversations, isEmpty);
  });

  test(
    'a custom repository registers, simulates, and survives relaunch',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'golem-custom-model-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final stateFile = File('${directory.path}/model.json');
      final preferencesRepository = InMemoryPreferencesRepository();
      ProviderContainer build(List<ModelCatalogEntry> catalog) =>
          ProviderContainer(
            overrides: [
              preferencesRepositoryProvider.overrideWithValue(
                preferencesRepository,
              ),
              modelCatalogEntriesProvider.overrideWithValue(modelCatalog),
              modelManagementRepositoryProvider.overrideWithValue(
                FakeModelManagementRepository(
                  stateFile,
                  catalog: catalog,
                  stepDelay: Duration.zero,
                ),
              ),
            ],
          );

      const spec = CustomModelSpec(
        repository: 'mlx-community/tiny-test',
        engine: ModelEngine.mlx,
      );
      final container = build(modelCatalog);
      addTearDown(container.dispose);
      await container.read(modelControllerProvider.future);
      await container.read(preferencesControllerProvider.future);
      await container
          .read(preferencesControllerProvider.notifier)
          .addCustomModel(spec);

      // The derived entry joins the effective catalog and can download.
      final effective = container.read(effectiveModelCatalogProvider);
      expect(effective.map((e) => e.key), contains(spec.key));
      await container.read(modelControllerProvider.notifier).download(spec.key);
      final state = container.read(modelControllerProvider).requireValue;
      expect(state.statusOf(spec.key).phase, ArtifactPhase.installed);
      expect(
        state.statusOf(spec.key).downloadedBytes,
        spec.toCatalogEntry().totalBytes,
      );

      // Relaunch: the composition root merges persisted specs back into the
      // repository catalog, so the installed state survives.
      final merged = [...modelCatalog, spec.toCatalogEntry()];
      final relaunched = build(merged);
      addTearDown(relaunched.dispose);
      final reloaded = await relaunched.read(modelControllerProvider.future);
      expect(reloaded.statusOf(spec.key).phase, ArtifactPhase.installed);
    },
  );

  test('storage probing keys on message counts, not chat identity', () async {
    final cache = _CountingCacheProbe();
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(
          FakeInferenceRepository(eventDelay: Duration.zero),
        ),
        preferencesRepositoryProvider.overrideWithValue(
          InMemoryPreferencesRepository(),
        ),
        modelManagementRepositoryProvider.overrideWithValue(
          const _StaticState(ModelState()),
        ),
        cacheProbeProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(storageBreakdownProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(chatControllerProvider.future);
    await container.read(storageBreakdownProvider.future);
    final baseline = cache.calls;

    // Metadata-only state reassignments (what every streaming delta also
    // is, shape-wise) must not re-run the disk probes: the drawer meter
    // keeps this provider listened at all times.
    final chat = container.read(chatControllerProvider.notifier);
    await chat.send('Count me');
    await container.read(storageBreakdownProvider.future);
    final afterSend = cache.calls;
    expect(afterSend, greaterThan(baseline), reason: 'new messages re-probe');
    // The actual guard for the per-token regression: one send streams
    // dozens of deltas, but only the message-count edges may re-probe.
    // Reinstating a raw chat-state watch blows straight past this cap.
    expect(
      afterSend - baseline,
      lessThanOrEqualTo(4),
      reason: 'a send must re-probe per message added, not per token',
    );
    final active = container
        .read(chatControllerProvider)
        .requireValue
        .active!
        .id;
    await chat.togglePinned(active);
    await chat.renameConversation(active, 'Same counts');
    await container.read(storageBreakdownProvider.future);
    expect(
      cache.calls,
      afterSend,
      reason: 'identity-only chat changes must not re-run disk probes',
    );
  });

  test('storage breakdown sums buckets and tracks chat size', () async {
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(
          FakeInferenceRepository(eventDelay: Duration.zero),
        ),
        preferencesRepositoryProvider.overrideWithValue(
          InMemoryPreferencesRepository(),
        ),
        modelManagementRepositoryProvider.overrideWithValue(
          _StaticState(
            const ModelState(
              artifacts: {
                'gemma4-mlx': ArtifactStatus(
                  phase: ArtifactPhase.installed,
                  downloadedBytes: 1000,
                ),
              },
            ),
          ),
        ),
        cacheProbeProvider.overrideWithValue(FakeCacheProbe(sizeBytes: 500)),
      ],
    );
    addTearDown(container.dispose);
    // An active subscription, as the Storage screen would hold: the
    // breakdown watches chat state, and an invalidation that lands
    // mid-computation only recomputes for a live listener.
    final subscription = container.listen(storageBreakdownProvider, (_, _) {});
    addTearDown(subscription.close);
    final before = await container.read(storageBreakdownProvider.future);
    expect(before.modelsBytes, 1000);
    expect(before.cacheBytes, 500);
    expect(before.chatsBytes, greaterThan(0));
    expect(before.usedBytes, before.modelsBytes + before.chatsBytes + 500);
    // The free/total seams are unwired here — the figures must be null,
    // never invented.
    expect(before.freeBytes, isNull);
    expect(before.totalBytes, isNull);

    await container.read(chatControllerProvider.notifier).send('Grow the file');
    final after = await container.read(storageBreakdownProvider.future);
    expect(after.chatsBytes, greaterThan(before.chatsBytes));
  });

  test('pin, message delete, and branch round-trip and persist', () async {
    final container = containerWith();
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.future);
    final controller = container.read(chatControllerProvider.notifier);
    await controller.send('First prompt');
    var state = container.read(chatControllerProvider).requireValue;
    final originalId = state.active!.id;
    final userId = state.active!.messages.first.id;
    final assistantId = state.active!.messages.last.id;

    await controller.togglePinned(originalId);
    state = container.read(chatControllerProvider).requireValue;
    expect(state.active!.pinned, isTrue);

    await controller.branchFrom(userId);
    state = container.read(chatControllerProvider).requireValue;
    expect(state.conversations, hasLength(2));
    expect(state.active!.id, isNot(originalId));
    expect(state.active!.messages.map((m) => m.id), [userId]);
    expect(state.active!.pinned, isFalse);
    final original = state.conversations.singleWhere((c) => c.id == originalId);
    expect(original.messages, hasLength(2), reason: 'the source is intact');

    // Unknown ids no-op instead of corrupting state.
    await controller.branchFrom('missing');
    expect(
      container.read(chatControllerProvider).requireValue.conversations,
      hasLength(2),
    );

    await controller.selectConversation(originalId);
    await controller.deleteMessage(assistantId);
    state = container.read(chatControllerProvider).requireValue;
    expect(state.active!.messages.map((m) => m.id), [userId]);
  });

  test('preparation and generation address the same model', () async {
    final inference = _RecordingInferenceRepository();
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(inference),
      ],
    );
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.future);
    final controller = container.read(chatControllerProvider.notifier);
    await controller.send('Hello');
    expect(inference.lastModelKey, isNull);
    expect(inference.lastPrepareModelKey, isNull);

    final activeId = container
        .read(chatControllerProvider)
        .requireValue
        .active!
        .id;
    await controller.setConversationModel(activeId, 'qwen35-gguf');
    expect(
      container.read(chatControllerProvider).requireValue.active!.modelKey,
      'qwen35-gguf',
    );
    await controller.regenerate();
    expect(inference.lastModelKey, 'qwen35-gguf');
    // Preparation must address the same model the stream will: a keyless
    // prepare here would load the boot artifact and generate() would then
    // swap it out, loading twice for one answer.
    expect(inference.lastPrepareModelKey, 'qwen35-gguf');
  });

  test('the OOM injection surfaces the design failure copy', () async {
    final container = containerWith();
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.future);
    final controller = container.read(chatControllerProvider.notifier);
    await controller.send('please [oom] now');
    final state = container.read(chatControllerProvider).requireValue;
    expect(state.generation, GenerationPhase.failed);
    expect(
      state.failure?.message,
      'Ran out of memory at 4,096 tokens. Lower the context length or '
      'pick a smaller model.',
    );
    expect(state.failure?.kind, ChatFailureKind.outOfMemory);
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
    expect(state.failure?.kind, ChatFailureKind.missingModel);
    expect(state.failure?.artifactKey, 'test-mlx');
    expect(state.failure?.message, contains('not downloaded'));
    // The engine was never touched: no hang-like prepare, no cryptic error.
    expect(inference.prepares, 0);
    // Discard clears the typed failure whole.
    await container.read(chatControllerProvider.notifier).discardFailure();
    expect(container.read(chatControllerProvider).requireValue.failure, isNull);
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

  test(
    'memory pressure unloads an idle engine and records the phase',
    () async {
      final directory = Directory.systemTemp.createTempSync('golem-pressure-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final inference = _RecordingInferenceRepository();
      final container = ProviderContainer(
        overrides: [
          chatHistoryRepositoryProvider.overrideWithValue(
            InMemoryChatHistoryRepository(),
          ),
          inferenceRepositoryProvider.overrideWithValue(inference),
          modelManagementRepositoryProvider.overrideWithValue(
            fakeModels(directory),
          ),
        ],
      );
      addTearDown(container.dispose);
      await installActiveModel(container);
      await container.read(chatControllerProvider.future);
      final controller = container.read(modelControllerProvider.notifier);
      await controller.toggleRuntime();
      expect(
        container.read(modelControllerProvider).requireValue.runtime,
        RuntimePhase.loaded,
      );

      await controller.releaseEngineWhileInactive();
      expect(inference.unloads, 1);
      expect(
        container.read(modelControllerProvider).requireValue.runtime,
        RuntimePhase.unloaded,
      );
      // Persisted too, so Settings stays honest after a relaunch.
      expect(
        (await fakeModels(directory).load()).runtime,
        RuntimePhase.unloaded,
      );

      // A second signal on an already-empty engine is a no-op.
      await controller.releaseEngineWhileInactive();
      expect(inference.unloads, 1);
    },
  );

  test('memory pressure never interrupts an active generation', () async {
    final directory = Directory.systemTemp.createTempSync('golem-pressure2-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final inference = _RecordingInferenceRepository();
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(inference),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
      ],
    );
    addTearDown(container.dispose);
    await installActiveModel(container);
    await container.read(chatControllerProvider.future);
    final models = container.read(modelControllerProvider.notifier);
    await models.toggleRuntime();

    // Park the generation mid-stream so the chat is deterministically
    // non-idle when the signal arrives.
    inference.generateGate = Completer<void>();
    final chat = container.read(chatControllerProvider.notifier);
    final send = chat.send('slow question');
    while (container.read(chatControllerProvider).requireValue.generation ==
        GenerationPhase.idle) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await models.releaseEngineWhileInactive();
    expect(inference.unloads, 0, reason: 'a visible stream must survive');
    inference.generateGate!.complete();
    await send;

    await models.releaseEngineWhileInactive();
    expect(inference.unloads, 1, reason: 'idle again: the signal applies');
  });

  test('toggling without an installed model refuses per backend', () async {
    final directory = Directory.systemTemp.createTempSync('golem-refuse-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final inference = _RecordingInferenceRepository();

    // Fake backend copy: nothing installed yet, fake wording.
    final fakeContainer = ProviderContainer(
      overrides: [
        inferenceRepositoryProvider.overrideWithValue(inference),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
      ],
    );
    addTearDown(fakeContainer.dispose);
    await fakeContainer.read(modelControllerProvider.future);
    await fakeContainer.read(modelControllerProvider.notifier).toggleRuntime();
    final refused = fakeContainer.read(modelControllerProvider).requireValue;
    expect(refused.runtime, RuntimePhase.failed);
    expect(refused.failure, 'Install the selected simulated model first.');
    expect(inference.prepares, 0, reason: 'the engine is never touched');

    // Real backend copy: the same refusal names the download instead.
    final realContainer = ProviderContainer(
      overrides: [
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
    addTearDown(realContainer.dispose);
    await realContainer.read(modelControllerProvider.future);
    await realContainer.read(modelControllerProvider.notifier).toggleRuntime();
    final realRefused = realContainer
        .read(modelControllerProvider)
        .requireValue;
    expect(realRefused.runtime, RuntimePhase.failed);
    expect(realRefused.failure, 'Download and install the active model first.');
    expect(inference.prepares, 0);
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
    expect(state.failure, isNull);
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
    // The persist layer never recorded unloaded for an engine still
    // holding weights. (This is the fake's simulated phase; the real
    // repository additionally reconciles any persisted loaded back to
    // unloaded on relaunch — covered in its own suite.)
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
