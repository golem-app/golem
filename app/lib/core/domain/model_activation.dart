/// Stays in core (#69): chat, Settings, and Storage all resolve the live
/// model through these helpers, so none of the three can own them.
library;

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

/// What the simulation falls back to when nothing has been chosen: the default
/// family, of the engine this platform's real build composes. Hardcoding one
/// engine here would have the chip, the header and the next turn name an
/// artifact the platform could not run while the picker's badge named another
/// (#118).
String? simulatedFallbackKey(
  InferenceBackendConfig backend,
  List<ModelCatalogEntry> catalog,
) {
  final family = catalog.where((entry) => entry.key.startsWith('gemma4-'));
  return family
          .where((entry) => entry.engine == backend.simulatedEngine)
          .firstOrNull
          ?.key ??
      family.firstOrNull?.key ??
      catalog.firstOrNull?.key;
}

/// The compatible verified artifact this process should use when a stored
/// choice is unavailable. Catalog order is stable, so every caller reaches the
/// same fallback without rewriting historical conversation data.
String? startupModelKey({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  required Set<String> loadableKeys,
  String? preferredKey,
}) {
  if (backend.sideloaded) return null;
  if (backend.simulatedInference) {
    return preferredKey ??
        backend.artifactKey ??
        simulatedFallbackKey(backend, catalog);
  }
  for (final key in [preferredKey, backend.artifactKey]) {
    if (key != null && loadableKeys.contains(key)) return key;
  }
  return catalog
      .where((entry) => loadableKeys.contains(entry.key))
      .firstOrNull
      ?.key;
}

/// The artifact this build boots with, before any conversation has chosen one
/// and before the engine has loaded anything. Surfaces scoped to the build's
/// own prompt profile name this rather than the open chat's choice: the
/// response-style screen edits `backend.profileKey`'s sampling, so a caption
/// following the conversation would describe a different model from the values
/// under it (#129).
String? bootModelKey(
  InferenceBackendConfig backend,
  List<ModelCatalogEntry> catalog,
) => backend.sideloaded
    ? null
    : backend.artifactKey ?? simulatedFallbackKey(backend, catalog);

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
  if (chosen != null) return chosen;
  if (loadableKeys != null) {
    return startupModelKey(
      backend: backend,
      catalog: catalog,
      loadableKeys: loadableKeys,
      preferredKey: residentModelKey,
    );
  }
  return residentModelKey ??
      backend.artifactKey ??
      simulatedFallbackKey(backend, catalog);
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
