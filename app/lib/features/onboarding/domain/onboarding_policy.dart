import '../../../core/domain/app_preferences.dart';
import '../../../core/domain/app_state.dart';
import '../../../core/domain/device_eligibility.dart';
import '../../../core/domain/inference_backend.dart';
import '../../../core/domain/model_catalog.dart';
import '../../../core/domain/models.dart';

/// Whether the root should present first run, wait for persisted state, or
/// enter chat. Existing installs are detected from all three stores so adding
/// #26 cannot strand a user who already has chats or model work on disk.
bool shouldShowFirstRun({
  required AppPreferences preferences,
  required ChatState chats,
  required ModelState models,
  required InferenceBackendConfig backend,
}) {
  if (preferences.onboardingVersion >= currentOnboardingVersion) return false;
  if (backend.sideloaded) return false;
  if (chats.conversations.isNotEmpty) return false;
  if (models.artifacts.isNotEmpty ||
      models.runtime != RuntimePhase.unloaded ||
      models.failure != null) {
    return false;
  }
  return true;
}

enum OnboardingModelBlock { otherEngine, needsPreferredTier, unsupportedDevice }

final class OnboardingModelOption {
  const OnboardingModelOption({
    required this.entry,
    required this.enabled,
    required this.recommended,
    this.block,
  });

  final ModelCatalogEntry entry;
  final bool enabled;
  final bool recommended;
  final OnboardingModelBlock? block;

  String? get disabledReason => switch (block) {
    OnboardingModelBlock.otherEngine =>
      'This build uses the ${entry.engine == ModelEngine.mlx ? 'GGUF' : 'MLX'} engine.',
    OnboardingModelBlock.needsPreferredTier =>
      'Needs more memory than this phone reports.',
    OnboardingModelBlock.unsupportedDevice =>
      'Models are unavailable on this device.',
    null => null,
  };
}

/// The pinned catalog stays visible in QA and on production devices. Entries
/// for the other compiled engine remain visible but disabled; a light-tier
/// device can choose either Qwen 3.5 2B artifact its build can execute.
List<OnboardingModelOption> onboardingModelOptions({
  required List<ModelCatalogEntry> catalog,
  required InferenceBackendConfig backend,
  required DeviceEligibility eligibility,
}) {
  // QA is a hardware-independent product simulation: it shows and can run the
  // entire pinned catalog deterministically without weights. Production/dev
  // continue to use the launch-time device verdict from #27.
  final effectiveTier = backend.simulatedInference
      ? DeviceTier.preferred
      : eligibility.tier;
  final preliminary =
      <({ModelCatalogEntry entry, OnboardingModelBlock? block})>[
        for (final entry in catalog)
          (
            entry: entry,
            block: !backend.simulatedInference && !eligibility.runsModels
                ? OnboardingModelBlock.unsupportedDevice
                : !backend.simulatedInference &&
                      !backend.kind.loads(entry.engine)
                ? OnboardingModelBlock.otherEngine
                : effectiveTier == DeviceTier.light &&
                      entry.key != backend.artifactKey &&
                      !entry.key.startsWith('qwen35-2b-')
                ? OnboardingModelBlock.needsPreferredTier
                : null,
          ),
      ];
  final enabled = preliminary.where((item) => item.block == null).toList();
  final recommendedKey = _recommendedKey(
    enabled.map((item) => item.entry).toList(),
    backend: backend,
    tier: effectiveTier,
  );
  return [
    for (final item in preliminary)
      OnboardingModelOption(
        entry: item.entry,
        enabled: item.block == null,
        recommended: item.entry.key == recommendedKey,
        block: item.block,
      ),
  ];
}

String? recommendedOnboardingModelKey({
  required List<ModelCatalogEntry> catalog,
  required InferenceBackendConfig backend,
  required DeviceEligibility eligibility,
  String? selectedKey,
}) {
  final options = onboardingModelOptions(
    catalog: catalog,
    backend: backend,
    eligibility: eligibility,
  );
  if (options.any(
    (option) => option.enabled && option.entry.key == selectedKey,
  )) {
    return selectedKey;
  }
  return options.where((option) => option.recommended).firstOrNull?.entry.key;
}

String? _recommendedKey(
  List<ModelCatalogEntry> enabled, {
  required InferenceBackendConfig backend,
  required DeviceTier tier,
}) {
  if (enabled.any((entry) => entry.key == backend.artifactKey)) {
    return backend.artifactKey;
  }
  final family = tier == DeviceTier.light ? 'qwen35-2b-' : 'gemma4-';
  final candidates = enabled.where((entry) => entry.key.startsWith(family));
  if (backend.simulatedInference) {
    return candidates
            .where((entry) => entry.engine == ModelEngine.mlx)
            .firstOrNull
            ?.key ??
        candidates.firstOrNull?.key ??
        enabled.firstOrNull?.key;
  }
  return candidates.firstOrNull?.key ?? enabled.firstOrNull?.key;
}
