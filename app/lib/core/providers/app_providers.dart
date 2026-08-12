import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../app_identity.dart';
import '../application/session_bridges.dart';
import '../domain/app_preferences.dart';
import '../domain/app_state.dart';
import '../domain/device_eligibility.dart';
import '../domain/generation_settings.dart';
import '../domain/inference_backend.dart';
import '../domain/model_catalog.dart';
import '../domain/models.dart';
import '../repositories/contracts.dart';
import '../services/cache_probe.dart';
import '../services/custom_repository_resolver.dart';
import '../services/device_storage.dart';
import '../startup/startup_sequence.dart';
import 'retry.dart';

part 'app_providers.g.dart';

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

/// The chat session's capabilities offered across feature boundaries (#88):
/// ChatController binds itself in during `build()`, and the model feature
/// reads session facts here instead of the chat provider.
/// KeepAlive: the binding must outlive route transitions, like its owner.
@Riverpod(keepAlive: true, retry: noRetry)
ChatSessionBridge chatSessionBridge(Ref ref) => ChatSessionBridge();

/// The model feature's counterpart to [chatSessionBridge] (#88): chat and
/// preferences command the model controller through this seam.
/// KeepAlive: the binding must outlive route transitions, like its owner.
@Riverpod(keepAlive: true, retry: noRetry)
ModelSessionBridge modelSessionBridge(Ref ref) => ModelSessionBridge();

@Riverpod(keepAlive: true, retry: noRetry)
DiskCapacityProbe deviceCapacityProbe(Ref ref) =>
    throw UnimplementedError('Override deviceCapacityProbeProvider at startup');

@Riverpod(keepAlive: true, retry: noRetry)
String documentsPath(Ref ref) =>
    throw UnimplementedError('Override documentsPathProvider at startup');

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
        await ref.read(chatSessionBridgeProvider).persistCurrent();
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
        await ref.read(chatSessionBridgeProvider).persistCurrent();
      } on Exception {
        // The disk wipe and preference both landed; the toggle stays off.
      }
      return true;
    }
    // The wipe landed but the preference did not: the toggle stays on, so
    // put the chats back on disk to match what the UI now claims.
    try {
      await ref.read(chatSessionBridgeProvider).persistCurrent();
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
        .read(modelSessionBridgeProvider)
        .registerCustomModel(spec.toCatalogEntry());
    return true;
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
