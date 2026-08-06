import '../../core/domain/inference_backend.dart';
import '../../core/domain/model_catalog.dart';

/// The catalog key a conversation effectively runs.
///
/// A real engine runs its configured artifact no matter what the
/// conversation stored (per-chat switching arrives with #20), so on real
/// backends the per-chat choice must never outrank [InferenceBackendConfig.artifactKey]
/// — every label derived from this would otherwise name a model that is
/// not running. Only the fake, which honors [modelKey] in generation,
/// lets the stored choice win.
String effectiveModelKey({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  String? modelKey,
}) =>
    (backend.simulatedInference ? modelKey : null) ??
    backend.artifactKey ??
    (catalog.any((entry) => entry.key == 'gemma4-mlx')
        ? 'gemma4-mlx'
        : catalog.first.key);

/// Display name for the effective model, for the nav subtitle and the
/// composer's model chip.
String chatModelLabel({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  String? modelKey,
}) {
  final key = effectiveModelKey(
    backend: backend,
    catalog: catalog,
    modelKey: modelKey,
  );
  return catalog.where((entry) => entry.key == key).firstOrNull?.displayName ??
      key;
}

/// The nav bar's second line. Honesty is non-negotiable: simulated
/// builds say so, only a real engine claims "on device".
String chatModelSubtitle({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  String? modelKey,
}) {
  final label = chatModelLabel(
    backend: backend,
    catalog: catalog,
    modelKey: modelKey,
  );
  return backend.simulatedInference
      ? '$label · simulated'
      : '$label · on device';
}
