import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/app_state.dart';
import '../domain/generation_settings.dart';
import '../domain/inference_backend.dart';
import '../domain/model_catalog.dart';
import '../domain/models.dart';
import '../repositories/contracts.dart';
import '../startup/startup_sequence.dart';

part 'app_providers.g.dart';

@Riverpod(keepAlive: true)
ChatHistoryRepository chatHistoryRepository(Ref ref) =>
    throw UnimplementedError(
      'Override chatHistoryRepositoryProvider at startup',
    );

@Riverpod(keepAlive: true)
InferenceRepository inferenceRepository(Ref ref) =>
    throw UnimplementedError('Override inferenceRepositoryProvider at startup');

@Riverpod(keepAlive: true)
ModelManagementRepository modelManagementRepository(Ref ref) =>
    throw UnimplementedError(
      'Override modelManagementRepositoryProvider at startup',
    );

@Riverpod(keepAlive: true)
BenchmarkRepository benchmarkRepository(Ref ref) =>
    throw UnimplementedError('Override benchmarkRepositoryProvider at startup');

@Riverpod(keepAlive: true)
List<ModelCatalogEntry> modelCatalogEntries(Ref ref) =>
    throw UnimplementedError('Override modelCatalogEntriesProvider at startup');

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) =>
    throw UnimplementedError('Override settingsRepositoryProvider at startup');

/// The resolved inference backend for this process. Deliberately a fake
/// default value rather than a throwing seam — a documented exception to
/// the repository-provider discipline: this is a value signal that dozens
/// of widgets read for honest "simulated" labeling, and host tests (which
/// run as the dev flavor) must see the fake without every container
/// overriding it. main() always overrides it with the resolved config;
/// a regression test pins the fake default.
@Riverpod(keepAlive: true)
InferenceBackendConfig inferenceBackend(Ref ref) =>
    const InferenceBackendConfig.fake();

/// Persisted per-model generation settings. Reads resolve against the
/// broker profile's recommended defaults at the consumer, never here —
/// only user-set values are stored.
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  @override
  Future<GenerationSettings> build() =>
      ref.read(settingsRepositoryProvider).load();

  GenerationSettings get _value => state.requireValue;

  Future<void> updateModel(
    String profileKey,
    SamplingOverrides overrides,
  ) async {
    final next = _value.withModel(profileKey, overrides);
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }

  Future<void> resetModel(String profileKey) =>
      updateModel(profileKey, const SamplingOverrides());
}

@Riverpod(keepAlive: true)
class ChatController extends _$ChatController {
  int _generationEpoch = 0;

  @override
  Future<ChatState> build() async {
    ref.onDispose(() => _generationEpoch++);
    final snapshot = await ref.read(chatHistoryRepositoryProvider).load();
    return ChatState(
      conversations: snapshot.conversations,
      activeId: snapshot.activeId,
    );
  }

  Future<void> _persist(ChatState value) => ref
      .read(chatHistoryRepositoryProvider)
      .save(
        ChatHistorySnapshot(
          conversations: value.conversations,
          activeId: value.activeId,
        ),
      );

  ChatState get _value => state.requireValue;

  Future<void> newChat() async {
    stop();
    final now = DateTime.now();
    final conversation = ChatConversation(
      id: newId(),
      title: 'New chat',
      messages: const [],
      updatedAt: now,
    );
    final next = ChatState(
      conversations: [conversation, ..._value.conversations],
      activeId: conversation.id,
    );
    state = AsyncData(next);
    await _persist(next);
  }

  Future<void> selectConversation(String id) async {
    if (_value.generation != GenerationPhase.idle) return;
    if (!_value.conversations.any((item) => item.id == id)) return;
    final next = _value.copyWith(activeId: id, clearFailure: true);
    state = AsyncData(next);
    await _persist(next);
  }

  Future<void> renameConversation(String id, String title) async {
    final normalized = normalizeTitle(title);
    final next = _value.copyWith(
      conversations: [
        for (final item in _value.conversations)
          if (item.id == id) item.copyWith(title: normalized) else item,
      ],
    );
    state = AsyncData(next);
    await _persist(next);
  }

  Future<void> deleteConversation(String id) async {
    stop();
    final remaining = _value.conversations
        .where((item) => item.id != id)
        .toList();
    final requested = _value.activeId == id
        ? remaining.firstOrNull?.id
        : _value.activeId;
    final next = ChatState(conversations: remaining, activeId: requested);
    state = AsyncData(next);
    await _persist(next);
  }

  Future<void> toggleReasoning() async {
    final active = _value.active;
    if (active == null || _value.generation != GenerationPhase.idle) return;
    final next = _replaceActive(
      active.copyWith(reasoningEnabled: !active.reasoningEnabled),
    );
    state = AsyncData(next);
    await _persist(next);
  }

  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _value.generation != GenerationPhase.idle) return;
    if (_value.active == null) await newChat();
    final active = _value.active!;
    final user = ChatMessage(
      id: newId(),
      role: MessageRole.user,
      text: text,
      createdAt: DateTime.now(),
    );
    final title = active.messages.isEmpty ? normalizeTitle(text) : active.title;
    final updated = active.copyWith(
      title: title,
      messages: [...active.messages, user],
      updatedAt: DateTime.now(),
    );
    final next = _replaceActive(updated).copyWith(clearFailure: true);
    state = AsyncData(next);
    await _persist(next);
    if (!ref.mounted) return;
    await _startGeneration();
  }

  Future<void> regenerate() async {
    final active = _value.active;
    if (active == null || _value.generation != GenerationPhase.idle) return;
    final messages = [...active.messages];
    if (messages.lastOrNull?.role == MessageRole.assistant) {
      messages.removeLast();
    }
    final next = _replaceActive(
      active.copyWith(messages: messages),
    ).copyWith(clearFailure: true, hasUnsavedAssistant: false);
    state = AsyncData(next);
    await _persist(next);
    await _startGeneration();
  }

  Future<void> editAndTruncate(String messageId, String rawText) async {
    final text = rawText.trim();
    final active = _value.active;
    if (text.isEmpty ||
        active == null ||
        _value.generation != GenerationPhase.idle) {
      return;
    }
    final index = active.messages.indexWhere((item) => item.id == messageId);
    if (index < 0 || active.messages[index].role != MessageRole.user) return;
    final edited = ChatMessage(
      id: active.messages[index].id,
      role: MessageRole.user,
      text: text,
      createdAt: active.messages[index].createdAt,
    );
    final next = _replaceActive(
      active.copyWith(
        messages: [...active.messages.take(index), edited],
        title: index == 0 ? normalizeTitle(text) : active.title,
        updatedAt: DateTime.now(),
      ),
    ).copyWith(clearFailure: true);
    state = AsyncData(next);
    await _persist(next);
    await _startGeneration();
  }

  Future<void> _startGeneration() async {
    final active = _value.active;
    if (active == null ||
        active.messages.lastOrNull?.role != MessageRole.user) {
      return;
    }
    final epoch = ++_generationEpoch;
    // Real backend with the active artifact not installed: fail fast into
    // the banner's download CTA before touching the engine — prepare()
    // would only produce a cryptic missing-file error after a hang-like
    // pause.
    final backend = ref.read(inferenceBackendProvider);
    if (!backend.simulatedInference && backend.artifactKey != null) {
      final installed = await _activeModelInstalled();
      if (!ref.mounted || epoch != _generationEpoch) return;
      if (installed == false) {
        state = AsyncData(
          _value.copyWith(
            generation: GenerationPhase.failed,
            failure:
                'The local model is not downloaded on this device yet. '
                'Download it to start chatting.',
            missingModelArtifactKey: backend.artifactKey,
          ),
        );
        return;
      }
    }
    final assistant = ChatMessage(
      id: newId(),
      role: MessageRole.assistant,
      text: '',
      reasoning: '',
      createdAt: DateTime.now(),
      isStreaming: true,
    );
    state = AsyncData(
      _replaceActive(
        active.copyWith(messages: [...active.messages, assistant]),
      ).copyWith(
        generation: GenerationPhase.preparing,
        hasUnsavedAssistant: true,
        clearFailure: true,
      ),
    );
    try {
      await ref.read(inferenceRepositoryProvider).prepare();
      if (!ref.mounted || epoch != _generationEpoch) return;
      state = AsyncData(_value.copyWith(generation: GenerationPhase.streaming));
      final context = active.promptContext;
      final overrides = await _samplingOverrides();
      if (!ref.mounted || epoch != _generationEpoch) return;
      await for (final event
          in ref
              .read(inferenceRepositoryProvider)
              .generate(
                context: context,
                reasoningEnabled: active.reasoningEnabled,
                overrides: overrides,
              )) {
        if (!ref.mounted || epoch != _generationEpoch) return;
        if (event is CompletedEvent) break;
        final current = _value.active;
        if (current == null || current.messages.isEmpty) return;
        final messages = [...current.messages];
        final draft = messages.last;
        if (event is ReasoningDelta) {
          messages[messages.length - 1] = draft.copyWith(
            reasoning: '${draft.reasoning ?? ''}${event.text}',
          );
        } else if (event is AnswerDelta) {
          messages[messages.length - 1] = draft.copyWith(
            text: '${draft.text}${event.text}',
          );
        } else if (event is AnswerResetEvent) {
          messages[messages.length - 1] = draft.copyWith(text: '');
        } else if (event is MetricsEvent) {
          messages[messages.length - 1] = draft.copyWith(
            metrics: event.metrics,
          );
        }
        state = AsyncData(_replaceActive(current.copyWith(messages: messages)));
      }
      if (!ref.mounted || epoch != _generationEpoch) return;
      await _finalizeGeneration();
    } catch (error) {
      if (!ref.mounted || epoch != _generationEpoch) return;
      final current = _value.active;
      if (current != null && current.messages.isNotEmpty) {
        final messages = [...current.messages];
        messages[messages.length - 1] = messages.last.copyWith(
          isStreaming: false,
        );
        state = AsyncData(
          _replaceActive(current.copyWith(messages: messages)).copyWith(
            generation: GenerationPhase.failed,
            failure: error.toString().replaceFirst('Bad state: ', ''),
            hasUnsavedAssistant: true,
          ),
        );
      }
    }
  }

  /// Whether the active artifact is installed, or null when model state is
  /// unavailable — then generation proceeds and prepare() stays the loud
  /// failure path rather than this controller inventing a verdict.
  Future<bool?> _activeModelInstalled() async {
    try {
      final models = await ref.read(modelControllerProvider.future);
      return models.activeModelInstalled;
    } catch (_) {
      return null;
    }
  }

  /// The persisted overrides for the active model profile. Settings that
  /// fail to surface must never block chat — the fake ignores overrides
  /// anyway, and the repository already folds corrupt files into defaults —
  /// so an unavailable settings store degrades to profile defaults.
  Future<SamplingOverrides?> _samplingOverrides() async {
    try {
      final settings = await ref.read(settingsControllerProvider.future);
      return settings.overridesFor(
        ref.read(inferenceBackendProvider).profileKey,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _finalizeGeneration() async {
    final active = _value.active;
    if (active == null || active.messages.isEmpty) return;
    final messages = [...active.messages];
    messages[messages.length - 1] = messages.last.copyWith(isStreaming: false);
    final next =
        _replaceActive(
          active.copyWith(messages: messages, updatedAt: DateTime.now()),
        ).copyWith(
          generation: GenerationPhase.idle,
          hasUnsavedAssistant: false,
          clearFailure: true,
        );
    state = AsyncData(next);
    await _persist(next);
  }

  void stop() {
    _generationEpoch++;
    if (!state.hasValue || _value.generation == GenerationPhase.idle) return;
    unawaited(ref.read(inferenceRepositoryProvider).cancel());
    final active = _value.active;
    if (active == null || active.messages.isEmpty) return;
    final messages = [...active.messages];
    if (messages.last.isStreaming) {
      if (messages.last.text.isEmpty &&
          (messages.last.reasoning?.isEmpty ?? true)) {
        messages.removeLast();
      } else {
        messages[messages.length - 1] = messages.last.copyWith(
          isStreaming: false,
        );
      }
    }
    final next = _replaceActive(active.copyWith(messages: messages)).copyWith(
      generation: GenerationPhase.idle,
      hasUnsavedAssistant: false,
      clearFailure: true,
    );
    state = AsyncData(next);
    unawaited(_persist(next));
  }

  Future<void> retryFailure() async {
    final active = _value.active;
    if (active == null) return;
    final messages = [...active.messages];
    if (messages.lastOrNull?.role == MessageRole.assistant) {
      messages.removeLast();
    }
    state = AsyncData(
      _replaceActive(active.copyWith(messages: messages)).copyWith(
        generation: GenerationPhase.idle,
        clearFailure: true,
        hasUnsavedAssistant: false,
      ),
    );
    await _startGeneration();
  }

  Future<void> discardFailure() async {
    final active = _value.active;
    if (active == null) return;
    final messages = [...active.messages];
    if (messages.lastOrNull?.role == MessageRole.assistant) {
      messages.removeLast();
    }
    final next = _replaceActive(active.copyWith(messages: messages)).copyWith(
      generation: GenerationPhase.idle,
      clearFailure: true,
      hasUnsavedAssistant: false,
    );
    state = AsyncData(next);
    await _persist(next);
  }

  ChatState _replaceActive(ChatConversation conversation) => _value.copyWith(
    conversations: [
      conversation,
      for (final item in _value.conversations)
        if (item.id != conversation.id) item,
    ],
    activeId: conversation.id,
  );
}

@Riverpod(keepAlive: true)
class ModelController extends _$ModelController {
  int _operationEpoch = 0;
  // One mutating model operation at a time. Pause and cancel stay exempt:
  // they are the escape hatches that end an in-flight download.
  bool _busy = false;

  @override
  Future<ModelState> build() =>
      ref.read(modelManagementRepositoryProvider).load();

  Future<void> download(String artifactKey) async {
    if (_busy) return;
    _busy = true;
    try {
      final epoch = ++_operationEpoch;
      await for (final value
          in ref
              .read(modelManagementRepositoryProvider)
              .download(artifactKey)) {
        if (!ref.mounted || epoch != _operationEpoch) return;
        state = AsyncData(value);
      }
    } catch (error) {
      // Operational failures arrive as failed-phase snapshots; anything that
      // still throws must land on the card, not blank the whole screen as an
      // AsyncError.
      _publishFailure(artifactKey, error);
    } finally {
      _busy = false;
    }
  }

  Future<void> pause(String artifactKey) async {
    _operationEpoch++;
    try {
      final value = await ref
          .read(modelManagementRepositoryProvider)
          .pause(artifactKey);
      if (!ref.mounted) return;
      state = AsyncData(value);
    } catch (error) {
      _publishFailure(artifactKey, error);
    }
  }

  Future<void> cancel(String artifactKey) async {
    _operationEpoch++;
    try {
      final value = await ref
          .read(modelManagementRepositoryProvider)
          .cancel(artifactKey);
      if (!ref.mounted) return;
      state = AsyncData(value);
    } catch (error) {
      _publishFailure(artifactKey, error);
    }
  }

  Future<void> delete(String artifactKey) async {
    if (_busy) return;
    _busy = true;
    try {
      // Never delete weights the engine may still have mapped: releasing
      // the runtime comes first, and an unload failure aborts the delete.
      if (artifactKey == state.value?.activeArtifactKey) {
        await ref.read(inferenceRepositoryProvider).unload();
        if (!ref.mounted) return;
      }
      final value = await ref
          .read(modelManagementRepositoryProvider)
          .delete(artifactKey);
      if (!ref.mounted) return;
      state = AsyncData(value);
    } catch (error) {
      _publishFailure(artifactKey, error);
    } finally {
      _busy = false;
    }
  }

  void _publishFailure(String artifactKey, Object error) {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.withArtifact(
        artifactKey,
        current
            .statusOf(artifactKey)
            .copyWith(phase: ArtifactPhase.failed, failure: '$error'),
      ),
    );
  }

  /// The persisted RuntimePhase must reflect the engine, not bookkeeping:
  /// Load drives a real `prepare()` before `loaded` is recorded, Unload a
  /// real `unload()` before `unloaded` — the deferred #37 finding. Engine
  /// failures stay in-memory as a failed phase with the message; the
  /// repository's stale-`loading` reconciliation already covers crashes.
  Future<void> toggleRuntime() async {
    if (_busy) return;
    _busy = true;
    try {
      final repository = ref.read(modelManagementRepositoryProvider);
      final current = state.requireValue;
      if (current.runtime == RuntimePhase.loaded) {
        try {
          await ref.read(inferenceRepositoryProvider).unload();
        } catch (error) {
          if (!ref.mounted) return;
          state = AsyncData(
            current.copyWith(runtime: RuntimePhase.failed, failure: '$error'),
          );
          return;
        }
        if (!ref.mounted) return;
        final value = await repository.unloadRuntime();
        if (!ref.mounted) return;
        state = AsyncData(value);
      } else {
        // Publish the loading phase immediately so the UI can disable the
        // toggle while the engine loads.
        state = AsyncData(
          current.copyWith(runtime: RuntimePhase.loading, clearFailure: true),
        );
        if (!current.activeModelInstalled) {
          // The repository refuses with a persisted failed phase and a
          // clear message; the engine is never touched.
          final value = await repository.loadRuntime();
          if (!ref.mounted) return;
          state = AsyncData(value);
          return;
        }
        try {
          await ref.read(inferenceRepositoryProvider).prepare();
        } catch (error) {
          if (!ref.mounted) return;
          state = AsyncData(
            current.copyWith(runtime: RuntimePhase.failed, failure: '$error'),
          );
          return;
        }
        if (!ref.mounted) return;
        final value = await repository.loadRuntime();
        if (!ref.mounted) return;
        state = AsyncData(value);
      }
    } finally {
      _busy = false;
    }
  }
}

@Riverpod(keepAlive: true)
class StartupController extends _$StartupController {
  static const missingModel = bool.fromEnvironment('GOLEM_MISSING_MODEL');
  static const injectedFailure = bool.fromEnvironment('GOLEM_SPLASH_FAILURE');
  static const injectedTimeout = bool.fromEnvironment('GOLEM_SPLASH_TIMEOUT');

  @override
  Future<StartupState> build() async {
    state = const AsyncData(StartupState(progress: 0.18));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    state = const AsyncData(
      StartupState(phase: StartupPhase.preloading, progress: 0.72),
    );
    if (missingModel) {
      state = const AsyncData(
        StartupState(phase: StartupPhase.missingModel, progress: 0.86),
      );
    }
    final scenario = injectedFailure
        ? StartupScenario.failure
        : injectedTimeout
        ? StartupScenario.timeout
        : missingModel
        ? StartupScenario.missingModel
        : StartupScenario.ready;
    return const StartupSequence().run(scenario);
  }

  Future<void> retry() async {
    state = const AsyncData(StartupState(progress: 0.2));
    // Recovery deliberately succeeds — the injected failure exists to show
    // the failure UI, retry to show the recovery path — but it runs through
    // the same StartupSequence timing policy as a real launch.
    final result = await const StartupSequence().run(StartupScenario.ready);
    if (!ref.mounted) return;
    state = AsyncData(result);
  }
}

@Riverpod(keepAlive: true)
class BenchmarkController extends _$BenchmarkController {
  int _epoch = 0;

  @override
  BenchmarkState build() => const BenchmarkState();

  // A result belongs to the exact case/phase combination it was produced
  // for, so any selection change or new run discards it.
  void selectCase(String caseId) =>
      state = state.copyWith(caseId: caseId, clearResult: true);
  void selectPhase(BenchmarkPhase phase) =>
      state = state.copyWith(phase: phase, clearResult: true);

  Future<void> run() async {
    final epoch = ++_epoch;
    state = state.copyWith(isRunning: true, clearResult: true);
    final result = await ref
        .read(benchmarkRepositoryProvider)
        .run(state.caseId, state.phase);
    if (epoch != _epoch) return;
    state = state.copyWith(isRunning: false, result: result);
  }

  void stop() {
    _epoch++;
    state = state.copyWith(isRunning: false);
  }

  Future<String?> export() async {
    final result = state.result;
    if (result == null) return null;
    return ref.read(benchmarkRepositoryProvider).export(result);
  }
}
