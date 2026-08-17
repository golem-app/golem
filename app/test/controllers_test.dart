import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/device_eligibility.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/domain/response_style_mapping.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_benchmark_repository.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/core/repositories/fake_model_management_repository.dart';
import 'package:golem_flutter/core/services/cache_probe.dart';
import 'package:golem_flutter/features/benchmark/application/benchmark_providers.dart';
import 'package:golem_flutter/features/chat/application/chat_providers.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';
import 'package:golem_flutter/features/settings/application/preferences_providers.dart';
import 'package:golem_flutter/features/settings/application/settings_providers.dart';
import 'package:golem_flutter/features/settings/application/storage_providers.dart';

import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_preferences_repository.dart';
import 'support/in_memory_settings_repository.dart';
import 'support/scripted_chat_history_repository.dart';

Future<String> _fixtureAsset(String key) async =>
    '[{"role": "user", "content": "${'x' * 400}"}]';

/// One catalog behind both the fake downloader and `modelCatalogEntriesProvider`
/// in these containers: chat resolves the model a send needs through the
/// catalog, so a repository stocking keys the catalog does not carry would test
/// a world that cannot exist.
const _testCatalog = [
  ModelCatalogEntry(
    key: 'test-mlx',
    displayName: 'Test MLX',
    engine: ModelEngine.mlx,
    quantization: '4-bit',
    repository: 'example/test-mlx',
    revision: '0123456789abcdef',
    profileKey: 'gemma4',
    files: [
      ModelArtifactFile(path: 'model.safetensors', bytes: 12, sha256: 'a'),
    ],
  ),
];

FakeModelManagementRepository fakeModels(Directory directory) =>
    FakeModelManagementRepository(
      File('${directory.path}/model.json'),
      catalog: _testCatalog,
      activeArtifactKey: 'test-mlx',
      stepDelay: Duration.zero,
    );

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

final class _RecordingInferenceRepository implements InferenceRepository {
  _RecordingInferenceRepository({
    this.failPrepare = false,
    this.failUnload = false,
    this.generationFailure,
  });

  final bool failPrepare;
  final bool failUnload;
  final InferenceFailureKind? generationFailure;
  SamplingOverrides? lastOverrides;
  String? lastModelKey;
  String? lastPrepareModelKey;
  String? lastSystemPrompt;
  int prepares = 0;
  int unloads = 0;
  int releases = 0;

  @override
  void releaseEngine() => releases++;

  String initialResidentKey = 'test-mlx';

  final ValueNotifier<InferenceResidency> _residency =
      ValueNotifier<InferenceResidency>(const InferenceResidency.unloaded());

  @override
  ValueListenable<InferenceResidency> get residency => _residency;

  @override
  Future<void> prepare({String? modelKey}) async {
    prepares++;
    lastPrepareModelKey = modelKey;
    if (failPrepare) throw StateError('injected prepare failure');
    // Mirrors the real repository: a keyless prepare makes the initial
    // configuration resident, sideloaded path or not.
    _residency.value = InferenceResidency(
      loaded: true,
      catalogKey: modelKey ?? initialResidentKey,
    );
  }

  @override
  Future<void> unload() async {
    unloads++;
    if (failUnload) throw StateError('injected unload failure');
    _residency.value = const InferenceResidency.unloaded();
  }

  @override
  Future<void> cancel() async {}

  /// When set, generate parks mid-stream until completed — for tests that
  /// need a deterministically in-flight generation.
  Completer<void>? generateGate;

  @override
  Stream<InferenceEvent> generate({
    required List<PromptMessage> context,
    required bool reasoningEnabled,
    SamplingOverrides? overrides,
    String? modelKey,
    String? systemPrompt,
  }) async* {
    lastOverrides = overrides;
    lastModelKey = modelKey;
    lastSystemPrompt = systemPrompt;
    yield const AnswerDelta('ok');
    if (generationFailure case final kind?) {
      throw InferenceException(kind, 'diagnostic ${kind.name}');
    }
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

/// A repository whose [load] answer changes between calls — a stand-in for
/// reconciliation discovering a transfer the app had not known about.
final class _ReconcilingModels implements ModelManagementRepository {
  _ReconcilingModels(this.answers);

  final List<ModelState> answers;
  int loads = 0;
  final List<String> downloads = [];

  ModelState get _latest => answers[(loads - 1).clamp(0, answers.length - 1)];

  @override
  Future<ModelState> load() async =>
      answers[(loads++).clamp(0, answers.length - 1)];

  @override
  Stream<ModelState> download(String artifactKey) {
    downloads.add(artifactKey);
    return Stream.value(
      _latest.withArtifact(
        artifactKey,
        const ArtifactStatus(phase: ArtifactPhase.installed),
      ),
    );
  }

  @override
  Future<ModelState> recordRuntime(
    RuntimePhase phase, {
    String? failure,
  }) async => _latest;
  @override
  Future<ModelState> pause(String artifactKey) async => _latest;
  @override
  Future<ModelState> cancel(String artifactKey) async => _latest;
  @override
  Future<ModelState> delete(String artifactKey) async => _latest;
  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => _latest;
}

/// Loads once, then fails — a store that becomes unreadable between passes.
final class _ThrowingOnSecondLoad implements ModelManagementRepository {
  int _loads = 0;
  static final _installed = const ModelState().withArtifact(
    'gemma4-gguf',
    const ArtifactStatus(phase: ArtifactPhase.installed),
  );

  @override
  Future<ModelState> load() async {
    if (_loads++ > 0) throw const FormatException('unreadable');
    return _installed;
  }

  @override
  Stream<ModelState> download(String artifactKey) => Stream.value(_installed);
  @override
  Future<ModelState> recordRuntime(
    RuntimePhase phase, {
    String? failure,
  }) async => _installed;
  @override
  Future<ModelState> pause(String artifactKey) async => _installed;
  @override
  Future<ModelState> cancel(String artifactKey) async => _installed;
  @override
  Future<ModelState> delete(String artifactKey) async => _installed;
  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => _installed;
}

/// Records which transfer commands reach the repository, for the refusal path.
final class _TransferRecorder implements ModelManagementRepository {
  _TransferRecorder(this._state);

  ModelState _state;
  final List<String> downloads = [];
  final List<String> cancels = [];

  @override
  Future<ModelState> load() async => _state;

  @override
  Stream<ModelState> download(String artifactKey) {
    downloads.add(artifactKey);
    return Stream.value(_state);
  }

  @override
  Future<ModelState> cancel(String artifactKey) async {
    cancels.add(artifactKey);
    _state = _state.withArtifact(
      artifactKey,
      const ArtifactStatus(phase: ArtifactPhase.notDownloaded),
    );
    return _state;
  }

  @override
  Future<ModelState> recordRuntime(
    RuntimePhase phase, {
    String? failure,
  }) async => _state;
  @override
  Future<ModelState> pause(String artifactKey) async => _state;
  @override
  Future<ModelState> delete(String artifactKey) async => _state;
  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => _state;
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
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
        preferencesRepositoryProvider.overrideWithValue(
          InMemoryPreferencesRepository(),
        ),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
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

  group('chat persistence recovery', () {
    ProviderContainer persistenceContainer(
      ChatHistoryRepository history, {
      InMemoryPreferencesRepository? preferences,
      Duration inferenceDelay = Duration.zero,
    }) {
      final container = ProviderContainer(
        overrides: [
          chatHistoryRepositoryProvider.overrideWithValue(history),
          preferencesRepositoryProvider.overrideWithValue(
            preferences ?? InMemoryPreferencesRepository(),
          ),
          inferenceRepositoryProvider.overrideWithValue(
            FakeInferenceRepository(eventDelay: inferenceDelay),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('save failures keep the turn and do not block generation', () async {
      final history = InMemoryChatHistoryRepository()..failingSaves = 3;
      final container = persistenceContainer(history);
      await container.read(chatControllerProvider.future);

      await container.read(chatControllerProvider.notifier).send('Keep me');

      final chat = container.read(chatControllerProvider).requireValue;
      expect(chat.active!.messages.map((message) => message.role), [
        MessageRole.user,
        MessageRole.assistant,
      ]);
      expect(chat.generation, GenerationPhase.idle);
      expect(chat.persistencePhase, ChatPersistencePhase.failed);
      expect(history.saveCalls, 3);
      expect(history.snapshot.conversations, isEmpty);
    });

    test('only the latest overlapping completion changes status', () async {
      final newerSuccess = ScriptedChatHistoryRepository();
      final firstContainer = persistenceContainer(newerSuccess);
      await firstContainer.read(chatControllerProvider.future);
      final firstController = firstContainer.read(
        chatControllerProvider.notifier,
      );

      final oldFailure = firstController.newChat();
      final id = firstContainer
          .read(chatControllerProvider)
          .requireValue
          .active!
          .id;
      final latestSuccess = firstController.renameConversation(id, 'Latest');
      expect(newerSuccess.saves, hasLength(2));

      newerSuccess.saves[1].succeed();
      await latestSuccess;
      newerSuccess.saves[0].fail();
      await oldFailure;
      expect(
        firstContainer
            .read(chatControllerProvider)
            .requireValue
            .persistencePhase,
        ChatPersistencePhase.idle,
      );

      final newerFailure = ScriptedChatHistoryRepository();
      final secondContainer = persistenceContainer(newerFailure);
      await secondContainer.read(chatControllerProvider.future);
      final secondController = secondContainer.read(
        chatControllerProvider.notifier,
      );
      final oldSuccess = secondController.newChat();
      final secondId = secondContainer
          .read(chatControllerProvider)
          .requireValue
          .active!
          .id;
      final latestFailure = secondController.renameConversation(
        secondId,
        'Newest',
      );
      expect(newerFailure.saves, hasLength(2));

      newerFailure.saves[1].fail();
      await latestFailure;
      newerFailure.saves[0].succeed();
      await oldSuccess;
      expect(
        secondContainer
            .read(chatControllerProvider)
            .requireValue
            .persistencePhase,
        ChatPersistencePhase.failed,
      );
    });

    test('retry commits the latest live snapshot and clears status', () async {
      final history = InMemoryChatHistoryRepository()..failingSaves = 2;
      final container = persistenceContainer(history);
      await container.read(chatControllerProvider.future);
      final controller = container.read(chatControllerProvider.notifier);

      await controller.newChat();
      final id = container.read(chatControllerProvider).requireValue.active!.id;
      await controller.renameConversation(id, 'Latest title');
      expect(
        container.read(chatControllerProvider).requireValue.persistencePhase,
        ChatPersistencePhase.failed,
      );

      await controller.retryPersistence();

      expect(history.snapshot.conversations.single.title, 'Latest title');
      expect(
        container.read(chatControllerProvider).requireValue.persistencePhase,
        ChatPersistencePhase.idle,
      );
    });

    test('history off stays silent and re-enable failure is visible', () async {
      final history = InMemoryChatHistoryRepository();
      final preferences = InMemoryPreferencesRepository(
        const AppPreferences(saveHistory: false),
      );
      final container = persistenceContainer(history, preferences: preferences);
      await container.read(chatControllerProvider.future);
      await container.read(preferencesControllerProvider.future);

      await container.read(chatControllerProvider.notifier).send('Memory only');
      expect(history.saveCalls, 0);
      expect(
        container.read(chatControllerProvider).requireValue.persistencePhase,
        ChatPersistencePhase.idle,
      );

      history.failingSaves = 1;
      expect(
        await container
            .read(preferencesControllerProvider.notifier)
            .setSaveHistory(true),
        isTrue,
      );
      expect(history.saveCalls, 1);
      expect(
        container.read(chatControllerProvider).requireValue.persistencePhase,
        ChatPersistencePhase.failed,
      );
    });

    test('fire-and-forget Stop contains a typed write failure', () async {
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        final history = InMemoryChatHistoryRepository();
        final container = persistenceContainer(
          history,
          inferenceDelay: const Duration(milliseconds: 20),
        );
        await container.read(chatControllerProvider.future);
        final controller = container.read(chatControllerProvider.notifier);
        final send = controller.send('Stop this');

        while (container.read(chatControllerProvider).requireValue.generation ==
            GenerationPhase.idle) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        history.failingSaves = 1;
        controller.stop();
        await send;
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(chatControllerProvider).requireValue.persistencePhase,
          ChatPersistencePhase.failed,
        );
      }, (error, stackTrace) => uncaught.add(error));
      expect(uncaught, isEmpty);
    });

    test('failed delete-all lets an in-flight retry settle status', () async {
      final history = ScriptedChatHistoryRepository();
      final container = persistenceContainer(history);
      await container.read(chatControllerProvider.future);
      final controller = container.read(chatControllerProvider.notifier);

      final initialSave = controller.newChat();
      history.saves.single.fail();
      await initialSave;
      expect(
        container.read(chatControllerProvider).requireValue.persistencePhase,
        ChatPersistencePhase.failed,
      );

      final retry = controller.retryPersistence();
      expect(history.saves, hasLength(2));
      expect(
        container.read(chatControllerProvider).requireValue.persistencePhase,
        ChatPersistencePhase.retrying,
      );
      final delete = controller.deleteAllChats();
      expect(history.saves, hasLength(3));
      history.saves[2].fail();
      expect(await delete, isFalse);

      history.saves[1].fail();
      await retry;
      expect(
        container.read(chatControllerProvider).requireValue.persistencePhase,
        ChatPersistencePhase.failed,
      );
      expect(
        container.read(chatControllerProvider).requireValue.conversations,
        isNotEmpty,
      );
    });

    test('failed delete-all does not hide an in-flight save failure', () async {
      final history = ScriptedChatHistoryRepository();
      final container = persistenceContainer(history);
      await container.read(chatControllerProvider.future);
      final controller = container.read(chatControllerProvider.notifier);

      final save = controller.newChat();
      expect(history.saves, hasLength(1));
      final delete = controller.deleteAllChats();
      expect(history.saves, hasLength(2));
      history.saves[1].fail();
      expect(await delete, isFalse);

      history.saves[0].fail();
      await save;
      expect(
        container.read(chatControllerProvider).requireValue.persistencePhase,
        ChatPersistencePhase.failed,
      );
      expect(
        container.read(chatControllerProvider).requireValue.conversations,
        isNotEmpty,
      );
    });
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

  group('download reconciliation', () {
    ProviderContainer withModels(ModelManagementRepository models) {
      final container = ProviderContainer(
        overrides: [
          chatHistoryRepositoryProvider.overrideWithValue(
            InMemoryChatHistoryRepository(),
          ),
          modelManagementRepositoryProvider.overrideWithValue(models),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    // The headline path: the app relaunches believing nothing is running, and
    // reconciliation finds the OS still moving bytes.
    test('a transfer found on return is re-attached, not restarted', () async {
      final models = _ReconcilingModels([
        const ModelState(),
        const ModelState().withArtifact(
          'gemma4-gguf',
          const ArtifactStatus(phase: ArtifactPhase.downloading),
        ),
      ]);
      final container = withModels(models);
      await container.read(modelControllerProvider.future);
      expect(models.downloads, isEmpty);

      await container
          .read(modelControllerProvider.notifier)
          .reconcileDownloads();

      // Exactly one attach, and the phase follows it through to installed.
      expect(models.downloads, ['gemma4-gguf']);
      final state = container.read(modelControllerProvider).value!;
      expect(state.statusOf('gemma4-gguf').phase, ArtifactPhase.installed);
    });

    test('nothing in flight attaches to nothing', () async {
      final models = _ReconcilingModels([const ModelState()]);
      final container = withModels(models);
      await container.read(modelControllerProvider.future);
      await container
          .read(modelControllerProvider.notifier)
          .reconcileDownloads();
      expect(models.downloads, isEmpty);
    });

    // Reconciliation is a repair pass; a failure in it must never replace a
    // usable snapshot with an error screen.
    test('a failed reconcile leaves the last good snapshot alone', () async {
      final container = withModels(_ThrowingOnSecondLoad());
      final first = await container.read(modelControllerProvider.future);
      expect(first.statusOf('gemma4-gguf').phase, ArtifactPhase.installed);

      await container
          .read(modelControllerProvider.notifier)
          .reconcileDownloads();

      final after = container.read(modelControllerProvider);
      expect(after.hasError, isFalse);
      expect(
        after.value!.statusOf('gemma4-gguf').phase,
        ArtifactPhase.installed,
      );
    });
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
    'switching a chat\'s model switches which profile\'s sampling applies',
    () async {
      // The defect this pins: sampling used to follow the build's boot profile,
      // so a chat switched from Gemma to Qwen silently kept Gemma's numbers.
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
          modelCatalogEntriesProvider.overrideWithValue(modelCatalog),
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const GenerationSettings()
                  .withModel('gemma4', const SamplingOverrides(maxTokens: 111))
                  .withModel('qwen35', const SamplingOverrides(maxTokens: 222)),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(chatControllerProvider.future);
      final controller = container.read(chatControllerProvider.notifier);
      await controller.send('Hello');
      expect(inference.lastOverrides?.maxTokens, 111);

      // gemma4-gguf → qwen35-gguf: a profile change, not merely a model change.
      final id = container.read(chatControllerProvider).requireValue.active!.id;
      await controller.setConversationModel(id, 'qwen35-gguf');
      await controller.send('Again');
      expect(inference.lastOverrides?.maxTokens, 222);
      expect(inference.lastModelKey, 'qwen35-gguf');
    },
  );

  test('a real backend refuses a model it could not load', () async {
    final directory = Directory.systemTemp.createTempSync('golem-select-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(
          _RecordingInferenceRepository(),
        ),
        inferenceBackendProvider.overrideWithValue(
          const InferenceBackendConfig(
            kind: InferenceBackendKind.mlx,
            profileKey: 'gemma4',
            artifactKey: 'test-mlx',
            modelPath: 'documents:models/test-mlx',
            modelPathFromCatalog: true,
          ),
        ),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
      ],
    );
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.future);
    final controller = container.read(chatControllerProvider.notifier);
    await controller.send('Hello');
    final id = container.read(chatControllerProvider).requireValue.active!.id;
    // The send failed into the missing-model banner, which is the state a user
    // recovers from by picking a model.
    expect(
      container.read(chatControllerProvider).requireValue.failure?.kind,
      ChatFailureKind.missingModel,
    );

    // Not installed yet: the choice is refused, so no label can name it. This
    // is the invariant every "follow the selection" label depends on.
    await controller.setConversationModel(id, 'test-mlx');
    expect(
      container.read(chatControllerProvider).requireValue.active!.modelKey,
      isNull,
    );

    await installActiveModel(container);
    await controller.setConversationModel(id, 'test-mlx');
    final state = container.read(chatControllerProvider).requireValue;
    expect(state.active!.modelKey, 'test-mlx');
    // Switching clears the stale failure, so the banner does not outlive the
    // model it was about.
    expect(state.failure, isNull);
    expect(state.generation, GenerationPhase.idle);
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
    'fallback generation uses the fallback model sampling profile',
    () async {
      final inference = _RecordingInferenceRepository();
      final history = InMemoryChatHistoryRepository(
        ChatHistorySnapshot(
          activeId: 'stale-gemma-chat',
          conversations: [
            ChatConversation(
              id: 'stale-gemma-chat',
              title: 'Stale Gemma chat',
              messages: const [],
              updatedAt: DateTime.utc(2026, 8, 13),
              modelKey: 'gemma4-gguf',
            ),
          ],
        ),
      );
      final container = ProviderContainer(
        overrides: [
          chatHistoryRepositoryProvider.overrideWithValue(history),
          inferenceRepositoryProvider.overrideWithValue(inference),
          inferenceBackendProvider.overrideWithValue(
            const InferenceBackendConfig(
              kind: InferenceBackendKind.mlx,
              profileKey: 'gemma4',
              artifactKey: 'gemma4-mlx',
              modelPath: 'documents:models/gemma4-mlx',
              modelPathFromCatalog: true,
            ),
          ),
          deviceEligibilityProvider.overrideWithValue(
            const DeviceEligibility(tier: DeviceTier.preferred),
          ),
          modelCatalogEntriesProvider.overrideWithValue(modelCatalog),
          modelManagementRepositoryProvider.overrideWithValue(
            const _StaticState(
              ModelState(
                artifacts: {
                  'qwen35-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
                },
              ),
            ),
          ),
          preferencesRepositoryProvider.overrideWithValue(
            InMemoryPreferencesRepository(
              const AppPreferences()
                  .withStyle('gemma4', ResponseStyle.precise)
                  .withStyle('qwen35', ResponseStyle.creative),
            ),
          ),
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const GenerationSettings()
                  .withModel(
                    'gemma4',
                    const SamplingOverrides(temperature: 0.11),
                  )
                  .withModel(
                    'qwen35',
                    const SamplingOverrides(temperature: 0.77),
                  ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(modelControllerProvider.future);
      await container.read(chatControllerProvider.future);
      await container
          .read(chatControllerProvider.notifier)
          .send('Use fallback');

      expect(inference.lastPrepareModelKey, 'qwen35-mlx');
      expect(inference.lastModelKey, 'qwen35-mlx');
      expect(inference.lastOverrides?.temperature, 0.77);
      expect(
        inference.lastOverrides?.topP,
        styleOverridesFor('qwen35', ResponseStyle.creative).topP,
      );
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

  test('the OOM injection surfaces a semantic failure', () async {
    final container = containerWith();
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.future);
    final controller = container.read(chatControllerProvider.notifier);
    await controller.send('please [oom] now');
    final state = container.read(chatControllerProvider).requireValue;
    expect(state.generation, GenerationPhase.failed);
    expect(state.failure?.kind, ChatFailureKind.outOfMemory);
  });

  test(
    'deterministic engine refusals retain semantic recovery kinds',
    () async {
      const expected = {
        InferenceFailureKind.modelUnavailable: ChatFailureKind.modelUnavailable,
        InferenceFailureKind.unsupportedModel: ChatFailureKind.unsupportedModel,
        InferenceFailureKind.attachmentUnavailable:
            ChatFailureKind.attachmentUnavailable,
        InferenceFailureKind.unsupportedImages:
            ChatFailureKind.unsupportedImages,
        InferenceFailureKind.invalidModelArtifact:
            ChatFailureKind.invalidModelArtifact,
        InferenceFailureKind.unsupportedDevice:
            ChatFailureKind.unsupportedDevice,
      };
      for (final MapEntry(:key, :value) in expected.entries) {
        final container = ProviderContainer(
          overrides: [
            chatHistoryRepositoryProvider.overrideWithValue(
              InMemoryChatHistoryRepository(),
            ),
            inferenceRepositoryProvider.overrideWithValue(
              _RecordingInferenceRepository(generationFailure: key),
            ),
          ],
        );
        await container.read(chatControllerProvider.future);
        await container.read(chatControllerProvider.notifier).send('Hello');
        expect(
          container.read(chatControllerProvider).requireValue.failure?.kind,
          value,
          reason: key.name,
        );
        container.dispose();
      }
    },
  );

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
            kind: InferenceBackendKind.mlx,
            profileKey: 'gemma4',
            artifactKey: 'test-mlx',
            modelPath: 'documents:models/test-mlx',
            modelPathFromCatalog: true,
          ),
        ),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
      ],
    );
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.future);
    await container.read(chatControllerProvider.notifier).send('Hello');

    final state = container.read(chatControllerProvider).requireValue;
    expect(state.generation, GenerationPhase.failed);
    expect(state.failure?.kind, ChatFailureKind.missingModel);
    expect(state.failure?.artifactKey, 'test-mlx');
    // The engine was never touched: no hang-like prepare, no cryptic error.
    expect(inference.prepares, 0);
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
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
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
          modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
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
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
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

  test('engine commands refuse while an answer is streaming', () async {
    // #124: Settings > Models could unload or delete the resident artifact
    // mid-stream, truncating the answer. releaseEngineWhileInactive was the
    // only command that checked; these two were not.
    final directory = Directory.systemTemp.createTempSync('golem-midstream-');
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
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
      ],
    );
    addTearDown(container.dispose);
    await installActiveModel(container);
    await container.read(chatControllerProvider.future);
    final models = container.read(modelControllerProvider.notifier);
    await models.toggleRuntime();

    inference.generateGate = Completer<void>();
    final chat = container.read(chatControllerProvider.notifier);
    final send = chat.send('slow question');
    while (container.read(chatControllerProvider).requireValue.generation ==
        GenerationPhase.idle) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    await models.toggleRuntime();
    expect(inference.unloads, 0, reason: 'unload must not truncate an answer');
    await models.delete(
      container.read(modelControllerProvider).requireValue.activeArtifactKey!,
    );
    expect(inference.unloads, 0, reason: 'delete must not truncate an answer');

    inference.generateGate!.complete();
    await send;

    // Idle again, so the same command now applies.
    await models.toggleRuntime();
    expect(inference.unloads, 1);
  });

  test('teardown releases the engine synchronously, mid-answer', () async {
    // The framework does not await lifecycle handlers, so this must complete
    // without the event loop turning: an asynchronous release races the
    // isolate's destruction and the worker aborts the process (#124).
    final directory = Directory.systemTemp.createTempSync('golem-teardown-');
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
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
      ],
    );
    addTearDown(container.dispose);
    await installActiveModel(container);
    await container.read(chatControllerProvider.future);
    final models = container.read(modelControllerProvider.notifier);
    await models.toggleRuntime();

    inference.generateGate = Completer<void>();
    final chat = container.read(chatControllerProvider.notifier);
    final send = chat.send('slow question');
    while (container.read(chatControllerProvider).requireValue.generation ==
        GenerationPhase.idle) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    models.releaseEngineForTeardown();
    expect(
      inference.releases,
      1,
      reason: 'released before this statement returns, and not gated on idle',
    );

    inference.generateGate!.complete();
    await send;
  });

  test('a failed answer does not block unloading or deleting', () async {
    // GenerationPhase.failed is sticky until the user retries or discards, so
    // treating "not idle" as "in flight" would leave Settings > Models inert
    // exactly when the out-of-memory copy sends the user there (#124).
    final directory = Directory.systemTemp.createTempSync('golem-failed-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final inference = _RecordingInferenceRepository(
      generationFailure: InferenceFailureKind.outOfMemory,
    );
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(inference),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
      ],
    );
    addTearDown(container.dispose);
    await installActiveModel(container);
    await container.read(chatControllerProvider.future);
    final models = container.read(modelControllerProvider.notifier);
    await models.toggleRuntime();

    await container.read(chatControllerProvider.notifier).send('boom');
    expect(
      container.read(chatControllerProvider).requireValue.generation,
      GenerationPhase.failed,
      reason: 'the failure must still be on screen',
    );

    await models.toggleRuntime();
    expect(
      inference.unloads,
      1,
      reason: 'unload stays available after a failure',
    );
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
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
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
            kind: InferenceBackendKind.mlx,
            profileKey: 'gemma4',
            artifactKey: 'test-mlx',
            modelPath: 'documents:models/test-mlx',
            modelPathFromCatalog: true,
          ),
        ),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
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
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
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
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
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
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
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

  test('memory pressure releases a sideloaded model too', () async {
    final directory = Directory.systemTemp.createTempSync('golem-side2-test-');
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
            modelPath: '/sideloaded/model.gguf',
          ),
        ),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
      ],
    );
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.future);
    // A sideload is outside the catalog, so the lazy load leaves the
    // persisted phase at unloaded — while the engine holds the weights.
    await container.read(chatControllerProvider.notifier).send('Hello');
    await container.read(modelControllerProvider.future);
    final models = container.read(modelControllerProvider.notifier);
    expect(
      container.read(modelControllerProvider).requireValue.runtime,
      RuntimePhase.unloaded,
    );

    await models.releaseEngineWhileInactive();
    expect(inference.unloads, 1, reason: 'resident weights must be released');

    // And the phase it never claimed is not rewritten on the way out.
    expect((await fakeModels(directory).load()).runtime, RuntimePhase.unloaded);
    await models.releaseEngineWhileInactive();
    expect(inference.unloads, 1, reason: 'nothing resident: a no-op');
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
            kind: InferenceBackendKind.mlx,
            profileKey: 'gemma4',
            artifactKey: 'test-mlx',
            modelPath: 'documents:models/test-mlx',
            modelPathFromCatalog: true,
          ),
        ),
        modelManagementRepositoryProvider.overrideWithValue(
          fakeModels(directory),
        ),
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
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
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
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
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
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
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
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

  group('an unsupported device is admitted to nothing (#27)', () {
    const refusal = DeviceEligibility(
      tier: DeviceTier.unsupported,
      reason: DeviceIneligibilityReason.belowMemoryFloor,
      message: 'This device cannot run models.',
    );
    const realBackend = InferenceBackendConfig(
      kind: InferenceBackendKind.mlx,
      profileKey: 'gemma4',
      artifactKey: 'test-mlx',
      modelPath: 'documents:models/test-mlx',
      modelPathFromCatalog: true,
    );

    ProviderContainer containerFor(
      Directory directory,
      _RecordingInferenceRepository inference, {
      DeviceEligibility eligibility = refusal,
      InferenceBackendConfig backend = realBackend,
      ChatHistoryRepository? history,
      SettingsRepository? settings,
      ModelManagementRepository? models,
    }) => ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          history ?? InMemoryChatHistoryRepository(),
        ),
        settingsRepositoryProvider.overrideWithValue(
          settings ?? InMemorySettingsRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(inference),
        inferenceBackendProvider.overrideWithValue(backend),
        deviceEligibilityProvider.overrideWithValue(eligibility),
        modelManagementRepositoryProvider.overrideWithValue(
          models ?? fakeModels(directory),
        ),
        modelCatalogEntriesProvider.overrideWithValue(_testCatalog),
      ],
    );

    test(
      'a send refuses before the engine, with no download offered',
      () async {
        final directory = Directory.systemTemp.createTempSync('golem-floor-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final inference = _RecordingInferenceRepository();
        final container = containerFor(directory, inference);
        addTearDown(container.dispose);
        await container.read(chatControllerProvider.future);
        await container.read(chatControllerProvider.notifier).send('Hello');

        final state = container.read(chatControllerProvider).requireValue;
        expect(state.generation, GenerationPhase.failed);
        expect(state.failure?.kind, ChatFailureKind.unsupportedDevice);
        // No artifact key means the banner has no download CTA to render: the
        // refusal must never turn into an offer to fetch gigabytes.
        expect(state.failure?.artifactKey, isNull);
        expect(inference.prepares, 0);
      },
    );

    test('the refusal precedes the missing-model CTA', () async {
      final directory = Directory.systemTemp.createTempSync('golem-floor-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final container = containerFor(
        directory,
        _RecordingInferenceRepository(),
      );
      addTearDown(container.dispose);
      await container.read(chatControllerProvider.future);
      // The model is not installed either, so both gates apply. The device
      // verdict is the one worth telling: downloading would not help.
      await container.read(chatControllerProvider.notifier).send('Hello');
      expect(
        container.read(chatControllerProvider).requireValue.failure?.kind,
        ChatFailureKind.unsupportedDevice,
      );
    });

    test('download starts nothing at all', () async {
      final directory = Directory.systemTemp.createTempSync('golem-floor-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final container = containerFor(
        directory,
        _RecordingInferenceRepository(),
      );
      addTearDown(container.dispose);
      await container.read(modelControllerProvider.future);
      await container
          .read(modelControllerProvider.notifier)
          .download('test-mlx');

      // Not a failed phase either: the card already carries the reason, and a
      // second copy of it in destructive red would read as something breaking.
      final status = container
          .read(modelControllerProvider)
          .requireValue
          .statusOf('test-mlx');
      expect(status.phase, ArtifactPhase.notDownloaded);
      expect(status.failure, isNull);
      expect(status.downloadedBytes, 0);
    });

    test(
      'a transfer the platform still holds is stopped, not adopted',
      () async {
        final directory = Directory.systemTemp.createTempSync('golem-floor-');
        addTearDown(() => directory.deleteSync(recursive: true));
        // The one path that still reaches download() on a refused device: an
        // upgrade onto this build with a transfer already in flight.
        final models = _TransferRecorder(
          const ModelState().withArtifact(
            'test-mlx',
            const ArtifactStatus(
              phase: ArtifactPhase.downloading,
              downloadedBytes: 4096,
            ),
          ),
        );
        final container = containerFor(
          directory,
          _RecordingInferenceRepository(),
          models: models,
        );
        addTearDown(container.dispose);
        await container.read(modelControllerProvider.future);
        await container
            .read(modelControllerProvider.notifier)
            .reconcileDownloads();

        expect(models.downloads, isEmpty);
        expect(models.cancels, ['test-mlx']);
      },
    );

    test('the runtime toggle refuses without touching the engine', () async {
      final directory = Directory.systemTemp.createTempSync('golem-floor-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final inference = _RecordingInferenceRepository();
      final container = containerFor(directory, inference);
      addTearDown(container.dispose);
      await container.read(modelControllerProvider.future);
      await container.read(modelControllerProvider.notifier).toggleRuntime();

      final state = container.read(modelControllerProvider).requireValue;
      expect(state.runtime, RuntimePhase.failed);
      expect(state.failure, refusal.message);
      expect(inference.prepares, 0);
    });

    test('chats and settings survive the classification', () async {
      final directory = Directory.systemTemp.createTempSync('golem-floor-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final history = InMemoryChatHistoryRepository();
      final settings = InMemorySettingsRepository();
      final container = containerFor(
        directory,
        _RecordingInferenceRepository(),
        history: history,
        settings: settings,
      );
      addTearDown(container.dispose);
      await container.read(chatControllerProvider.future);
      await container.read(chatControllerProvider.notifier).send('Hello');
      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .updateModel('gemma4', const SamplingOverrides(maxTokens: 64));

      // The user's own words and settings are untouched by a refusal that is
      // about hardware, and both are on disk for the next launch.
      final stored = await history.load();
      expect(stored.conversations.single.messages.single.text, 'Hello');
      expect(settings.settings.overridesFor('gemma4').maxTokens, 64);
    });

    test('a simulated backend is never gated by the device', () async {
      final directory = Directory.systemTemp.createTempSync('golem-floor-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final container = containerFor(
        directory,
        _RecordingInferenceRepository(),
        backend: const InferenceBackendConfig.fake(),
      );
      addTearDown(container.dispose);
      await container.read(chatControllerProvider.future);
      await container.read(chatControllerProvider.notifier).send('Hello');
      // QA stays deterministic and model-free: the fake loads nothing, so the
      // floor has nothing to protect and the send completes as always.
      expect(
        container.read(chatControllerProvider).requireValue.failure,
        isNull,
      );

      await container.read(modelControllerProvider.future);
      await container
          .read(modelControllerProvider.notifier)
          .download('test-mlx');
      expect(
        container
            .read(modelControllerProvider)
            .requireValue
            .statusOf('test-mlx')
            .phase,
        ArtifactPhase.installed,
      );
    });
  });
}
