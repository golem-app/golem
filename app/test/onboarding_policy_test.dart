import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/backend_policy.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/device_eligibility.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/onboarding/domain/onboarding_policy.dart';
import 'package:golem_flutter/core/domain/model_activation.dart';
import 'package:golem_flutter/core/domain/model_admission.dart';

void main() {
  group('first-run decision', () {
    const backend = InferenceBackendConfig.fake();

    bool decide({
      AppPreferences preferences = const AppPreferences(),
      bool hasConversations = false,
      ModelState models = const ModelState(),
      InferenceBackendConfig configuredBackend = backend,
    }) => shouldShowFirstRun(
      preferences: preferences,
      hasConversations: hasConversations,
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
      expect(decide(hasConversations: true), isFalse);
      // A downgrade carries a version this build has never heard of. It is
      // still a completed install, so the comparison is `>=` and not `==`.
      expect(
        decide(
          preferences: const AppPreferences(
            onboardingVersion: currentOnboardingVersion + 1,
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
      // Every clause has to hold, not any of them: an artifact installed by a
      // build that predates onboarding carries no bytes and no failure, and is
      // exactly the legacy install that must not be sent through setup.
      expect(
        decide(
          models: const ModelState(
            artifacts: {
              'gemma4-gguf': ArtifactStatus(phase: ArtifactPhase.installed),
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

    test('the simulation recommends what this platform would run', () {
      // The recommendation is hardware-independent by design, but not
      // platform-independent: the engine is a build composition, so Android
      // QA featuring an MLX artifact advertised a model that build could
      // never execute (#118).
      String? recommendedOn(HostPlatform platform) =>
          recommendedAdmittedModelKey(
            catalog: modelCatalog,
            backend: resolveBackendPolicy(
              backendName: 'fake',
              profileDefine: '',
              artifactDefine: '',
              modelPathDefine: '',
              tier: DeviceTier.light,
              platform: platform,
            ),
            eligibility: const DeviceEligibility(tier: DeviceTier.light),
          );
      expect(recommendedOn(HostPlatform.ios), 'gemma4-mlx');
      expect(recommendedOn(HostPlatform.android), 'gemma4-gguf');
      expect(recommendedOn(HostPlatform.macos), 'gemma4-gguf');
    });

    test('the simulation falls back to what it recommends', () {
      // The badge and the label have to agree: a fallback pinned to one engine
      // let the chip, the header and the next turn name an artifact the
      // platform could not run while the badge named another.
      String? fallbackOn(HostPlatform platform) => effectiveModelKey(
        backend: resolveBackendPolicy(
          backendName: 'fake',
          profileDefine: '',
          artifactDefine: '',
          modelPathDefine: '',
          tier: DeviceTier.preferred,
          platform: platform,
        ),
        catalog: modelCatalog,
        loadableKeys: const <String>{},
      );
      expect(fallbackOn(HostPlatform.ios), 'gemma4-mlx');
      expect(fallbackOn(HostPlatform.android), 'gemma4-gguf');
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

    // The un-localized fallback sentence, which is what a build with no
    // localizations shows. It has to name the engine this build *runs*, which
    // is the opposite of the one the refused artifact needs.
    test('a refused artifact names the engine this build runs', () {
      String reasonFor(InferenceBackendConfig backend, String key) =>
          modelAdmissionOptions(
            catalog: modelCatalog,
            backend: backend,
            eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
          ).firstWhere((option) => option.entry.key == key).disabledReason!;

      expect(
        reasonFor(llama, 'gemma4-mlx'),
        'This build uses the GGUF engine.',
      );
      expect(
        reasonFor(
          const InferenceBackendConfig(
            kind: InferenceBackendKind.mlx,
            profileKey: 'gemma4',
            artifactKey: 'gemma4-mlx',
            modelPath: 'documents:models/gemma4-mlx',
            modelPathFromCatalog: true,
          ),
          'gemma4-gguf',
        ),
        'This build uses the MLX engine.',
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

  group('startup gate decision', () {
    ({StartupGate gate, bool migrateLegacy}) resolve({
      bool pristineAtLaunch = false,
      bool onboardingComplete = true,
      bool hasUsableModel = true,
      ArtifactStatus selectedStatus = const ArtifactStatus(),
    }) => resolveStartupGate(
      pristineAtLaunch: pristineAtLaunch,
      onboardingComplete: onboardingComplete,
      hasUsableModel: hasUsableModel,
      selectedStatus: selectedStatus,
    );

    test('a usable model admits the shell, pristine or not', () {
      expect(resolve().gate, const GateAdmitted());
      // The install that was pristine at launch and has since acquired a model
      // still owes its onboarding: it is admitted only once setup completed it.
      expect(
        resolve(pristineAtLaunch: true, onboardingComplete: true).gate,
        const GateAdmitted(),
      );
    });

    test('the legacy stamp is owed exactly once, and only when admitted', () {
      // The install this exists for: chats or model work on disk from before
      // onboarding existed, so it must not be sent through setup, but its
      // version has to be recorded or the next launch asks again.
      expect(
        resolve(onboardingComplete: false).migrateLegacy,
        isTrue,
        reason: 'a usable legacy install is admitted and stamped',
      );
      expect(resolve().migrateLegacy, isFalse);
      expect(
        resolve(onboardingComplete: false, hasUsableModel: false).migrateLegacy,
        isFalse,
        reason: 'nothing is stamped while setup is still required',
      );
    });

    test('a pristine install opens setup at its own welcome', () {
      // Not the download step, whatever bytes a *different* artifact carries:
      // a fresh install has made no choice for a resume to belong to.
      expect(
        resolve(
          pristineAtLaunch: true,
          hasUsableModel: false,
          selectedStatus: const ArtifactStatus(
            phase: ArtifactPhase.paused,
            downloadedBytes: 400,
          ),
        ).gate,
        const GateFirstRun(FirstRunEntry.fresh),
      );
    });

    test('an interrupted upgrade resumes rather than re-choosing', () {
      expect(
        resolve(hasUsableModel: false).gate,
        const GateFirstRun(FirstRunEntry.chooseModel),
      );
      // Either signal is enough: a cancelled transfer keeps its bytes while
      // reverting to notDownloaded, and a failed one keeps its phase.
      expect(
        resolve(
          hasUsableModel: false,
          selectedStatus: const ArtifactStatus(downloadedBytes: 400),
        ).gate,
        const GateFirstRun(FirstRunEntry.resumeDownload),
      );
      expect(
        resolve(
          hasUsableModel: false,
          selectedStatus: const ArtifactStatus(phase: ArtifactPhase.failed),
        ).gate,
        const GateFirstRun(FirstRunEntry.resumeDownload),
      );
    });
  });
}
