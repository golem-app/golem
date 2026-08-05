import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';

class RecoveryBanner extends ConsumerWidget {
  const RecoveryBanner({
    required this.message,
    this.missingModelArtifactKey,
    super.key,
  });

  final String message;

  /// When set, the failure is the missing-model condition and the banner
  /// offers the download itself. Multi-gigabyte downloads start only from
  /// this explicit tap, never silently.
  final String? missingModelArtifactKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    key: const Key('recovery-banner'),
    margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(GolemTheme.errorSurface, context),
      borderRadius: BorderRadius.circular(18),
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
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 13)),
            ),
            CupertinoButton(
              key: const Key('retry-generation'),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () =>
                  ref.read(chatControllerProvider.notifier).retryFailure(),
              child: const Text('Retry'),
            ),
            CupertinoButton(
              key: const Key('discard-generation'),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () =>
                  ref.read(chatControllerProvider.notifier).discardFailure(),
              child: const Text('Discard'),
            ),
          ],
        ),
        if (missingModelArtifactKey != null)
          _DownloadActiveModelButton(artifactKey: missingModelArtifactKey!),
      ],
    ),
  );
}

class _DownloadActiveModelButton extends ConsumerWidget {
  const _DownloadActiveModelButton({required this.artifactKey});

  final String artifactKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref
        .watch(modelCatalogEntriesProvider)
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
