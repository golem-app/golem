import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/features/chat/application/chat_providers.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';
import 'package:golem_flutter/features/onboarding/application/startup_gate_controller.dart';
import 'package:golem_flutter/features/onboarding/domain/onboarding_policy.dart';

import 'support/harness.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_preferences_repository.dart';

/// The app's admission boundary, as provider state (#126).
///
/// It used to be five `State` fields on `FirstRunGate` mutated from `build`
/// and two post-frame callbacks, so every case here needed a widget tree and
/// the right number of pumps. The two branches that gate a *failed* launch —
/// a store that will not read, and its retry — had no test at all.
void main() {
  const installedGemma = ModelState(
    artifacts: {'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed)},
  );
  const completed = AppPreferences(
    onboardingVersion: currentOnboardingVersion,
    onboardingModelKey: 'gemma4-mlx',
  );

  /// The gate once it and the three stores it watches have all resolved.
  Future<StartupGate> settled(ProviderContainer container) =>
      container.read(startupGateControllerProvider.future);

  /// Lets the resolved stores propagate without waiting for the parked one.
  Future<void> turn() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  StartupGate? gateOf(ProviderContainer container) =>
      container.read(startupGateControllerProvider).value;

  group('the store path', () {
    test('the shell waits while a store has not answered yet', () async {
      final history = _ParkedHistory();
      final container = buildContainer(
        chatHistory: history,
        preferences: InMemoryPreferencesRepository(completed),
        model: installedGemma,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        startupGateControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await turn();
      expect(
        gateOf(container),
        isA<GateWaiting>(),
        reason: 'chat history has not resolved, so nothing may render',
      );

      history.release();
      await turn();
      expect(gateOf(container), isA<GateAdmitted>());
    });

    test('a store that will not read offers a retry that re-reads it', () async {
      // Never covered before: `first-run-read-failure` and `startup-gate-retry`
      // are the launch-failure path, and the widget owned both.
      final history = InMemoryChatHistoryRepository()..failingLoads = 1;
      final container = buildContainer(
        chatHistory: history,
        preferences: InMemoryPreferencesRepository(completed),
        model: installedGemma,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        startupGateControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      expect(await settled(container), isA<GateUnavailable>());

      container.read(startupGateControllerProvider.notifier).retry();
      expect(
        await settled(container),
        isA<GateAdmitted>(),
        reason: 'retry must invalidate the store, not just this provider',
      );
    });

    test(
      'a usable legacy install is admitted and stamped exactly once',
      () async {
        final preferences = InMemoryPreferencesRepository();
        final container = buildContainer(
          history: seedHistory(),
          preferences: preferences,
          model: installedGemma,
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          startupGateControllerProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);

        expect(
          await settled(container),
          isA<GateAdmitted>(),
          reason: 'the shell is admitted before the stamp, not behind it',
        );
        expect(preferences.preferences.onboardingVersion, 0);

        await turn();
        expect(
          preferences.preferences.onboardingVersion,
          currentOnboardingVersion,
        );
        // The stamp changes the preferences this provider watches. Without the
        // one-shot guard, the rebuild it causes writes again, forever.
        expect(preferences.saves, 1);

        await turn();
        expect(preferences.saves, 1);
      },
    );

    test('a stamp that fails is not retried in the same session', () async {
      // The stamp rolls back on a failed write, which restores exactly the
      // preferences that asked for it — so without the one-shot guard the
      // rebuild the rollback causes writes again, and again.
      final preferences = InMemoryPreferencesRepository()..failingSaves = 1;
      final container = buildContainer(
        history: seedHistory(),
        preferences: preferences,
        model: installedGemma,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        startupGateControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      expect(await settled(container), isA<GateAdmitted>());
      await turn();

      expect(preferences.saves, 0);
      expect(
        preferences.preferences.onboardingVersion,
        0,
        reason: 'the next launch stamps it; this session does not re-attempt',
      );
      expect(gateOf(container), isA<GateAdmitted>());
    });

    test('a pristine install is sent to setup and stamps nothing', () async {
      final preferences = InMemoryPreferencesRepository();
      final container = buildContainer(preferences: preferences);
      addTearDown(container.dispose);
      final subscription = container.listen(
        startupGateControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      expect(await settled(container), const GateFirstRun(FirstRunEntry.fresh));
      expect(preferences.saves, 0);
      expect(preferences.preferences.onboardingVersion, 0);
    });

    test(
      'losing the last model re-gates without relatching pristine',
      () async {
        // The latch is what stops a mid-session deletion reading as a fresh
        // install: this device has completed setup, so it must land on model
        // choice, not back at the welcome step.
        final container = buildContainer(
          preferences: InMemoryPreferencesRepository(completed),
          models: _RuntimeRecordingModels(installedGemma),
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          startupGateControllerProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);

        expect(await settled(container), isA<GateAdmitted>());

        await container
            .read(modelControllerProvider.notifier)
            .delete('gemma4-mlx');
        expect(
          await settled(container),
          const GateFirstRun(FirstRunEntry.chooseModel),
        );
      },
    );

    test('an admitted shell is not re-published while chat streams', () async {
      // This provider wraps every route. Chat reassigns its state on every
      // streaming token, so an admission value that is not value-equal would
      // notify the app root once per token.
      final container = buildContainer(
        history: seedHistory(),
        preferences: InMemoryPreferencesRepository(completed),
        model: installedGemma,
      );
      addTearDown(container.dispose);
      var notifications = 0;
      final subscription = container.listen(
        startupGateControllerProvider,
        (_, _) => notifications++,
      );
      addTearDown(subscription.close);

      expect(await settled(container), isA<GateAdmitted>());
      final admitted = notifications;

      await container.read(chatControllerProvider.future);
      await container
          .read(chatControllerProvider.notifier)
          .send('Stream to me');
      await turn();

      expect(gateOf(container), isA<GateAdmitted>());
      expect(
        notifications,
        admitted,
        reason: 'a token must not re-publish the admission boundary',
      );
    });
  });

  group('the sideload path', () {
    const sideloaded = InferenceBackendConfig(
      kind: InferenceBackendKind.mlx,
      profileKey: 'gemma4',
      modelPath: 'documents:operator/model',
    );

    test(
      'a sideload that will not load blocks the shell until it does',
      () async {
        final inference = _ValidatingSideload(failuresRemaining: 1);
        final models = _RuntimeRecordingModels(const ModelState());
        final container = buildContainer(
          backend: sideloaded,
          inference: inference,
          models: models,
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          startupGateControllerProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);

        await expectLater(
          settled(container),
          throwsA(isA<InferenceException>()),
        );
        expect(gateOf(container), isNull);
        expect(inference.prepareCalls, 1);

        container.read(startupGateControllerProvider.notifier).retry();
        expect(await settled(container), isA<GateAdmitted>());
        expect(inference.prepareCalls, 2);
      },
    );

    test('a loaded sideload is reflected as resident runtime', () async {
      // Settings reads ModelState.runtime, so without this it offers "Load"
      // for weights the engine is already holding. toggleRuntime already
      // exempts sideloads from the installed-artifact check for the same
      // reason; reflectEngineLoaded did not.
      final models = _RuntimeRecordingModels(const ModelState());
      final container = buildContainer(
        backend: sideloaded,
        inference: _ValidatingSideload(failuresRemaining: 0),
        models: models,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        startupGateControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      expect(await settled(container), isA<GateAdmitted>());
      expect(
        container.read(modelControllerProvider).requireValue.runtime,
        RuntimePhase.loaded,
      );
    });
  });
}

/// A history seam whose first read parks until the test releases it, so the
/// waiting branch is observable without counting pumped frames.
final class _ParkedHistory implements ChatHistoryRepository {
  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<ChatHistorySnapshot> load() async {
    await _gate.future;
    return const ChatHistorySnapshot(conversations: []);
  }

  @override
  Future<void> save(ChatHistorySnapshot snapshot) async {}

  @override
  Future<int> storedBytes() async => 0;
}

/// Applies what it is told to record, unlike [StaticModels], so the runtime
/// phase a load reflects is readable back.
final class _RuntimeRecordingModels implements ModelManagementRepository {
  _RuntimeRecordingModels(this._state);

  ModelState _state;

  @override
  Future<ModelState> load() async => _state;

  @override
  Future<ModelState> recordRuntime(
    RuntimePhase phase, {
    String? failure,
  }) async => _state = _state.copyWith(runtime: phase, failure: failure);

  @override
  Future<ModelState> delete(String artifactKey) async =>
      _state = _state.withArtifact(artifactKey, const ArtifactStatus());

  @override
  Stream<ModelState> download(String artifactKey) => Stream.value(_state);

  @override
  Future<ModelState> pause(String artifactKey) async => _state;

  @override
  Future<ModelState> cancel(String artifactKey) async => _state;

  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => _state;
}

/// The operator sideload seam: `prepare()` is both the load and the check.
final class _ValidatingSideload implements InferenceRepository {
  _ValidatingSideload({required this.failuresRemaining});

  int failuresRemaining;
  int prepareCalls = 0;

  final ValueNotifier<InferenceResidency> _residency =
      ValueNotifier<InferenceResidency>(const InferenceResidency.unloaded());

  @override
  ValueListenable<InferenceResidency> get residency => _residency;

  @override
  void releaseEngine() {}

  @override
  Future<void> prepare({String? modelKey}) async {
    prepareCalls++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const InferenceException(
        InferenceFailureKind.invalidModelArtifact,
        'injected invalid sideload',
      );
    }
    _residency.value = const InferenceResidency(loaded: true);
  }

  @override
  Future<void> unload() async =>
      _residency.value = const InferenceResidency.unloaded();

  @override
  Future<void> cancel() async {}

  @override
  Stream<InferenceEvent> generate({
    required List<PromptMessage> context,
    required bool reasoningEnabled,
    SamplingOverrides? overrides,
    String? modelKey,
    String? systemPrompt,
  }) => const Stream.empty();
}
