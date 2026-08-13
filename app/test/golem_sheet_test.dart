import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/chrome/golem_sheet.dart';

import 'support/harness.dart';

void main() {
  testWidgets('actions dismiss from the nested shell navigator', (
    tester,
  ) async {
    var acted = false;
    await tester.pumpWidget(
      wrapApp(
        child: Navigator(
          onGenerateRoute: (_) => CupertinoPageRoute<void>(
            builder: (context) => CupertinoPageScaffold(
              key: const Key('shell-page'),
              child: Center(
                child: CupertinoButton(
                  key: const Key('open-actions'),
                  onPressed: () => showGolemActions(
                    context: context,
                    actions: [
                      GolemSheetAction(
                        key: const Key('nested-action'),
                        label: 'Act',
                        onPressed: () {
                          Navigator.pop(context);
                          acted = true;
                        },
                      ),
                    ],
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-actions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nested-action')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nested-action')));
    await tester.pumpAndSettle();

    expect(acted, isTrue);
    expect(find.byKey(const Key('nested-action')), findsNothing);
    expect(find.byKey(const Key('shell-page')), findsOneWidget);
  }, variant: bothChromes);
}
