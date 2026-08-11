import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/chrome/golem_sheet.dart';

import 'support/harness.dart';

void main() {
  // The sheet ceiling caps the space above the keyboard, and bodies pad for
  // the keyboard inside it. A cap that merely subtracted the inset charged for
  // it twice and clipped the bottom of a rename sheet clean off.
  testWidgets('a keyboard-padded sheet keeps its whole body', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(
      wrapApp(
        brightness: Brightness.light,
        child: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showGolemSheet<void>(
              context: context,
              sheetKey: const Key('probe-sheet'),
              builder: (context) => Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SizedBox(height: 160, child: Text('body')),
                    SizedBox(
                      key: Key('probe-footer'),
                      height: 50,
                      child: Text('save'),
                    ),
                  ],
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    // A keyboard covering 336 of the 874-point viewport.
    tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 3);
    addTearDown(tester.view.reset);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byKey(const Key('probe-sheet')));
    final footer = tester.getRect(find.byKey(const Key('probe-footer')));
    expect(
      footer.bottom,
      lessThanOrEqualTo(sheet.bottom + 0.5),
      reason: 'the footer must sit inside the sheet, not past its edge',
    );
    expect(footer.height, 50, reason: 'and it must not be squeezed away');
  });
}
