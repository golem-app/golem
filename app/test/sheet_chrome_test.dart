import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/chrome/golem_sheet.dart';

import 'support/harness.dart';

void main() {
  // The chrome pads for the keyboard and the ceiling reserves room for that
  // padding. Getting either half wrong hides the bottom of a sheet: a cap that
  // merely subtracted the inset charged for it twice and clipped the Save
  // button clean off the rename sheet on a real iPhone, and four of the five
  // bodies never padded at all, so their last row sat behind the keyboard.
  //
  // The numbers matter: the harness pins devicePixelRatio to 1, so a
  // FakeViewPadding is in logical points, and the body must be tall enough
  // that the two formulas actually differ. With a 300pt keyboard on an 874pt
  // viewport the correct cap is (874-300)*0.8+300 = 759 and the wrong one is
  // (874-300)*0.8 = 459, so a 520pt body distinguishes them.
  testWidgets('a keyboard-padded sheet keeps its whole body', (tester) async {
    setViewport(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrapApp(
        brightness: Brightness.light,
        child: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showGolemSheet<void>(
              context: context,
              sheetKey: const Key('probe-sheet'),
              // No inset padding here on purpose: the chrome owns it now, so
              // a body that never thought about the keyboard still clears it.
              builder: (context) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 170, child: Text('body')),
                  SizedBox(
                    key: Key('probe-footer'),
                    height: 50,
                    child: Text('save'),
                  ),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byKey(const Key('probe-sheet')));
    final footer = tester.getRect(find.byKey(const Key('probe-footer')));
    expect(footer.height, 50, reason: 'the footer must not be squeezed away');
    expect(
      footer.bottom,
      lessThanOrEqualTo(sheet.bottom + 0.5),
      reason: 'and it must sit inside the sheet, not past its edge',
    );
    expect(
      footer.bottom,
      lessThanOrEqualTo(874 - 300 + 0.5),
      reason: 'nor behind the keyboard',
    );
  }, variant: iosChrome);
}
