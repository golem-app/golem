import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/app_state.dart';
import '../../../core/domain/generation_settings.dart';
import '../../../core/domain/model_catalog.dart';
import '../../../core/domain/models.dart';
import '../../../core/domain/response_style_mapping.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';
import '../../../core/repositories/contracts.dart';
import '../../../core/services/image_intake.dart';
import '../../models/application/model_providers.dart';
import '../../models/application/storage_providers.dart';
import '../../preferences/application/generation_settings_providers.dart';
import '../../preferences/application/preferences_providers.dart';
import 'chat_conversation_edits.dart';
import 'chat_failure_classifier.dart';
import 'chat_persistence.dart';
import 'generation_event_reducer.dart';
import 'generation_target.dart';

part 'chat_providers.g.dart';

// The decisions this notifier used to hold inline now live beside it and are
// unit tested without a container (#127): chat_persistence, conversation edits,
// generation target, the event reducer, the failure classifier. What stays here
// is state ownership — epochs, mounted checks, and the order commands run in —
// which is the one thing a notifier cannot delegate. Kept out of the doc
// comment: riverpod_generator copies those into three places in the .g.dart.
/// KeepAlive: the chat session aggregate — in-flight generation and unsaved
/// turns must survive every route transition.
@Riverpod(keepAlive: true, retry: noRetry)
class ChatController extends _$ChatController {
  int _generationEpoch = 0;
  int _persistenceEpoch = 0;

  /// Conversation and message counts as of the last storage invalidation.
  /// The breakdown is disk probing, and this notifier reassigns state on every
  /// streaming delta, so it must key on a count rather than on the state — or
  /// it re-runs per token for the always-mounted drawer meter.
  ///
  /// Held here rather than derived over there because storage accounting sits
  /// below chat in the feature direction (#129): a signal travels the opposite
  /// way from a dependency, so the writer invalidates instead of the reader
  /// watching upward.
  (int, int) _storedVolume = (0, 0);

  /// The repository behind the generation currently in flight, captured when it
  /// starts. Held rather than read on demand because [Ref] is unusable inside a
  /// dispose callback: riverpod 3.3.2 asserts `_debugCallbackStack == 0` in
  /// every Ref member and increments that counter around each onDispose
  /// listener, so `ref.read` there fails outright in debug builds.
  InferenceRepository? _inFlight;

  @override
  Future<ChatState> build() async {
    ref.onDispose(() {
      _generationEpoch++;
      _persistenceEpoch++;
      // Native decode outlives the provider otherwise, and keeps producing
      // into a stream nobody reads (#127).
      unawaited(_inFlight?.cancel());
      _inFlight = null;
    });
    // Bound before the first await so commands arriving during hydration see
    // it. Watched, not read: if the bridge is ever refreshed, this rebuild
    // re-binds the fresh instance instead of leaving readers unbound (#88).
    final bridge = ref.watch(chatSessionBridgeProvider);
    bridge.bindPersistCurrent(persistCurrent);
    bridge.bindSessionState(() => state.value);
    final persistence = _persistence();
    final snapshot = await persistence.load();
    await persistence.retainReferenced(snapshot.conversations);
    final hydrated = ChatState(
      conversations: snapshot.conversations,
      activeId: snapshot.activeId,
    );
    // Recorded, not published: the breakdown reads the store's bytes off disk,
    // so hydration changes no figure it reports.
    _storedVolume = _volumeOf(hydrated);
    return hydrated;
  }

  /// Republishes the storage breakdown when this session's contribution to it
  /// changes. Metadata-only writes — a rename, a pin, a model switch — leave
  /// the counts alone and cost nothing.
  void _invalidateStorage(ChatState value) {
    if (!ref.mounted) return;
    final volume = _volumeOf(value);
    if (volume == _storedVolume) return;
    _storedVolume = volume;
    ref.invalidate(storageBreakdownProvider);
  }

  static (int, int) _volumeOf(ChatState value) {
    var messages = 0;
    for (final conversation in value.conversations) {
      messages += conversation.messages.length;
    }
    return (value.conversations.length, messages);
  }

  /// Every seam read before the first await: a persistence attempt outlives its
  /// provider on a fast dispose, and Ref is unusable past that point.
  ///
  /// Deliberately does not read preferences, which [build] would then do too:
  /// resolving that controller from inside this one's build deadlocks — the
  /// dual-recovery golden hangs indefinitely rather than failing. The privacy
  /// gate is read at persist time instead, where it is already needed.
  ChatPersistence _persistence() => ChatPersistence(
    history: ref.read(chatHistoryRepositoryProvider),
    attachments: ref.read(attachmentRepositoryProvider),
  );

  /// False only once preferences have loaded and say so. Unknown counts as on:
  /// a cold start must save, rather than silently drop the first turns while
  /// the store is still opening.
  bool get _saveHistory =>
      ref.read(preferencesControllerProvider).value?.saveHistory ?? true;

  Future<void> _persist(
    ChatState value, {
    bool showRetryProgress = false,
  }) async {
    final epoch = ++_persistenceEpoch;
    final persistence = _persistence();
    final saveHistory = _saveHistory;
    _invalidateStorage(value);

    if (showRetryProgress && ref.mounted && epoch == _persistenceEpoch) {
      _setPersistencePhase(ChatPersistencePhase.retrying);
    }

    if (!saveHistory) {
      // With history off, attachment bytes follow the live session instead of
      // a durable snapshot. No history write or retry is permitted here.
      await persistence.retainReferenced(value.conversations);
      if (ref.mounted && epoch == _persistenceEpoch) {
        _setPersistencePhase(ChatPersistencePhase.idle);
      }
      return;
    }

    final snapshot = ChatPersistence.snapshotOf(value);
    if (await persistence.save(snapshot) == ChatSaveOutcome.writeFailed) {
      if (ref.mounted && epoch == _persistenceEpoch) {
        _setPersistencePhase(ChatPersistencePhase.failed);
      }
      return;
    }

    // A later attempt owns both the warning and attachment collection. A
    // stale success may leave extra bytes behind, but can never delete bytes a
    // newer durable snapshot still references.
    if (epoch != _persistenceEpoch) return;
    if (ref.mounted) _setPersistencePhase(ChatPersistencePhase.idle);
    await persistence.retainReferenced(snapshot.conversations);
  }

  void _setPersistencePhase(ChatPersistencePhase phase) {
    if (!state.hasValue || _value.persistencePhase == phase) return;
    state = AsyncData(_value.copyWith(persistencePhase: phase));
  }

  /// The save-history re-enable path.
  Future<void> persistCurrent() async {
    if (!state.hasValue) return;
    await _persist(_value);
  }

  /// User-triggered recovery for the standing persistence notice. The latest
  /// live snapshot is captured at the tap, never the originally failed value.
  Future<void> retryPersistence() async {
    if (!state.hasValue ||
        _value.persistencePhase != ChatPersistencePhase.failed) {
      return;
    }
    await _persist(_value, showRetryProgress: true);
  }

  /// The confirmation alert lives at the widget layer; this is past consent.
  /// The disk wipe runs first and gates the in-memory clear: a failed wipe
  /// returns false with the chats still shown, because "deleted" must never
  /// be presented while the store still holds them.
  Future<bool> deleteAllChats() async {
    stop();
    final persistence = _persistence();
    if (!await persistence.wipe()) return false;
    // Only a committed wipe supersedes an earlier save or retry. If the wipe
    // fails, that attempt must still be allowed to settle the recovery notice.
    _persistenceEpoch++;
    if (ref.mounted) state = const AsyncData(ChatState());
    // The one emptying path that never persists, so it invalidates by hand.
    _invalidateStorage(const ChatState());
    await persistence.retainReferenced(const []);
    return true;
  }

  /// The user's own export, so unlike a shared transcript it keeps reasoning.
  String? exportAllChats() {
    if (!state.hasValue) return null;
    return ChatHistorySnapshot(
      conversations: _value.conversations,
      activeId: _value.activeId,
    ).encode();
  }

  ChatState get _value => state.requireValue;

  List<ModelCatalogEntry> get _catalog =>
      ref.read(effectiveModelCatalogProvider);

  Future<void> newChat() async {
    stop();
    final backend = ref.read(inferenceBackendProvider);
    final selectedKey = backend.simulatedInference
        ? ref.read(preferencesControllerProvider).value?.onboardingModelKey
        : ref.read(startupModelKeyProvider);
    final next = withNewConversation(
      _value,
      ChatConversation(
        id: newId(),
        title: '',
        messages: const [],
        updatedAt: DateTime.now(),
        // First run is allowed to name a compatible model before its weights
        // finish downloading. Sending remains gated in the composer and again
        // in _startGeneration; after installation the existing loadable-key
        // rule makes every model label follow this persisted choice.
        modelKey: selectedKey,
      ),
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
    final next = withEditedConversation(
      _value,
      id,
      (item) => item.copyWith(title: normalizeTitle(title)),
    );
    state = AsyncData(next);
    await _persist(next);
  }

  Future<void> deleteConversation(String id) async {
    stop();
    final next = withoutConversation(_value, id);
    state = AsyncData(next);
    await _persist(next);
  }

  Future<void> toggleReasoning() async {
    final active = _value.active;
    if (active == null || _value.generation != GenerationPhase.idle) return;
    final next = withActiveConversation(
      _value,
      active.copyWith(reasoningEnabled: !active.reasoningEnabled),
    );
    state = AsyncData(next);
    await _persist(next);
  }

  Future<void> togglePinned(String id) async {
    // Metadata-only, like rename: safe while a generation streams.
    final next = withEditedConversation(
      _value,
      id,
      (item) => item.togglePinned(),
    );
    state = AsyncData(next);
    await _persist(next);
  }

  /// Refuses a model this build could not load, which is what lets every label
  /// name the choice immediately: a stored selection is always honorable on the
  /// next send (#20).
  Future<void> setConversationModel(String id, String? modelKey) async {
    // A failed turn may be switched away from: picking another model is the
    // natural recovery from a missing one, and blocking it dead-ends the
    // banner. Only work in flight is protected.
    if (_value.generation == GenerationPhase.preparing ||
        _value.generation == GenerationPhase.streaming) {
      return;
    }
    if (modelKey != null && !_selectable(modelKey)) return;
    final next =
        withEditedConversation(
          _value,
          id,
          (item) => item.withModel(modelKey),
        ).copyWith(
          // Whatever the last model failed at is no longer this chat's problem.
          generation: GenerationPhase.idle,
          clearFailure: true,
        );
    state = AsyncData(next);
    await _persist(next);
  }

  /// The fake simulates any switch; a real engine takes only an installed
  /// artifact of the engine it composed, and a sideload takes none at all —
  /// there is no key to switch back to.
  bool _selectable(String modelKey) {
    final backend = ref.read(inferenceBackendProvider);
    if (backend.simulatedInference) return true;
    if (backend.sideloaded) return false;
    return ref.read(loadableModelKeysProvider).contains(modelKey);
  }

  Future<void> deleteMessage(String messageId) async {
    final active = _value.active;
    if (active == null || _value.generation != GenerationPhase.idle) return;
    final next = withActiveConversation(
      _value,
      active.withoutMessage(messageId),
    );
    state = AsyncData(next);
    await _persist(next);
  }

  Future<void> branchFrom(String messageId) async {
    final active = _value.active;
    if (active == null || _value.generation != GenerationPhase.idle) return;
    final branched = active.branchUpTo(
      messageId,
      id: newId(),
      now: DateTime.now(),
    );
    if (branched == null) return;
    final next = withNewConversation(_value, branched);
    state = AsyncData(next);
    await _persist(next);
  }

  /// [images] are attachments the composer already validated; their bytes are
  /// copied into the store here, so the message references ids only.
  Future<void> send(
    String rawText, {
    List<PreparedImage> images = const [],
  }) async {
    final text = rawText.trim();
    // An image alone is a complete turn — "what is this?" is implied.
    if ((text.isEmpty && images.isEmpty) ||
        _value.generation != GenerationPhase.idle) {
      return;
    }
    if (_value.active == null) await newChat();
    if (!ref.mounted) return;
    final active = _value.active!;

    final store = _persistence();
    final List<MessagePart> parts;
    try {
      parts = [
        for (final image in images) await store.store(image),
        if (text.isNotEmpty) TextPart(text),
      ];
    } catch (error, stackTrace) {
      // The bytes never reached disk, so nothing is half-sent: surface the
      // failure and keep the composer's content for another try.
      if (ref.mounted) {
        state = AsyncData(
          _value.copyWith(
            failure: const ChatFailure(kind: ChatFailureKind.attachmentSave),
          ),
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (!ref.mounted) return;

    final user = ChatMessage(
      id: newId(),
      role: MessageRole.user,
      parts: parts,
      createdAt: DateTime.now(),
    );
    final title = active.messages.isEmpty ? normalizeTitle(text) : active.title;
    final updated = active.copyWith(
      title: title,
      messages: [...active.messages, user],
      updatedAt: DateTime.now(),
    );
    final next = withActiveConversation(
      _value,
      updated,
    ).copyWith(clearFailure: true);
    state = AsyncData(next);
    await _persist(next);
    if (!ref.mounted) return;
    await _startGeneration();
  }

  Future<void> regenerate() async {
    final active = _value.active;
    if (active == null || _value.generation != GenerationPhase.idle) return;
    final next = withActiveConversation(
      _value,
      withTrailingTurnsDropped(active),
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
    final edited = withEditedAndTruncated(
      active,
      messageId,
      text,
      now: DateTime.now(),
    );
    if (edited == null) return;
    final next = withActiveConversation(
      _value,
      edited,
    ).copyWith(clearFailure: true);
    state = AsyncData(next);
    await _persist(next);
    await _startGeneration();
  }

  /// Reached after an await from every caller but [retryFailure], so the guard
  /// below is the one that covers send, regenerate and editAndTruncate alike.
  Future<void> _startGeneration() async {
    if (!ref.mounted) return;
    final active = _value.active;
    if (active == null ||
        active.messages.lastOrNull?.role != MessageRole.user) {
      return;
    }
    final epoch = ++_generationEpoch;
    final backend = ref.read(inferenceBackendProvider);
    final String? modelKey;
    final ModelCatalogEntry? entry;
    switch (resolveGenerationTarget(
      backend: backend,
      deviceRefusal: ref.read(deviceRefusalProvider),
      catalog: _catalog,
      conversationModelKey: active.modelKey,
      residentModelKey: ref.read(residentModelKeyProvider),
      loadableKeys: ref.read(loadableModelKeysProvider),
    )) {
      case GenerationRefused(:final failure):
        state = AsyncData(
          _value.copyWith(generation: GenerationPhase.failed, failure: failure),
        );
        return;
      case GenerationReady(:final key, entry: final resolved):
        modelKey = key;
        entry = resolved;
    }
    if (!backend.simulatedInference && !backend.sideloaded && entry != null) {
      final installed = await _modelInstalled(entry.key);
      if (!ref.mounted || epoch != _generationEpoch) return;
      if (installed == false) {
        state = AsyncData(
          _value.copyWith(
            generation: GenerationPhase.failed,
            failure: notInstalledFailure(entry.key),
          ),
        );
        return;
      }
    }
    final assistant = ChatMessage.text(
      id: newId(),
      role: MessageRole.assistant,
      text: '',
      reasoning: '',
      createdAt: DateTime.now(),
      isStreaming: true,
    );
    state = AsyncData(
      withActiveConversation(
        _value,
        active.copyWith(messages: [...active.messages, assistant]),
      ).copyWith(
        generation: GenerationPhase.preparing,
        hasUnsavedAssistant: true,
        clearFailure: true,
      ),
    );
    final inference = ref.read(inferenceRepositoryProvider);
    _inFlight = inference;
    try {
      // The effective target, not blindly the boot or historical chat key:
      // generate() below activates the same target, so a keyless prepare would
      // cost two multi-gigabyte loads per send and a stale key could cross
      // model profiles.
      await inference.prepare(modelKey: modelKey);
      if (!ref.mounted || epoch != _generationEpoch) return;
      // After this prepare() the engine holds weights, so Settings may not keep
      // claiming "Unloaded". Awaited on purpose: a recorded phase must not race
      // the stream it describes.
      if (!backend.simulatedInference) {
        await ref.read(modelSessionBridgeProvider).reflectEngineLoaded();
        if (!ref.mounted || epoch != _generationEpoch) return;
      }
      state = AsyncData(_value.copyWith(generation: GenerationPhase.streaming));
      final context = active.promptContext;
      final overrides = await _samplingOverrides(modelKey);
      final systemPrompt = await _systemPrompt();
      if (!ref.mounted || epoch != _generationEpoch) return;
      await for (final event in inference.generate(
        context: context,
        reasoningEnabled: active.reasoningEnabled,
        overrides: overrides,
        modelKey: modelKey,
        systemPrompt: systemPrompt,
      )) {
        if (!ref.mounted || epoch != _generationEpoch) return;
        if (event is CompletedEvent) break;
        final current = _value.active;
        if (current == null || current.messages.isEmpty) return;
        final messages = applyGenerationEvent(current.messages, event);
        if (messages == null) continue;
        state = AsyncData(
          withActiveConversation(_value, current.copyWith(messages: messages)),
        );
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
          withActiveConversation(
            _value,
            current.copyWith(messages: messages),
          ).copyWith(
            generation: GenerationPhase.failed,
            failure: chatFailureFor(error),
            hasUnsavedAssistant: true,
          ),
        );
      }
    } finally {
      // Only this generation's capture is released; a newer one has already
      // replaced it and owns its own teardown.
      if (epoch == _generationEpoch) _inFlight = null;
    }
  }

  /// Null when model state is unavailable — generation then proceeds and
  /// prepare() stays the loud failure path, rather than inventing a verdict.
  ///
  /// The read sits outside the guard so the guard covers only the awaited work.
  /// That is a smaller claim than it looks: riverpod delivers an unwired seam
  /// as a ProviderException on the future, which is an Exception and is still
  /// caught here. What the narrowing buys is that an Error — a cast, a failed
  /// assertion — is no longer swallowed as "model state unavailable".
  Future<bool?> _modelInstalled(String artifactKey) async {
    final models = ref.read(modelControllerProvider.future);
    try {
      return (await models).statusOf(artifactKey).phase ==
          ArtifactPhase.installed;
    } on Exception {
      return null;
    }
  }

  /// The response style's values with the user's hand-set Advanced overrides
  /// layered on top, knob by knob. Settings that fail to surface must never
  /// block chat, so each layer degrades independently to nothing. Only the
  /// awaited load is guarded, and only against Exception — see _modelInstalled
  /// for what that does and does not buy.
  Future<SamplingOverrides?> _samplingOverrides(String? modelKey) async {
    final profileKey = _profileKeyFor(modelKey);
    final settings = ref.read(settingsControllerProvider.future);
    final preferences = ref.read(preferencesControllerProvider.future);
    var manual = const SamplingOverrides();
    try {
      manual = (await settings).overridesFor(profileKey);
    } on Exception {
      // Degrades to no manual overrides.
    }
    var style = const SamplingOverrides();
    try {
      final loaded = await preferences;
      style = styleOverridesFor(profileKey, loaded.styleFor(profileKey));
    } on Exception {
      // Degrades to the profile's own defaults.
    }
    final merged = layerOverrides(manual: manual, style: style);
    return merged.isEmpty ? null : merged;
  }

  /// The profile of the model this chat runs, so hand-set sampling and the
  /// response style follow a switch instead of staying on the build's boot
  /// profile — switching Gemma to Qwen otherwise applies Gemma's numbers (#20).
  String _profileKeyFor(String? modelKey) {
    final entry = modelKey == null
        ? null
        : _catalog.where((item) => item.key == modelKey).firstOrNull;
    return entry?.profileKey ?? ref.read(inferenceBackendProvider).profileKey;
  }

  /// Null for the model's default; an unreadable preferences store degrades to
  /// null rather than blocking the turn. Guarded like _samplingOverrides.
  Future<String?> _systemPrompt() async {
    final preferences = ref.read(preferencesControllerProvider.future);
    try {
      final prompt = (await preferences).systemPrompt?.trim();
      return prompt == null || prompt.isEmpty ? null : prompt;
    } on Exception {
      return null;
    }
  }

  Future<void> _finalizeGeneration() async {
    final active = _value.active;
    if (active == null || active.messages.isEmpty) return;
    final messages = [...active.messages];
    messages[messages.length - 1] = messages.last.copyWith(isStreaming: false);
    final next =
        withActiveConversation(
          _value,
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
    _inFlight = null;
    if (!state.hasValue || _value.generation == GenerationPhase.idle) return;
    unawaited(ref.read(inferenceRepositoryProvider).cancel());
    final active = _value.active;
    if (active == null || active.messages.isEmpty) return;
    final next = withActiveConversation(_value, withStreamingSettled(active))
        .copyWith(
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
    state = AsyncData(
      withActiveConversation(_value, withTrailingTurnsDropped(active)).copyWith(
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
    final next =
        withActiveConversation(
          _value,
          withTrailingTurnsDropped(active),
        ).copyWith(
          generation: GenerationPhase.idle,
          clearFailure: true,
          hasUnsavedAssistant: false,
        );
    state = AsyncData(next);
    await _persist(next);
  }

  /// Removes the failed assistant draft and the user turn that deterministically
  /// cannot be replayed, such as one whose attachment disappeared. This is an
  /// explicit recovery action; ordinary Discard keeps the user's message.
  Future<void> removeFailedTurn() async {
    final active = _value.active;
    if (active == null) return;
    final next =
        withActiveConversation(
          _value,
          withTrailingTurnsDropped(active, alsoUser: true),
        ).copyWith(
          generation: GenerationPhase.idle,
          clearFailure: true,
          hasUnsavedAssistant: false,
        );
    state = AsyncData(next);
    await _persist(next);
  }

  /// The context-exhausted recovery: retrying can never fit the same
  /// conversation back into the window, so the banner offers a fresh chat.
  Future<void> startFreshChatFromFailure() async {
    await discardFailure();
    // The sixth post-await site, and the only one not reached through
    // _startGeneration: newChat opens with stop(), whose first act reads state.
    if (!ref.mounted) return;
    await newChat();
  }
}
