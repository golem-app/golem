import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/app_preferences.dart';
import '../domain/app_state.dart';
import '../domain/chat_search.dart';
import '../domain/generation_settings.dart';
import '../domain/inference_backend.dart';
import '../domain/model_catalog.dart';
import '../domain/models.dart';
import '../domain/response_style_mapping.dart';
import '../repositories/contracts.dart';
import '../services/cache_probe.dart';
import '../services/device_storage.dart';
import '../services/image_intake.dart';
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

@Riverpod(keepAlive: true)
PreferencesRepository preferencesRepository(Ref ref) =>
    throw UnimplementedError(
      'Override preferencesRepositoryProvider at startup',
    );

@Riverpod(keepAlive: true)
AttachmentRepository attachmentRepository(Ref ref) => throw UnimplementedError(
  'Override attachmentRepositoryProvider at startup',
);

@Riverpod(keepAlive: true)
CacheProbe cacheProbe(Ref ref) =>
    throw UnimplementedError('Override cacheProbeProvider at startup');

@Riverpod(keepAlive: true)
DiskSpaceProbe diskFreeSpaceProbe(Ref ref) =>
    throw UnimplementedError('Override diskFreeSpaceProbeProvider at startup');

/// The resolved inference backend for this process. A fake default rather than
/// a throwing seam — a documented exception to the repository-provider
/// discipline: dozens of widgets read it for honest "simulated" labeling, and
/// host tests (the dev flavor) must see the fake without every container
/// overriding it. main() always overrides it with the resolved config.
@Riverpod(keepAlive: true)
InferenceBackendConfig inferenceBackend(Ref ref) =>
    const InferenceBackendConfig.fake();

/// The catalog key of the model resident in the engine, straight from the
/// residency owner (#42). Null while the engine is empty — label helpers fall
/// back to the configured artifact, so a lazy first load does not blank the
/// chrome. Always null under a simulated backend, without touching the
/// repository seam: label-only containers must not need one.
@Riverpod(keepAlive: true)
String? residentModelKey(Ref ref) {
  if (ref.watch(inferenceBackendProvider).simulatedInference) return null;
  final listenable = ref.watch(inferenceRepositoryProvider).residentModelKey;
  void onChange() => ref.invalidateSelf();
  listenable.addListener(onChange);
  ref.onDispose(() => listenable.removeListener(onChange));
  return listenable.value;
}

@Riverpod(keepAlive: true)
DiskCapacityProbe deviceCapacityProbe(Ref ref) =>
    throw UnimplementedError('Override deviceCapacityProbeProvider at startup');

@Riverpod(keepAlive: true)
String documentsPath(Ref ref) =>
    throw UnimplementedError('Override documentsPathProvider at startup');

typedef StorageBreakdown = ({
  int modelsBytes,
  int chatsBytes,
  int attachmentsBytes,
  int cacheBytes,
  int? freeBytes,
  int? totalBytes,
});

extension StorageBreakdownTotals on StorageBreakdown {
  int get usedBytes => modelsBytes + chatsBytes + attachmentsBytes + cacheBytes;
}

/// A cheap signature that changes only when conversations or messages are added
/// or removed. ChatController reassigns state on every streaming delta, so
/// anything as heavy as disk probing must key on this rather than the raw chat
/// state, or it re-runs per token for the always-mounted drawer meter.
@Riverpod(keepAlive: true)
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

/// Storage accounting for the drawer meter and the Storage screen. Free and
/// total bytes are null whenever the platform cannot report them (or the seams
/// are unwired) — surfaces hide those figures instead of inventing them.
@Riverpod(keepAlive: true)
Future<StorageBreakdown> storageBreakdown(Ref ref) async {
  // Every dependency registers before the first await: a watch first taken
  // mid-computation would race its own invalidation.
  ref.watch(chatStorageSignatureProvider);
  final history = ref.watch(chatHistoryRepositoryProvider);
  AttachmentRepository? attachments;
  try {
    attachments = ref.watch(attachmentRepositoryProvider);
  } catch (_) {}
  CacheProbe? cache;
  try {
    cache = ref.watch(cacheProbeProvider);
  } catch (_) {}
  DiskSpaceProbe? free;
  try {
    free = ref.watch(diskFreeSpaceProbeProvider);
  } catch (_) {}
  DiskCapacityProbe? capacity;
  try {
    capacity = ref.watch(deviceCapacityProbeProvider);
  } catch (_) {}
  String? path;
  try {
    path = ref.watch(documentsPathProvider);
  } catch (_) {}
  final models = await ref.watch(modelControllerProvider.future);
  final modelsBytes = models.artifacts.values.fold(
    0,
    (sum, status) => sum + status.downloadedBytes,
  );
  var chatsBytes = 0;
  try {
    chatsBytes = await history.storedBytes();
  } catch (_) {}
  var attachmentsBytes = 0;
  try {
    attachmentsBytes = await attachments?.storedBytes() ?? 0;
  } catch (_) {}
  var cacheBytes = 0;
  try {
    cacheBytes = await cache?.sizeBytes() ?? 0;
  } catch (_) {}
  int? freeBytes;
  try {
    freeBytes = path == null ? null : await free?.freeBytes(path);
  } catch (_) {
    freeBytes = null;
  }
  int? totalBytes;
  try {
    totalBytes = path == null ? null : await capacity?.totalBytes(path);
  } catch (_) {
    totalBytes = null;
  }
  return (
    modelsBytes: modelsBytes,
    chatsBytes: chatsBytes,
    attachmentsBytes: attachmentsBytes,
    cacheBytes: cacheBytes,
    freeBytes: freeBytes,
    totalBytes: totalBytes,
  );
}

/// Pinned entries plus the user's custom repositories, derived — never stored —
/// so the pinned manifest stays the single source of model knowledge.
@Riverpod(keepAlive: true)
List<ModelCatalogEntry> effectiveModelCatalog(Ref ref) {
  final pinned = ref.watch(modelCatalogEntriesProvider);
  final custom =
      ref.watch(preferencesControllerProvider).value?.customModels ??
      const <CustomModelSpec>[];
  final pinnedKeys = {for (final entry in pinned) entry.key};
  return [
    ...pinned,
    for (final spec in custom)
      if (!pinnedKeys.contains(spec.key)) spec.toCatalogEntry(),
  ];
}

/// The raw field text stays widget-local in the search screen (debounced
/// 350 ms); only the normalized query lands here, so results derive reactively.
@Riverpod(keepAlive: true)
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';

  void publish(String raw) => state = raw.trim();
}

@Riverpod(keepAlive: true)
List<ChatSearchResult> chatSearchResults(Ref ref) {
  final query = ref.watch(searchQueryProvider);
  final conversations = ref.watch(chatControllerProvider).value?.conversations;
  return searchConversations(conversations ?? const [], query);
}

/// Only user-set values are stored; profile defaults resolve at the consumer.
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
    // A tap can land in the cold-start load window; dropping it beats throwing
    // on requireValue while the store is still reading.
    if (!state.hasValue) return;
    final next = _value.withModel(profileKey, overrides);
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }

  Future<void> resetModel(String profileKey) =>
      updateModel(profileKey, const SamplingOverrides());
}

/// Persisted app-wide preferences. Every command follows the settings idiom —
/// drop taps that land in the cold-start load window, publish, then save.
@Riverpod(keepAlive: true)
class PreferencesController extends _$PreferencesController {
  @override
  Future<AppPreferences> build() =>
      ref.read(preferencesRepositoryProvider).load();

  AppPreferences get _value => state.requireValue;

  Future<void> _commit(AppPreferences next) async {
    state = AsyncData(next);
    await ref.read(preferencesRepositoryProvider).save(next);
  }

  Future<void> setTheme(ThemeSetting theme) async {
    if (!state.hasValue) return;
    await _commit(_value.copyWith(theme: theme));
  }

  Future<void> setTextScale(double scale) async {
    if (!state.hasValue) return;
    await _commit(_value.copyWith(textScale: scale));
  }

  Future<void> setShowMetrics(bool value) async {
    if (!state.hasValue) return;
    await _commit(_value.copyWith(showMetrics: value));
  }

  Future<void> setExpandReasoning(bool value) async {
    if (!state.hasValue) return;
    await _commit(_value.copyWith(expandReasoning: value));
  }

  Future<void> setHapticsOnSend(bool value) async {
    if (!state.hasValue) return;
    await _commit(_value.copyWith(hapticsOnSend: value));
  }

  Future<void> setAdvancedMode(bool value) async {
    if (!state.hasValue) return;
    await _commit(_value.copyWith(advancedMode: value));
  }

  /// Null or blank clears the prompt back to the model default.
  Future<void> setSystemPrompt(String? prompt) async {
    if (!state.hasValue) return;
    final trimmed = prompt?.trim();
    await _commit(
      _value.copyWith(
        systemPrompt: () => trimmed == null || trimmed.isEmpty ? null : trimmed,
      ),
    );
  }

  Future<void> setResponseStyle(String profileKey, ResponseStyle style) async {
    if (!state.hasValue) return;
    await _commit(_value.withStyle(profileKey, style));
  }

  /// Turning history off empties the on-disk store immediately: the design copy
  /// promises chats disappear. Past consent — the alert lives in the widget.
  Future<void> setSaveHistory(bool save) async {
    if (!state.hasValue) return;
    await _commit(_value.copyWith(saveHistory: save));
    if (save) {
      await ref.read(chatControllerProvider.notifier).persistCurrent();
    } else {
      await ref
          .read(chatHistoryRepositoryProvider)
          .save(const ChatHistorySnapshot(conversations: []));
    }
  }

  Future<void> addCustomModel(CustomModelSpec spec) async {
    if (!state.hasValue) return;
    await _commit(_value.withCustomModel(spec));
    await ref
        .read(modelControllerProvider.notifier)
        .registerCustomModel(spec.toCatalogEntry());
  }
}

@Riverpod(keepAlive: true)
class ChatController extends _$ChatController {
  int _generationEpoch = 0;

  @override
  Future<ChatState> build() async {
    ref.onDispose(() => _generationEpoch++);
    final snapshot = await ref.read(chatHistoryRepositoryProvider).load();
    await _retainReferenced(_attachments, snapshot.conversations);
    return ChatState(
      conversations: snapshot.conversations,
      activeId: snapshot.activeId,
    );
  }

  Future<void> _persist(ChatState value) async {
    // Every seam is read before the first await: this method outlives its
    // provider on a fast dispose, and Ref is unusable past that point. Privacy
    // gate: with history off, chats live in memory only; a cold start saves.
    final preferences = ref.read(preferencesControllerProvider).value;
    final history = ref.read(chatHistoryRepositoryProvider);
    final attachments = _attachments;

    // Attachment bytes follow the live conversations, not the disk snapshot:
    // with history off the pictures must stay readable for the session.
    await _retainReferenced(attachments, value.conversations);
    if (preferences != null && !preferences.saveHistory) return;
    await history.save(
      ChatHistorySnapshot(
        conversations: value.conversations,
        activeId: value.activeId,
      ),
    );
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

  /// The confirmation alert lives at the widget layer; this is past consent.
  Future<void> deleteAllChats() async {
    stop();
    final next = ChatState(conversations: const []);
    state = AsyncData(next);
    // Both seams read before the first await, as in _persist.
    final history = ref.read(chatHistoryRepositoryProvider);
    final attachments = _attachments;
    // Directly, not via _persist: the wipe must reach disk even when the
    // save-history gate is closed.
    await history.save(const ChatHistorySnapshot(conversations: []));
    await _retainReferenced(attachments, const []);
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

  Future<void> setConversationModel(String id, String? modelKey) async {
    if (_value.generation != GenerationPhase.idle) return;
    final next = _value.copyWith(
      conversations: [
        for (final item in _value.conversations)
          if (item.id == id) item.withModel(modelKey) else item,
      ],
    );
    state = AsyncData(next);
    await _persist(next);
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
          failure: const ChatFailure(
            kind: ChatFailureKind.generic,
            message: 'That image could not be saved. Try attaching it again.',
          ),
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
    final title = active.messages.isEmpty
        ? normalizeTitle(text.isEmpty ? 'Image' : text)
        : active.title;
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
    final edited = ChatMessage.text(
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
    // Real backend with the active artifact not installed: fail fast into the
    // banner's download CTA — prepare() would only give a cryptic missing-file
    // error after a hang-like pause. Catalog-derived paths only: an
    // operator-supplied GOLEM_MODEL_PATH must reach prepare() untouched.
    final backend = ref.read(inferenceBackendProvider);
    if (!backend.simulatedInference &&
        backend.artifactKey != null &&
        backend.modelPathFromCatalog) {
      final installed = await _activeModelInstalled();
      if (!ref.mounted || epoch != _generationEpoch) return;
      if (installed == false) {
        state = AsyncData(
          _value.copyWith(
            generation: GenerationPhase.failed,
            failure: ChatFailure(
              kind: ChatFailureKind.missingModel,
              message:
                  'The local model is not downloaded on this device yet. '
                  'Download it to start chatting.',
              artifactKey: backend.artifactKey,
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
      // The conversation's own model, not the boot configuration: generate()
      // below activates `active.modelKey`, so a keyless prepare would cost two
      // multi-gigabyte loads per send.
      await ref
          .read(inferenceRepositoryProvider)
          .prepare(modelKey: active.modelKey);
      if (!ref.mounted || epoch != _generationEpoch) return;
      // After this prepare() the engine holds weights, so Settings may not keep
      // claiming "Unloaded". Awaited on purpose: a recorded phase must not race
      // the stream it describes.
      if (!backend.simulatedInference) {
        await ref.read(modelControllerProvider.notifier).reflectEngineLoaded();
        if (!ref.mounted || epoch != _generationEpoch) return;
      }
      state = AsyncData(_value.copyWith(generation: GenerationPhase.streaming));
      final context = active.promptContext;
      final overrides = await _samplingOverrides();
      final systemPrompt = await _systemPrompt();
      if (!ref.mounted || epoch != _generationEpoch) return;
      await for (final event
          in ref
              .read(inferenceRepositoryProvider)
              .generate(
                context: context,
                reasoningEnabled: active.reasoningEnabled,
                overrides: overrides,
                modelKey: active.modelKey,
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

  /// Typed inference exceptions carry their own copy and recovery kind; the
  /// rest get fixed generic copy — raw exception text never reaches it (§19.4).
  static ChatFailure _classifiedFailure(Object error) => switch (error) {
    InferenceException(:final kind, :final message) => ChatFailure(
      kind: switch (kind) {
        InferenceFailureKind.contextExhausted =>
          ChatFailureKind.contextExhausted,
        InferenceFailureKind.outOfMemory => ChatFailureKind.outOfMemory,
        InferenceFailureKind.insufficientMemory =>
          ChatFailureKind.insufficientMemory,
        InferenceFailureKind.engine ||
        InferenceFailureKind.budgetExhaustedBeforeAnswer =>
          ChatFailureKind.generic,
      },
      message: message,
    ),
    _ => const ChatFailure(
      kind: ChatFailureKind.generic,
      message: 'Something went wrong while generating a response.',
    ),
  };

  /// Null when model state is unavailable — generation then proceeds and
  /// prepare() stays the loud failure path, rather than inventing a verdict.
  Future<bool?> _activeModelInstalled() async {
    try {
      final models = await ref.read(modelControllerProvider.future);
      return models.activeModelInstalled;
    } catch (_) {
      return null;
    }
  }

  /// The response style's values with the user's hand-set Advanced overrides
  /// layered on top, knob by knob. Settings that fail to surface must never
  /// block chat, so each layer degrades independently to nothing.
  Future<SamplingOverrides?> _samplingOverrides() async {
    final profileKey = ref.read(inferenceBackendProvider).profileKey;
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
      // still throws must land on the card, not blank the screen as AsyncError.
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

  /// Records that the engine holds weights after ChatController's lazy
  /// prepare(). Skips sideloaded paths — outside the catalog's phase tracking.
  Future<void> reflectEngineLoaded() async {
    if (_busy) return;
    final current = state.value;
    if (current == null ||
        current.runtime == RuntimePhase.loaded ||
        !current.activeModelInstalled) {
      return;
    }
    _busy = true;
    try {
      final value = await ref
          .read(modelManagementRepositoryProvider)
          .recordRuntime(RuntimePhase.loaded);
      if (!ref.mounted) return;
      state = AsyncData(value);
    } catch (_) {
      // Phase bookkeeping must never disturb an in-flight generation.
    } finally {
      _busy = false;
    }
  }

  /// Fast and non-streaming, so it skips the busy gate.
  Future<void> registerCustomModel(ModelCatalogEntry entry) async {
    try {
      final value = await ref
          .read(modelManagementRepositoryProvider)
          .addModel(entry);
      if (!ref.mounted) return;
      state = AsyncData(value);
    } catch (error) {
      _publishFailure(entry.key, error);
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

  /// The persisted RuntimePhase must reflect the engine, not bookkeeping: a
  /// real `prepare()`/`unload()` runs before the phase is recorded — the
  /// deferred #37 finding, and only the inference repository touches the engine
  /// (#42). Engine failures stay in memory as a failed phase.
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
        final value = await repository.recordRuntime(RuntimePhase.unloaded);
        if (!ref.mounted) return;
        state = AsyncData(value);
      } else {
        // Publish loading at once so the UI can disable the toggle.
        state = AsyncData(
          current.copyWith(runtime: RuntimePhase.loading, clearFailure: true),
        );
        if (!current.activeModelInstalled) {
          // Refuse with a persisted failed phase; the engine is never touched.
          final value = await repository.recordRuntime(
            RuntimePhase.failed,
            failure: _installFirstFailure(current),
          );
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
        final value = await repository.recordRuntime(RuntimePhase.loaded);
        if (!ref.mounted) return;
        state = AsyncData(value);
      }
    } finally {
      _busy = false;
    }
  }

  /// Frees the engine on an OS memory-pressure signal or backgrounding — the
  /// app must never hold multi-gigabyte weights it is not using while the
  /// platform reclaims memory. Only when idle: an advisory signal never cancels
  /// a visible stream, and the busy guard keeps it off a model operation.
  Future<void> releaseEngineWhileInactive() async {
    if (_busy) return;
    final current = state.value;
    if (current == null) return;
    final chat = ref.read(chatControllerProvider).value;
    if (chat != null && chat.generation != GenerationPhase.idle) return;
    _busy = true;
    try {
      final inference = ref.read(inferenceRepositoryProvider);
      // Residency decides, not the catalog phase: a GOLEM_MODEL_PATH load is
      // outside phase tracking, yet just as resident and just as jetsammable.
      final loaded = current.runtime == RuntimePhase.loaded;
      if (!loaded && inference.residentModelKey.value == null) return;
      await inference.unload();
      if (!ref.mounted || !loaded) return;
      final value = await ref
          .read(modelManagementRepositoryProvider)
          .recordRuntime(RuntimePhase.unloaded);
      if (!ref.mounted) return;
      state = AsyncData(value);
    } catch (_) {
      // Advisory signal: no user-visible failure state.
    } finally {
      _busy = false;
    }
  }

  /// The load-refusal copy for a not-installed active model. Owned here since
  /// #42: the management repository no longer knows why a load was refused.
  String _installFirstFailure(ModelState current) {
    if (current.activeArtifactKey == null) {
      return 'Inference is a build-time opt-in; no backend is configured.';
    }
    return ref.read(inferenceBackendProvider).simulatedInference
        ? 'Install the selected simulated model first.'
        : 'Download and install the active model first.';
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
    // Recovery deliberately succeeds: the injected failure exists to show the
    // failure UI, retry the recovery path — with real StartupSequence timing.
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

  // A result belongs to the exact case/phase it was produced for.
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
