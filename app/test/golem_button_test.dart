import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/chrome/golem_button.dart';
import 'package:golem_flutter/core/chrome/golem_chrome.dart';
import 'package:golem_flutter/core/chrome/golem_tappable.dart';

import 'support/harness.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget button, {
    required CrossAxisAlignment alignment,
  }) => tester.pumpWidget(
    wrapApp(
      child: Center(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: alignment,
            children: [button],
          ),
        ),
      ),
    ),
  );

  testWidgets('a secondary button that does not expand sizes to its label', (
    tester,
  ) async {
    // `expand` is read by the filled and tinted variants; a secondary one that
    // ignored it would demand an infinite minimum width and blow up the layout
    // in exactly the loose parent a compact button is asked for.
    await pump(
      tester,
      const GolemButton.plain(
        key: Key('compact'),
        label: 'Resume',
        onPressed: _noop,
        expand: false,
      ),
      alignment: CrossAxisAlignment.start,
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('compact'))).width,
      lessThan(320),
    );
  });

  testWidgets('a secondary button expands by default', (tester) async {
    await pump(
      tester,
      const GolemButton.plain(
        key: Key('wide'),
        label: 'Resume',
        onPressed: _noop,
      ),
      alignment: CrossAxisAlignment.stretch,
    );
    expect(tester.getSize(find.byKey(const Key('wide'))).width, 320);
  });

  testWidgets('a secondary button still owns the platform minimum', (
    tester,
  ) async {
    await pump(
      tester,
      const GolemButton.destructive(
        key: Key('destructive'),
        label: 'Cancel and discard',
        onPressed: _noop,
      ),
      alignment: CrossAxisAlignment.stretch,
    );
    expect(
      tester.getSize(find.byKey(const Key('destructive'))).height,
      greaterThanOrEqualTo(GolemChrome.current.minimumTapTarget),
    );
  }, variant: bothChromes);

  test('a row height on a square target is a contradiction, not a no-op', () {
    // It used to be accepted and dropped, which is the class of silent miss
    // GolemTappable exists to end.
    expect(
      () => GolemTappable(
        minimumHeight: 56,
        onPressed: _noop,
        child: const SizedBox.shrink(),
      ),
      throwsAssertionError,
    );
  });
}

void _noop() {}
