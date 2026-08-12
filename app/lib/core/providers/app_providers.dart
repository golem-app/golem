import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../app_identity.dart';
import '../application/storage_breakdown_service.dart';
import '../domain/app_preferences.dart';
import '../domain/app_state.dart';
import '../domain/device_eligibility.dart';
import '../domain/equality.dart';
import '../domain/generation_settings.dart';
import '../domain/inference_backend.dart';
import '../domain/model_activation.dart' as domain;
import '../domain/model_catalog.dart';
import '../domain/models.dart';
import '../domain/response_style_mapping.dart';
import '../repositories/contracts.dart';
import '../services/cache_probe.dart';
import '../services/custom_repository_resolver.dart';
import '../services/device_storage.dart';
import '../services/image_intake.dart';
import '../startup/startup_sequence.dart';
import 'retry.dart';

// The breakdown types moved with their service; consumers keep importing
// them from here beside the provider that produces them.
export '../application/storage_breakdown_service.dart'
    show StorageBreakdown, StorageBreakdownTotals;

part 'app_providers.g.dart';

/// A value-equal projection of the only preference leaf the model-catalog
/// derivations consume. Watching the whole [AppPreferences] object made a
/// language or theme change invalidate the catalog while the app root was
/// rebuilding Localizations, which trips Riverpod 3.3.2's known mid-build
/// refresh hazard. The unmodifiable view remains owned by AppPreferences.
final class _CustomModelsSelection {
  const _CustomModelsSelection(this.models);

  final List<CustomModelSpec> models;

  @override
  bool operator ==(Object other) =>
      other is _CustomModelsSelection && listEquals(other.models, models);

  @override
  int get hashCode => listHash(models);
}

_CustomModelsSelection _customModelsFrom(AsyncValue<AppPreferences> value) =>
    _CustomModelsSelection(
      value.value?.customModels ?? const <CustomModelSpec>[],
    );

// Lifetime policy (#69): the repository/probe seams below are keepAlive
// because they are composition-injected process-lifetime dependencies —
// overridden once in main.dart, never recomputed; disposing one could only
// re-throw its seam. Providers with a narrower owner say so individually.

@Riverpod(keepAlive: true, retry: noRetry)
ChatHistoryRepository chatHistoryRepository(Ref ref) =>
    throw UnimplementedError(
      'Override chatHistoryRepositoryProvider at startup',
    );

@Riverpod(keepAlive: true, retry: noRetry)
InferenceRepository inferenceRepository(Ref ref) =>
    throw UnimplementedError('Override inferenceRepositoryProvider at startup');

@Riverpod(keepAlive: true, retry: noRetry)
ModelManagementRepository modelManagementRepository(Ref ref) =>
    throw UnimplementedError(
      'Override modelManagementRepositoryProvider at startup',
    );

@Riverpod(keepAlive: true, retry: noRetry)
BenchmarkRepository benchmarkRepository(Ref ref) =>
    throw UnimplementedError('Override benchmarkRepositoryProvider at startup');

@Riverpod(keepAlive: true, retry: noRetry)
List<ModelCatalogEntry> modelCatalogEntries(Ref ref) =>
    throw UnimplementedError('Override modelCatalogEntriesProvider at startup');

@Riverpod(keepAlive: true, retry: noRetry)
CustomRepositoryResolver customRepositoryResolver(Ref ref) =>
    throw UnimplementedError(
      'Override customRepositoryResolverProvider at startup',
    );

@Riverpod(keepAlive: true, retry: noRetry)
SettingsRepository settingsRepository(Ref ref) =>
    throw UnimplementedError('Override settingsRepositoryProvider at startup');

@Riverpod(keepAlive: true, retry: noRetry)
PreferencesRepository preferencesRepository(Ref ref) =>
    throw UnimplementedError(
      'Override preferencesRepositoryProvider at startup',
    );

@Riverpod(keepAlive: true, retry: noRetry)
AttachmentRepository attachmentRepository(Ref ref) => throw UnimplementedError(
  'Override attachmentRepositoryProvider at startup',
);

@Riverpod(keepAlive: true, retry: noRetry)
CacheProbe cacheProbe(Ref ref) =>
    throw UnimplementedError('Override cacheProbeProvider at startup');

@Riverpod(keepAlive: true, retry: noRetry)
DiskSpaceProbe diskFreeSpaceProbe(Ref ref) =>
    throw UnimplementedError('Override diskFreeSpaceProbeProvider at startup');

/// The resolved inference backend for this process. A fake default rather than
/// a throwing seam — a documented exception to the repository-provider
/// discipline: dozens of widgets read it for honest "simulated" labeling, and
/// host tests (the dev flavor) must see the fake without every container
/// overriding it. main() always overrides it with the resolved config.
/// KeepAlive: process-constant boot configuration.
@Riverpod(keepAlive: true, retry: noRetry)
InferenceBackendConfig inferenceBackend(Ref ref) =>
    const InferenceBackendConfig.fake();

/// What this device is allowed to run, classified once at launch (#27). A
/// permitting default rather than a throwing seam, for the same reason
/// [inferenceBackend] has one: surfaces across chat and Settings read it, and a
/// container that never classified a device must not refuse anything. main()
/// always overrides it with the real verdict.
/// KeepAlive: process-constant boot configuration.
@Riverpod(keepAlive: true, retry: noRetry)
DeviceEligibility deviceEligibility(Ref ref) =>
    const DeviceEligibility.unclassified();

/// The refusal an unsupported device must present before any download or load,
/// or null when this device may run models. Derived once and watched by every
/// surface that gates on it, so the rule — including that a simulated backend
/// is never gated, since it loads no weights and gating it would only make QA
/// depend on hardware — exists in exactly one place.
/// KeepAlive: derived from two process-constant boot values.
@Riverpod(keepAlive: true, retry: noRetry)
String? deviceRefusal(Ref ref) =>
    ref.watch(inferenceBackendProvider).simulatedInference
    ? null
    : ref.watch(deviceEligibilityProvider).refusal;

/// The catalog key of the model resident in the engine, straight from the
/// residency owner (#42). Null while the engine is empty — label helpers fall
/// back to the configured artifact, so a lazy first load does not blank the
/// chrome. Always null under a simulated backend, without touching the
/// repository seam: label-only containers must not need one.
/// KeepAlive: holds the live ValueListenable subscription onto #42's
/// residency owner; autoDispose would churn that listener per route.
@Riverpod(keepAlive: true, retry: noRetry)
String? residentModelKey(Ref ref) {
  if (ref.watch(inferenceBackendProvider).simulatedInference) return null;
  final listenable = ref.watch(inferenceRepositoryProvider).residentModelKey;
  void onChange() => ref.invalidateSelf();
  listenable.addListener(onChange);
  ref.onDispose(() => listenable.removeListener(onChange));
  return listenable.value;
}

@Riverpod(keepAlive: true, retry: noRetry)
DiskCapacityProbe deviceCapacityProbe(Ref ref) =>
    throw UnimplementedError('Override deviceCapacityProbeProvider at startup');

@Riverpod(keepAlive: true, retry: noRetry)
String documentsPath(Ref ref) =>
    throw UnimplementedError('Override documentsPathProvider at startup');

/// A cheap signature that changes only when conversations or messages are added
/// or removed. ChatController reassigns state on every streaming delta, so
/// anything as heavy as disk probing must key on this rather than the raw chat
/// state, or it re-runs per token for the always-mounted drawer meter.
/// KeepAlive, deliberately (#69): would classify as an autoDispose derived
/// value, but on the pinned flutter_riverpod (3.3.2) a widget-watched
/// derivation over an async controller still trips Flutter's element-update
/// invariant when a provider scope is swapped mid-test — the class of bug
/// fixed upstream in 3.4.0 ("markNeedsBuild ... inside Widget lifecycle").
/// Revisit when the pin crosses 3.4.0.
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

/// Storage accounting for the drawer meter and the Storage screen. Free and
/// total bytes are null whenever the platform cannot report them (or the seams
/// are unwired) — surfaces hide those figures instead of inventing them. The
/// provider owns seam tolerance; the service owns the computation and its
/// required-vs-optional failure policy.
/// KeepAlive, deliberately (#69): the always-mounted drawer meter watches it
/// continuously anyway, and the 3.3.2 scope-swap hazard (see
/// chatStorageSignature) rules autoDispose out. Staleness is owned by
/// invalidation — the storage signature upstream and `ref.invalidate` after
/// a cache clear — never by a `KeepAliveLink` TTL (§4.4, a silent no-op on
/// keepAlive providers). Revisit when the pin crosses 3.4.0.
@Riverpod(keepAlive: true, retry: noRetry)
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
  return StorageBreakdownService(
    history: history,
    attachments: attachments,
    cache: cache,
    free: free,
    capacity: capacity,
    documentsPath: path,
  ).compute(models: models);
}

/// Pinned entries plus the user's custom repositories, derived — never stored —
/// so the pinned manifest stays the single source of model knowledge.
/// KeepAlive, deliberately (#69): watched by always-mounted chat surfaces
/// (composer, drawer, recovery banner), so disposal would never fire in
/// practice — and the 3.3.2 scope-swap hazard (see chatStorageSignature)
/// rules autoDispose out. Revisit when the pin crosses 3.4.0.
@Riverpod(keepAlive: true, retry: noRetry)
List<ModelCatalogEntry> effectiveModelCatalog(Ref ref) {
  final pinned = ref.watch(modelCatalogEntriesProvider);
  final custom = ref
      .watch(preferencesControllerProvider.select(_customModelsFrom))
      .models;
  final pinnedKeys = {for (final entry in pinned) entry.key};
  return [
    ...pinned,
    for (final spec in custom)
      if (!pinnedKeys.contains(spec.key)) spec.toCatalogEntry(),
  ];
}

/// The models a per-chat selection may name: installed, and of the engine this
/// build composed. Derived here so chat, Settings, and Storage cannot disagree
/// about which model is live (#20).
/// KeepAlive, deliberately (#69): same grounds as effectiveModelCatalog —
/// continuously watched, and the 3.3.2 scope-swap hazard. Revisit when the
/// pin crosses 3.4.0.
@Riverpod(keepAlive: true, retry: noRetry)
Set<String> loadableModelKeys(Ref ref) => domain.loadableModelKeys(
  backend: ref.watch(inferenceBackendProvider),
  catalog: ref.watch(effectiveModelCatalogProvider),
  models: ref.watch(modelControllerProvider).value,
);

/// The keys a download may be *started* for: the pinned catalog, plus custom
/// repositories that resolved against Hugging Face and so have a real file
/// list. An unresolved entry synthesizes its files, so a request for it could
/// not succeed — Settings and the chat picker both withhold the affordance
/// rather than failing on the tap, and derive that from here so the rule has
/// one statement (#79).
/// KeepAlive, deliberately (#69): same grounds as loadableModelKeys.
@Riverpod(keepAlive: true, retry: noRetry)
Set<String> downloadableModelKeys(Ref ref) {
  final simulated =
      ref.watch(modelControllerProvider).value?.simulated ??
      ref.watch(inferenceBackendProvider).simulatedInference;
  final pinned = {
    for (final entry in ref.watch(modelCatalogEntriesProvider)) entry.key,
  };
  final resolved = {
    for (final spec
        in ref
            .watch(preferencesControllerProvider.select(_customModelsFrom))
            .models)
      if (spec.resolved != null) spec.key,
  };
  return {
    for (final entry in ref.watch(effectiveModelCatalogProvider))
      if (simulated ||
          pinned.contains(entry.key) ||
          resolved.contains(entry.key))
        entry.key,
  };
}

/// Only user-set values are stored; profile defaults resolve at the consumer.
/// KeepAlive: a §3.2 client-state owner — the session's sole in-memory read
/// owner over write-through persistence.
@Riverpod(keepAlive: true, retry: noRetry)
class SettingsController extends _$SettingsController {
  /// The last state known to be on disk — what a failed commit snaps back
  /// to. Rolling back to the merely-previous state would restore another
  /// commit's unpersisted optimistic value when failures overlap.
  late GenerationSettings _persisted;

  @override
  Future<GenerationSettings> build() async {
    final loaded = await ref.read(settingsRepositoryProvider).load();
    _persisted = loaded;
    return loaded;
  }

  GenerationSettings get _value => state.requireValue;

  /// False means the write failed and the presented state snapped back to
  /// the last persisted value — the caller owns telling the user. Commands
  /// never throw, so fire-and-forget call sites stay safe.
  Future<bool> updateModel(
    String profileKey,
    SamplingOverrides overrides,
  ) async {
    // A tap can land in the cold-start load window; dropping it beats throwing
    // on requireValue while the store is still reading.
    if (!state.hasValue) return false;
    final next = _value.withModel(profileKey, overrides);
    state = AsyncData(next);
    try {
      await ref.read(settingsRepositoryProvider).save(next);
      _persisted = next;
      return true;
    } on Exception {
      // Roll back only while this commit is still the presented one; a newer
      // commit owns the presentation (and its own outcome) otherwise.
      if (ref.mounted && identical(state.value, next)) {
        state = AsyncData(_persisted);
      }
      return false;
    }
  }

  Future<bool> resetModel(String profileKey) =>
      updateModel(profileKey, const SamplingOverrides());
}

/// Persisted app-wide preferences. Every command follows the settings idiom —
/// drop taps that land in the cold-start load window, publish, then save —
/// and returns false after rolling back a failed write, never throwing.
/// KeepAlive: a §3.2 client-state owner; theme and text scale drive the app
/// root on every frame.
@Riverpod(keepAlive: true, retry: noRetry)
class PreferencesController extends _$PreferencesController {
  /// The last state known to be on disk — what a failed commit snaps back
  /// to. Rolling back to the merely-previous state would restore another
  /// commit's unpersisted optimistic value when failures overlap.
  late AppPreferences _persisted;

  @override
  Future<AppPreferences> build() async {
    final loaded = await ref.read(preferencesRepositoryProvider).load();
    _persisted = loaded;
    return loaded;
  }

  AppPreferences get _value => state.requireValue;

  /// Publishes the transformed preferences, persists them, and reports the
  /// outcome; a failed write snaps presentation back to the last persisted
  /// value. The cold-start guard lives here so every command shares it —
  /// a tap in the load window is dropped rather than thrown on requireValue.
  Future<bool> _commit(AppPreferences Function(AppPreferences) change) async {
    if (!state.hasValue) return false;
    final next = change(_value);
    state = AsyncData(next);
    try {
      await ref.read(preferencesRepositoryProvider).save(next);
      _persisted = next;
      return true;
    } on Exception {
      // Roll back only while this commit is still the presented one; a newer
      // commit owns the presentation (and its own outcome) otherwise.
      if (ref.mounted && identical(state.value, next)) {
        state = AsyncData(_persisted);
      }
      return false;
    }
  }

  Future<bool> setTheme(ThemeSetting theme) =>
      _commit((value) => value.copyWith(theme: theme));

  Future<bool> setLanguage(AppLanguage language) =>
      _commit((value) => value.copyWith(language: language));

  Future<bool> setTextScale(double scale) =>
      _commit((value) => value.copyWith(textScale: scale));

  Future<bool> setShowMetrics(bool value) =>
      _commit((current) => current.copyWith(showMetrics: value));

  Future<bool> setExpandReasoning(bool value) =>
      _commit((current) => current.copyWith(expandReasoning: value));

  Future<bool> setHapticsOnSend(bool value) =>
      _commit((current) => current.copyWith(hapticsOnSend: value));

  Future<bool> setAdvancedMode(bool value) =>
      _commit((current) => current.copyWith(advancedMode: value));

  Future<bool> setOnboardingModel(String modelKey) => _commit(
    (current) => current.copyWith(onboardingModelKey: () => modelKey),
  );

  Future<bool> completeOnboarding({
    String? modelKey,
    bool clearModel = false,
  }) => _commit(
    (current) => current.copyWith(
      onboardingVersion: currentOnboardingVersion,
      onboardingModelKey: clearModel
          ? () => null
          : modelKey == null
          ? null
          : () => modelKey,
    ),
  );

  /// Null or blank clears the prompt back to the model default.
  Future<bool> setSystemPrompt(String? prompt) {
    final trimmed = prompt?.trim();
    return _commit(
      (value) => value.copyWith(
        systemPrompt: () => trimmed == null || trimmed.isEmpty ? null : trimmed,
      ),
    );
  }

  Future<bool> setResponseStyle(String profileKey, ResponseStyle style) =>
      _commit((value) => value.withStyle(profileKey, style));

  /// Turning history off empties the on-disk store immediately: the design copy
  /// promises chats disappear. Past consent — the alert lives in the widget.
  /// The wipe runs before the commit, so a failed wipe can never present as
  /// "history off" while chats still sit on disk; a wipe that lands under a
  /// commit that then fails is undone, so disk always matches the toggle.
  Future<bool> setSaveHistory(bool save) async {
    if (!state.hasValue) return false;
    if (save) {
      final committed = await _commit(
        (value) => value.copyWith(saveHistory: true),
      );
      if (!committed) return false;
      // The preference commit owns this command's success. Chat persistence
      // reports its own failure through the standing chat notice.
      try {
        await ref.read(chatControllerProvider.notifier).persistCurrent();
      } on Exception {
        // A non-contract failure must not roll back a preference that landed.
      }
      return true;
    }
    try {
      await ref
          .read(chatHistoryRepositoryProvider)
          .save(const ChatHistorySnapshot(conversations: []));
    } on Exception {
      return false;
    }
    final committed = await _commit(
      (value) => value.copyWith(saveHistory: false),
    );
    if (committed) {
      // This reaches the history-off branch: no second write, but any standing
      // warning is cleared and attachment ownership follows the live session.
      try {
        await ref.read(chatControllerProvider.notifier).persistCurrent();
      } on Exception {
        // The disk wipe and preference both landed; the toggle stays off.
      }
      return true;
    }
    // The wipe landed but the preference did not: the toggle stays on, so
    // put the chats back on disk to match what the UI now claims.
    try {
      await ref.read(chatControllerProvider.notifier).persistCurrent();
    } on Exception {
      // Disk and toggle disagree until the next chat mutation re-persists.
    }
    return false;
  }

  /// The preference commit owns success: a failed model-card registration
  /// surfaces on the card itself (its failed-phase channel) while the stored
  /// spec is retained, so the next launch re-merges it into the catalog.
  Future<bool> addCustomModel(CustomModelSpec spec) async {
    final committed = await _commit((value) => value.withCustomModel(spec));
    if (!committed) return false;
    await ref
        .read(modelControllerProvider.notifier)
        .registerCustomModel(spec.toCatalogEntry());
    return true;
  }
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
    final onboardingModelKey = ref
        .read(preferencesControllerProvider)
        .value
        ?.onboardingModelKey;
    final backend = ref.read(inferenceBackendProvider);
    final selectedEntry = onboardingModelKey == null
        ? null
        : _catalog()
              .where((entry) => entry.key == onboardingModelKey)
              .firstOrNull;
    final conversation = ChatConversation(
      id: newId(),
      title: '',
      messages: const [],
      updatedAt: now,
      // First run is allowed to name a compatible model before its weights
      // finish downloading. Sending remains gated in the composer and again in
      // _startGeneration; after installation the existing loadable-key rule
      // makes every model label follow this persisted choice.
      modelKey:
          selectedEntry != null &&
              (backend.simulatedInference ||
                  backend.kind.loads(selectedEntry.engine))
          ? selectedEntry.key
          : null,
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
    final target = active.modelKey ?? backend.artifactKey;
    final entry = target == null
        ? null
        : _catalog().where((item) => item.key == target).firstOrNull;
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

  /// Typed inference exceptions retain their recovery kind and safe arguments;
  /// presentation owns localized copy. Unknown errors stay generic, and raw
  /// exception text never reaches the banner (§19.4).
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
  Future<SamplingOverrides?> _samplingOverrides() async {
    final profileKey = _activeProfileKey();
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
  String _activeProfileKey() {
    final modelKey = _value.active?.modelKey;
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

/// KeepAlive: a command controller whose downloads, busy guard, and epochs
/// must survive leaving the Models screen (§3.4 — an autoDispose command
/// provider dies mid-flight).
@Riverpod(keepAlive: true, retry: noRetry)
class ModelController extends _$ModelController {
  int _operationEpoch = 0;
  // One mutating model operation at a time. Pause and cancel stay exempt:
  // they are the escape hatches that end an in-flight download.
  bool _busy = false;
  bool _releasing = false;

  /// The subset of [_busy] operations that command the engine. Freeing the
  /// engine skips these but not a download: unloading beneath `prepare()` or
  /// beneath `delete()`'s own unload is a real collision, while a transfer
  /// stuck on an unresponsive platform must never block memory relief.
  bool _engineBusy = false;

  @override
  Future<ModelState> build() =>
      ref.read(modelManagementRepositoryProvider).load();

  /// Re-runs reconciliation and re-attaches to anything the platform is still
  /// transferring. Called at startup once the first state has settled, and on
  /// every return to the foreground — the only moment a transfer the OS moved
  /// on without telling anyone can be noticed.
  ///
  /// Deliberately outside the busy guard: a download stuck waiting on a
  /// platform that stopped answering is precisely when this has to run.
  Future<void> reconcileDownloads() async {
    try {
      // Never before build has installed its own value: Riverpod assigns that
      // result after the fact, and would overwrite the fresher snapshot below
      // with the one the launch pass resolved to — leaving the card stale and
      // the busy guard raised, so the user's own tap does nothing.
      await future;
      final value = await ref.read(modelManagementRepositoryProvider).load();
      if (!ref.mounted) return;
      state = AsyncData(value);
      await _reattach(value);
    } catch (_) {
      // Reconciliation is a repair pass; a failed one must not blank the
      // screen or replace a usable snapshot with an error.
    }
  }

  /// Streams a transfer the platform is already running so its progress
  /// reaches the UI. [download] adopts rather than enqueues, so this never
  /// starts a second writer.
  Future<void> _reattach(ModelState value) async {
    if (_busy) return;
    for (final entry in value.artifacts.entries) {
      if (entry.value.phase == ArtifactPhase.downloading) {
        await download(entry.key);
        return;
      }
    }
  }

  Future<void> download(String artifactKey) async {
    if (_busy) return;
    // Defence in depth behind the withheld card button and the chat banner's
    // absent CTA (#27): a device that can never load these weights must never
    // spend gigabytes fetching them, whichever path asked. Reconciliation is
    // the path that still can — it re-adopts a transfer the platform is still
    // running — so that one is stopped rather than relabelled. Nothing is
    // published over it: the card already carries the reason.
    if (ref.read(deviceRefusalProvider) != null) {
      final phase = state.value?.statusOf(artifactKey).phase;
      if (phase == ArtifactPhase.downloading || phase == ArtifactPhase.paused) {
        await cancel(artifactKey);
      }
      return;
    }
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
    _engineBusy = true;
    try {
      // Never delete weights the engine may still have mapped: releasing
      // the runtime comes first, and an unload failure aborts the delete.
      // Residency decides, since a switch can make any installed artifact the
      // one that is mapped (#20).
      final resident =
          ref.read(inferenceRepositoryProvider).residentModelKey.value ??
          state.value?.activeArtifactKey;
      if (artifactKey == resident) {
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
      _engineBusy = false;
    }
  }

  /// Records that the engine holds weights after ChatController's lazy
  /// prepare(). Skips sideloaded paths — outside the catalog's phase tracking.
  Future<void> reflectEngineLoaded() async {
    if (_busy) return;
    final current = state.value;
    final target = _engineTargetKey();
    if (current == null ||
        current.runtime == RuntimePhase.loaded ||
        target == null ||
        current.statusOf(target).phase != ArtifactPhase.installed) {
      return;
    }
    _busy = true;
    _engineBusy = true;
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
      _engineBusy = false;
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
            .copyWith(
              phase: ArtifactPhase.failed,
              failure: '$error',
              failureReason: const ArtifactFailure(
                ArtifactFailureKind.transfer,
              ),
            ),
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
    _engineBusy = true;
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
        // An unsupported device refuses ahead of every other condition (#27):
        // installed weights change nothing about what this hardware can run.
        // Only this branch — unloading stays reachable, so a phase persisted
        // by an earlier build can always be corrected.
        final refusal = ref.read(deviceRefusalProvider);
        if (refusal != null) {
          final value = await repository.recordRuntime(
            RuntimePhase.failed,
            failure: refusal,
          );
          if (!ref.mounted) return;
          state = AsyncData(value);
          return;
        }
        // A sideload's path is the operator's own and has no catalog phase to
        // gate on; everything else must be installed before the engine is
        // touched, and which artifact that is follows the active chat (#20).
        final backend = ref.read(inferenceBackendProvider);
        final target = _engineTargetKey();
        if (!backend.sideloaded &&
            (target == null ||
                current.statusOf(target).phase != ArtifactPhase.installed)) {
          // Refuse with a persisted failed phase; the engine is never touched.
          final value = await repository.recordRuntime(
            RuntimePhase.failed,
            failure: _installFirstFailure(target),
          );
          if (!ref.mounted) return;
          state = AsyncData(value);
          return;
        }
        try {
          await ref.read(inferenceRepositoryProvider).prepare(modelKey: target);
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
      _engineBusy = false;
    }
  }

  /// Frees the engine on an OS memory-pressure signal or backgrounding — the
  /// app must never hold multi-gigabyte weights it is not using while the
  /// platform reclaims memory. Only when idle: an advisory signal never cancels
  /// a visible stream, and the busy guard keeps it off a model operation.
  Future<void> releaseEngineWhileInactive() async {
    // Not gated on the download guard. This is the only defence against holding
    // multi-gigabyte weights under the platform's background memory ceiling,
    // and a download stuck on an unresponsive platform would otherwise disable
    // it for the rest of the process — the app is then jetsammed on the next
    // background transition, which is exactly what this exists to prevent.
    // Engine operations are a different matter: unloading underneath one is a
    // collision, not a rescue.
    if (_engineBusy) return;
    final current = state.value;
    if (current == null) return;
    final chat = ref.read(chatControllerProvider).value;
    if (chat != null && chat.generation != GenerationPhase.idle) return;
    // Its own guard: backgrounding and memory pressure can both fire, and this
    // still must not unload twice.
    if (_releasing) return;
    _releasing = true;
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
      _releasing = false;
    }
  }

  /// The model the engine would load now: the active chat's choice when it has
  /// one, else the boot artifact. Null for a sideload, whose path no catalog key
  /// describes, and for a build with no inference backend at all.
  String? _engineTargetKey() {
    final backend = ref.read(inferenceBackendProvider);
    if (backend.sideloaded) return null;
    final active = ref.read(chatControllerProvider).value?.active;
    return active?.modelKey ?? state.value?.activeArtifactKey;
  }

  /// The load-refusal copy for a not-installed target. Owned here since #42:
  /// the management repository no longer knows why a load was refused.
  String _installFirstFailure(String? target) {
    if (target == null) {
      return 'Inference is a build-time opt-in; no backend is configured.';
    }
    return ref.read(inferenceBackendProvider).simulatedInference
        ? 'Install the selected simulated model first.'
        : 'Download and install the active model first.';
  }
}

/// KeepAlive: the startup outcome is process-lifetime. This is the scripted
/// splash theatre (minimum hold, progress ticks, injected demo scenarios);
/// real launch failures and their retry live before this scope exists, in
/// the bootstrap gate (docs/decisions/0006-launch-bootstrap.md).
@Riverpod(keepAlive: true, retry: noRetry)
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
    final scenario = startupScenarioFor(
      identity: AppIdentity.current,
      missingModel: missingModel,
      injectedFailure: injectedFailure,
      injectedTimeout: injectedTimeout,
    );
    if (scenario == StartupScenario.missingModel) {
      state = const AsyncData(
        StartupState(phase: StartupPhase.missingModel, progress: 0.86),
      );
    }
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
