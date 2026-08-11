import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/device_eligibility.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/onboarding/first_run_gate.dart';
import 'package:golem_flutter/features/onboarding/first_run_screen.dart';

import 'support/harness.dart';
import 'support/in_memory_preferences_repository.dart';

void main() {
  testWidgets('the root gate distinguishes fresh and legacy installs', (
    tester,
  ) async {
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
      model: const ModelState(simulated: true),
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
  });

  testWidgets('declining consent completes first run without a download', (
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

    expect(preferences.preferences.onboardingVersion, currentOnboardingVersion);
    expect(preferences.preferences.onboardingModelKey, 'gemma4-mlx');
    expect(find.byKey(const Key('first-run-model')), findsNothing);
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
    final blocked = tester.widget<CupertinoButton>(
      find.byKey(const Key('send-button')),
    );
    expect(blocked.onPressed, isNull);
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
    final ready = tester.widget<CupertinoButton>(
      find.byKey(const Key('send-button')),
    );
    expect(ready.onPressed, isNotNull);
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
        tester
            .widget<CupertinoButton>(find.byKey(const Key('send-button')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'first run survives large text, RTL, and platform tap targets',
    (tester) async {
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
    String? failure,
  }) async => _state;
}
