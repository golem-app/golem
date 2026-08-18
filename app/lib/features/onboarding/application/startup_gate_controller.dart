import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/app_preferences.dart';
import '../../../core/domain/app_state.dart';
import '../../../core/domain/model_admission.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';
import '../../chat/application/chat_providers.dart';
import '../../models/application/model_providers.dart';
import '../../preferences/application/preferences_providers.dart';
import '../domain/onboarding_policy.dart';

part 'startup_gate_controller.g.dart';

/// Everything the gate decides on from the chat store. Projected rather than
/// watched whole because [ChatController] reassigns its state on every
/// streaming token: without this, the provider wrapping every route would be
/// invalidated once per token for a decision that cannot have changed. A
/// record, so the comparison Riverpod's `select` makes is structural.
typedef _GateChats = ({bool loading, bool available, bool seeded});

_GateChats _chatsFrom(AsyncValue<ChatState> value) => (
  loading: value.isLoading,
  available: value.hasValue,
  seeded: value.value?.conversations.isNotEmpty ?? false,
);

/// The app root's admission decision (#126). It was a widget state machine:
/// sideload validation ran from a post-frame callback into `setState`, the
/// pristine-at-launch latch was mutated inside `build`, and the legacy
/// onboarding stamp was a write scheduled from `build`. Correctness depended
/// on how many frames pumped and none of it was observable through a provider.
///
/// KeepAlive: [_pristineAtLaunch] means what it says. A disposed element would
/// relatch it against whatever the stores hold later in the session, which is
/// the one thing the latch exists to prevent.
@Riverpod(keepAlive: true, retry: noRetry)
class StartupGateController extends _$StartupGateController {
  /// Whether this install was untouched when the process started. Latched
  /// rather than derived: deleting the last model mid-session must re-gate the
  /// shell without the app then deciding it is looking at a fresh install.
  bool? _pristineAtLaunch;

  /// The legacy stamp is a one-shot write, and it changes the preferences this
  /// build watches — so without this the rebuild it causes would write again.
  bool _migrated = false;

  @override
  Future<StartupGate> build() async {
    if (ref.watch(deviceRefusalProvider) != null) {
      return const GateUnsupported();
    }
    final backend = ref.watch(inferenceBackendProvider);
    if (backend.sideloaded) return _admitSideload();

    final preferences = ref.watch(preferencesControllerProvider);
    final chats = ref.watch(chatControllerProvider.select(_chatsFrom));
    final models = ref.watch(modelControllerProvider);
    // Loading and read failure are gate values, not AsyncValue states: the
    // sideload branch above owns this provider's own loading and error, which
    // is what lets the two failure panes stay distinguishable.
    if (preferences.isLoading || chats.loading || models.isLoading) {
      return const GateWaiting();
    }
    if (!preferences.hasValue || !chats.available || !models.hasValue) {
      return const GateUnavailable();
    }

    _pristineAtLaunch ??= shouldShowFirstRun(
      preferences: preferences.requireValue,
      hasConversations: chats.seeded,
      models: models.requireValue,
      backend: backend,
    );
    final decision = resolveStartupGate(
      pristineAtLaunch: _pristineAtLaunch!,
      onboardingComplete:
          preferences.requireValue.onboardingVersion >=
          currentOnboardingVersion,
      hasUsableModel: ref.watch(loadableModelKeysProvider).isNotEmpty,
      // Only consulted when setup is required, which keeps the catalog scan
      // and these two dependencies off the admitted path — the one this
      // provider takes on every rebuild for the life of an installed app.
      //
      // Inspect the same admitted key FirstRunScreen will render. An upgrade
      // can carry an interrupted artifact for the other platform engine (for
      // example GGUF from the old iOS auto policy); its bytes must not send
      // the compatible, untouched MLX recommendation to an unactionable
      // resume UI.
      selectedStatus: () {
        final selectedKey = recommendedAdmittedModelKey(
          catalog: ref.watch(modelCatalogEntriesProvider),
          backend: backend,
          eligibility: ref.watch(deviceEligibilityProvider),
          selectedKey: preferences.requireValue.onboardingModelKey,
        );
        return selectedKey == null
            ? const ArtifactStatus()
            : models.requireValue.statusOf(selectedKey);
      },
    );
    if (decision.migrateLegacy && !_migrated) {
      _migrated = true;
      // Published before the write, so the shell is admitted at once — what
      // the post-frame callback this replaced did.
      state = AsyncData(decision.gate);
      // Then out of the synchronous build frame before writing. Riverpod
      // asserts that a provider does not modify another during its own
      // initialization, and `await command()` is not enough on its own:
      // awaiting still runs the callee's prologue inline, and the preferences
      // commit publishes optimistically before its own first await.
      await null;
      if (!ref.mounted) return decision.gate;
      await ref
          .read(preferencesControllerProvider.notifier)
          .completeOnboarding();
    }
    return decision.gate;
  }

  /// Blocks the shell on the operator's own weights, because loading them *is*
  /// the validation: a `GOLEM_MODEL_PATH` the engine cannot open must not
  /// reach a composer that would report it as a failed turn instead.
  Future<StartupGate> _admitSideload() async {
    await ref.read(inferenceRepositoryProvider).prepare();
    if (!ref.mounted) return const GateAdmitted();
    unawaited(_reflectResident());
    return const GateAdmitted();
  }

  /// The engine now holds weights, so Settings may not keep claiming
  /// "Unloaded". Bookkeeping, so it can neither gate nor veto admission: the
  /// weights loaded either way, and this reaches the model store — a store the
  /// sideload path otherwise never touches, and one that must not be able to
  /// tell the operator their own file is invalid, or hold the shell shut while
  /// it hydrates.
  Future<void> _reflectResident() async {
    try {
      await ref.read(modelSessionBridgeProvider).reflectEngineLoaded();
    } catch (_) {
      // Deliberately broad: nothing awaits this, so anything escaping reaches
      // the zone as an unhandled error, over a phase that is a label.
    }
  }

  /// The failure panes' one way out. Deliberately not a bare invalidation of
  /// this provider: on the store path that would re-read three providers
  /// already sitting on their own errors, which never re-runs anything. Their
  /// invalidation is the retry, and the latch is dropped with them.
  void retry() {
    _pristineAtLaunch = null;
    if (!ref.read(inferenceBackendProvider).sideloaded) {
      ref.invalidate(preferencesControllerProvider);
      ref.invalidate(chatControllerProvider);
      ref.invalidate(modelControllerProvider);
    }
    ref.invalidateSelf();
  }
}
