import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/app_preferences.dart';
import '../../../core/domain/model_catalog.dart';
import '../../../core/domain/repository_resolution.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';
import '../../preferences/application/preferences_providers.dart';
import 'custom_repository_workflow.dart';

part 'custom_repository_controller.g.dart';

/// What the Add flow has learned about the repository currently in the field.
sealed class AddRepositoryOutcome {
  const AddRepositoryOutcome();
}

final class AddIdle extends AddRepositoryOutcome {
  const AddIdle();
}

final class AddResolving extends AddRepositoryOutcome {
  const AddResolving();
}

final class AddResolved extends AddRepositoryOutcome {
  const AddResolved(this.resolution);

  final RepositoryResolved resolution;
}

/// Several loadable weight files exist; the user picks, this never guesses.
final class AddNeedsWeights extends AddRepositoryOutcome {
  const AddNeedsWeights(this.candidates);

  final List<ResolvedWeightCandidate> candidates;
}

final class AddRefused extends AddRepositoryOutcome {
  const AddRefused(this.reason);

  final RepositoryRejection reason;
}

/// The whole Add draft: what was typed, which engine it names, and what
/// resolving it found.
final class CustomRepositoryDraft {
  const CustomRepositoryDraft({
    this.repository = '',
    this.revision = '',
    this.engine = ModelEngine.mlx,
    this.outcome = const AddIdle(),
  });

  final String repository;
  final String revision;
  final ModelEngine engine;
  final AddRepositoryOutcome outcome;

  /// Empty means the default branch, which is what the placeholder says.
  String get ref => revision.trim().isEmpty ? 'main' : revision.trim();

  CustomRepositoryDraft copyWith({
    String? repository,
    String? revision,
    ModelEngine? engine,
    AddRepositoryOutcome? outcome,
  }) => CustomRepositoryDraft(
    repository: repository ?? this.repository,
    revision: revision ?? this.revision,
    engine: engine ?? this.engine,
    outcome: outcome ?? this.outcome,
  );
}

/// The Advanced-mode add-a-repository flow (#129). It was a `sealed` state
/// machine owned by `_ModelsScreenState`, driven through `setState` callbacks
/// threaded down into the card.
///
/// KeepAlive: `ListView(children:)` disposes off-screen elements, so an
/// autoDispose provider would drop a resolution the moment the card scrolled
/// out — which is exactly why the state used to live on the screen. Holding
/// the typed text here as well is what the move buys: the draft and the fields
/// now leave and re-enter the screen together, where before the resolution card
/// could come back over two empty fields.
@Riverpod(keepAlive: true, retry: noRetry)
class CustomRepositoryController extends _$CustomRepositoryController {
  @override
  CustomRepositoryDraft build() => const CustomRepositoryDraft();

  /// Any edit makes an existing resolution stale, and showing a commit and
  /// file list for a repository the user has since retyped is worse than
  /// nothing.
  void edit({String? repository, String? revision}) {
    state = state.copyWith(
      repository: repository,
      revision: revision,
      outcome: state.outcome is AddIdle ? null : const AddIdle(),
    );
  }

  /// A resolution belongs to one engine's file selection, so switching engines
  /// drops it.
  void selectEngine(ModelEngine engine) {
    if (engine == state.engine) return;
    state = state.copyWith(engine: engine, outcome: const AddIdle());
  }

  /// [weightsFile] answers an [AddNeedsWeights]; the first pass never guesses.
  Future<void> resolve({String? weightsFile}) async {
    final repository = state.repository.trim();
    if (repository.isEmpty) return;
    // Every seam read before the first await; the workflow owns the collision
    // derivation and the resolver's failure contract.
    final workflow = CustomRepositoryWorkflow(
      resolver: ref.read(customRepositoryResolverProvider),
    );
    final pinned = ref.read(modelCatalogEntriesProvider);
    final custom =
        ref.read(preferencesControllerProvider).value?.customModels ??
        const <CustomModelSpec>[];
    final engine = state.engine;
    final ref_ = state.ref;
    state = state.copyWith(outcome: const AddResolving());
    final outcome = await workflow.resolve(
      repository: repository,
      engine: engine,
      ref: ref_,
      weightsFile: weightsFile,
      pinned: pinned,
      custom: custom,
    );
    // The user may have retyped or switched engines while the Hub was read;
    // that edit already published AddIdle, and this answer describes what they
    // no longer have on screen.
    if (state.repository.trim() != repository || state.engine != engine) return;
    state = state.copyWith(
      outcome: switch (outcome) {
        RepositoryResolved() => AddResolved(outcome),
        RepositoryNeedsWeightChoice(:final candidates) => AddNeedsWeights(
          candidates,
        ),
        RepositoryRejected(:final reason) => AddRefused(reason),
      },
    );
  }

  /// Commits the resolution on screen. False means the preference write failed
  /// and rolled back — the card stays up, so Add remains the retry affordance.
  Future<bool> add() async {
    final outcome = state.outcome;
    if (outcome is! AddResolved) return false;
    final added = await ref
        .read(preferencesControllerProvider.notifier)
        .addCustomModel(
          CustomModelSpec(
            repository: state.repository.trim(),
            engine: state.engine,
            revision: state.ref,
            profile: outcome.resolution.profile,
            resolved: outcome.resolution.resolved,
          ),
        );
    if (added) state = const CustomRepositoryDraft();
    return added;
  }
}
