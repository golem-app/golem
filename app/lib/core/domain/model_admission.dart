/// Which pinned artifacts this device is allowed to have, and why not when it
/// is not. One policy, because two surfaces ask it: first run curates the
/// initial download (#26) and the per-chat picker offers switches (#79). When
/// they each answered for themselves they disagreed — the picker offered a
/// light-tier phone the larger model that onboarding had just refused it.
///
/// Admission only. Whether an artifact is installed, mid-transfer or already
/// chosen belongs to the surface asking.
library;

import 'device_eligibility.dart';
import 'inference_backend.dart';
import 'model_catalog.dart';

/// Why a hand-added repository cannot be fetched. One sentence, because the
/// Settings card and the chat picker both refuse it and had already drifted
/// apart by a clause on the day they were written.
const unresolvedRepositoryReason =
    'This repository has not been resolved against Hugging Face, so its files '
    'are unknown. Add it again to resolve it.';

enum ModelAdmissionBlock { otherEngine, needsPreferredTier, unsupportedDevice }

final class ModelAdmissionOption {
  const ModelAdmissionOption({
    required this.entry,
    required this.enabled,
    required this.recommended,
    required this.memoryKnown,
    this.block,
  });

  final ModelCatalogEntry entry;
  final bool enabled;
  final bool recommended;
  final ModelAdmissionBlock? block;

  /// Whether the reading behind a tier refusal actually happened. The light
  /// tier is also where an unreadable probe lands, and unknown is not a low
  /// value (ADR 0007) — so the refusal may not describe it as one.
  final bool memoryKnown;

  String? get disabledReason => switch (block) {
    ModelAdmissionBlock.otherEngine =>
      'This build uses the '
          '${entry.engine == ModelEngine.mlx ? 'GGUF' : 'MLX'} engine.',
    ModelAdmissionBlock.needsPreferredTier when !memoryKnown =>
      'Golem could not read this phone’s memory, so it ships the lighter '
          'model here.',
    ModelAdmissionBlock.needsPreferredTier =>
      'Needs more memory than this phone reports.',
    ModelAdmissionBlock.unsupportedDevice =>
      'Models are unavailable on this device.',
    null => null,
  };
}

/// The pinned catalog stays visible in QA and on production devices. Entries
/// for the other compiled engine remain visible but disabled; a light-tier
/// device can choose either Qwen 3.5 2B artifact its build can execute.
List<ModelAdmissionOption> modelAdmissionOptions({
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
  final preliminary = <({ModelCatalogEntry entry, ModelAdmissionBlock? block})>[
    for (final entry in catalog)
      (
        entry: entry,
        block: !backend.simulatedInference && !eligibility.runsModels
            ? ModelAdmissionBlock.unsupportedDevice
            : !backend.simulatedInference && !backend.kind.loads(entry.engine)
            ? ModelAdmissionBlock.otherEngine
            : effectiveTier == DeviceTier.light &&
                  entry.key != backend.artifactKey &&
                  !entry.key.startsWith('qwen35-2b-')
            ? ModelAdmissionBlock.needsPreferredTier
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
      ModelAdmissionOption(
        entry: item.entry,
        enabled: item.block == null,
        recommended: item.entry.key == recommendedKey,
        block: item.block,
        memoryKnown: eligibility.memoryKnown,
      ),
  ];
}

String? recommendedAdmittedModelKey({
  required List<ModelCatalogEntry> catalog,
  required InferenceBackendConfig backend,
  required DeviceEligibility eligibility,
  String? selectedKey,
}) {
  final options = modelAdmissionOptions(
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
    // The simulation enables every engine, so something has to break the tie.
    // It used to be a hardcoded MLX preference, which made Android QA feature
    // an artifact that build could not execute while dev on the same phone
    // recommended GGUF (#118). The platform's composed engine breaks it now.
    return candidates
            .where((entry) => entry.engine == backend.simulatedEngine)
            .firstOrNull
            ?.key ??
        candidates.firstOrNull?.key ??
        enabled.firstOrNull?.key;
  }
  return candidates.firstOrNull?.key ?? enabled.firstOrNull?.key;
}
