import '../core/domain/model_catalog.dart';
import '../core/repositories/contracts.dart'
    show InferenceException, InferenceFailureKind;
import 'model_catalog.dart';
import 'model_profile.dart';
import 'runtime.dart';

/// One catalog configuration resolved for the engine: the key, engine,
/// model path, and broker profile derived together so they can never
/// disagree — the same invariant `InferenceBackendConfig` states for the
/// boot-resolved value, extended to runtime activation (#42).
final class ModelRuntimeConfig {
  const ModelRuntimeConfig({
    required this.catalogKey,
    required this.engine,
    required this.modelPath,
    required this.profile,
  });

  final String catalogKey;
  final BrokerEngine engine;

  /// `documents:`-prefixed for catalog installs; absolute for operator
  /// sideloads. Prefix resolution stays with the repository, which knows
  /// the documents directory.
  final String modelPath;

  final ModelProfile profile;
}

/// The broker engine that loads artifacts of a catalog engine family.
BrokerEngine brokerEngineFor(ModelEngine engine) => switch (engine) {
  ModelEngine.gguf => BrokerEngine.llamaCpp,
  ModelEngine.mlx => BrokerEngine.mlx,
};

/// Resolves a catalog key to everything a load needs.
///
/// The profile comes from the entry's declared [ModelCatalogEntry.profileKey]
/// and a [ProfileRegistry] lookup — never from slicing the key. That is what
/// lets a resolved custom repository carrying a supported profile spec
/// activate through exactly the same path as a pinned model (#43).
///
/// Every refusal is an [InferenceException] rather than a raw error, so the
/// chat surface can map it to actionable copy the way it already maps engine
/// failures (handbook v4.2A §5.2, §8.1). All of them happen *before* any
/// multi-gigabyte load is attempted.
ModelRuntimeConfig resolveModelRuntimeConfig(
  String catalogKey, {
  List<ModelCatalogEntry>? catalog,
  ProfileRegistry? profiles,
}) {
  final entries = catalog ?? modelCatalog;
  final registry = profiles ?? ProfileRegistry.builtIn;
  final entry = entries.where((item) => item.key == catalogKey).firstOrNull;
  if (entry == null) {
    // InferenceException.message is user-presentable copy (handbook v4.2A
    // §5.3), and this is reachable in normal use — a conversation persists its
    // modelKey, and a later build may no longer carry that entry. The internal
    // key stays on `cause` for diagnostics instead of in the banner.
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
  );
}
