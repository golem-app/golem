import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/device_eligibility.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/onboarding/domain/onboarding_policy.dart';
import 'package:golem_flutter/core/domain/model_admission.dart';

void main() {
  group('first-run decision', () {
    const backend = InferenceBackendConfig.fake();

    bool decide({
      AppPreferences preferences = const AppPreferences(),
      ChatState chats = const ChatState(),
      ModelState models = const ModelState(),
      InferenceBackendConfig configuredBackend = backend,
    }) => shouldShowFirstRun(
      preferences: preferences,
      chats: chats,
      models: models,
      backend: configuredBackend,
    );

    test('only a genuinely pristine install enters onboarding', () {
      expect(decide(), isTrue);
      expect(
        decide(
          preferences: const AppPreferences(
            onboardingVersion: currentOnboardingVersion,
          ),
        ),
        isFalse,
      );
      expect(
        decide(
          models: const ModelState(
            artifacts: {
              'gemma4-gguf': ArtifactStatus(),
              'gemma4-mlx': ArtifactStatus(),
            },
          ),
        ),
        isTrue,
      );
      expect(
        decide(
          chats: ChatState(
            conversations: [
              ChatConversation(
                id: 'existing',
                title: 'Existing chat',
                messages: const [],
                updatedAt: DateTime.utc(2026, 8, 11),
              ),
            ],
          ),
        ),
        isFalse,
      );
      expect(
        decide(
          models: const ModelState(
            artifacts: {
              'gemma4-gguf': ArtifactStatus(
                phase: ArtifactPhase.paused,
                downloadedBytes: 42,
              ),
            },
          ),
        ),
        isFalse,
      );
    });

    test('an operator sideload bypasses consumer download setup', () {
      expect(
        decide(
          configuredBackend: const InferenceBackendConfig(
            kind: InferenceBackendKind.llama,
            profileKey: 'gemma4',
            modelPath: 'documents:operator/model.gguf',
          ),
        ),
        isFalse,
      );
    });
  });

  group('device model policy', () {
    const fake = InferenceBackendConfig.fake();
    const llama = InferenceBackendConfig(
      kind: InferenceBackendKind.llama,
      profileKey: 'gemma4',
      artifactKey: 'gemma4-gguf',
      modelPath: 'documents:models/gemma4-gguf/model.gguf',
      modelPathFromCatalog: true,
    );

    test('QA shows and enables the full catalog deterministically', () {
      final options = modelAdmissionOptions(
        catalog: modelCatalog,
        backend: fake,
        eligibility: const DeviceEligibility(tier: DeviceTier.light),
      );
      expect(options, hasLength(modelCatalog.length));
      expect(options.every((option) => option.enabled), isTrue);
      expect(
        recommendedAdmittedModelKey(
          catalog: modelCatalog,
          backend: fake,
          eligibility: const DeviceEligibility(tier: DeviceTier.light),
        ),
        'gemma4-mlx',
      );
    });

    test('a light real build enables only its configured 2B artifact', () {
      const lightLlama = InferenceBackendConfig(
        kind: InferenceBackendKind.llama,
        profileKey: 'qwen35',
        artifactKey: 'qwen35-2b-gguf',
        modelPath: 'documents:models/qwen35-2b-gguf/model.gguf',
        modelPathFromCatalog: true,
      );
      final options = modelAdmissionOptions(
        catalog: modelCatalog,
        backend: lightLlama,
        eligibility: const DeviceEligibility(tier: DeviceTier.light),
      );
      expect(
        options
            .where((option) => option.enabled)
            .map((option) => option.entry.key),
        {'qwen35-2b-gguf'},
      );
      expect(
        recommendedAdmittedModelKey(
          catalog: modelCatalog,
          backend: lightLlama,
          eligibility: const DeviceEligibility(tier: DeviceTier.light),
        ),
        'qwen35-2b-gguf',
      );
    });

    test('a configured larger artifact wins on a light device', () {
      final options = modelAdmissionOptions(
        catalog: modelCatalog,
        backend: llama,
        eligibility: const DeviceEligibility(tier: DeviceTier.light),
      );
      expect(
        options
            .where((option) => option.enabled)
            .map((option) => option.entry.key),
        {'gemma4-gguf', 'qwen35-2b-gguf'},
      );
      expect(
        options.where((option) => option.recommended).single.entry.key,
        'gemma4-gguf',
      );
    });

    test('preferred llama tier enables its engine and marks Gemma default', () {
      final options = modelAdmissionOptions(
        catalog: modelCatalog,
        backend: llama,
        eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
      );
      expect(
        options
            .where((option) => option.enabled)
            .map((option) => option.entry.engine),
        everyElement(ModelEngine.gguf),
      );
      expect(
        options.where((option) => option.recommended).single.entry.key,
        'gemma4-gguf',
      );
      expect(
        options
            .where((option) => option.entry.engine == ModelEngine.mlx)
            .every((option) => option.block == ModelAdmissionBlock.otherEngine),
        isTrue,
      );
    });

    test(
      'a valid persisted choice wins without relabelling it recommended',
      () {
        expect(
          recommendedAdmittedModelKey(
            catalog: modelCatalog,
            backend: llama,
            eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
            selectedKey: 'qwen35-gguf',
          ),
          'qwen35-gguf',
        );
        expect(
          modelAdmissionOptions(
            catalog: modelCatalog,
            backend: llama,
            eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
          ).where((option) => option.recommended).single.entry.key,
          'gemma4-gguf',
        );
      },
    );
  });
}
