import '../../core/domain/inference_backend.dart';
import '../../core/domain/model_catalog.dart';

/// The catalog key a conversation effectively runs.
///
/// On real backends the label follows actual residency (#42): the model
/// the engine holds right now ([residentModelKey]) outranks everything,
/// and the boot-configured [InferenceBackendConfig.artifactKey] fills in
/// while the engine is still empty before the lazy first load. The stored
/// per-chat choice never outranks residency there — a label naming a
/// model that is not running would lie. Only the fake, which honors
/// [modelKey] in generation, lets the stored choice win.
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

/// Display name for the effective model, for the nav subtitle and the
/// composer's model chip.
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
/// Read from the catalog entry, never from a display name: capability belongs
/// to an exact artifact on an exact engine, and the same model family can be
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
