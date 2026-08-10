import '../../core/domain/inference_backend.dart';
import '../../core/domain/model_catalog.dart';

/// The catalog key a conversation effectively runs.
///
/// On real backends this follows actual residency (#42) — a label naming a
/// model that is not running would lie — so [residentModelKey] outranks the
/// stored per-chat choice, and [InferenceBackendConfig.artifactKey] fills in
/// before the lazy first load. Only the fake, which honors [modelKey] in
/// generation, lets the stored choice win.
String effectiveModelKey({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  String? modelKey,
  String? residentModelKey,
}) =>
    (backend.simulatedInference ? modelKey : residentModelKey) ??
    backend.artifactKey ??
    (catalog.any((entry) => entry.key == 'gemma4-mlx')
        ? 'gemma4-mlx'
        : catalog.first.key);

String chatModelLabel({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  String? modelKey,
  String? residentModelKey,
}) {
  final key = effectiveModelKey(
    backend: backend,
    catalog: catalog,
    modelKey: modelKey,
    residentModelKey: residentModelKey,
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
  String? residentModelKey,
}) {
  final label = chatModelLabel(
    backend: backend,
    catalog: catalog,
    modelKey: modelKey,
    residentModelKey: residentModelKey,
  );
  return backend.simulatedInference
      ? '$label · simulated'
      : '$label · on device';
}

/// Whether the model this chat effectively runs accepts images.
///
/// Read from the catalog entry, never a display name: the same family can be
/// image-capable through one engine and text-only through another (#18).
bool chatModelSupportsImages({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  String? modelKey,
  String? residentModelKey,
}) {
  final key = effectiveModelKey(
    backend: backend,
    catalog: catalog,
    modelKey: modelKey,
    residentModelKey: residentModelKey,
  );
  return catalog
          .where((entry) => entry.key == key)
          .firstOrNull
          ?.supportsImages ??
      false;
}
