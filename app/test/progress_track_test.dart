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
}
