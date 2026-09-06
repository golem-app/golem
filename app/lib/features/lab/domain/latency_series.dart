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

  static const empty = LatencySeries._(
    gapsMs: [],
    medianMs: null,
    stallIndexes: {},
  );

  /// From [instantsMs], in arrival order. Fewer than two instants have no gap.
  factory LatencySeries.from(List<double> instantsMs) {
    if (instantsMs.length < 2) return empty;
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
      // No stalls against a zero median: coarse or batched stamps make
      // every non-zero gap "twice the median" of nothing.
      stallIndexes: {
        if (median > 0)
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

/// The decode rate over the trailing [windowMs] of a run's clock, from the
/// token instants that fell inside it — measured work over an explicit
/// window, and only for tokens: a chunk gap counts nothing. [elapsedMs] is
/// how far the instants' own clock has come, and the interval runs from the
/// window's first instant to now, so a rate sinks while arrivals stall and
/// reaches nothing once they leave the window, instead of freezing at the
/// last burst.
double? liveDecodeRate(
  List<double> instantsMs,
  double elapsedMs, {
  double windowMs = 2000,
}) {
  final start = elapsedMs - windowMs;
  var count = 0;
  double? first;
  for (final instant in instantsMs) {
    if (instant <= start || instant > elapsedMs) continue;
    first ??= instant;
    count++;
  }
  if (count < 2 || elapsedMs <= first!) return null;
  return (count - 1) / ((elapsedMs - first) / 1000);
}
