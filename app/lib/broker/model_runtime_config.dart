import '../core/domain/model_catalog.dart';
import '../core/repositories/contracts.dart'
    show InferenceException, InferenceFailureKind;
import 'model_catalog.dart';
import 'model_profile.dart';
import 'runtime.dart';

/// Key, engine, path, and profile resolved together so they cannot disagree —
/// `InferenceBackendConfig`'s boot invariant, extended to runtime (#42).
final class ModelRuntimeConfig {
  const ModelRuntimeConfig({
    required this.catalogKey,
    required this.engine,
    required this.modelPath,
    required this.profile,
    this.projectorPath,
    this.supportsImages = false,
  });

  final String catalogKey;
  final BrokerEngine engine;

  /// `documents:`-prefixed for catalog installs, absolute for sideloads; the
  /// repository resolves the prefix, since it knows the documents directory.
  final String modelPath;

  final ModelProfile profile;

  /// Resolved together with [modelPath] so the pair cannot disagree.
  final String? projectorPath;

  /// Whether this exact artifact on this exact engine accepts images. The
  /// catalog entry decides; the profile only says how an image is expressed.
  final bool supportsImages;
}

BrokerEngine brokerEngineFor(ModelEngine engine) => switch (engine) {
  ModelEngine.gguf => BrokerEngine.llamaCpp,
  ModelEngine.mlx => BrokerEngine.mlx,
};

/// The profile comes from the entry's declared [ModelCatalogEntry.profileKey]
/// through a [ProfileRegistry] — never from slicing the key — which lets a
/// custom repository activate through the same path as a pinned model (#43).
/// Every refusal is a typed [InferenceException] the chat surface maps to
/// actionable copy (handbook v4.2A §5.2, §8.1), all before any load.
ModelRuntimeConfig resolveModelRuntimeConfig(
  String catalogKey, {
  List<ModelCatalogEntry>? catalog,
  ProfileRegistry? profiles,
}) {
  final entries = catalog ?? modelCatalog;
  final registry = profiles ?? ProfileRegistry.builtIn;
  final entry = entries.where((item) => item.key == catalogKey).firstOrNull;
  if (entry == null) {
    // Reachable in normal use: a conversation persists its modelKey and a later
    // build may no longer carry that entry. The message is user-facing copy
    // (handbook v4.2A §5.3), so the internal key rides on `cause`.
    throw InferenceException(
      InferenceFailureKind.engine,
      "This chat's model is not available in this version of Golem. "
      'Choose another model to continue.',
      cause: StateError('Unknown catalog key "$catalogKey".'),
    );
  }

  final profile = registry[entry.profileKey];
  if (profile == null) {
    throw InferenceException(
      InferenceFailureKind.engine,
      entry.profileKey == unresolvedProfileKey
          ? 'This model has not been checked against a supported chat '
                'template yet, so it cannot be loaded. Add it again to '
                'resolve it.'
          : 'This model declares the chat template "${entry.profileKey}", '
                'which this build does not support. Remove it and add a '
                'supported model.',
    );
  }

  final modelPath = modelPathForEntry(entry);
  if (modelPath == null) {
    throw InferenceException(
      InferenceFailureKind.engine,
      'This model does not name exactly one weights file, so it cannot be '
      'loaded. Remove it and add a supported model.',
    );
  }

  return ModelRuntimeConfig(
    catalogKey: catalogKey,
    engine: brokerEngineFor(entry.engine),
    modelPath: modelPath,
    profile: profile,
    projectorPath: projectorPathForEntry(entry),
    // Artifact capability and template expressiveness must both hold.
    supportsImages: entry.supportsImages && profile.spec.supportsImages,
  );
}
