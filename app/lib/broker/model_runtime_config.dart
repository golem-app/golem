import '../core/domain/model_catalog.dart';
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

/// Resolves a pinned catalog key to everything a load needs. Throws a
/// [StateError] with actionable text for keys that cannot be activated:
/// `custom-*` entries encode no broker profile (their downloads and
/// activation arrive with the custom-repository work), and unknown keys
/// are a caller bug.
ModelRuntimeConfig resolveModelRuntimeConfig(String catalogKey) {
  final entry = modelCatalog.where((item) => item.key == catalogKey).firstOrNull;
  if (entry == null) {
    throw StateError(
      catalogKey.startsWith('custom-')
          ? 'Custom repository models cannot be activated yet: "$catalogKey" '
                'carries no broker profile.'
          : 'Unknown catalog key "$catalogKey".',
    );
  }
  final profileKey = _profileKeyFor(catalogKey, entry.engine);
  final profile = modelProfiles[profileKey];
  if (profile == null) {
    throw StateError(
      'Catalog key "$catalogKey" implies broker profile "$profileKey", '
      'which is not registered.',
    );
  }
  return ModelRuntimeConfig(
    catalogKey: catalogKey,
    engine: brokerEngineFor(entry.engine),
    modelPath: primaryModelPathFor(catalogKey),
    profile: profile,
  );
}

/// Pinned keys follow `<profile>-<engine>`; the engine suffix is stripped
/// against the entry's actual engine rather than guessed from the string.
String _profileKeyFor(String catalogKey, ModelEngine engine) {
  final suffix = switch (engine) {
    ModelEngine.gguf => '-gguf',
    ModelEngine.mlx => '-mlx',
  };
  if (!catalogKey.endsWith(suffix)) {
    throw StateError(
      'Catalog key "$catalogKey" does not follow the <profile>$suffix shape.',
    );
  }
  return catalogKey.substring(0, catalogKey.length - suffix.length);
}
