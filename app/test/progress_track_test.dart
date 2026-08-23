import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/theme/golem_theme.dart';
import 'package:golem_flutter/core/widgets/progress_track.dart';

void main() {
  // The track is shared by the splash, the Settings download rows and the chat
  // model picker, and it painted nothing at any value: the fill was laid out
  // at the right width and zero height, so every progress bar in the app was
  // an empty groove with a percentage beside it (#79, caught on a real
  // download at 47%).
  testWidgets('the fill has the width of its value and the full height', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                ProgressTrack(
                  value: 0.25,
                  trackColor: GolemTheme.divider,
                  fillColor: GolemTheme.accent,
                  height: 6,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final fill = tester.getRect(find.byType(FractionallySizedBox));
    expect(fill.width, closeTo(50, 0.01));
    expect(fill.height, 6, reason: 'a zero-height fill is an invisible one');
  });

  testWidgets('the groove spans its parent even when the parent centres', (
    tester,
  ) async {
    // The splash and the setup banner put the track in a centre-aligned
    // Column. With no width of its own it shrink-wrapped the fill, so the bar
    // itself was value-wide and centred and appeared to grow outward from the
    // middle in both directions.
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                ProgressTrack(
                  value: 0.25,
                  trackColor: GolemTheme.divider,
                  fillColor: GolemTheme.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final track = tester.getRect(find.byType(ClipRRect));
    expect(track.width, 200);
    final fill = tester.getRect(find.byType(FractionallySizedBox));
    expect(fill.left, track.left);
    expect(fill.width, closeTo(50, 0.01));
  });

  // This measures the placement the *stack* makes: the fill shrink-wraps, so
  // the stack's alignment is what puts it here and moving that is what this
  // catches.
  testWidgets('the fill grows from the leading edge, not the middle', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                ProgressTrack(
                  value: 0.5,
                  trackColor: GolemTheme.divider,
                  fillColor: GolemTheme.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final track = tester.getRect(find.byType(ClipRRect));
    final fill = tester.getRect(find.byType(FractionallySizedBox));
    expect(fill.left, track.left);
  });

  // Leading, not left: Arabic is a shipped locale, and a bar that filled from
  // the left there would run backwards against the text beside it.
  testWidgets('right-to-left grows the fill from the right', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: SizedBox(
              width: 200,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  ProgressTrack(
                    value: 0.5,
                    trackColor: GolemTheme.divider,
                    fillColor: GolemTheme.accent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final track = tester.getRect(find.byType(ClipRRect));
    final fill = tester.getRect(find.byType(FractionallySizedBox));
    expect(fill.right, track.right);
    expect(fill.left, greaterThan(track.left));
  });

  // The contract is the track's to keep, not the caller's: of the five
  // surfaces that once held a bar, three clamped and two did not (#123). A byte
  // count past its total, or a division against a stale total, must stop at
  // the groove rather than paint past it.
  testWidgets('a value past one fills the groove and no further', (
    tester,
  ) async {
    Future<void> pumpValue(double value) => tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProgressTrack(
                  value: value,
                  trackColor: GolemTheme.divider,
                  fillColor: GolemTheme.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await pumpValue(1.5);
    expect(tester.getRect(find.byType(FractionallySizedBox)).width, 200);
    // 0 / 0 against a stale total: NaN is neither below nor above the range,
    // and must not reach FractionallySizedBox's assert.
    await pumpValue(double.nan);
    expect(tester.getRect(find.byType(FractionallySizedBox)).width, 200);
  });

  testWidgets('a value below zero paints an empty groove', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                ProgressTrack(
                  value: -0.5,
                  trackColor: GolemTheme.divider,
                  fillColor: GolemTheme.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(FractionallySizedBox)).width, 0);
  });
}
