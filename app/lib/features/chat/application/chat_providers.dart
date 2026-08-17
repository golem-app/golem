import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/app_state.dart';
import '../../../core/domain/generation_settings.dart';
import '../../../core/domain/model_catalog.dart';
import '../../../core/domain/model_activation.dart';
import '../../../core/domain/models.dart';
import '../../../core/domain/response_style_mapping.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';
import '../../../core/repositories/contracts.dart';
import '../../../core/services/image_intake.dart';
import '../../models/application/model_providers.dart';
import '../../settings/application/preferences_providers.dart';
import '../../settings/application/settings_providers.dart';

part 'chat_providers.g.dart';

/// A cheap signature that changes only when conversations or messages are added
/// or removed. ChatController reassigns state on every streaming delta, so
/// anything as heavy as disk probing must key on this rather than the raw chat
/// state, or it re-runs per token for the always-mounted drawer meter.
/// KeepAlive, deliberately (#69): would classify as an autoDispose derived
/// value, but on the pinned flutter_riverpod (3.3.2) a widget-watched
/// derivation over an async controller still trips Flutter's element-update
/// invariant when a provider scope is swapped mid-test — the class of bug
/// fixed upstream in 3.4.0 ("markNeedsBuild ... inside Widget lifecycle").
/// The pin cannot move on this SDK — flutter_test's test_api caps analyzer
/// below the ^13 the newer generator needs, and the family is exact-pinned
/// end to end (docs/notes/dependencies.md). Revisit on the SDK bump (#38).
@Riverpod(keepAlive: true, retry: noRetry)
(int, int) chatStorageSignature(Ref ref) {
  final conversations =
      ref.watch(chatControllerProvider).value?.conversations ??
      const <ChatConversation>[];
  var messages = 0;
  for (final conversation in conversations) {
    messages += conversation.messages.length;
  }
  return (conversations.length, messages);
}

/// KeepAlive: the chat session aggregate — in-flight generation and unsaved
/// turns must survive every route transition.
@Riverpod(keepAlive: true, retry: noRetry)
class ChatController extends _$ChatController {
  int _generationEpoch = 0;
  int _persistenceEpoch = 0;

  @override
  Future<ChatState> build() async {
    ref.onDispose(() {
      _generationEpoch++;
      _persistenceEpoch++;
    });
    // Bound before the first await so commands arriving during hydration see
    // it. Watched, not read: if the bridge is ever refreshed, this rebuild
    // re-binds the fresh instance instead of leaving readers unbound (#88).
    final bridge = ref.watch(chatSessionBridgeProvider);
    bridge.bindPersistCurrent(persistCurrent);
    bridge.bindSessionState(() => state.value);
    final snapshot = await ref.read(chatHistoryRepositoryProvider).load();
    await _retainReferenced(_attachments, snapshot.conversations);
    return ChatState(
      conversations: snapshot.conversations,
      activeId: snapshot.activeId,
    );
  }

  Future<void> _persist(
    ChatState value, {
    bool showRetryProgress = false,
  }) async {
    final epoch = ++_persistenceEpoch;
    // Every seam is read before the first await: this method outlives its
    // provider on a fast dispose, and Ref is unusable past that point. Privacy
    // gate: with history off, chats live in memory only; a cold start saves.
    final preferences = ref.read(preferencesControllerProvider).value;
    final history = ref.read(chatHistoryRepositoryProvider);
    final attachments = _attachments;

    if (showRetryProgress && ref.mounted && epoch == _persistenceEpoch) {
      _setPersistencePhase(ChatPersistencePhase.retrying);
    }

    if (preferences != null && !preferences.saveHistory) {
      // With history off, attachment bytes follow the live session instead of
      // a durable snapshot. No history write or retry is permitted here.
      await _retainReferenced(attachments, value.conversations);
      if (ref.mounted && epoch == _persistenceEpoch) {
        _setPersistencePhase(ChatPersistencePhase.idle);
      }
      return;
    }

    final snapshot = _persistenceSnapshot(value);
    try {
      await history.save(snapshot);
    } on PersistenceException catch (error) {
      if (error.kind != PersistenceFailureKind.write) rethrow;
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
    await _retainReferenced(attachments, snapshot.conversations);
  }

  /// The newest complete, persistence-eligible view of the live session. A
  /// streaming or failed assistant draft is intentionally absent until Stop
  /// or finalization marks it durable; the user turn and every completed turn
  /// remain included.
  static ChatHistorySnapshot _persistenceSnapshot(ChatState value) {
    final active = value.active;
    if (!value.hasUnsavedAssistant ||
        active == null ||
        active.messages.lastOrNull?.role != MessageRole.assistant) {
      return ChatHistorySnapshot(
        conversations: value.conversations,
        activeId: value.activeId,
      );
    }
    final messages = [...active.messages]..removeLast();
    return ChatHistorySnapshot(
      conversations: [
        for (final conversation in value.conversations)
          if (conversation.id == active.id)
            active.copyWith(messages: messages)
          else
            conversation,
      ],
      activeId: value.activeId,
    );
  }

  void _setPersistencePhase(ChatPersistencePhase phase) {
    if (!state.hasValue || _value.persistencePhase == phase) return;
    state = AsyncData(_value.copyWith(persistencePhase: phase));
  }

  /// Null when the seam is unwired, which label-only test containers rely on.
  AttachmentRepository? get _attachments {
    try {
      return ref.read(attachmentRepositoryProvider);
    } catch (_) {
      return null;
    }
  }

  /// Drops attachment bytes no conversation references. Failures are swallowed:
  /// an orphan costs disk, an aborted send would cost the user their message.
  static Future<void> _retainReferenced(
    AttachmentRepository? attachments,
    List<ChatConversation> conversations,
  ) async {
    if (attachments == null) return;
    try {
      await attachments.retainOnly({
        for (final conversation in conversations) ...conversation.attachmentIds,
      });
    } catch (_) {}
  }

  Future<ImagePart> _storeAttachment(PreparedImage image) async {
    final attachments = _attachments;
    if (attachments == null) {
      throw StateError('No attachment store is wired.');
    }
    final stored = await attachments.store(
      image.bytes,
      mimeType: image.mimeType,
    );
    return ImagePart(
      attachmentId: stored.id,
      mimeType: stored.mimeType,
      width: image.width,
      height: image.height,
      byteCount: stored.byteCount,
    );
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
    // Both seams read before the first await, as in _persist.
    final history = ref.read(chatHistoryRepositoryProvider);
    final attachments = _attachments;
    try {
      // Directly, not via _persist: the wipe must reach disk even when the
      // save-history gate is closed.
      await history.save(const ChatHistorySnapshot(conversations: []));
    } on Exception {
      return false;
    }
    // Only a committed wipe supersedes an earlier save or retry. If the wipe
    // fails, that attempt must still be allowed to settle the recovery notice.
    _persistenceEpoch++;
    if (ref.mounted) state = AsyncData(ChatState(conversations: const []));
    await _retainReferenced(attachments, const []);
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

  Future<void> newChat() async {
    stop();
    final now = DateTime.now();
    final backend = ref.read(inferenceBackendProvider);
    final selectedKey = backend.simulatedInference
        ? ref.read(preferencesControllerProvider).value?.onboardingModelKey
        : ref.read(startupModelKeyProvider);
    final conversation = ChatConversation(
      id: newId(),
      title: '',
      messages: const [],
      updatedAt: now,
      // First run is allowed to name a compatible model before its weights
      // finish downloading. Sending remains gated in the composer and again in
      // _startGeneration; after installation the existing loadable-key rule
      // makes every model label follow this persisted choice.
      modelKey: selectedKey,
    );
    final next = ChatState(
      conversations: [conversation, ..._value.conversations],
      activeId: conversation.id,
      persistencePhase: _value.persistencePhase,
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
    final next = ChatState(
      conversations: remaining,
      activeId: requested,
      persistencePhase: _value.persistencePhase,
    );
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

  Future<void> togglePinned(String id) async {
    // Metadata-only, like rename: safe while a generation streams.
    final next = _value.copyWith(
      conversations: [
        for (final item in _value.conversations)
          if (item.id == id) item.togglePinned() else item,
      ],
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
    final next = _value.copyWith(
      conversations: [
        for (final item in _value.conversations)
          if (item.id == id) item.withModel(modelKey) else item,
      ],
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
    try {
      return ref.read(loadableModelKeysProvider).contains(modelKey);
    } catch (_) {
      return false;
    }
  }

  /// Empty when the catalog seam is unwired. A container without one must not
  /// turn a send into a crash — the same degrade-independently rule the
  /// settings layers follow, and prepare() stays the loud path.
  List<ModelCatalogEntry> _catalog() {
    try {
      return ref.read(effectiveModelCatalogProvider);
    } catch (_) {
      return const [];
    }
  }

  Future<void> deleteMessage(String messageId) async {
    final active = _value.active;
    if (active == null || _value.generation != GenerationPhase.idle) return;
    final next = _replaceActive(active.withoutMessage(messageId));
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
    final next = ChatState(
      conversations: [branched, ..._value.conversations],
      activeId: branched.id,
      persistencePhase: _value.persistencePhase,
    );
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
    final active = _value.active!;

    final List<MessagePart> parts;
    try {
      parts = [
        for (final image in images) await _storeAttachment(image),
        if (text.isNotEmpty) TextPart(text),
      ];
    } catch (error, stackTrace) {
      // The bytes never reached disk, so nothing is half-sent: surface the
      // failure and keep the composer's content for another try.
      state = AsyncData(
        _value.copyWith(
          failure: const ChatFailure(kind: ChatFailureKind.attachmentSave),
        ),
      );
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
    // withText, not a fresh text message: a re-run of an image turn is still an
    // image turn, and dropping the part would unlink its bytes on the next save.
    final edited = active.messages[index].withText(text);
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
    // Real backend with the model this send needs not installed: fail fast into
    // the banner's download CTA — prepare() would only give a cryptic
    // missing-file error after a hang-like pause. The conversation's own choice
    // decides which artifact that is (#20). An operator-supplied
    // GOLEM_MODEL_PATH must reach prepare() untouched, and a key this build no
    // longer carries is prepare()'s own typed failure to describe.
    final backend = ref.read(inferenceBackendProvider);
    // A device outside every supported tier stops here (#27): prepare() could
    // only fail, and the missing-model banner below would otherwise offer a
    // multi-gigabyte download whose weights this device can never load. The
    // sideload exemption does not apply — an operator's own file needs the
    // same memory and the same instruction set.
    final refusal = ref.read(deviceRefusalProvider);
    if (refusal != null) {
      state = AsyncData(
        _value.copyWith(
          generation: GenerationPhase.failed,
          failure: const ChatFailure(kind: ChatFailureKind.unsupportedDevice),
        ),
      );
      return;
    }
    Set<String>? loadable;
    try {
      loadable = ref.read(loadableModelKeysProvider);
    } catch (_) {
      // Narrow controller tests and degraded containers may omit the catalog
      // seams. The repository remains the final authority in that case.
    }
    final catalog = _catalog();
    final resolvedTarget = effectiveModelKey(
      backend: backend,
      catalog: catalog,
      modelKey: active.modelKey,
      residentModelKey: ref.read(residentModelKeyProvider),
      loadableKeys: loadable,
    );
    // A known empty compatible set is authoritative. Only a deliberately
    // narrow/degraded container that could not expose that set delegates the
    // old key to the repository as a final typed-failure boundary.
    final target =
        resolvedTarget ??
        (loadable == null ? active.modelKey ?? backend.artifactKey : null);
    final entry = target == null
        ? null
        : _catalog().where((item) => item.key == target).firstOrNull;
    if (!backend.simulatedInference && !backend.sideloaded && target == null) {
      state = AsyncData(
        _value.copyWith(
          generation: GenerationPhase.failed,
          failure: ChatFailure(
            kind: ChatFailureKind.missingModel,
            artifactKey: backend.artifactKey,
          ),
        ),
      );
      return;
    }
    if (!backend.simulatedInference && !backend.sideloaded && entry != null) {
      final installed = await _modelInstalled(entry.key);
      if (!ref.mounted || epoch != _generationEpoch) return;
      if (installed == false) {
        state = AsyncData(
          _value.copyWith(
            generation: GenerationPhase.failed,
            failure: ChatFailure(
              kind: ChatFailureKind.missingModel,
              artifactKey: entry.key,
            ),
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
      _replaceActive(
        active.copyWith(messages: [...active.messages, assistant]),
      ).copyWith(
        generation: GenerationPhase.preparing,
        hasUnsavedAssistant: true,
        clearFailure: true,
      ),
    );
    try {
      // The effective target, not blindly the boot or historical chat key:
      // generate() below activates the same target, so a keyless prepare would
      // cost two multi-gigabyte loads per send and a stale key could cross
      // model profiles.
      await ref.read(inferenceRepositoryProvider).prepare(modelKey: target);
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
      final overrides = await _samplingOverrides(target);
      final systemPrompt = await _systemPrompt();
      if (!ref.mounted || epoch != _generationEpoch) return;
      await for (final event
          in ref
              .read(inferenceRepositoryProvider)
              .generate(
                context: context,
                reasoningEnabled: active.reasoningEnabled,
                overrides: overrides,
                modelKey: target,
                systemPrompt: systemPrompt,
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
          messages[messages.length - 1] = draft.withText(
            '${draft.text}${event.text}',
          );
        } else if (event is AnswerResetEvent) {
          messages[messages.length - 1] = draft.withText('');
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
            failure: _classifiedFailure(error),
            hasUnsavedAssistant: true,
          ),
        );
      }
    }
  }

  /// Typed inference exceptions retain their recovery kind and safe arguments;
  /// presentation owns localized copy. Unknown errors stay generic, and raw
  /// exception text never reaches the banner (handbook v5.0 §8.1).
  static ChatFailure _classifiedFailure(Object error) => switch (error) {
    InferenceException(:final kind, :final contextTokens) => ChatFailure(
      kind: switch (kind) {
        InferenceFailureKind.contextExhausted =>
          ChatFailureKind.contextExhausted,
        InferenceFailureKind.outOfMemory => ChatFailureKind.outOfMemory,
        InferenceFailureKind.insufficientMemory =>
          ChatFailureKind.insufficientMemory,
        InferenceFailureKind.budgetExhaustedBeforeAnswer =>
          ChatFailureKind.budgetExhaustedBeforeAnswer,
        InferenceFailureKind.modelUnavailable =>
          ChatFailureKind.modelUnavailable,
        InferenceFailureKind.unsupportedModel =>
          ChatFailureKind.unsupportedModel,
        InferenceFailureKind.attachmentUnavailable =>
          ChatFailureKind.attachmentUnavailable,
        InferenceFailureKind.unsupportedImages =>
          ChatFailureKind.unsupportedImages,
        InferenceFailureKind.invalidModelArtifact =>
          ChatFailureKind.invalidModelArtifact,
        InferenceFailureKind.unsupportedDevice =>
          ChatFailureKind.unsupportedDevice,
        InferenceFailureKind.engine => ChatFailureKind.generic,
      },
      contextTokens: contextTokens,
    ),
    _ => const ChatFailure(kind: ChatFailureKind.generic),
  };

  /// Null when model state is unavailable — generation then proceeds and
  /// prepare() stays the loud failure path, rather than inventing a verdict.
  Future<bool?> _modelInstalled(String artifactKey) async {
    try {
      final models = await ref.read(modelControllerProvider.future);
      return models.statusOf(artifactKey).phase == ArtifactPhase.installed;
    } catch (_) {
      return null;
    }
  }

  /// The response style's values with the user's hand-set Advanced overrides
  /// layered on top, knob by knob. Settings that fail to surface must never
  /// block chat, so each layer degrades independently to nothing.
  Future<SamplingOverrides?> _samplingOverrides(String? modelKey) async {
    final profileKey = _profileKeyFor(modelKey);
    var manual = const SamplingOverrides();
    try {
      final settings = await ref.read(settingsControllerProvider.future);
      manual = settings.overridesFor(profileKey);
    } catch (_) {}
    var style = const SamplingOverrides();
    try {
      final preferences = await ref.read(preferencesControllerProvider.future);
      style = styleOverridesFor(profileKey, preferences.styleFor(profileKey));
    } catch (_) {}
    final merged = layerOverrides(manual: manual, style: style);
    return merged.isEmpty ? null : merged;
  }

  /// The profile of the model this chat runs, so hand-set sampling and the
  /// response style follow a switch instead of staying on the build's boot
  /// profile — switching Gemma to Qwen otherwise applies Gemma's numbers (#20).
  String _profileKeyFor(String? modelKey) {
    final entry = modelKey == null
        ? null
        : _catalog().where((item) => item.key == modelKey).firstOrNull;
    return entry?.profileKey ?? ref.read(inferenceBackendProvider).profileKey;
  }

  /// Null for the model's default; unavailable preferences degrade to null.
  Future<String?> _systemPrompt() async {
    try {
      final preferences = await ref.read(preferencesControllerProvider.future);
      final prompt = preferences.systemPrompt?.trim();
      return prompt == null || prompt.isEmpty ? null : prompt;
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

  /// Removes the failed assistant draft and the user turn that deterministically
  /// cannot be replayed, such as one whose attachment disappeared. This is an
  /// explicit recovery action; ordinary Discard keeps the user's message.
  Future<void> removeFailedTurn() async {
    final active = _value.active;
    if (active == null) return;
    final messages = [...active.messages];
    if (messages.lastOrNull?.role == MessageRole.assistant) {
      messages.removeLast();
    }
    if (messages.lastOrNull?.role == MessageRole.user) {
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

  /// The context-exhausted recovery: retrying can never fit the same
  /// conversation back into the window, so the banner offers a fresh chat.
  Future<void> startFreshChatFromFailure() async {
    await discardFailure();
    await newChat();
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
