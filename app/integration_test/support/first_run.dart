import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parks until the simulated first-run model is verified and the start button
/// is live. Tolerates the button not having been built yet — the journeys call
/// this ahead of any pump — and names that case apart from a verification that
/// never arrives.
Future<void> waitForVerifiedFirstRunModel(WidgetTester tester) async {
  final button = find.descendant(
    of: find.byKey(const Key('first-run-start-chatting')),
    matching: find.byType(CupertinoButton),
  );
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (button.evaluate().isEmpty ||
      tester.widget<CupertinoButton>(button).onPressed == null) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        button.evaluate().isEmpty
            ? 'The first-run start button never appeared.'
            : 'The simulated first-run model was never verified.',
      );
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}
