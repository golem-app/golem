import '../../core/domain/inference_backend.dart';
import '../../core/domain/model_activation.dart';
import '../../core/domain/model_catalog.dart';

/// How the resolved model is phrased on screen. Which model it is belongs to
/// `core/domain/model_activation.dart`; this file only words it.
String chatModelLabel({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  String? modelKey,
  String? residentModelKey,
  Set<String>? loadableKeys,
}) {
  final key = effectiveModelKey(
    backend: backend,
    catalog: catalog,
    modelKey: modelKey,
    residentModelKey: residentModelKey,
    loadableKeys: loadableKeys,
  );
  if (key == null) return sideloadedModelLabel(backend.modelPath!);
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
  Set<String>? loadableKeys,
}) {
  final label = chatModelLabel(
    backend: backend,
    catalog: catalog,
    modelKey: modelKey,
    residentModelKey: residentModelKey,
    loadableKeys: loadableKeys,
  );
  return backend.simulatedInference
      ? '$label · simulated'
      : '$label · on device';
}

/// Whether the model this chat effectively runs accepts images.
///
/// Read from the catalog entry, never a display name: the same family can be
/// image-capable through one engine and text-only through another (#18). A
/// sideload has no entry, so it has no capability proof and stays text-only.
bool chatModelSupportsImages({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  String? modelKey,
  String? residentModelKey,
  Set<String>? loadableKeys,
}) {
  final key = effectiveModelKey(
    backend: backend,
    catalog: catalog,
    modelKey: modelKey,
    residentModelKey: residentModelKey,
    loadableKeys: loadableKeys,
  );
  if (key == null) return false;
  return catalog
          .where((entry) => entry.key == key)
          .firstOrNull
          ?.supportsImages ??
      false;
}
