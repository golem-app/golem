import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show clampDouble;

/// Rounded determinate progress track shared by the splash and settings
/// download rows.
///
/// [value] is a fraction, 0 to 1. Anything outside that range is bounded here,
/// so no caller clamps.
class ProgressTrack extends StatelessWidget {
  const ProgressTrack({
    required this.value,
    required this.trackColor,
    required this.fillColor,
    this.height = 6,
    super.key,
  });
  final double value;
  final Color trackColor;
  final Color fillColor;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height / 2),
    child: SizedBox(
      // The groove spans whatever it is given. Without an explicit width the
      // track shrink-wraps the fill, so in a centre-aligned parent — the
      // splash, the setup banner — the *whole bar* was value-wide and centred,
      // growing outward from the middle in both directions as it progressed.
      width: double.infinity,
      height: height,
      child: Stack(
        // Stack's own default, restated because this is the placement that
        // decides where the fill sits: under the default loose fit the
        // FractionallySizedBox shrink-wraps its child, so the alignment written
        // on *that* box never applied at all — it read as the guarantee for
        // years and was not one (#120). Nothing about the layout changed when
        // it moved here; what changed is that the line you can break is now the
        // line that matters, and progress_track_test.dart breaks it.
        alignment: AlignmentDirectional.topStart,
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: CupertinoDynamicColor.resolve(trackColor, context),
            ),
          ),
          // heightFactor is not optional: without it the fill's ColoredBox has
          // no child to size to, collapses to zero height, and the track paints
          // empty at every value.
          // clampDouble, not num.clamp: NaN lands on the full bar instead of
          // passing through to FractionallySizedBox's assert.
          FractionallySizedBox(
            widthFactor: clampDouble(value, 0, 1),
            heightFactor: 1,
            child: ColoredBox(
              color: CupertinoDynamicColor.resolve(fillColor, context),
            ),
          ),
        ],
      ),
    ),
  );
}
