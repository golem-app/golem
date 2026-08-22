import 'package:flutter/cupertino.dart';

import '../../../core/theme/golem_theme.dart';
import '../../../core/widgets/labeled_progress.dart';
import '../../../core/widgets/text_measure.dart';
import '../../../l10n/l10n.dart';
import '../artifact_transfer.dart';

/// How much room the surface gives a transfer.
enum TransferDensity {
  /// First run, where the download is the only thing on the screen: the
  /// percentage leads at hero size.
  prominent,

  /// A card inside a list, where a hero percentage per model would shout.
  dense,
}

/// The live block of a transfer: how far along, how fast, how much is left.
///
/// The card *around* it stays per surface — first run draws a bordered
/// container with a name and a format line, Settings a `GolemCard` with
/// metadata rows — and so does the copy. What is shared is everything the
/// projection already decided, laid out the same way at two sizes (#131).
///
/// Mounted for the phases that have a bar — a transfer, a pause, and since
/// #143 a verification, which counts the bytes it has hashed. Completion is
/// not a partial state, and each surface has its own row for it.
class TransferCard extends StatelessWidget {
  const TransferCard({
    required this.transfer,
    required this.density,
    required this.semanticsLabel,
    this.caption,
    this.showBytes = true,
    super.key,
  });

  final ArtifactTransferPresentation transfer;
  final TransferDensity density;

  /// What the bar is, as a screen reader hears it.
  final String semanticsLabel;

  /// The painted caption. Absent at [TransferDensity.prominent], where the
  /// percentage itself is the headline.
  final String? caption;

  /// Whether the `1.00 GB of 4.00 GB` line is painted under the bar. Off where
  /// the surface already states them — the Settings card's status row reads
  /// "Downloading 1.42 GB of 3.30 GB · simulated" one line above this bar, and
  /// a second copy is both noise and, at large text, a wrapped one.
  final bool showBytes;

  @override
  Widget build(BuildContext context) {
    final prominent = density == TransferDensity.prominent;
    final chip = transfer.chip == null
        ? null
        : _PaceChip(
            label: transfer.chip!,
            live: transfer.chipIsLive,
            slot: transfer.chipSlot,
          );
    return LabeledProgress(
      semanticsLabel: semanticsLabel,
      fraction: transfer.fraction,
      percent: transfer.percent,
      caption: prominent ? '${transfer.percent}%' : caption,
      // The hero reserves "100%" so the sign never moves as digits come.
      captionSlot: prominent ? '100%' : null,
      captionStyle: prominent
          ? GolemText.hero.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            )
          : const TextStyle(fontSize: 13),
      trailing: chip,
      captionYields: !prominent,
      // At hero size the caption *is* the percentage; printing it twice on one
      // line would be a typo, not a design.
      showPercent: !prominent,
      // The size, the rate and the time left are the only place a user on the
      // first-run screen can learn them, and they read out there.
      announceDetail: prominent,
      detailLeading: showBytes
          ? context.l10n.downloadAmount(transfer.transferred, transfer.total)
          : null,
      detail: transfer.remainder,
      detailStyle: prominent
          ? GolemText.footnoteStrong
          : const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      trackHeight: prominent ? 10 : 6,
      spacing: prominent ? GolemSpace.s3 : 7,
    );
  }
}

/// The rate or state chip riding the caption line: accent while bytes are
/// moving, quiet once they have stopped.
class _PaceChip extends StatelessWidget {
  const _PaceChip({required this.label, required this.live, this.slot});

  final String label;
  final bool live;

  /// See [ArtifactTransferPresentation.chipSlot].
  final String? slot;

  @override
  Widget build(BuildContext context) {
    final style = GolemText.captionStrong.copyWith(
      // The rate ticks; tabular digits keep every digit one width, and the
      // slot keeps the pill one width when the digit count changes.
      fontFeatures: const [FontFeature.tabularFigures()],
      color: live
          ? CupertinoDynamicColor.resolve(GolemTheme.accentIcon, context)
          : CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          live ? GolemTheme.accentSoft : GolemTheme.fillQuiet,
          context,
        ),
        borderRadius: BorderRadius.circular(GolemRadius.pill),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: slot == null ? 0 : textWidth(context, slot!, style),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: style,
        ),
      ),
    );
  }
}
