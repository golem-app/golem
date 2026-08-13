/// Windowed throughput samples for the download bench (#36).
///
/// The prior spike round read rates off the model card's progress text, which
/// produced numbers that could not be compared or reproduced. This meter
/// timestamps monotonic byte counts and derives rates from deltas, so every
/// reported figure traces to two (time, bytes) samples.
///
/// Test-only, and never linked into the app.
final class RateMeter {
  RateMeter({this.rampSeconds = 5});

  /// Seconds excluded from the steady rate: connection setup, redirect
  /// chasing, and TCP ramp all land in the first moments and would understate
  /// a short window.
  final int rampSeconds;

  final Stopwatch _clock = Stopwatch();
  final List<(Duration, int)> _samples = [];

  void start() => _clock.start();

  /// Records [bytesReceived], which must be monotonic for one transfer.
  void record(int bytesReceived) =>
      _samples.add((_clock.elapsed, bytesReceived));

  bool get isEmpty => _samples.isEmpty;
  int get lastBytes => _samples.isEmpty ? 0 : _samples.last.$2;
  Duration get elapsed => _clock.elapsed;

  /// Whole-window average in decimal MB/s — curl's `%{speed_download}`
  /// convention, so host and in-app rows compare directly.
  double get averageMbs {
    if (_samples.isEmpty) return 0;
    final (t, bytes) = _samples.last;
    return t.inMilliseconds == 0 ? 0 : bytes / t.inMilliseconds / 1000;
  }

  /// Average after the ramp, or the whole-window average when the transfer
  /// never outlived the ramp.
  double get steadyMbs {
    final ramp = Duration(seconds: rampSeconds);
    final after = _samples.where((s) => s.$1 >= ramp).toList();
    if (after.length < 2) return averageMbs;
    final (t0, b0) = after.first;
    final (t1, b1) = after.last;
    final ms = (t1 - t0).inMilliseconds;
    return ms == 0 ? averageMbs : (b1 - b0) / ms / 1000;
  }

  /// The average across the largest gap between samples — the honest number
  /// for a backgrounded run, where a suspended process cannot sample and only
  /// the bracketing observations exist.
  double get largestGapMbs {
    if (_samples.length < 2) return averageMbs;
    var gap = Duration.zero;
    var rate = 0.0;
    for (var i = 1; i < _samples.length; i++) {
      final (t0, b0) = _samples[i - 1];
      final (t1, b1) = _samples[i];
      if (t1 - t0 > gap) {
        gap = t1 - t0;
        rate = (b1 - b0) / (t1 - t0).inMilliseconds / 1000;
      }
    }
    return rate;
  }

  /// `window_s` is the measured span (last sample's clock), never the
  /// nominal cap — rates in this line divide by it, and a reader must be
  /// able to recompute them. The cap goes into [capSeconds] as `cap_s`; a
  /// backgrounded window can legitimately overrun it (suspension freezes
  /// the timers, and the flush grace extends the span).
  String line({
    required String transport,
    required int round,
    required int capSeconds,
    String mode = 'foreground',
    String extra = '',
  }) {
    final span = _samples.isEmpty ? elapsed : _samples.last.$1;
    return 'DOWNLOAD_BENCH transport=$transport round=$round mode=$mode '
        'window_s=${span.inSeconds} cap_s=$capSeconds bytes=$lastBytes '
        'rate_mbs=${averageMbs.toStringAsFixed(2)} '
        'steady_mbs=${steadyMbs.toStringAsFixed(2)}'
        '${extra.isEmpty ? '' : ' $extra'}';
  }

  String hudDetail(String transport, int round, int rounds) =>
      '${steadyMbs.toStringAsFixed(1)} MB/s · $transport · '
      'window ${round + 1}/$rounds';
}
