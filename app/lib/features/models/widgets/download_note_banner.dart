import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/chrome/golem_icon_button.dart';
import '../../../core/domain/download_pace.dart';
import '../../../core/domain/model_catalog.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../l10n/bidi.dart';
import '../../../l10n/l10n.dart';
import '../application/download_note_providers.dart';

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
    this.margin,
    super.key,
  });

  final ModelCatalogEntry entry;

  /// Tighter paddings and caption type for the chat setup banner.
  final bool compact;

  /// Applied only while visible, so hidden notes leave no stray spacing in
  /// the surfaces that embed the banner unconditionally.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(downloadNoteVisibleProvider(entry.key))) {
      return const SizedBox.shrink();
    }
    // The advice quotes measured pacing, so it exists only on the two
    // platforms the #36 spike measured. One switch owns the label/rate pair;
    // splitting them once let macOS claim iOS's figure.
    final (platform, backgroundMbs) = switch (defaultTargetPlatform) {
      TargetPlatform.android => ('Android', androidBackgroundMbs),
      TargetPlatform.iOS => ('iOS', iosBackgroundMbs),
      _ => (null, 0.0),
    };
    if (platform == null) return const SizedBox.shrink();
    // Frozen at attempt start: the comparison keeps one pair of figures for
    // the whole attempt instead of counting down under the reader.
    final downloaded = ref.watch(
      downloadNoteFiguresProvider.select((figures) => figures[entry.key] ?? 0),
    );
    final remaining = entry.totalBytes <= downloaded
        ? 0
        : entry.totalBytes - downloaded;
    final backgroundMinutes = aboutMinutes(backgroundMbs, remaining);
    final foregroundMinutes = aboutMinutes(downloadForegroundMbs, remaining);
    // Near the end both figures floor to the same minute count and the
    // comparison would read "about 1 minute instead of about 1 minute" —
    // there is no longer a trade-off worth interrupting for.
    if (backgroundMinutes <= foregroundMinutes) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final body = l10n.downloadNoteBody(
      platform,
      ltrIsolate(l10n.rateMbs(backgroundMbs.toStringAsFixed(1))),
      l10n.aboutMinutes(backgroundMinutes),
      l10n.aboutMinutes(foregroundMinutes),
    );
    return Container(
      margin: margin,
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
              // No semanticLabel on the glyph: the Semantics above already
              // names the control, and a second label would read twice.
              child: GolemIconButton(
                key: const Key('download-note-dismiss'),
                icon: CupertinoIcons.xmark,
                size: 16,
                color: CupertinoDynamicColor.resolve(
                  GolemTheme.mutedInk,
                  context,
                ),
                onPressed: () => ref
                    .read(downloadNoteDismissalProvider.notifier)
                    .dismiss(entry.key),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
