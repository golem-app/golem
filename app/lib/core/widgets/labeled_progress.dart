import 'package:flutter/cupertino.dart';

import '../../l10n/l10n.dart';
import '../theme/golem_theme.dart';
import 'progress_track.dart';

/// A determinate bar that reads as one thing.
///
/// Split across three nodes — a caption, a number, an unlabelled groove — a
/// transfer announced as unrelated fragments, and two of the four surfaces
/// showing one announced nothing at all. The whole widget is a single
/// semantics container carrying the caption and the percentage, with its
/// children excluded, and deliberately not a live region: re-announcing every
/// tick of a multi-gigabyte download would talk over the rest of the screen.
///
/// [captionStyle] and [detailStyle] are parameters because the same bar is a
/// muted caption inside a picker row and body-ink inside a settings card; the
/// layout, the spacing and the reading are what is shared.
class LabeledProgress extends StatelessWidget {
  const LabeledProgress({
    required this.semanticsLabel,
    required this.fraction,
    required this.percent,
    this.caption,
    this.captionStyle,
    this.trailing,
    this.showPercent = true,
    this.detail,
    this.detailStyle,
    this.detailLeading,
    this.trackHeight = 6,
    this.spacing = 7,
    super.key,
  });

  /// What the bar is for, as a screen reader hears it. Present even where no
  /// caption is painted.
  final String semanticsLabel;

  final double fraction;
  final int percent;

  /// The painted caption, or null for a bar that stands under copy which
  /// already says what it is.
  final String? caption;
  final TextStyle? captionStyle;

  /// A chip or badge riding the caption line, right of the caption and left of
  /// the percentage.
  final Widget? trailing;

  /// Whether the percentage is painted. Off where the phase makes it
  /// meaningless — a verification is not 40% verified.
  final bool showPercent;

  /// The time or amount left, under the bar and right-aligned. Inside the same
  /// excluded subtree: the reading stays caption plus percentage.
  final String? detail;
  final TextStyle? detailStyle;

  /// The left half of the line under the bar — the byte count a prominent card
  /// quotes beside its time left. Null where that line carries one figure.
  final String? detailLeading;

  final double trackHeight;

  /// The gap above and below the bar. Wider on a card that leads with the
  /// percentage than on a row inside a list.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final captionText = captionStyle ?? GolemText.caption;
    final hasHeader = caption != null || trailing != null || showPercent;
    return Semantics(
      container: true,
      label: semanticsLabel,
      value: context.l10n.percentValue(percent),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasHeader) ...[
              Row(
                children: [
                  Expanded(
                    child: caption == null
                        ? const SizedBox.shrink()
                        : Text(caption!, style: captionText),
                  ),
                  ?trailing,
                  if (showPercent) Text('$percent%', style: captionText),
                ],
              ),
              SizedBox(height: spacing),
            ],
            ProgressTrack(
              value: fraction,
              trackColor: GolemTheme.divider,
              fillColor: GolemTheme.accent,
              height: trackHeight,
            ),
            if (detail != null || detailLeading != null) ...[
              SizedBox(height: spacing),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: detailLeading == null
                        ? const SizedBox.shrink()
                        : Text(
                            detailLeading!,
                            style: GolemText.footnote.copyWith(
                              color: CupertinoDynamicColor.resolve(
                                GolemTheme.mutedInk,
                                context,
                              ),
                            ),
                          ),
                  ),
                  if (detail case final detail?)
                    Text(detail, style: detailStyle ?? GolemText.captionStrong),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
