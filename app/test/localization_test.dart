import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/services/repository_resolver.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/settings/language_screen.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_en.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_pl.dart';
import 'package:golem_flutter/l10n/l10n.dart';
import 'package:golem_flutter/l10n/presentation_messages.dart';

import 'support/harness.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_preferences_repository.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';

void main() {
  test('English and Polish catalogs have identical resources', () {
    Map<String, Object?> catalog(String path) =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    final english = catalog('lib/l10n/app_en.arb')..remove('@@locale');
    final polish = catalog('lib/l10n/app_pl.arb')..remove('@@locale');
    final englishKeys = english.keys
        .where((key) => !key.startsWith('@'))
        .toSet();
    final polishKeys = polish.keys.where((key) => !key.startsWith('@')).toSet();
    expect(polishKeys, englishKeys);
    for (final key in englishKeys) {
      expect((polish[key] as String).trim(), isNotEmpty, reason: key);
      expect(english.containsKey('@$key'), isTrue, reason: key);
    }
  });

  test('locale resolution chooses Polish and falls back to English', () {
    expect(
      resolveAppLocale(const [
        Locale('pl', 'PL'),
      ], AppLocalizations.supportedLocales),
      const Locale('pl'),
    );
    expect(
      resolveAppLocale(const [
        Locale('de', 'DE'),
      ], AppLocalizations.supportedLocales),
      const Locale('en'),
    );
  });

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
    for (final reason in RepositoryRejection.values) {
      final english = repositoryRejectionMessage(en, reason);
      final polish = repositoryRejectionMessage(pl, reason);
      expect(english, isNotEmpty, reason: reason.name);
      expect(polish, isNotEmpty, reason: reason.name);
      expect(english, endsWith('.'), reason: reason.name);
      expect(polish, endsWith('.'), reason: reason.name);
      expect(polish, isNot(english), reason: reason.name);
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
      'The model needs 2.00 GB free, but only 0.40 GB is available.',
    );
    expect(
      artifactFailureMessage(pl, storage),
      'Model wymaga 2.00 GB wolnego miejsca, ale dostępne jest tylko 0.40 GB.',
    );
    expect(
      artifactFailureMessage(pl, hash),
      'Plik model.gguf nie przeszedł weryfikacji integralności. '
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
}
