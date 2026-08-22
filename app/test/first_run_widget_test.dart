import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/device_eligibility.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';
import 'package:golem_flutter/features/onboarding/application/onboarding_controller.dart';
import 'package:golem_flutter/features/onboarding/first_run_gate.dart';
import 'package:golem_flutter/features/onboarding/first_run_screen.dart';

import 'support/harness.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/validating_sideload.dart';
import 'support/in_memory_preferences_repository.dart';

void main() {
  testWidgets(
    'the root gate requires a model and migrates a usable legacy install',
    (tester) async {
      await pumpWithRepositories(
        tester,
        model: const ModelState(simulated: true),
        child: const FirstRunGate(
          key: Key('fresh-gate'),
          child: SizedBox(key: Key('chat-after-first-run')),
        ),
      );
      expect(find.byKey(const Key('first-run-welcome')), findsOneWidget);
      expect(find.byKey(const Key('chat-after-first-run')), findsNothing);

      final legacyPreferences = InMemoryPreferencesRepository();
      await pumpWithRepositories(
        tester,
        history: seedHistory(),
        preferences: legacyPreferences,
        model: const ModelState(
          simulated: true,
          artifacts: {
            'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
          },
        ),
        child: const FirstRunGate(
          key: Key('legacy-gate'),
          child: SizedBox(key: Key('chat-after-first-run')),
        ),
      );
      expect(find.byKey(const Key('chat-after-first-run')), findsOneWidget);
      expect(find.byKey(const Key('first-run-welcome')), findsNothing);
      expect(
        legacyPreferences.preferences.onboardingVersion,
        currentOnboardingVersion,
      );
    },
  );

  testWidgets('declining consent keeps first run blocked without a download', (
    tester,
  ) async {
    final preferences = InMemoryPreferencesRepository();
    await pumpWithRepositories(
      tester,
      preferences: preferences,
      eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
      model: const ModelState(simulated: true),
      child: const FirstRunScreen(),
    );

    await tester.tap(find.byKey(const Key('first-run-get-started')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('first-run-model')), findsOneWidget);
    expect(find.textContaining('tok/s'), findsNothing);
    await tester.tap(find.byKey(const Key('first-run-download')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-download-consent')), findsOneWidget);
    expect(find.textContaining('no network'), findsOneWidget);
    expect(find.textContaining('no model weights'), findsOneWidget);
    await tester.tap(find.byKey(const Key('model-download-not-now')));
    await tester.pumpAndSettle();

    expect(preferences.preferences.onboardingVersion, 0);
    expect(preferences.preferences.onboardingModelKey, 'gemma4-mlx');
    expect(find.byKey(const Key('first-run-model')), findsOneWidget);
  });

  testWidgets('an operator sideload must load before the shell is exposed', (
    tester,
  ) async {
    final inference = ValidatingSideload(failuresRemaining: 1);
    await pumpWithRepositories(
      tester,
      inference: inference,
      backend: const InferenceBackendConfig(
        kind: InferenceBackendKind.mlx,
        profileKey: 'gemma4',
        modelPath: 'documents:operator/model',
      ),
      child: const FirstRunGate(
        child: SizedBox(key: Key('chat-after-first-run')),
      ),
    );

    expect(
      find.byKey(const Key('sideload-validation-failure')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('chat-after-first-run')), findsNothing);
    expect(inference.prepareCalls, 1);

    await tester.tap(find.byKey(const Key('startup-gate-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-after-first-run')), findsOneWidget);
    expect(inference.prepareCalls, 2);
    expect(inference.residency.value.loaded, isTrue);
    expect(inference.residency.value.catalogKey, isNull);
  });

  testWidgets('a store that will not read blocks the shell behind a retry', (
    tester,
  ) async {
    // The launch-failure path, untested until #126 moved it into a provider:
    // the gate owned both the failure pane and what its retry re-read, so
    // neither was reachable without a widget tree and the right pump count.
    final history = InMemoryChatHistoryRepository()..failingLoads = 1;
    await pumpWithRepositories(
      tester,
      chatHistory: history,
      preferences: InMemoryPreferencesRepository(
        const AppPreferences(
          onboardingVersion: currentOnboardingVersion,
          onboardingModelKey: 'gemma4-mlx',
        ),
      ),
      model: const ModelState(
        artifacts: {
          'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
        },
      ),
      child: const FirstRunGate(
        child: SizedBox(key: Key('chat-after-first-run')),
      ),
    );

    expect(find.byKey(const Key('first-run-read-failure')), findsOneWidget);
    expect(find.byKey(const Key('chat-after-first-run')), findsNothing);
    expect(find.byKey(const Key('sideload-validation-failure')), findsNothing);

    await tester.tap(find.byKey(const Key('startup-gate-retry')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('chat-after-first-run')),
      findsOneWidget,
      reason: 'retry must re-read the store, not only this gate',
    );
  });

  testWidgets('retrying a sideload shows the load, not the failure it retries', (
    tester,
  ) async {
    // Riverpod carries the error through a refresh — AsyncError.copyWithPrevious
    // keeps it — so reading this gate's error flag literally leaves the failure
    // pane and its live "Try again" button up for the whole reload, which on a
    // real sideload is tens of seconds of multi-gigabyte load. The widget it
    // replaced cleared the failure before starting. Settling hides this, so the
    // frames are pumped one at a time.
    final inference = ValidatingSideload(failuresRemaining: 1);
    await pumpWithRepositories(
      tester,
      inference: inference,
      backend: const InferenceBackendConfig(
        kind: InferenceBackendKind.mlx,
        profileKey: 'gemma4',
        modelPath: 'documents:operator/model',
      ),
      child: const FirstRunGate(
        child: SizedBox(key: Key('chat-after-first-run')),
      ),
    );
    expect(
      find.byKey(const Key('sideload-validation-failure')),
      findsOneWidget,
    );

    inference.park = true;
    await tester.tap(find.byKey(const Key('startup-gate-retry')));
    await tester.pump();

    expect(find.byKey(const Key('sideload-validating')), findsOneWidget);
    expect(
      find.byKey(const Key('sideload-validation-failure')),
      findsNothing,
      reason: 'the load it is retrying is what the shell is waiting on',
    );

    inference.release();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-after-first-run')), findsOneWidget);
    expect(inference.prepareCalls, 2);
  });

  testWidgets('download state cannot complete first run implicitly', (
    tester,
  ) async {
    final preferences = InMemoryPreferencesRepository();
    await pumpWithRepositories(
      tester,
      preferences: preferences,
      models: _OnboardingDownloadModels(),
      eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
      child: const FirstRunGate(
        child: SizedBox(key: Key('chat-after-first-run')),
      ),
    );

    await tester.tap(find.byKey(const Key('first-run-get-started')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('first-run-download')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-download-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('first-run-download-progress')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('chat-after-first-run')), findsNothing);
    expect(preferences.preferences.onboardingVersion, 0);

    await tester.tap(find.byKey(const Key('first-run-start-chatting')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-after-first-run')), findsOneWidget);
    expect(preferences.preferences.onboardingVersion, currentOnboardingVersion);
  });

  for (final state in <({String name, ArtifactStatus status})>[
    (
      name: 'interrupted',
      status: const ArtifactStatus(
        phase: ArtifactPhase.paused,
        downloadedBytes: 400,
      ),
    ),
    (
      name: 'corrupt',
      status: const ArtifactStatus(
        phase: ArtifactPhase.failed,
        downloadedBytes: 400,
        failureReason: ArtifactFailure(ArtifactFailureKind.hashVerification),
      ),
    ),
  ]) {
    testWidgets('${state.name} setup resumes at the blocking download state', (
      tester,
    ) async {
      final preferences = InMemoryPreferencesRepository(
        const AppPreferences(
          onboardingVersion: currentOnboardingVersion,
          onboardingModelKey: 'gemma4-mlx',
        ),
      );
      await pumpWithRepositories(
        tester,
        preferences: preferences,
        model: ModelState(
          simulated: true,
          artifacts: {'gemma4-mlx': state.status},
        ),
        child: const FirstRunGate(
          child: SizedBox(key: Key('chat-after-first-run')),
        ),
      );

      expect(
        find.byKey(const Key('first-run-download-progress')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('first-run-resume-download')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('first-run-welcome')), findsNothing);
      expect(find.byKey(const Key('chat-after-first-run')), findsNothing);
      expect(
        preferences.preferences.onboardingVersion,
        currentOnboardingVersion,
      );
    });
  }

  testWidgets('a running download offers the note, pause, and cancel', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
      model: const ModelState(
        simulated: true,
        artifacts: {
          'gemma4-mlx': ArtifactStatus(
            phase: ArtifactPhase.downloading,
            downloadedBytes: 900000000,
          ),
        },
      ),
      child: const FirstRunScreen(initialStep: FirstRunStep.download),
    );

    expect(find.byKey(const Key('first-run-download-note')), findsOneWidget);
    expect(find.byKey(const Key('first-run-pause-download')), findsOneWidget);
    expect(find.byKey(const Key('first-run-cancel-download')), findsOneWidget);

    await tester.tap(find.byKey(const Key('download-note-dismiss')));
    await tester.pump();
    expect(find.text('Keep Golem open for full speed.'), findsNothing);
    expect(
      find.byKey(const Key('first-run-cancel-download')),
      findsOneWidget,
      reason: 'dismissing the note leaves the transfer controls alone',
    );
  });

  testWidgets('a cancelled download leaves a restart affordance', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
      model: const ModelState(
        simulated: true,
        artifacts: {
          'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.notDownloaded),
        },
      ),
      child: const FirstRunScreen(initialStep: FirstRunStep.download),
    );
    // Cancel and Discard both land the artifact here; without this button
    // the required-setup step would be a dead end until relaunch.
    expect(find.byKey(const Key('first-run-restart-download')), findsOneWidget);
  });

  testWidgets('a failed download surfaces retry and discard together', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
      model: const ModelState(
        simulated: true,
        artifacts: {
          'gemma4-mlx': ArtifactStatus(
            phase: ArtifactPhase.failed,
            downloadedBytes: 900000000,
            failureReason: ArtifactFailure(ArtifactFailureKind.transfer),
          ),
        },
      ),
      child: const FirstRunScreen(initialStep: FirstRunStep.download),
    );

    expect(find.byKey(const Key('first-run-failure-banner')), findsOneWidget);
    expect(find.byKey(const Key('first-run-resume-download')), findsOneWidget);
    expect(find.byKey(const Key('first-run-discard-download')), findsOneWidget);
    expect(
      find.byKey(const Key('first-run-download-note')),
      findsOneWidget,
      reason: 'the banner widget mounts but renders nothing while failed',
    );
    expect(find.text('Keep Golem open for full speed.'), findsNothing);
  });

  testWidgets(
    'an interrupted artifact from the other engine returns to model choice',
    (tester) async {
      final preferences = InMemoryPreferencesRepository(
        const AppPreferences(
          onboardingVersion: currentOnboardingVersion,
          onboardingModelKey: 'gemma4-gguf',
        ),
      );
      await pumpWithRepositories(
        tester,
        preferences: preferences,
        backend: const InferenceBackendConfig(
          kind: InferenceBackendKind.mlx,
          profileKey: 'gemma4',
          artifactKey: 'gemma4-mlx',
          modelPath: 'documents:models/gemma4-mlx',
          modelPathFromCatalog: true,
        ),
        eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
        model: const ModelState(
          artifacts: {
            'gemma4-gguf': ArtifactStatus(
              phase: ArtifactPhase.paused,
              downloadedBytes: 400,
            ),
          },
        ),
        child: const FirstRunGate(
          child: SizedBox(key: Key('chat-after-first-run')),
        ),
      );

      expect(find.byKey(const Key('first-run-model')), findsOneWidget);
      expect(find.byKey(const Key('first-run-download')), findsOneWidget);
      expect(find.byKey(const Key('first-run-resume-download')), findsNothing);
      expect(find.textContaining('MLX ·'), findsOneWidget);
      expect(find.textContaining('GGUF ·'), findsNothing);
      expect(find.byKey(const Key('chat-after-first-run')), findsNothing);
    },
  );

  testWidgets('deleting the last compatible model immediately re-gates shell', (
    tester,
  ) async {
    setViewport(tester);
    final preferences = InMemoryPreferencesRepository(
      const AppPreferences(
        onboardingVersion: currentOnboardingVersion,
        onboardingModelKey: 'gemma4-mlx',
      ),
    );
    final models = _DeletableModels();
    final container = buildContainer(
      history: seedHistory(),
      preferences: preferences,
      models: models,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: wrapApp(
          child: const FirstRunGate(
            child: SizedBox(key: Key('chat-after-first-run')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-after-first-run')), findsOneWidget);

    await container.read(modelControllerProvider.notifier).delete('gemma4-mlx');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-after-first-run')), findsNothing);
    expect(find.byKey(const Key('first-run-model')), findsOneWidget);
    expect(preferences.preferences.onboardingVersion, currentOnboardingVersion);
  });

  testWidgets('an alternate selection is not relabelled as recommended', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
      model: const ModelState(simulated: true),
      child: const FirstRunScreen(),
    );

    await tester.tap(find.byKey(const Key('first-run-get-started')));
    await tester.pumpAndSettle();
    expect(find.text('RECOMMENDED'), findsOneWidget);
    await tester.tap(find.byKey(const Key('first-run-choose-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('first-run-model-qwen35-gguf')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('first-run-catalog-back')));
    await tester.pumpAndSettle();

    expect(find.text('Qwen 3.5 4B'), findsOneWidget);
    expect(find.text('RECOMMENDED'), findsNothing);
  });

  testWidgets('an incompatible persisted MLX key cannot label Android setup', (
    tester,
  ) async {
    final preferences = InMemoryPreferencesRepository(
      const AppPreferences(onboardingModelKey: 'gemma4-mlx'),
    );
    await pumpWithRepositories(
      tester,
      preferences: preferences,
      backend: const InferenceBackendConfig(
        kind: InferenceBackendKind.llama,
        profileKey: 'gemma4',
        artifactKey: 'gemma4-gguf',
        modelPath: 'documents:models/gemma4-gguf/model.gguf',
        modelPathFromCatalog: true,
      ),
      eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
      child: const FirstRunScreen(initialStep: FirstRunStep.model),
    );

    expect(find.textContaining('GGUF ·'), findsOneWidget);
    expect(find.textContaining('MLX ·'), findsNothing);
    expect(find.text('3.18 GB'), findsWidgets);
    expect(find.text('3.58 GB'), findsNothing);
  });

  testWidgets('deferred setup shows the compact note while downloading', (
    tester,
  ) async {
    final preferences = InMemoryPreferencesRepository(
      const AppPreferences(
        onboardingVersion: currentOnboardingVersion,
        onboardingModelKey: 'gemma4-mlx',
      ),
    );
    await pumpWithRepositories(
      tester,
      preferences: preferences,
      model: const ModelState(
        simulated: true,
        artifacts: {
          'gemma4-mlx': ArtifactStatus(
            phase: ArtifactPhase.downloading,
            downloadedBytes: 900000000,
          ),
        },
      ),
      child: const ChatScreen(),
    );
    expect(find.byKey(const Key('model-setup-banner')), findsOneWidget);
    expect(find.byKey(const Key('chat-download-note')), findsOneWidget);
    expect(find.text('Keep Golem open for full speed.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('download-note-dismiss')));
    await tester.pump();
    expect(find.text('Keep Golem open for full speed.'), findsNothing);
    expect(
      find.byKey(const Key('model-setup-pause')),
      findsOneWidget,
      reason: 'dismissing the note keeps the banner controls',
    );
  });

  testWidgets('deferred setup is persistent and gates only sending', (
    tester,
  ) async {
    final preferences = InMemoryPreferencesRepository(
      const AppPreferences(
        onboardingVersion: currentOnboardingVersion,
        onboardingModelKey: 'gemma4-mlx',
      ),
    );
    await pumpWithRepositories(
      tester,
      preferences: preferences,
      model: const ModelState(simulated: true),
      child: const ChatScreen(),
    );
    expect(find.byKey(const Key('model-setup-banner')), findsOneWidget);
    expect(find.byKey(const Key('model-setup-download')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'A draft stays editable',
    );
    await tester.pump();
    expect(
      pressedHandler(tester, find.byKey(const Key('send-button'))),
      isNull,
    );
    expect(find.byKey(const Key('open-drawer')), findsOneWidget);

    await pumpWithRepositories(
      tester,
      preferences: preferences,
      model: const ModelState(
        simulated: true,
        artifacts: {
          'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
        },
      ),
      child: const ChatScreen(),
    );
    expect(find.byKey(const Key('model-setup-banner')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'Ready to send',
    );
    await tester.pump();
    expect(
      pressedHandler(tester, find.byKey(const Key('send-button'))),
      isNotNull,
    );
  });

  testWidgets(
    'an installed conversation model is not blocked by the setup key',
    (tester) async {
      final preferences = InMemoryPreferencesRepository(
        const AppPreferences(
          onboardingVersion: currentOnboardingVersion,
          onboardingModelKey: 'gemma4-gguf',
        ),
      );
      await pumpWithRepositories(
        tester,
        preferences: preferences,
        backend: const InferenceBackendConfig(
          kind: InferenceBackendKind.llama,
          profileKey: 'gemma4',
          artifactKey: 'gemma4-gguf',
          modelPath: 'documents:models/gemma4-gguf/model.gguf',
          modelPathFromCatalog: true,
        ),
        history: ChatHistorySnapshot(
          activeId: 'alternate-chat',
          conversations: [
            ChatConversation(
              id: 'alternate-chat',
              title: 'Alternate model',
              updatedAt: DateTime.utc(2026, 8, 11),
              messages: const [],
              modelKey: 'qwen35-gguf',
            ),
          ],
        ),
        model: const ModelState(
          artifacts: {
            'qwen35-gguf': ArtifactStatus(phase: ArtifactPhase.installed),
          },
        ),
        child: const ChatScreen(),
      );

      await tester.enterText(
        find.byKey(const Key('chat-composer')),
        'Use the installed conversation model',
      );
      await tester.pump();
      expect(
        pressedHandler(tester, find.byKey(const Key('send-button'))),
        isNotNull,
      );
    },
  );

  testWidgets('first run survives large text, RTL, and platform tap targets', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
      model: const ModelState(simulated: true),
      child: const Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: FirstRunScreen(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('first-run-get-started')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('first-run-choose-model')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final guideline =
        debugDefaultTargetPlatformOverride == TargetPlatform.android
        ? androidTapTargetGuideline
        : iOSTapTargetGuideline;
    await expectLater(tester, meetsGuideline(guideline));
  }, variant: bothChromes);

  testWidgets('blocking setup survives large text and announces progress', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpWithRepositories(
      tester,
      textScale: 1.6,
      eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
      model: const ModelState(
        simulated: true,
        artifacts: {
          'gemma4-mlx': ArtifactStatus(
            phase: ArtifactPhase.downloading,
            downloadedBytes: 900000000,
          ),
        },
      ),
      child: const FirstRunScreen(initialStep: FirstRunStep.download),
    );

    expect(tester.takeException(), isNull);
    final progress = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Download progress',
    );
    expect(progress, findsOneWidget);
    expect(tester.getSemantics(progress).value, isNotEmpty);
    expect(
      tester
          .widget<CupertinoButton>(
            find.descendant(
              of: find.byKey(const Key('first-run-start-chatting')),
              matching: find.byType(CupertinoButton),
            ),
          )
          .onPressed,
      isNull,
    );
    semantics.dispose();
  }, variant: bothChromes);

  testWidgets(
    'verification uses honest indeterminate progress with accessible status',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpWithRepositories(
        tester,
        textScale: 1.6,
        eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
        // Both engines, because which artifact first run features follows the
        // platform the variant runs (#118) — the subject here is the
        // verification pane, not the choice.
        model: const ModelState(
          simulated: false,
          artifacts: {
            'gemma4-mlx': ArtifactStatus(
              phase: ArtifactPhase.verifying,
              downloadedBytes: 3583086498,
            ),
            'gemma4-gguf': ArtifactStatus(
              phase: ArtifactPhase.verifying,
              downloadedBytes: 3183086498,
            ),
          },
        ),
        child: const FirstRunScreen(initialStep: FirstRunStep.download),
        settle: false,
      );

      expect(tester.takeException(), isNull);
      final progress = find.byKey(const Key('first-run-verification-progress'));
      expect(progress, findsOneWidget);
      expect(find.byKey(const Key('first-run-download-track')), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(tester.getSemantics(progress).label, 'Verifying Gemma 4 E2B');
      expect(
        tester.getSemantics(progress).value,
        'Checking the downloaded files before they can run.',
      );
      expect(
        tester
            .widget<CupertinoButton>(
              find.descendant(
                of: find.byKey(const Key('first-run-start-chatting')),
                matching: find.byType(CupertinoButton),
              ),
            )
            .onPressed,
        isNull,
      );
      semantics.dispose();
    },
    variant: bothChromes,
  );
}

final class _OnboardingDownloadModels implements ModelManagementRepository {
  ModelState _state = const ModelState(simulated: true);

  @override
  Future<ModelState> load() async => _state;

  @override
  Stream<ModelState> download(String artifactKey) async* {
    _state = _state.withArtifact(
      artifactKey,
      const ArtifactStatus(phase: ArtifactPhase.downloading),
    );
    yield _state;
    _state = _state.withArtifact(
      artifactKey,
      const ArtifactStatus(phase: ArtifactPhase.installed),
    );
    yield _state;
  }

  @override
  Future<ModelState> pause(String artifactKey) async => _state;

  @override
  Future<ModelState> cancel(String artifactKey) async => _state;

  @override
  Future<ModelState> delete(String artifactKey) async => _state;

  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => _state;

  @override
  Future<ModelState> recordRuntime(
    RuntimePhase phase, {
    RuntimeFailureKind? failure,
  }) async => _state;
}

final class _DeletableModels implements ModelManagementRepository {
  ModelState _state = const ModelState(
    simulated: true,
    artifacts: {'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed)},
  );

  @override
  Future<ModelState> load() async => _state;

  @override
  Future<ModelState> delete(String artifactKey) async {
    _state = _state.withArtifact(artifactKey, const ArtifactStatus());
    return _state;
  }

  @override
  Stream<ModelState> download(String artifactKey) => Stream.value(_state);

  @override
  Future<ModelState> pause(String artifactKey) async => _state;

  @override
  Future<ModelState> cancel(String artifactKey) async => _state;

  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => _state;

  @override
  Future<ModelState> recordRuntime(
    RuntimePhase phase, {
    RuntimeFailureKind? failure,
  }) async => _state;
}
