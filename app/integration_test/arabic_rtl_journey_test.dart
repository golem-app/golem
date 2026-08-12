import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/chrome/golem_nav_bar.dart';
import 'package:golem_flutter/features/chat/application/chat_providers.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/settings/language_screen.dart';
import 'package:golem_flutter/main.dart' as app;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('Arabic selection, RTL navigation, composition, and recovery', (
    tester,
  ) async {
    await _launchToChat(tester);

    await tester.tap(find.byKey(const Key('open-drawer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('settings-language-row')));
    await tester.tap(find.byKey(const Key('settings-language-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-arabic')));
    await tester.pumpAndSettle();

    final languageContext = tester.element(find.byType(LanguageScreen));
    expect(Localizations.localeOf(languageContext).languageCode, 'ar');
    expect(Directionality.of(languageContext), TextDirection.rtl);
    expect(find.text('لغة النظام'), findsOneWidget);

    await _goBack(tester);
    await tester.pumpAndSettle();
    await _goBack(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-drawer')));
    await tester.pumpAndSettle();
    final drawerRect = tester.getRect(
      find.byKey(const Key('conversation-drawer')),
    );
    expect(
      drawerRect.right,
      closeTo(
        MediaQuery.sizeOf(tester.element(find.byType(ChatScreen))).width,
        1,
      ),
    );
    expect(drawerRect.left, greaterThan(0));
    // The RTL drawer covers the right side; dismiss through the visible chat
    // strip on the left rather than the barrier's obscured center.
    await tester.tapAt(Offset(20, drawerRect.center.dy));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('conversation-drawer'))).left,
      greaterThanOrEqualTo(
        MediaQuery.sizeOf(tester.element(find.byType(ChatScreen))).width,
      ),
    );

    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'اكتب ردًا عربيًا قصيرًا',
    );
    await tester.pump();
    final editor = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(editor.textDirection, TextDirection.rtl);
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recovery-banner')), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(
      container
          .read(chatControllerProvider)
          .requireValue
          .active!
          .messages
          .any((message) => message.text == 'اكتب ردًا عربيًا قصيرًا'),
      isTrue,
    );
    await tester.runAsync(
      () => container.read(chatControllerProvider.notifier).send('[fail]'),
    );
    final recoveryDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (find.byKey(const Key('recovery-banner')).evaluate().isEmpty) {
      if (DateTime.now().isAfter(recoveryDeadline)) {
        fail('The localized inference recovery banner never appeared.');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('recovery-banner')), findsOneWidget);
    expect(find.text('حدث خطأ أثناء إنشاء الرد.'), findsOneWidget);

    // Recreate the app root against the same QA preferences file. The manual
    // choice must survive process-style startup and win over system locale.
    await _launchToChat(tester);
    final chatContext = tester.element(find.byType(ChatScreen));
    expect(Localizations.localeOf(chatContext).languageCode, 'ar');
    expect(Directionality.of(chatContext), TextDirection.rtl);
  });
}

Future<void> _goBack(WidgetTester tester) async {
  final androidBack = find.byType(GolemBackButton);
  if (androidBack.evaluate().isNotEmpty) {
    await tester.tap(androidBack);
  } else {
    await tester.pageBack();
  }
}

Future<void> _launchToChat(WidgetTester tester) async {
  await app.launch();
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
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.byKey(const Key('first-run-start-chatting')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }
  if (find.byType(ChatScreen).evaluate().isEmpty) {
    fail('Chat screen did not become available.');
  }
}
