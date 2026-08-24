/// What resolving a Hugging Face repository can produce (#52). The types live
/// in `core/domain/` so the contract in `core/repositories/contracts.dart` can
/// describe a resolution without importing an implementation, and so the
/// localization layer can word a rejection without importing one either
/// (ADR 0014).
library;

import 'model_profile_spec.dart';
import 'resolved_repository.dart';

/// Why a repository cannot become a model. Presentation maps each stable
/// reason to localized copy; no catch-all "invalid repository" is allowed,
/// because that would tell the user nothing to change.
enum RepositoryRejection {
  malformedIdentifier,
  notFoundOrPrivate,
  gated,
  disabled,
  rateLimited,
  network,
  malformedMetadata,
  unsafePath,
  noWeights,
  shardedWeights,
  unsafeWeightFormat,
  missingRequiredFile,
  inconsistentMetadata,
  unsupportedArchitecture,
  headerTooLarge,
  duplicateEntry,
}

sealed class RepositoryResolution {
  const RepositoryResolution();
}

/// [profile] is null when nothing about the chat template proved a broker
/// profile — normal; the entry still lists and downloads, but cannot activate.
final class RepositoryResolved extends RepositoryResolution {
  const RepositoryResolved({
    required this.resolved,
    required this.profile,
    required this.templateFingerprint,
  });

  final ResolvedRepository resolved;
  final ModelProfileSpec? profile;

  /// The fingerprint that was looked up, present even when it matched nothing —
  /// it is what a future accepted-set addition would have to name.
  final String? templateFingerprint;

  bool get profileResolved => profile != null;
}

/// Several loadable weight files exist; the user picks, this never guesses.
final class RepositoryNeedsWeightChoice extends RepositoryResolution {
  const RepositoryNeedsWeightChoice(this.candidates);

  final List<ResolvedWeightCandidate> candidates;
}

final class ResolvedWeightCandidate {
  const ResolvedWeightCandidate(this.path, this.bytes);

  final String path;
  final int bytes;
}

final class RepositoryRejected extends RepositoryResolution {
  const RepositoryRejected(this.reason, {this.cause});

  final RepositoryRejection reason;

  /// Internal detail for logs — never shown.
  final Object? cause;
}
