/// What a latency chart draws from a run's arrival instants: the gaps between
/// consecutive arrivals, their median, and which gaps count as stalls.
///
/// Pure over the instants the engine stamped (milliseconds from the request's
/// acceptance). Whether an instant is a token or a chunk is the run's to say;
/// this only measures gaps, and never derives a throughput from them.
final class LatencySeries {
  const LatencySeries._({
    required this.gapsMs,
    required this.medianMs,
    required this.stallIndexes,
  });

  /// From [instantsMs], in arrival order. Fewer than two instants have no gap.
  factory LatencySeries.from(List<double> instantsMs) {
    if (instantsMs.length < 2) {
      return const LatencySeries._(
        gapsMs: [],
        medianMs: null,
        stallIndexes: {},
      );
    }
    final gaps = <double>[
      for (var i = 1; i < instantsMs.length; i++)
        instantsMs[i] - instantsMs[i - 1],
    ];
    final sorted = [...gaps]..sort();
    final middle = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
    return LatencySeries._(
      gapsMs: gaps,
      medianMs: median,
      stallIndexes: {
        for (var i = 0; i < gaps.length; i++)
          if (gaps[i] > median * stallFactor) i,
      },
    );
  }

  /// A gap this many times the median is a stall — what a reader feels as a
  /// hitch, as opposed to the average a spec sheet quotes.
  static const stallFactor = 2.0;

  final List<double> gapsMs;
  final double? medianMs;
  final Set<int> stallIndexes;

  int get stallCount => stallIndexes.length;
}
