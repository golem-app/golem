import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/app_state.dart';
import '../../../core/domain/models.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../l10n/bidi.dart';
import '../../../l10n/l10n.dart';
import '../../models/application/model_providers.dart';
import '../../onboarding/model_download_consent.dart';
import '../application/chat_providers.dart';
import 'model_picker_sheet.dart';

class RecoveryBanner extends ConsumerWidget {
  const RecoveryBanner({required this.failure, super.key});

  final ChatFailure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(
      chatControllerProvider.select((value) => value.value?.activeId),
    );
    // Retry re-runs the identical request, so it is only offered where
    // that can succeed. A conversation that no longer fits the context
    // window gets a new chat instead — the one recovery that works — and a
    // device outside every supported tier gets neither: no action taken here
    // changes what this hardware can run, so offering one would be a lie.
    final recovery = switch (failure.kind) {
      ChatFailureKind.unsupportedDevice => null,
      ChatFailureKind.contextExhausted => CupertinoButton(
        key: const Key('start-new-chat'),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onPressed: () => ref
            .read(chatControllerProvider.notifier)
            .startFreshChatFromFailure(),
        child: Text(context.l10n.newChat),
      ),
      ChatFailureKind.modelUnavailable ||
      ChatFailureKind.unsupportedModel ||
      ChatFailureKind.invalidModelArtifact when activeId != null =>
        CupertinoButton(
          key: const Key('choose-recovery-model'),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onPressed: () =>
              showModelPickerSheet(context, conversationId: activeId),
          child: Text(context.l10n.chooseDifferentModel),
        ),
      ChatFailureKind.attachmentUnavailable ||
      ChatFailureKind.unsupportedImages => CupertinoButton(
        key: const Key('remove-failed-turn'),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onPressed: () =>
            ref.read(chatControllerProvider.notifier).removeFailedTurn(),
        child: Text(context.l10n.deleteMessage),
      ),
      _ => CupertinoButton(
        key: const Key('retry-generation'),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onPressed: () =>
            ref.read(chatControllerProvider.notifier).retryFailure(),
        child: Text(context.l10n.retry),
      ),
    };
    return Container(
      key: const Key('recovery-banner'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(GolemTheme.errorSurface, context),
        borderRadius: BorderRadius.circular(GolemRadius.notice),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const ExcludeSemantics(
                child: Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  color: GolemTheme.destructive,
                ),
              ),
              const SizedBox(width: 10),
              // A turn that failed is the one thing a screen-reader user must
              // be told without going looking for it.
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _failureMessage(context, ref, failure),
                    style: GolemText.footnote,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ?recovery,
                CupertinoButton(
                  key: const Key('discard-generation'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: () => ref
                      .read(chatControllerProvider.notifier)
                      .discardFailure(),
                  child: Text(context.l10n.discard),
                ),
              ],
            ),
          ),
          if (failure.kind == ChatFailureKind.missingModel &&
              failure.artifactKey != null)
            _DownloadActiveModelButton(artifactKey: failure.artifactKey!),
        ],
      ),
    );
  }
}

String _failureMessage(
  BuildContext context,
  WidgetRef ref,
  ChatFailure failure,
) => switch (failure.kind) {
  ChatFailureKind.generic => context.l10n.generationFailed,
  ChatFailureKind.attachmentSave => context.l10n.attachmentSaveFailed,
  ChatFailureKind.attachmentUnavailable =>
    context.l10n.attachmentUnavailableFailure,
  ChatFailureKind.modelUnavailable => context.l10n.modelUnavailableFailure,
  ChatFailureKind.unsupportedModel => context.l10n.unsupportedModelFailure,
  ChatFailureKind.unsupportedImages => context.l10n.unsupportedImagesFailure,
  ChatFailureKind.invalidModelArtifact =>
    context.l10n.invalidModelArtifactFailure,
  ChatFailureKind.budgetExhaustedBeforeAnswer => context.l10n.budgetExhausted,
  ChatFailureKind.contextExhausted => context.l10n.contextExhausted,
  ChatFailureKind.outOfMemory =>
    failure.contextTokens == null
        ? context.l10n.outOfMemory
        : context.l10n.outOfMemoryAtContext(failure.contextTokens!),
  ChatFailureKind.insufficientMemory => context.l10n.insufficientMemory,
  ChatFailureKind.unsupportedDevice => context.l10n.modelsUnavailableGeneric,
  ChatFailureKind.missingModel => context.l10n.modelMissingForChat(
    ref
            .watch(effectiveModelCatalogProvider)
            .where((entry) => entry.key == failure.artifactKey)
            .firstOrNull
            ?.displayName ??
        context.l10n.model,
  ),
};

class _DownloadActiveModelButton extends ConsumerWidget {
  const _DownloadActiveModelButton({required this.artifactKey});

  final String artifactKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref
        .watch(effectiveModelCatalogProvider)
        .where((item) => item.key == artifactKey)
        .firstOrNull;
    final installed =
        ref.watch(modelControllerProvider).value?.statusOf(artifactKey).phase ==
        ArtifactPhase.installed;
    // Once the download finished the honest affordance is Retry above.
    if (entry == null || installed) return const SizedBox.shrink();
    final gigabytes = (entry.totalBytes / (1000 * 1000 * 1000)).toStringAsFixed(
      1,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: CupertinoButton(
        key: const Key('download-active-model'),
        color: GolemTheme.accent,
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        onPressed: () async {
          final status = ref
              .read(modelControllerProvider)
              .value
              ?.statusOf(artifactKey);
          if (status?.phase == ArtifactPhase.notDownloaded) {
            final approved = await confirmModelDownload(
              context: context,
              entry: entry,
              simulated:
                  ref.read(modelControllerProvider).value?.simulated ?? false,
            );
            if (!approved || !context.mounted) return;
          }
          ref.read(modelControllerProvider.notifier).download(artifactKey);
          // Progress, pause, and cancel live on the model card.
          context.push('/settings/models');
        },
        child: Text(
          context.l10n.downloadNamedModel(
            ltrIsolate(entry.displayName),
            ltrIsolate('$gigabytes GB'),
          ),
          style: const TextStyle(color: CupertinoColors.white, fontSize: 14),
        ),
      ),
    );
  }
}
