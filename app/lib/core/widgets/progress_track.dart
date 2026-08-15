import 'package:flutter/cupertino.dart';

/// Rounded determinate progress track shared by the splash and settings
/// download rows.
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
        // What holds the fill against the leading edge. Under the stack's
        // default loose fit the FractionallySizedBox shrink-wraps its child, so
        // its own alignment never applies and this is the only placement that
        // decides anything — it was written on the inner box for a long time,
        // where it did nothing at all (#120). Directional so a right-to-left
        // locale grows the bar from the right.
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
          FractionallySizedBox(
            widthFactor: value,
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
