import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/download_pace.dart';

/// A window wide enough to quote an ETA from: three samples a second apart.
DownloadPaceEstimator _settledWindow({int bytesPerSecond = 44000000}) =>
    DownloadPaceEstimator()
      ..add(Duration.zero, 0)
      ..add(const Duration(seconds: 1), bytesPerSecond)
      ..add(const Duration(seconds: 2), bytesPerSecond * 2)
      ..add(const Duration(seconds: 3), bytesPerSecond * 3);

void main() {
  group('DownloadPaceEstimator', () {
    test('is unknown until two samples span the minimum', () {
      final pace = DownloadPaceEstimator();
      expect(pace.mbPerSecond, isNull);
      pace.add(Duration.zero, 0);
      expect(pace.mbPerSecond, isNull);
      pace.add(const Duration(milliseconds: 200), 10000000);
      expect(pace.mbPerSecond, isNull, reason: 'span under 500 ms');
      pace.add(const Duration(milliseconds: 600), 30000000);
      expect(pace.mbPerSecond, isNotNull);
    });

    test('averages bytes over the observed span in decimal MB/s', () {
      final pace = DownloadPaceEstimator()
        ..add(Duration.zero, 0)
        ..add(const Duration(seconds: 1), 44000000);
      expect(pace.mbPerSecond, closeTo(44.0, 0.001));
    });

    test('evicts samples older than the window', () {
      final pace = DownloadPaceEstimator(window: const Duration(seconds: 4))
        ..add(Duration.zero, 0)
        // A slow first second, then a fast burst; once the slow sample ages
        // out, the rate reflects only the burst.
        ..add(const Duration(seconds: 1), 1000000)
        ..add(const Duration(seconds: 5), 5000000)
        ..add(const Duration(seconds: 6), 49000000);
      expect(pace.mbPerSecond, closeTo(44.0, 0.001));
    });

    test('a gap longer than the window starts a fresh attempt', () {
      // Averaging across a stall would quote the stall, not the transfer:
      // 10 MB over a 10 s silence is not a 1 MB/s link.
      final pace = DownloadPaceEstimator(window: const Duration(seconds: 4))
        ..add(Duration.zero, 0)
        ..add(const Duration(seconds: 10), 10000000);
      expect(pace.mbPerSecond, isNull, reason: 'post-stall window is fresh');
      pace.add(const Duration(seconds: 11), 54000000);
      expect(pace.mbPerSecond, closeTo(44.0, 0.001));
    });

    test('a clock step backwards starts a fresh attempt', () {
      final pace = DownloadPaceEstimator()
        ..add(const Duration(seconds: 10), 44000000)
        ..add(const Duration(seconds: 2), 50000000);
      expect(pace.mbPerSecond, isNull);
    });

    test('a byte regression starts a fresh attempt', () {
      final pace = DownloadPaceEstimator()
        ..add(Duration.zero, 0)
        ..add(const Duration(seconds: 1), 44000000)
        ..add(const Duration(seconds: 2), 5000000);
      expect(pace.mbPerSecond, isNull, reason: 'history cleared, one sample');
      pace.add(const Duration(seconds: 3), 10000000);
      expect(pace.mbPerSecond, closeTo(5.0, 0.001));
    });

    test('eta divides remaining bytes by the current rate', () {
      final pace = _settledWindow();
      expect(pace.eta(880000000), const Duration(seconds: 20));
      expect(pace.eta(0), Duration.zero);
      // A remaining count below zero is a bookkeeping slip upstream, and it
      // must still floor at zero rather than quote a negative ETA. Large
      // enough that the division does not round it to zero on its own.
      expect(pace.eta(-880000000), Duration.zero);
    });

    test('eta is unknown without a rate', () {
      final pace = DownloadPaceEstimator();
      expect(pace.eta(1000000), isNull);
      pace
        ..add(Duration.zero, 5000000)
        ..add(const Duration(seconds: 1), 5000000)
        ..add(const Duration(seconds: 2), 5000000)
        ..add(const Duration(seconds: 3), 5000000);
      expect(pace.mbPerSecond, 0.0);
      expect(pace.eta(1000000), isNull, reason: 'zero rate has no eta');
    });

    test('a window that quotes a rate is not yet one that quotes an eta', () {
      // The #146 spike: remaining bytes divided by the first honest reading.
      final pace = DownloadPaceEstimator()
        ..add(Duration.zero, 0)
        ..add(const Duration(seconds: 1), 44000000);
      expect(pace.mbPerSecond, isNotNull);
      expect(pace.eta(880000000), isNull, reason: 'two samples, one second');
      pace.add(const Duration(seconds: 2), 88000000);
      expect(pace.eta(880000000), isNull, reason: 'three samples, two seconds');
      pace.add(const Duration(seconds: 3), 132000000);
      expect(pace.eta(880000000), const Duration(seconds: 20));
    });

    test('the eta window outlives the rate window', () {
      // The platform downloader reports as rarely as once every 2.5 s, which
      // never reaches three samples inside the four-second rate window.
      final pace = DownloadPaceEstimator()
        ..add(Duration.zero, 0)
        ..add(const Duration(milliseconds: 2500), 110000000)
        ..add(const Duration(seconds: 5), 220000000);
      expect(pace.mbPerSecond, closeTo(44.0, 0.001));
      expect(pace.eta(880000000), const Duration(seconds: 20));
    });

    test('an eta ages out of its own window', () {
      final pace = DownloadPaceEstimator(etaWindow: const Duration(seconds: 6));
      for (var second = 0; second <= 6; second++) {
        pace.add(Duration(seconds: second), 44000000 * second);
      }
      expect(pace.eta(880000000), const Duration(seconds: 20));
      // A single later sample after a stall clears the history; the samples
      // behind it cannot be borrowed to keep quoting a time left.
      pace.add(const Duration(seconds: 20), 900000000);
      expect(pace.eta(880000000), isNull);
    });

    test('reset clears the window', () {
      final pace = _settledWindow()..reset();
      expect(pace.mbPerSecond, isNull);
      expect(pace.eta(880000000), isNull);
    });
  });

  group('DownloadEtaGate', () {
    test('withholds an estimate until the next tick agrees', () {
      final gate = DownloadEtaGate();
      expect(gate.admit(const Duration(minutes: 40)), isNull);
      expect(
        gate.admit(const Duration(minutes: 39)),
        const Duration(minutes: 39),
      );
    });

    test('an estimate an order out is never quoted', () {
      // The reported defect: "About 2173 minutes left" for a tick or two.
      final gate = DownloadEtaGate();
      expect(gate.admit(const Duration(minutes: 2173)), isNull);
      expect(gate.admit(const Duration(minutes: 300)), isNull);
      expect(gate.admit(const Duration(minutes: 40)), isNull);
      expect(
        gate.admit(const Duration(minutes: 38)),
        const Duration(minutes: 38),
      );
    });

    test('agreement is a quarter of the larger figure', () {
      final agreeing = DownloadEtaGate()..admit(const Duration(minutes: 40));
      expect(agreeing.admit(const Duration(minutes: 30)), isNotNull);
      final disagreeing = DownloadEtaGate()..admit(const Duration(minutes: 40));
      expect(disagreeing.admit(const Duration(minutes: 29)), isNull);
    });

    test('a settled gate keeps publishing, slowdown included', () {
      final gate = DownloadEtaGate()
        ..admit(const Duration(minutes: 40))
        ..admit(const Duration(minutes: 39));
      expect(
        gate.admit(const Duration(minutes: 90)),
        const Duration(minutes: 90),
      );
    });

    test('a withheld estimate re-arms the gate', () {
      final gate = DownloadEtaGate()
        ..admit(const Duration(minutes: 40))
        ..admit(const Duration(minutes: 39));
      expect(gate.admit(null), isNull);
      expect(
        gate.admit(const Duration(minutes: 39)),
        isNull,
        reason: 'a fresh window proves itself again',
      );
      expect(
        gate.admit(const Duration(minutes: 38)),
        const Duration(minutes: 38),
      );
    });

    test('reset re-arms the gate', () {
      final gate = DownloadEtaGate()
        ..admit(const Duration(minutes: 40))
        ..admit(const Duration(minutes: 39))
        ..reset();
      expect(gate.admit(const Duration(minutes: 39)), isNull);
    });

    test('two zero estimates agree', () {
      final gate = DownloadEtaGate()..admit(Duration.zero);
      expect(gate.admit(Duration.zero), Duration.zero);
    });
  });

  group('aboutTimeLeft', () {
    test('rounds up to whole minutes and floors at one', () {
      expect(aboutTimeLeft(const Duration(seconds: 54)), (
        hours: 0,
        minutes: 1,
      ));
      expect(aboutTimeLeft(const Duration(seconds: 61)), (
        hours: 0,
        minutes: 2,
      ));
      expect(aboutTimeLeft(const Duration(minutes: 2)), (hours: 0, minutes: 2));
      expect(aboutTimeLeft(Duration.zero), (hours: 0, minutes: 1));
    });

    test('rolls up to hours', () {
      expect(aboutTimeLeft(const Duration(minutes: 59)), (
        hours: 0,
        minutes: 59,
      ));
      expect(aboutTimeLeft(const Duration(minutes: 60)), (
        hours: 1,
        minutes: 0,
      ));
      expect(aboutTimeLeft(const Duration(minutes: 61)), (
        hours: 1,
        minutes: 1,
      ));
      expect(aboutTimeLeft(const Duration(minutes: 80)), (
        hours: 1,
        minutes: 20,
      ));
      expect(aboutTimeLeft(const Duration(minutes: 120)), (
        hours: 2,
        minutes: 0,
      ));
    });

    test('withholds anything past the ceiling', () {
      expect(aboutTimeLeft(etaCeiling), (hours: 24, minutes: 0));
      expect(aboutTimeLeft(etaCeiling + const Duration(seconds: 1)), isNull);
      // The figure this ticket was filed for.
      expect(aboutTimeLeft(const Duration(minutes: 2173)), isNull);
    });
  });
}
