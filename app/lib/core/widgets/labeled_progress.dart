import 'package:flutter/cupertino.dart';

import '../../l10n/l10n.dart';
import '../theme/golem_theme.dart';
import 'progress_track.dart';
import 'text_measure.dart';

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
    this.captionSlot,
    this.captionYields = true,
    this.showPercent = true,
    this.announcePercent = true,
    this.announceDetail = false,
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

  /// A value at least as wide as any [caption] this bar will paint, reserved
  /// and right-aligned so the caption's last glyph — the "%" of a hero
  /// percentage — never moves as the digits before it come and go.
  final String? captionSlot;

  /// Which of the caption and [trailing] gives way on a short line. A row
  /// inside a list wraps its caption and keeps the chip whole; a card led by a
  /// hero percentage keeps that on one line — split one glyph per line, "25%"
  /// was three lines tall and moved the whole first-run screen (#143) — and
  /// lets the chip trim itself instead.
  final bool captionYields;

  /// Whether the percentage is painted. Off where the caption already carries
  /// it, or where the surface has no room for it.
  final bool showPercent;

  /// Whether the percentage is *announced*. Deliberately separate from
  /// [showPercent], because the chat setup banner paints no number and is the
  /// only thing carrying how far along the transfer is.
  final bool announcePercent;

  /// Whether the figures under the bar read as their own nodes.
  ///
  /// A row inside a list keeps them silent: split across three nodes, the
  /// caption and the number announce as unrelated fragments. A card that is
  /// the whole screen does the opposite — the size, the rate and the time left
  /// are the only place a user can learn them, and first run has always read
  /// them out.
  final bool announceDetail;

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
    final captionWidget = caption == null
        ? const SizedBox.shrink()
        : ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: captionSlot == null
                  ? 0
                  : textWidth(context, captionSlot!, captionText),
            ),
            child: Text(
              caption!,
              style: captionText,
              maxLines: captionYields ? null : 1,
              softWrap: captionYields,
              textAlign: captionSlot == null ? null : TextAlign.end,
            ),
          );
    final bar = ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasHeader) ...[
            Row(
              children: [
                if (captionYields) ...[
                  Expanded(child: captionWidget),
                  ?trailing,
                ] else ...[
                  captionWidget,
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: trailing ?? const SizedBox.shrink(),
                    ),
                  ),
                ],
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
        ],
      ),
    );

    Widget? figures;
    if (detail != null || detailLeading != null) {
      // One line each, tabular digits, and an ellipsis rather than a wrap:
      // the figures tick every second, and a wrap is a height change that
      // moved the whole first-run screen under the reader (#143). Each
      // figure's flex is the width it needs, so both stay whole whenever the
      // row has room for both and trim in proportion when it does not —
      // split half and half, Android's wider face cut "About 2 minutes
      // left" short while the row still had room. No LayoutBuilder: the
      // first-run body sits under an IntrinsicHeight, which cannot ask one
      // for a height.
      const tabular = [FontFeature.tabularFigures()];
      final leadingStyle = GolemText.footnote.copyWith(
        fontFeatures: tabular,
        color: CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context),
      );
      final detailTextStyle = (detailStyle ?? GolemText.captionStrong).copyWith(
        fontFeatures: tabular,
      );
      int needs(String text, TextStyle style) {
        final width = textWidth(context, text, style).ceil();
        return width < 1 ? 1 : width;
      }

      figures = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (detailLeading case final leading?)
            Flexible(
              flex: needs(leading, leadingStyle),
              child: Text(
                leading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: leadingStyle,
              ),
            )
          else
            const Expanded(child: SizedBox.shrink()),
          if (detail case final detail?)
            Flexible(
              // The gap is part of what this child needs, or the figure is
              // short by exactly that much on the widths where it just fits.
              flex: needs(detail, detailTextStyle) + 8,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: detailTextStyle,
                ),
              ),
            ),
        ],
      );
      if (!announceDetail) figures = ExcludeSemantics(child: figures);
    }

    // explicitChildNodes: the figures under the bar keep their own readings
    // where a surface wants them; without it this container would swallow
    // their labels into its own and announce one run-on string.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticsLabel,
      value: announcePercent ? context.l10n.percentValue(percent) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar,
          if (figures case final figures?) ...[
            SizedBox(height: spacing),
            figures,
          ],
        ],
      ),
    );
  }
}
