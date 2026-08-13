import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/download_pace.dart';
import '../../../core/domain/model_catalog.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../l10n/bidi.dart';
import '../../../l10n/l10n.dart';
import '../application/download_note_providers.dart';
import '../application/model_providers.dart';

/// The foreground-speed note from the #36 evidence: while [entry] is actively
/// downloading, tell the user that keeping Golem open keeps the transfer at
/// link speed, with the platform's measured background pacing and the
/// concrete time cost of leaving. Renders nothing outside the `downloading`
/// phase or after a dismissal, so surfaces embed it unconditionally; all
/// surfaces share one dismissal state through [downloadNoteVisibleProvider].
class DownloadNoteBanner extends ConsumerWidget {
  const DownloadNoteBanner({
    required this.entry,
    this.compact = false,
    super.key,
  });

  final ModelCatalogEntry entry;

  /// Tighter paddings and caption type for the chat setup banner.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(downloadNoteVisibleProvider(entry.key))) {
      return const SizedBox.shrink();
    }
    final downloaded = ref.watch(
      modelControllerProvider.select(
        (value) => value.value?.statusOf(entry.key).downloadedBytes ?? 0,
      ),
    );
    final remaining = entry.totalBytes <= downloaded
        ? 0
        : entry.totalBytes - downloaded;
    final platform = defaultTargetPlatform == TargetPlatform.android
        ? 'Android'
        : 'iOS';
    final backgroundMbs = backgroundMbsFor(defaultTargetPlatform);
    final l10n = context.l10n;
    final body = l10n.downloadNoteBody(
      platform,
      ltrIsolate(l10n.rateMbs(backgroundMbs.toStringAsFixed(1))),
      l10n.aboutMinutes(aboutMinutes(backgroundMbs, remaining)),
      l10n.aboutMinutes(aboutMinutes(downloadForegroundMbs, remaining)),
    );
    return Container(
      padding: EdgeInsetsDirectional.fromSTEB(
        compact ? 10 : 14,
        compact ? 8 : 12,
        4,
        compact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          GolemTheme.cautionSurface,
          context,
        ),
        borderRadius: BorderRadius.circular(GolemRadius.notice),
        border: Border.all(
          color: CupertinoDynamicColor.resolve(
            GolemTheme.cautionBorder,
            context,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(top: compact ? 1 : 2),
            child: Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              size: compact ? 16 : 20,
              color: CupertinoDynamicColor.resolve(
                GolemTheme.cautionIcon,
                context,
              ),
            ),
          ),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.downloadNoteTitle,
                    style: compact
                        ? GolemText.captionStrong
                        : GolemText.footnoteStrong,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: (compact ? GolemText.caption : GolemText.footnote)
                        .copyWith(
                          color: CupertinoDynamicColor.resolve(
                            GolemTheme.mutedInk,
                            context,
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
          MergeSemantics(
            child: Semantics(
              button: true,
              label: l10n.dismissNote,
              child: CupertinoButton(
                key: const Key('download-note-dismiss'),
                padding: EdgeInsets.zero,
                minimumSize: const Size(
                  GolemSize.hitTarget,
                  GolemSize.hitTarget,
                ),
                onPressed: () => ref
                    .read(downloadNoteDismissalProvider.notifier)
                    .dismiss(entry.key),
                child: ExcludeSemantics(
                  child: Icon(
                    CupertinoIcons.xmark,
                    size: 16,
                    color: CupertinoDynamicColor.resolve(
                      GolemTheme.mutedInk,
                      context,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
