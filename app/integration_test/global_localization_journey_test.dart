import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/settings/language_screen.dart';
import 'package:golem_flutter/l10n/l10n.dart';
import 'package:golem_flutter/main.dart' as app;
import 'package:integration_test/integration_test.dart';

const _localeCases = [
  (
    key: 'language-spanish',
    locale: Locale('es'),
    systemLabel: 'Predeterminado del sistema',
  ),
  (
    key: 'language-brazilian-portuguese',
    locale: Locale('pt', 'BR'),
    systemLabel: 'Padrão do sistema',
  ),
  (key: 'language-japanese', locale: Locale('ja'), systemLabel: 'システムのデフォルト'),
  (
    key: 'language-indonesian',
    locale: Locale('id'),
    systemLabel: 'Bawaan sistem',
  ),
  (key: 'language-hindi', locale: Locale('hi'), systemLabel: 'सिस्टम डिफ़ॉल्ट'),
  (
    key: 'language-french',
    locale: Locale('fr'),
    systemLabel: 'Langue du système',
  ),
  (
    key: 'language-vietnamese',
    locale: Locale('vi'),
    systemLabel: 'Mặc định hệ thống',
  ),
  (
    key: 'language-turkish',
    locale: Locale('tr'),
    systemLabel: 'Sistem varsayılanı',
  ),
  (key: 'language-korean', locale: Locale('ko'), systemLabel: '시스템 기본값'),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets(
    'global language selection applies immediately, persists, and resets',
    (tester) async {
      await _launchToChat(tester);

      for (final localeCase in _localeCases) {
        await _openLanguageScreen(tester);
        await _revealLanguage(tester, Key(localeCase.key));
        await tester.tap(find.byKey(Key(localeCase.key)));
        await tester.pumpAndSettle();

        final languageContext = tester.element(find.byType(LanguageScreen));
        expect(Localizations.localeOf(languageContext), localeCase.locale);
        expect(find.text(localeCase.systemLabel), findsOneWidget);

        // Recreate the app root against the same QA preference store. The
        // explicit choice must survive process-style startup.
        await _launchToChat(tester);
        expect(
          Localizations.localeOf(tester.element(find.byType(ChatScreen))),
          localeCase.locale,
        );
      }

      await _openLanguageScreen(tester);
      await _revealLanguage(tester, const Key('language-system'));
      await tester.tap(find.byKey(const Key('language-system')));
      await tester.pumpAndSettle();
      final expectedSystemLocale = resolveAppLocale(
        WidgetsBinding.instance.platformDispatcher.locales,
        AppLocalizations.supportedLocales,
      );
      expect(
        Localizations.localeOf(tester.element(find.byType(LanguageScreen))),
        expectedSystemLocale,
      );

      await _launchToChat(tester);
      expect(
        Localizations.localeOf(tester.element(find.byType(ChatScreen))),
        expectedSystemLocale,
      );
    },
  );
}

Future<void> _openLanguageScreen(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-drawer')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-settings')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('settings-language-row')));
  await tester.tap(find.byKey(const Key('settings-language-row')));
  await tester.pumpAndSettle();
  expect(find.byType(LanguageScreen), findsOneWidget);
}

Future<void> _revealLanguage(WidgetTester tester, Key rowKey) async {
  final list = find.byKey(const Key('language-list'));
  final scrollable = find.descendant(
    of: list,
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.byKey(rowKey),
    180,
    scrollable: scrollable.first,
  );
  await tester.ensureVisible(find.byKey(rowKey));
  await tester.pumpAndSettle();
}

Future<void> _launchToChat(WidgetTester tester) async {
  // A second `runApp(BootstrapApp(...))` would update the existing State and
  // preserve its router location. Remove the old root first so this models a
  // process restart while leaving the QA preference file intact.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await app.launch();
  // `runApp` schedules the replacement tree. Pump once before inspecting the
  // bootstrap sentinel, otherwise a relaunch can still be looking at the old
  // Language screen and incorrectly conclude that startup has finished.
  await tester.pump();
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (find.byKey(const Key('launch-splash')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('The startup gate never completed.');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle(const Duration(seconds: 2));
  if (find.byKey(const Key('first-run-welcome')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('first-run-get-started')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('first-run-download')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-download-confirm')));
    await _waitForVerifiedFirstRunModel(tester);
    await tester.tap(find.byKey(const Key('first-run-start-chatting')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }
  if (find.byType(ChatScreen).evaluate().isEmpty) {
    fail('Chat screen did not become available.');
  }
}

Future<void> _waitForVerifiedFirstRunModel(WidgetTester tester) async {
  final button = find.descendant(
    of: find.byKey(const Key('first-run-start-chatting')),
    matching: find.byType(CupertinoButton),
  );
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (tester.widget<CupertinoButton>(button).onPressed == null) {
    if (DateTime.now().isAfter(deadline)) {
      fail('The simulated first-run model was never verified.');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}
