import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/app_state.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';

class RecoveryBanner extends ConsumerWidget {
  const RecoveryBanner({required this.failure, super.key});

  final ChatFailure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        child: const Text('New chat'),
      ),
      _ => CupertinoButton(
        key: const Key('retry-generation'),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onPressed: () =>
            ref.read(chatControllerProvider.notifier).retryFailure(),
        child: const Text('Retry'),
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
              const Icon(
                CupertinoIcons.exclamationmark_triangle_fill,
                color: GolemTheme.destructive,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(failure.message, style: GolemText.footnote)),
              ?recovery,
              CupertinoButton(
                key: const Key('discard-generation'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: () =>
                    ref.read(chatControllerProvider.notifier).discardFailure(),
                child: const Text('Discard'),
              ),
            ],
          ),
          if (failure.kind == ChatFailureKind.missingModel &&
              failure.artifactKey != null)
            _DownloadActiveModelButton(artifactKey: failure.artifactKey!),
        ],
      ),
    );
  }
}

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
        onPressed: () {
          ref.read(modelControllerProvider.notifier).download(artifactKey);
          // Progress, pause, and cancel live on the model card.
          context.push('/settings');
        },
        child: Text(
          'Download ${entry.displayName} ($gigabytes GB)',
          style: const TextStyle(color: CupertinoColors.white, fontSize: 14),
        ),
      ),
    );
  }
}
