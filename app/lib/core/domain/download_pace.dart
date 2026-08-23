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

/// The longest time left still worth printing. Past a day the figure has
/// stopped being information: it says the transfer will not finish on this
/// link, which the number itself already said less legibly (#146).
const etaCeiling = Duration(hours: 24);

/// Whole hours and minutes for an already-computed [eta] — rounded up to the
/// minute, floored at one — or null past [etaCeiling], so every surface
/// quoting a time left shares one reading and one ceiling.
({int hours, int minutes})? aboutTimeLeft(Duration eta) {
  if (eta > etaCeiling) return null;
  final minutes = (eta.inSeconds / 60).ceil();
  final rounded = minutes < 1 ? 1 : minutes;
  return (hours: rounded ~/ 60, minutes: rounded % 60);
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
  DownloadPaceEstimator({
    this.window = const Duration(seconds: 4),
    this.etaWindow = const Duration(seconds: 12),
  });

  /// How far back observations still count toward the rate.
  final Duration window;

  /// How far back they still count toward an ETA — longer than [window] on
  /// purpose. Remaining bytes divided by a young window printed "About 2173
  /// minutes left" on a real transfer (#146), and the platform downloader
  /// reports as rarely as once every 2.5 seconds, which is barely two samples
  /// inside [window].
  final Duration etaWindow;

  /// Below this observed span the rate is considered unknown.
  static const minimumSpan = Duration(milliseconds: 500);

  /// What an ETA needs beyond an honest rate: this much observed time and
  /// this many observations, over [etaWindow].
  static const etaMinimumSpan = Duration(seconds: 3);
  static const etaMinimumSamples = 3;

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
    final cutoff = elapsed - etaWindow;
    while (_samples.length > 2 && _samples.first.elapsed < cutoff) {
      _samples.removeAt(0);
    }
  }

  /// Decimal megabytes per second across the retained window, or `null` while
  /// the window is too thin to be honest.
  double? get mbPerSecond => _rateOver(window);

  /// Time to fetch [remainingBytes] at the settled rate, or `null` while the
  /// window is unknown, zero, or too young to divide by.
  Duration? eta(int remainingBytes) {
    final samples = _retained(etaWindow);
    if (samples.length < etaMinimumSamples) return null;
    if (samples.last.elapsed - samples.first.elapsed < etaMinimumSpan) {
      return null;
    }
    final rate = _rateOver(etaWindow);
    if (rate == null || rate <= 0) return null;
    if (remainingBytes <= 0) return Duration.zero;
    return Duration(milliseconds: (remainingBytes / (rate * 1000)).round());
  }

  void reset() => _samples.clear();

  /// The samples no older than [span] behind the newest, and never fewer than
  /// the last two: a cadence slower than [span] still has a rate, measured
  /// over the two readings it did deliver.
  List<({Duration elapsed, int bytes})> _retained(Duration span) {
    if (_samples.length < 2) return const [];
    final cutoff = _samples.last.elapsed - span;
    final first = _samples.indexWhere((sample) => sample.elapsed >= cutoff);
    final start = first < 0 || first > _samples.length - 2
        ? _samples.length - 2
        : first;
    return _samples.sublist(start);
  }

  double? _rateOver(Duration span) {
    final samples = _retained(span);
    if (samples.length < 2) return null;
    final observed = samples.last.elapsed - samples.first.elapsed;
    if (observed < minimumSpan) return null;
    final bytes = samples.last.bytes - samples.first.bytes;
    if (bytes < 0) return null;
    return bytes / observed.inMilliseconds / 1000;
  }
}

/// Holds an ETA back until the transfer proposes the same one twice.
///
/// A window wide enough to divide by is not yet a window worth quoting: the
/// first honest estimate of a transfer can still be an order out, and it is
/// the one a user reads while deciding whether to leave the phone alone. Two
/// consecutive estimates that agree are the cheapest evidence that the link
/// has settled. Once they do, every later estimate publishes — the figure is
/// then tracking a real link, and withholding it on a genuine slowdown would
/// blank the line the user is watching.
final class DownloadEtaGate {
  /// How far apart two consecutive estimates may be and still count as the
  /// same figure, as a fraction of the larger.
  static const agreement = 0.25;

  Duration? _proposed;
  bool _settled = false;

  /// The ETA to publish for [estimate], or null while the transfer has yet to
  /// propose it twice. A null estimate — a stall, a phase edge, a window that
  /// went thin — re-arms the gate.
  Duration? admit(Duration? estimate) {
    if (estimate == null) {
      reset();
      return null;
    }
    if (_settled) return estimate;
    final proposed = _proposed;
    _proposed = estimate;
    if (proposed == null || !_agrees(proposed, estimate)) return null;
    _settled = true;
    return estimate;
  }

  void reset() {
    _proposed = null;
    _settled = false;
  }

  static bool _agrees(Duration a, Duration b) {
    final larger = a > b ? a : b;
    if (larger == Duration.zero) return true;
    return (a - b).abs().inMicroseconds <= larger.inMicroseconds * agreement;
  }
}
