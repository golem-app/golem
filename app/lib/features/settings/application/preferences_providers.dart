import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/app_preferences.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';

part 'preferences_providers.g.dart';

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
