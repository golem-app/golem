import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/app/launch_composition.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/device_eligibility.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/providers/retry.dart';
import 'package:golem_flutter/features/onboarding/application/onboarding_controller.dart';

import 'package:golem_flutter/features/settings/application/preferences_providers.dart';
import 'support/harness.dart';
import 'support/in_memory_preferences_repository.dart';

void main() {
  test(
    'selection and completion persist through the preferences owner',
    () async {
      final preferences = InMemoryPreferencesRepository();
      final container = ProviderContainer.test(
        retry: noRetry,
        overrides: launchOverrides(
          launchDependenciesWith(
            eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
            preferences: preferences,
          ),
        ),
      );
      await container.read(preferencesControllerProvider.future);
      final subscription = container.listen(
        firstRunControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final controller = container.read(firstRunControllerProvider.notifier);
      controller.continueFromWelcome();
      expect(
        container.read(firstRunControllerProvider).step,
        FirstRunStep.model,
      );
      expect(await controller.selectModel('qwen35-gguf'), isTrue);
      expect(preferences.preferences.onboardingModelKey, 'qwen35-gguf');

      controller.showDownload();
      expect(
        container.read(firstRunControllerProvider).step,
        FirstRunStep.download,
      );
      expect(await controller.complete(), isTrue);
      expect(
        preferences.preferences.onboardingVersion,
        currentOnboardingVersion,
      );
      expect(preferences.preferences.onboardingModelKey, 'qwen35-gguf');
    },
  );

  test('unsupported completion persists no selected model', () async {
    final preferences = InMemoryPreferencesRepository();
    final container = ProviderContainer.test(
      retry: noRetry,
      overrides: launchOverrides(
        launchDependenciesWith(
          backend: const InferenceBackendConfig(
            kind: InferenceBackendKind.llama,
            profileKey: 'gemma4',
            artifactKey: 'gemma4-gguf',
            modelPath: 'documents:models/gemma4-gguf/model.gguf',
            modelPathFromCatalog: true,
          ),
          eligibility: const DeviceEligibility(
            tier: DeviceTier.unsupported,
            reason: DeviceIneligibilityReason.belowMemoryFloor,
            message: 'Unsupported for this test.',
          ),
          preferences: preferences,
        ),
      ),
    );
    await container.read(preferencesControllerProvider.future);
    final subscription = container.listen(
      firstRunControllerProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    final controller = container.read(firstRunControllerProvider.notifier);
    controller.continueFromWelcome();
    expect(
      container.read(firstRunControllerProvider).step,
      FirstRunStep.unsupported,
    );
    expect(await controller.complete(keepSelection: false), isTrue);
    expect(preferences.preferences.onboardingModelKey, isNull);
  });

  test(
    'a failed completion stays actionable without provider retries',
    () async {
      final preferences = InMemoryPreferencesRepository()..failingSaves = 1;
      final container = ProviderContainer.test(
        retry: noRetry,
        overrides: launchOverrides(
          launchDependenciesWith(preferences: preferences),
        ),
      );
      await container.read(preferencesControllerProvider.future);
      final subscription = container.listen(
        firstRunControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final controller = container.read(firstRunControllerProvider.notifier);
      controller.showDownload();
      expect(await controller.complete(), isFalse);
      expect(
        container.read(firstRunControllerProvider),
        isA<FirstRunState>()
            .having((state) => state.step, 'step', FirstRunStep.download)
            .having(
              (state) => state.failure,
              'failure',
              FirstRunFailure.setupSave,
            ),
      );
      expect(preferences.preferences.onboardingVersion, 0);
    },
  );
}
