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
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: CupertinoDynamicColor.resolve(trackColor, context),
            ),
          ),
          FractionallySizedBox(
            widthFactor: value,
            child: ColoredBox(
              color: CupertinoDynamicColor.resolve(fillColor, context),
            ),
          ),
        ],
      ),
    ),
  );
}
