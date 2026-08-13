import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/download_pace.dart';

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
      final pace = DownloadPaceEstimator()
        ..add(Duration.zero, 0)
        ..add(const Duration(seconds: 1), 44000000);
      expect(pace.eta(880000000), const Duration(seconds: 20));
      expect(pace.eta(0), Duration.zero);
    });

    test('eta is unknown without a rate', () {
      final pace = DownloadPaceEstimator();
      expect(pace.eta(1000000), isNull);
      pace
        ..add(Duration.zero, 5000000)
        ..add(const Duration(seconds: 1), 5000000);
      expect(pace.mbPerSecond, 0.0);
      expect(pace.eta(1000000), isNull, reason: 'zero rate has no eta');
    });

    test('reset clears the window', () {
      final pace = DownloadPaceEstimator()
        ..add(Duration.zero, 0)
        ..add(const Duration(seconds: 1), 44000000)
        ..reset();
      expect(pace.mbPerSecond, isNull);
    });
  });

  group('aboutMinutes', () {
    test('rounds up and floors at one minute', () {
      // 3.2 GB remaining at the iOS background rate: 3.2e9 / 3.8e6 ≈ 842 s.
      expect(aboutMinutes(iosBackgroundMbs, 3200000000), 15);
      // The same bytes at foreground pace finish within about two minutes.
      expect(aboutMinutes(downloadForegroundMbs, 3200000000), 2);
      expect(aboutMinutes(downloadForegroundMbs, 1000000), 1);
      expect(aboutMinutes(downloadForegroundMbs, 0), 1);
      expect(aboutMinutes(downloadForegroundMbs, -5), 1);
    });

    test('exact minute boundaries do not round up an extra minute', () {
      // 44 MB/s for exactly 2 minutes: 5,280,000,000 bytes.
      expect(aboutMinutes(downloadForegroundMbs, 5280000000), 2);
    });
  });

  group('aboutMinutesLeft', () {
    test('shares the round-up-floor-one rule with aboutMinutes', () {
      expect(aboutMinutesLeft(const Duration(seconds: 54)), 1);
      expect(aboutMinutesLeft(const Duration(seconds: 61)), 2);
      expect(aboutMinutesLeft(const Duration(minutes: 2)), 2);
      expect(aboutMinutesLeft(Duration.zero), 1);
    });
  });

  group('backgroundMbsFor', () {
    test('quotes the measured platform pacing', () {
      expect(backgroundMbsFor(TargetPlatform.iOS), iosBackgroundMbs);
      expect(backgroundMbsFor(TargetPlatform.android), androidBackgroundMbs);
      expect(backgroundMbsFor(TargetPlatform.macOS), iosBackgroundMbs);
    });
  });
}
