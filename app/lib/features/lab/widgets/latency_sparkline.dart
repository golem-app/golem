import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show listEquals, setEquals;

import '../../../core/theme/golem_theme.dart';
import '../domain/latency_series.dart';
import '../lab_theme.dart';

/// The gaps between consecutive arrivals as bars, stalls in the caution hue.
/// Draws the newest [maxBars] gaps so a long run never widens the card, and
/// says nothing about throughput — a gap is a gap whether it separates two
/// tokens or two chunks; the label beside it names which.
class LatencySparkline extends StatelessWidget {
  const LatencySparkline({
    required this.series,
    required this.semanticLabel,
    this.maxBars = 60,
    this.height = 18,
    super.key,
  });

  final LatencySeries series;
  final String semanticLabel;
  final int maxBars;
  final double height;

  @override
  Widget build(BuildContext context) {
    final gaps = series.gapsMs.length > maxBars
        ? series.gapsMs.sublist(series.gapsMs.length - maxBars)
        : series.gapsMs;
    final offset = series.gapsMs.length - gaps.length;
    return Semantics(
      label: semanticLabel,
      child: CustomPaint(
        key: const Key('lab-sparkline'),
        size: Size(gaps.length * _pitch, height),
        painter: _SparklinePainter(
          gaps: gaps,
          stalls: {
            for (final index in series.stallIndexes)
              if (index >= offset) index - offset,
          },
          accent: context.accent,
          stall: labResolve(GolemTheme.cautionIcon, context),
        ),
      ),
    );
  }

  static const _pitch = 4.6;
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.gaps,
    required this.stalls,
    required this.accent,
    required this.stall,
  });

  final List<double> gaps;
  final Set<int> stalls;
  final Color accent;
  final Color stall;

  @override
  void paint(Canvas canvas, Size size) {
    if (gaps.isEmpty) return;
    // The tallest bar is the largest gap on screen; the rest scale to it, so
    // the chart shows shape rather than an absolute a phone could not share.
    final ceiling = gaps.reduce((a, b) => a > b ? a : b);
    final paint = Paint();
    for (var i = 0; i < gaps.length; i++) {
      final ratio = ceiling <= 0 ? 0.0 : gaps[i] / ceiling;
      final barHeight = (ratio * size.height).clamp(2.0, size.height);
      final isStall = stalls.contains(i);
      paint.color = isStall ? stall : accent.withValues(alpha: 0.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * LatencySparkline._pitch,
            size.height - barHeight,
            3,
            barHeight,
          ),
          const Radius.circular(1.2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      !listEquals(old.gaps, gaps) ||
      !setEquals(old.stalls, stalls) ||
      old.accent != accent ||
      old.stall != stall;
}
