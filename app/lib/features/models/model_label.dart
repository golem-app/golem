import '../../core/domain/inference_backend.dart';
import '../../core/domain/model_activation.dart';
import '../../core/domain/model_catalog.dart';

/// How a resolved model is phrased on screen. *Which* model it is belongs to
/// `activeModelKeyProvider` for anything scoped to the open conversation, and
/// to `bootModelKey` for the surfaces scoped to the build's own profile; this
/// file only words the answer (#129).
String modelDisplayLabel({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  required String? activeKey,
}) {
  if (activeKey == null) return sideloadedModelLabel(backend.modelPath!);
  return catalog
          .where((entry) => entry.key == activeKey)
          .firstOrNull
          ?.displayName ??
      activeKey;
}

/// The nav bar's second line. Honesty is non-negotiable: simulated
/// builds say so, only a real engine claims "on device", and a device outside
/// every supported tier (#27) names no model at all — nothing will ever be
/// resident there, so naming one would be the loudest lie on the screen.
String modelSubtitle({
  required InferenceBackendConfig backend,
  required List<ModelCatalogEntry> catalog,
  required String? activeKey,
  bool runsModels = true,
  String unsupportedLabel = 'Unsupported device',
  String simulatedLabel = 'simulated',
  String onDeviceLabel = 'on device',
}) {
  if (!backend.simulatedInference && !runsModels) {
    return unsupportedLabel;
  }
  final label = modelDisplayLabel(
    backend: backend,
    catalog: catalog,
    activeKey: activeKey,
  );
  return backend.simulatedInference
      ? '$label · $simulatedLabel'
      : '$label · $onDeviceLabel';
}

/// Whether the model this chat effectively runs accepts images.
///
/// Read from the catalog entry, never a display name: the same family can be
/// image-capable through one engine and text-only through another (#18). A
/// sideload has no entry, so it has no capability proof and stays text-only.
bool modelSupportsImages({
  required List<ModelCatalogEntry> catalog,
  required String? activeKey,
}) {
  if (activeKey == null) return false;
  return catalog
          .where((entry) => entry.key == activeKey)
          .firstOrNull
          ?.supportsImages ??
      false;
}
