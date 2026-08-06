import '../../core/domain/inference_backend.dart';
import '../../core/domain/model_catalog.dart';

/// The catalog key a conversation effectively runs: its own choice, else
/// the build's active artifact, else the catalog's default-policy model.
String effectiveModelKey({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  String? modelKey,
}) =>
    modelKey ??
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
