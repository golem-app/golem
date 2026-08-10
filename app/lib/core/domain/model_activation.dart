import 'inference_backend.dart';
import 'model_catalog.dart';
import 'models.dart';

/// The keys a real engine can activate right now: installed, of the engine this
/// build composed, and carrying a chat template the broker recognizes. A
/// per-chat selection is constrained to this set, which is what lets every label
/// follow the selection without naming weights the next send would fail to load
/// (#20).
///
/// The template condition is not cosmetic: a custom repository whose template
/// matched no fingerprint resolves and installs anyway, and only
/// resolveModelRuntimeConfig refuses it — one send too late to keep the promise
/// above.
Set<String> loadableModelKeys({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  required ModelState? models,
}) {
  if (models == null) return const {};
  return {
    for (final entry in catalog)
      if (entry.profileKey != unresolvedProfileKey &&
          backend.kind.loads(entry.engine) &&
          models.statusOf(entry.key).phase == ArtifactPhase.installed)
        entry.key,
  };
}

/// The catalog key a conversation effectively runs, or null when a real engine
/// holds an operator-sideloaded file no catalog entry describes.
///
/// The per-chat choice wins on a real engine only when it is in [loadableKeys],
/// so it can never name a model the next send would fail to load (#20).
/// Without that set — label-only containers — residency (#42) stays the
/// authority, and [InferenceBackendConfig.artifactKey] fills in before the lazy
/// first load. The fake honors the choice unconditionally, as it always has.
String? effectiveModelKey({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  String? modelKey,
  String? residentModelKey,
  Set<String>? loadableKeys,
}) {
  if (backend.sideloaded) return null;
  final String? chosen;
  if (backend.simulatedInference) {
    chosen = modelKey;
  } else if (modelKey != null && (loadableKeys?.contains(modelKey) ?? false)) {
    chosen = modelKey;
  } else {
    chosen = null;
  }
  return chosen ??
      residentModelKey ??
      backend.artifactKey ??
      (catalog.any((entry) => entry.key == 'gemma4-mlx')
          ? 'gemma4-mlx'
          : catalog.first.key);
}

/// The file or directory an operator pointed the build at — never the path
/// around it, which is the developer's machine and not the user's business.
String sideloadedModelLabel(String modelPath) {
  final name = modelPath
      .replaceFirst('documents:', '')
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .lastOrNull;
  return name == null || name.isEmpty ? 'Sideloaded model' : name;
}
