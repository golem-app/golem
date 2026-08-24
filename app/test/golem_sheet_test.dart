import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/chrome/golem_sheet.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_pl.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_tr.dart';

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

  // The Cupertino action sheet's cancel button is the one control every one of
  // these sheets has and no caller ever labels, so its default was the English
  // word in twelve locales (#130).
  testWidgets('the cancel button follows the locale', (tester) async {
    for (final (locale, expected) in [
      (const Locale('pl'), AppLocalizationsPl().cancel),
      (const Locale('tr'), AppLocalizationsTr().cancel),
    ]) {
      await tester.pumpWidget(
        wrapApp(
          locale: locale,
          child: Builder(
            builder: (context) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  key: const Key('open-actions'),
                  onPressed: () => showGolemActions(
                    context: context,
                    actions: [GolemSheetAction(label: 'Act', onPressed: () {})],
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-actions')));
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget, reason: '$locale');
      expect(find.text('Cancel'), findsNothing, reason: '$locale');
      await tester.tap(find.text(expected));
      await tester.pumpAndSettle();
    }
  }, variant: iosChrome);
}
