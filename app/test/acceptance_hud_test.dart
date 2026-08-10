import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/acceptance_hud.dart';

/// The HUD is test-only and never linked into the app, so nothing else compiles
/// it. These cover the parts an operator actually reads off a phone across the
/// room — the numbers — which is exactly where a silent regression would hide.
void main() {
  group('formatBytes', () {
    test('reads in gigabytes from a gigabyte up', () {
      expect(formatBytes(3178000000), '3.18 GB');
      expect(formatBytes(1000000000), '1.00 GB');
    });

    test('reads in megabytes below that', () {
      // "0.00 GB" for the first minute of a download says nothing at all.
      expect(formatBytes(999999999), '1000 MB');
      expect(formatBytes(4200000), '4 MB');
      expect(formatBytes(0), '0 MB');
    });
  });

  group('formatElapsed', () {
    test('is zero-padded minutes and seconds', () {
      expect(formatElapsed(Duration.zero), '00:00');
      expect(formatElapsed(const Duration(seconds: 9)), '00:09');
      expect(formatElapsed(const Duration(minutes: 4, seconds: 12)), '04:12');
    });

    test('keeps counting past an hour rather than wrapping', () {
      expect(formatElapsed(const Duration(hours: 1, minutes: 5)), '65:00');
    });
  });

  group('HudProgress', () {
    test('captions bytes against the total', () {
      const progress = HudProgress(received: 1840000000, total: 3180000000);
      expect(progress.caption, '1.84 GB / 3.18 GB');
      expect(progress.fraction, closeTo(0.5786, 0.0001));
    });

    test('captions free text on its own', () {
      const progress = HudProgress(detail: 'turn 7 of 12');
      expect(progress.caption, 'turn 7 of 12');
      expect(progress.fraction, isNull);
    });

    test('joins bytes and detail when both are given', () {
      const progress = HudProgress(
        received: 500000000,
        total: 1000000000,
        detail: 'verifying',
      );
      expect(progress.caption, '500 MB / 1.00 GB · verifying');
    });

    test('has no fraction without a total to divide by', () {
      expect(const HudProgress(received: 10, total: 0).fraction, isNull);
      expect(const HudProgress(received: 10).fraction, isNull);
    });

    test('still reads the count when no total was given', () {
      // A bar needs both operands; the number does not, and dropping it would
      // paint an empty caption line under the step.
      expect(const HudProgress(received: 4200000).caption, '4 MB');
    });

    test('is empty only when it was given nothing', () {
      expect(const HudProgress().caption, isEmpty);
    });

    test('clamps a total that under-reports the bytes on disk', () {
      // A resumed download can report more received than the catalog claims;
      // a bar past 100% would read as a bug in the run rather than the pin.
      expect(const HudProgress(received: 12, total: 10).fraction, 1.0);
    });
  });

  // Last, and alone: the mount latch and the notifiers behind it are static,
  // so exactly one test may take the screen over.
  testWidgets('ticks each finished step off and drops stale progress', (
    tester,
  ) async {
    AcceptanceHud.takeOver();
    AcceptanceHud.step('Installing gemma4-gguf');
    AcceptanceHud.progress(received: 1840000000, total: 3180000000);
    await tester.pump();
    expect(find.text('Installing gemma4-gguf'), findsOneWidget);
    expect(find.text('1.84 GB / 3.18 GB'), findsOneWidget);

    AcceptanceHud.step('Text turn');
    await tester.pump();
    expect(find.text('✓  Installing gemma4-gguf'), findsOneWidget);
    expect(find.text('Text turn'), findsOneWidget);
    // The previous step's bytes must not linger under the new one.
    expect(find.text('1.84 GB / 3.18 GB'), findsNothing);

    AcceptanceHud.finish('Done');
    await tester.pump();
    expect(find.text('✓  Text turn'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    // The pulse repeats forever; unmount it rather than leave a live ticker.
    await tester.pumpWidget(const SizedBox.shrink());
    // And leave the statics as they were found, or the next run of anything
    // that mounts the HUD inherits this test's steps.
    AcceptanceHud.reset();
  });
}
