/// Download pace: a trailing-window rate estimate over observed byte counts,
/// the snapshot the surfaces read it as, and the spike-#36 throughput
/// constants the foreground-download note quotes.
///
/// The estimator carries no clock and no platform knowledge — callers feed it
/// `(elapsed, bytes)` observations and read decimal MB/s back (the same
/// convention as curl and `docs/notes/download-throughput.md`, where the
/// constants below were measured).
library;

import 'models.dart';

/// Whole minutes, rounded up and floored at one, for an already-computed
/// [eta], so every
/// surface quoting an ETA shares one minutes policy.
int aboutMinutesLeft(Duration eta) {
  final rounded = (eta.inSeconds / 60).ceil();
  return rounded < 1 ? 1 : rounded;
}

/// One artifact's live pace, published only while a rate is honest.
final class DownloadPaceSnapshot {
  const DownloadPaceSnapshot({
    required this.artifactKey,
    required this.mbPerSecond,
    this.eta,
    this.phase = ArtifactPhase.downloading,
  });

  final String artifactKey;

  /// Decimal MB/s over the estimator's trailing window — of the network while
  /// [phase] is downloading, of the hash while it is verifying. Only the
  /// former is quoted as a rate; the latter exists for its [eta].
  final double mbPerSecond;

  /// Time left at the current rate, when the catalog knows the total size.
  final Duration? eta;

  /// Which in-flight phase the window measured, so a surface never reads a
  /// hash rate as a transfer rate across the phase edge.
  final ArtifactPhase phase;

  @override
  bool operator ==(Object other) =>
      other is DownloadPaceSnapshot &&
      other.artifactKey == artifactKey &&
      other.mbPerSecond == mbPerSecond &&
      other.eta == eta &&
      other.phase == phase;

  @override
  int get hashCode => Object.hash(artifactKey, mbPerSecond, eta, phase);
}

/// A trailing-window average over `(elapsed, bytes)` observations.
///
/// The window discards samples older than [window] behind the newest one, so
/// the rate tracks the recent transfer instead of averaging over stalls that
/// have already recovered. With fewer than two samples, or a span shorter than
/// [minimumSpan], the rate is unknown (`null`) rather than a guess — the UI
/// shows nothing during warm-up instead of a fabricated figure.
final class DownloadPaceEstimator {
  DownloadPaceEstimator({this.window = const Duration(seconds: 4)});

  /// How far back observations still count toward the rate.
  final Duration window;

  /// Below this observed span the rate is considered unknown.
  static const minimumSpan = Duration(milliseconds: 500);

  final List<({Duration elapsed, int bytes})> _samples = [];

  /// Records a byte count observed [elapsed] after this attempt began. A byte
  /// count lower than the previous one means the transfer was replaced (a new
  /// attempt, a discard); a gap longer than [window] means the transfer
  /// stalled and recovered, and averaging across the silence would quote a
  /// wildly wrong rate; a decreasing [elapsed] means the clock stepped. All
  /// three clear the history so the sample starts a fresh window.
  void add(Duration elapsed, int bytes) {
    if (_samples.isNotEmpty) {
      final last = _samples.last;
      if (bytes < last.bytes ||
          elapsed < last.elapsed ||
          elapsed - last.elapsed > window) {
        reset();
      }
    }
    _samples.add((elapsed: elapsed, bytes: bytes));
    final cutoff = elapsed - window;
    while (_samples.length > 2 && _samples.first.elapsed < cutoff) {
      _samples.removeAt(0);
    }
  }

  /// Decimal megabytes per second across the retained window, or `null` while
  /// the window is too thin to be honest.
  double? get mbPerSecond {
    if (_samples.length < 2) return null;
    final span = _samples.last.elapsed - _samples.first.elapsed;
    if (span < minimumSpan) return null;
    final bytes = _samples.last.bytes - _samples.first.bytes;
    if (bytes < 0) return null;
    return bytes / span.inMilliseconds / 1000;
  }

  /// Time to fetch [remainingBytes] at the current rate, or `null` while the
  /// rate is unknown or zero.
  Duration? eta(int remainingBytes) {
    final rate = mbPerSecond;
    if (rate == null || rate <= 0) return null;
    if (remainingBytes <= 0) return Duration.zero;
    return Duration(milliseconds: (remainingBytes / (rate * 1000)).round());
  }

  void reset() => _samples.clear();
}
