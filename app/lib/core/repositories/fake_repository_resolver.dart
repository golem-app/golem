/// The deterministic stand-in for [CustomRepositoryResolver], beside the other
/// fakes it keeps company with.
library;

import '../domain/model_catalog.dart';
import '../domain/repository_resolution.dart';
import '../domain/resolved_repository.dart';
import 'contracts.dart';

/// Resolves without a network, deterministically from the repository name.
///
/// Used by qa builds, widget tests, goldens and journeys. It reports no profile,
/// which keeps the fake's custom entries exactly as unresolvable as they have
/// always been — nothing was validated, so claiming a profile would be a lie the
/// real path never tells.
final class DeterministicRepositoryResolver
    implements CustomRepositoryResolver {
  const DeterministicRepositoryResolver();

  @override
  Future<RepositoryResolution> resolve({
    required String repository,
    required ModelEngine engine,
    String ref = 'main',
    String? weightsFile,
    Set<String> existingKeys = const {},
  }) async {
    if (existingKeys.contains(customCatalogKeyFor(repository))) {
      return const RepositoryRejected(RepositoryRejection.duplicateEntry);
    }
    final hash = _fnv64('$repository@$ref');
    final bytes = 1200 * 1000 * 1000 + (hash % (2000 * 1000 * 1000));
    final name = repository.contains('/')
        ? repository.split('/').last
        : repository;
    return RepositoryResolved(
      resolved: ResolvedRepository(
        commitSha: _deterministicSha('$repository@$ref'),
        quantization: 'custom',
        displayName: name,
        files: [
          ModelArtifactFile(
            path: switch (engine) {
              ModelEngine.gguf => '$name.gguf',
              ModelEngine.mlx => 'model.safetensors',
            },
            bytes: bytes,
            role: switch (engine) {
              ModelEngine.gguf => ModelFileRole.weights,
              ModelEngine.mlx => ModelFileRole.snapshot,
            },
          ),
        ],
      ),
      profile: null,
      templateFingerprint: null,
    );
  }

  /// 40 hex characters, so a simulated entry is shaped like a real commit.
  static String _deterministicSha(String seed) {
    final digest = StringBuffer();
    var value = seed;
    while (digest.length < 40) {
      digest.write(_fnv64(value).toRadixString(16).padLeft(16, '0'));
      value = '$value.';
    }
    return digest.toString().substring(0, 40);
  }

  static int _fnv64(String value) {
    var hash = 0xcbf29ce484222325;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash;
  }
}
