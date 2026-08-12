import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/services/repository_resolver.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';
import 'package:golem_flutter/features/settings/application/preferences_providers.dart';
import 'package:golem_flutter/features/settings/language_screen.dart';
import 'package:golem_flutter/l10n/bidi.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_ar.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_en.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_pl.dart';
import 'package:golem_flutter/l10n/l10n.dart';
import 'package:golem_flutter/l10n/presentation_messages.dart';

import 'support/harness.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_preferences_repository.dart';

void main() {
  test('translated catalogs have complete non-empty resources', () {
    Map<String, Object?> catalog(String path) =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    final english = catalog('lib/l10n/app_en.arb')..remove('@@locale');
    final polish = catalog('lib/l10n/app_pl.arb')..remove('@@locale');
    final arabic = catalog('lib/l10n/app_ar.arb')..remove('@@locale');
    final englishKeys = english.keys
        .where((key) => !key.startsWith('@'))
        .toSet();
    final polishKeys = polish.keys.where((key) => !key.startsWith('@')).toSet();
    final arabicKeys = arabic.keys.where((key) => !key.startsWith('@')).toSet();
    for (final translation in [polish, arabic]) {
      final translatedKeys = translation.keys
          .where((key) => !key.startsWith('@'))
          .toSet();
      expect(translatedKeys, englishKeys);
      for (final key in englishKeys) {
        expect((translation[key] as String).trim(), isNotEmpty, reason: key);
        expect(english.containsKey('@$key'), isTrue, reason: key);
      }
    }
    expect(polishKeys, englishKeys);
    expect(arabicKeys, englishKeys);
    expect(arabic['settingsTitle'], 'الإعدادات');
    expect(arabic['privacyStatement'], contains('الخصوصية'));
  });

  test(
    'locale resolution chooses Polish and Arabic and falls back to English',
    () {
      expect(
        resolveAppLocale(const [
          Locale('pl', 'PL'),
        ], AppLocalizations.supportedLocales),
        const Locale('pl'),
      );
      expect(
        resolveAppLocale(const [
          Locale('ar', 'SA'),
        ], AppLocalizations.supportedLocales),
        const Locale('ar'),
      );
      expect(
        resolveAppLocale(const [
          Locale('de', 'DE'),
        ], AppLocalizations.supportedLocales),
        const Locale('en'),
      );
    },
  );

  test('Arabic plural categories render zero, one, two, few, many, other', () {
    final ar = AppLocalizationsAr();
    expect(ar.chatCount(0), 'لا محادثات');
    expect(ar.chatCount(1), 'محادثة واحدة');
    expect(ar.chatCount(2), 'محادثتان');
    expect(ar.chatCount(3), '3 محادثات');
    expect(ar.chatCount(11), '11 محادثة');
    expect(ar.chatCount(102), '102 محادثة');
  });

  test(
    'content direction uses first strong text and technical values isolate',
    () {
      expect(contentTextDirection('مرحبا API'), TextDirection.rtl);
      expect(contentTextDirection('API مرحبا'), TextDirection.ltr);
      expect(
        contentTextDirection('123', fallback: TextDirection.rtl),
        TextDirection.rtl,
      );
      expect(ltrIsolate('model.gguf'), '\u2066model.gguf\u2069');
    },
  );

  test('Polish plural categories render correctly', () {
    final pl = AppLocalizationsPl();
    expect(pl.chatCount(0), 'Brak czatów');
    expect(pl.chatCount(1), '1 czat');
    expect(pl.chatCount(2), '2 czaty');
    expect(pl.chatCount(5), '5 czatów');
    expect(pl.chatCount(12), '12 czatów');
    expect(pl.chatCount(22), '22 czaty');
    expect(pl.chatCount(25), '25 czatów');
  });

  test('every repository refusal has actionable English and Polish copy', () {
    final en = AppLocalizationsEn();
    final pl = AppLocalizationsPl();
    final ar = AppLocalizationsAr();
    for (final reason in RepositoryRejection.values) {
      final english = repositoryRejectionMessage(en, reason);
      final polish = repositoryRejectionMessage(pl, reason);
      final arabic = repositoryRejectionMessage(ar, reason);
      expect(english, isNotEmpty, reason: reason.name);
      expect(polish, isNotEmpty, reason: reason.name);
      expect(english, endsWith('.'), reason: reason.name);
      expect(polish, endsWith('.'), reason: reason.name);
      expect(polish, isNot(english), reason: reason.name);
      expect(arabic, isNotEmpty, reason: reason.name);
      expect(arabic, isNot(english), reason: reason.name);
      // User copy must not leak URLs or HTTP status codes from diagnostics.
      expect(english, isNot(contains('http')), reason: reason.name);
      expect(
        english,
        isNot(matches(RegExp(r'\b[45]\d\d\b'))),
        reason: reason.name,
      );
    }
  });

  test('download failures preserve localized actionable parameters', () {
    final en = AppLocalizationsEn();
    final pl = AppLocalizationsPl();
    const storage = ArtifactStatus(
      phase: ArtifactPhase.failed,
      failure: 'raw diagnostic must stay hidden',
      failureReason: ArtifactFailure(
        ArtifactFailureKind.insufficientStorage,
        requiredBytes: 2000000000,
        availableBytes: 400000000,
      ),
    );
    const hash = ArtifactStatus(
      phase: ArtifactPhase.failed,
      failureReason: ArtifactFailure(
        ArtifactFailureKind.hashVerification,
        fileName: 'model.gguf',
      ),
    );
    expect(
      artifactFailureMessage(en, storage),
      'The model needs \u20662.00 GB\u2069 free, but only '
      '\u20660.40 GB\u2069 is available.',
    );
    expect(
      artifactFailureMessage(pl, storage),
      'Model wymaga \u20662.00 GB\u2069 wolnego miejsca, ale dostępne jest '
      'tylko \u20660.40 GB\u2069.',
    );
    expect(
      artifactFailureMessage(pl, hash),
      'Plik \u2066model.gguf\u2069 nie przeszedł weryfikacji integralności. '
      'Ponów pobieranie.',
    );
    expect(artifactFailureMessage(pl, storage), isNot(contains('raw')));
  });

  test(
    'language preference is sparse, migrates, and rejects unknown codes',
    () {
      expect(
        AppPreferences.fromJson(const {'schemaVersion': 4}).language,
        AppLanguage.system,
      );
      expect(
        AppPreferences.fromJson(const {
          'schemaVersion': 5,
          'language': 'pl',
        }).language,
        AppLanguage.polish,
      );
      expect(
        AppPreferences.fromJson(const {
          'schemaVersion': 5,
          'language': 'ar',
        }).language,
        AppLanguage.arabic,
      );
      expect(
        AppPreferences.fromJson(const {
          'schemaVersion': 5,
          'language': 'xx',
        }).language,
        AppLanguage.system,
      );
      expect(const AppPreferences().toJson().containsKey('language'), isFalse);
      expect(
        const AppPreferences(
          language: AppLanguage.english,
        ).toJson()['language'],
        'en',
      );
      expect(
        const AppPreferences(language: AppLanguage.arabic).toJson()['language'],
        'ar',
      );
    },
  );

  test(
    'changing language does not invalidate the effective model catalog',
    () async {
      final repository = InMemoryPreferencesRepository();
      final container = buildContainer(preferences: repository);
      addTearDown(container.dispose);
      await container.read(preferencesControllerProvider.future);
      final catalog = container.read(effectiveModelCatalogProvider);
      var rebuilds = 0;
      final subscription = container.listen(
        effectiveModelCatalogProvider,
        (_, _) => rebuilds += 1,
      );
      addTearDown(subscription.close);

      expect(
        await container
            .read(preferencesControllerProvider.notifier)
            .setLanguage(AppLanguage.polish),
        isTrue,
      );
      expect(container.read(effectiveModelCatalogProvider), same(catalog));
      expect(rebuilds, 0);
    },
  );

  testWidgets('Language screen renders Polish and changes the persisted code', (
    tester,
  ) async {
    final repository = InMemoryPreferencesRepository(
      const AppPreferences(language: AppLanguage.polish),
    );
    await pumpWithRepositories(
      tester,
      locale: const Locale('pl'),
      preferences: repository,
      child: const LanguageScreen(),
    );
    expect(find.text('Język'), findsWidgets);
    expect(find.text('Domyślny systemu'), findsOneWidget);
    expect(find.text('Polski'), findsOneWidget);

    await tester.tap(find.byKey(const Key('language-english')));
    await tester.pumpAndSettle();
    expect((await repository.load()).language, AppLanguage.english);
  });

  testWidgets('untitled rename uses a Polish placeholder and stays semantic', (
    tester,
  ) async {
    final conversation = ChatConversation(
      id: 'untitled',
      title: '',
      messages: const [],
      updatedAt: DateTime.utc(2026, 8, 12),
    );
    final history = InMemoryChatHistoryRepository(
      ChatHistorySnapshot(
        conversations: [conversation],
        activeId: conversation.id,
      ),
    );
    await pumpWithRepositories(
      tester,
      locale: const Locale('pl'),
      chatHistory: history,
      child: const ChatScreen(),
    );
    await tester.tap(find.byKey(const Key('open-drawer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation-menu-untitled')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-rename')));
    await tester.pumpAndSettle();

    final field = tester.widget<CupertinoTextField>(
      find.byKey(const Key('rename-field')),
    );
    expect(field.controller!.text, isEmpty);
    expect(field.placeholder, 'Nowy czat');

    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();
    expect(history.snapshot.conversations.single.title, isEmpty);
  });

  testWidgets('Polish language screen survives large text and RTL', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      locale: const Locale('pl'),
      textScale: 1.6,
      preferences: InMemoryPreferencesRepository(
        const AppPreferences(language: AppLanguage.polish),
      ),
      child: const Directionality(
        textDirection: TextDirection.rtl,
        child: LanguageScreen(),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(AppLocalizationsEn().languageEnglish), findsOneWidget);
  });

  testWidgets('Arabic selection renders RTL and persists immediately', (
    tester,
  ) async {
    final repository = InMemoryPreferencesRepository();
    await pumpWithRepositories(
      tester,
      locale: const Locale('ar'),
      textScale: 1.6,
      preferences: repository,
      child: const LanguageScreen(),
    );
    expect(
      Directionality.of(tester.element(find.byType(LanguageScreen))),
      TextDirection.rtl,
    );
    expect(find.text('العربية'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('language-arabic')));
    await tester.pumpAndSettle();
    expect((await repository.load()).language, AppLanguage.arabic);
  });
}
