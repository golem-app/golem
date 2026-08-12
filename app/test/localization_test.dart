import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/services/repository_resolver.dart';
import 'package:golem_flutter/core/theme/golem_typography.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';
import 'package:golem_flutter/features/settings/application/preferences_providers.dart';
import 'package:golem_flutter/features/settings/language_screen.dart';
import 'package:golem_flutter/l10n/bidi.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_ar.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_en.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_es.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_fr.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_hi.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_id.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_ja.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_ko.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_pl.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_pt.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_tr.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_vi.dart';
import 'package:golem_flutter/l10n/l10n.dart';
import 'package:golem_flutter/l10n/presentation_messages.dart';

import 'support/harness.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_preferences_repository.dart';

Map<String, Object?> _catalog(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

Set<String> _resourceKeys(Map<String, Object?> catalog) => catalog.keys
    .where((key) => key != '@@locale' && !key.startsWith('@'))
    .toSet();

Set<String> _placeholders(String message) => RegExp(
  r'\{([a-z][A-Za-z0-9_]*)\s*(?:,|\})',
).allMatches(message).map((match) => match.group(1)!).toSet();

/// Source-identical copy is limited to the product/speaker names, stable
/// endonyms, standardized units and parameters, and documented loanwords in
/// `docs/localization.md`. A new exception needs a product-language decision.
const _invariantCopyAllowlist = <String>{
  'appName',
  'assistantSpeaker',
  'languageEnglish',
  'languagePolish',
  'languageSpanish',
  'languageBrazilianPortuguese',
  'languageJapanese',
  'languageIndonesian',
  'languageHindi',
  'languageFrench',
  'languageVietnamese',
  'languageTurkish',
  'languageKorean',
  'languageArabic',
  'bytesDecimal',
  'megabytes',
  'samplingTopP',
  'samplingTopK',
  'styleSource',
  'tokenRate',
  // The ordinary Spanish negative response is spelled identically.
  'no',
  // Standard Indonesian technical loanwords.
  'settingsSectionModel',
  'settingsModel',
  'model',
  'prompt',
};

void main() {
  test('translated catalogs have exact keys, metadata, and placeholders', () {
    final english = _catalog('lib/l10n/app_en.arb');
    final englishKeys = _resourceKeys(english);
    final translations = <String, Map<String, Object?>>{
      'pl': _catalog('lib/l10n/app_pl.arb'),
      'ar': _catalog('lib/l10n/app_ar.arb'),
      'es': _catalog('lib/l10n/app_es.arb'),
      'pt': _catalog('lib/l10n/app_pt.arb'),
      'pt_BR': _catalog('lib/l10n/app_pt_BR.arb'),
      'ja': _catalog('lib/l10n/app_ja.arb'),
      'id': _catalog('lib/l10n/app_id.arb'),
      'hi': _catalog('lib/l10n/app_hi.arb'),
      'fr': _catalog('lib/l10n/app_fr.arb'),
      'vi': _catalog('lib/l10n/app_vi.arb'),
      'tr': _catalog('lib/l10n/app_tr.arb'),
      'ko': _catalog('lib/l10n/app_ko.arb'),
    };
    for (final key in englishKeys) {
      final metadata = english['@$key']! as Map<String, Object?>;
      final description = metadata['description'];
      expect(description, isA<String>(), reason: key);
      expect((description! as String).trim(), isNotEmpty, reason: key);
      final sourcePlaceholders = _placeholders(english[key]! as String);
      final documentedPlaceholders =
          ((metadata['placeholders'] as Map<String, Object?>?)?.keys.toSet() ??
          const <String>{});
      expect(documentedPlaceholders, sourcePlaceholders, reason: key);
    }
    for (final MapEntry(key: locale, value: translation)
        in translations.entries) {
      expect(_resourceKeys(translation), englishKeys, reason: locale);
      for (final key in englishKeys) {
        final translated = translation[key]! as String;
        expect(translated.trim(), isNotEmpty, reason: '$locale:$key');
        expect(
          _placeholders(translated),
          _placeholders(english[key]! as String),
          reason: '$locale:$key',
        );
      }
    }
    final pt = Map<String, Object?>.from(translations['pt']!)
      ..remove('@@locale');
    final ptBr = Map<String, Object?>.from(translations['pt_BR']!)
      ..remove('@@locale');
    expect(pt, ptBr, reason: 'Flutter-required pt fallback must mirror pt_BR');
    expect(translations['ar']!['settingsTitle'], 'الإعدادات');
    expect(translations['ar']!['privacyStatement'], contains('الخصوصية'));
  });

  test('new catalogs contain only documented source-identical copy', () {
    final english = _catalog('lib/l10n/app_en.arb');
    for (final locale in [
      'es',
      'pt_BR',
      'ja',
      'id',
      'hi',
      'fr',
      'vi',
      'tr',
      'ko',
    ]) {
      final translation = _catalog('lib/l10n/app_$locale.arb');
      for (final key in _resourceKeys(english)) {
        if (translation[key] == english[key]) {
          expect(
            _invariantCopyAllowlist,
            contains(key),
            reason: '$locale:$key unexpectedly retains English source copy',
          );
        }
      }
    }
  });

  test('language endonyms stay stable in every UI locale', () {
    final localizations = [
      AppLocalizationsEn(),
      AppLocalizationsPl(),
      AppLocalizationsAr(),
      AppLocalizationsEs(),
      AppLocalizationsPt(),
      AppLocalizationsPtBr(),
      AppLocalizationsJa(),
      AppLocalizationsId(),
      AppLocalizationsHi(),
      AppLocalizationsFr(),
      AppLocalizationsVi(),
      AppLocalizationsTr(),
      AppLocalizationsKo(),
    ];
    for (final l10n in localizations) {
      expect(l10n.languageEnglish, 'English');
      expect(l10n.languagePolish, 'Polski');
      expect(l10n.languageSpanish, 'Español (Latinoamérica)');
      expect(l10n.languageBrazilianPortuguese, 'Português (Brasil)');
      expect(l10n.languageJapanese, '日本語');
      expect(l10n.languageIndonesian, 'Bahasa Indonesia');
      expect(l10n.languageHindi, 'हिन्दी');
      expect(l10n.languageFrench, 'Français');
      expect(l10n.languageVietnamese, 'Tiếng Việt');
      expect(l10n.languageTurkish, 'Türkçe');
      expect(l10n.languageKorean, '한국어');
      expect(l10n.languageArabic, 'العربية');
    }
  });

  test('script-sensitive catalog and presentation rules stay intact', () {
    expect(
      localizedUppercase('gizlilik ve indirilenler', const Locale('tr')),
      'GİZLİLİK VE İNDİRİLENLER',
    );
    expect(localizedUppercase('निजता', const Locale('hi')), 'निजता');
    expect(localizedUppercase('개인정보 보호', const Locale('ko')), '개인정보 보호');
    expect(
      localizedLabelStyle(GolemText.overline, const Locale('hi')).letterSpacing,
      0,
    );
    expect(
      localizedLabelStyle(GolemText.badge, const Locale('ko')).letterSpacing,
      0,
    );
    expect(
      localizedLabelStyle(GolemText.overline, const Locale('fr')).letterSpacing,
      GolemText.overline.letterSpacing,
    );

    final vietnamese = File('lib/l10n/app_vi.arb').readAsStringSync();
    expect(vietnamese, isNot(matches(RegExp(r'[\u0300-\u036f]'))));
    expect(vietnamese, contains('Tiếng Việt'));

    final french = _catalog('lib/l10n/app_fr.arb');
    for (final key in _resourceKeys(french)) {
      expect(
        french[key]! as String,
        isNot(matches(RegExp(r' [?!;:]'))),
        reason: 'fr:$key must use non-breaking punctuation spacing',
      );
    }
    expect(french['deleteChatTitle'], contains('\u202f?'));
    expect(french['systemPromptExample'], contains('\u00a0:'));
  });

  test('Japanese fallback faces precede Korean CJK faces', () {
    final fallbacks = GolemFont.fallbacks;
    final appleJapanese = fallbacks.indexOf('Hiragino Sans');
    final androidJapanese = fallbacks.indexOf('Noto Sans CJK JP');
    final appleKorean = fallbacks.indexOf('Apple SD Gothic Neo');
    final androidKorean = fallbacks.indexOf('Noto Sans CJK KR');
    expect(appleJapanese, isNonNegative);
    expect(androidJapanese, isNonNegative);
    expect(appleJapanese, lessThan(appleKorean));
    expect(androidJapanese, lessThan(androidKorean));
  });

  test(
    'locale resolution handles exact, regional, ordered, and fallback cases',
    () {
      expect(AppLocalizations.supportedLocales.first, const Locale('en'));
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
          Locale('es', 'MX'),
        ], AppLocalizations.supportedLocales),
        const Locale('es'),
      );
      expect(
        resolveAppLocale(const [
          Locale('pt', 'BR'),
        ], AppLocalizations.supportedLocales),
        const Locale('pt', 'BR'),
      );
      expect(
        resolveAppLocale(const [
          Locale('pt', 'PT'),
        ], AppLocalizations.supportedLocales),
        const Locale('pt'),
      );
      expect(
        resolveAppLocale(const [
          Locale('ja', 'JP'),
        ], AppLocalizations.supportedLocales),
        const Locale('ja'),
      );
      expect(
        resolveAppLocale(const [
          Locale('id', 'ID'),
        ], AppLocalizations.supportedLocales),
        const Locale('id'),
      );
      for (final locale in const [
        (preferred: Locale('hi', 'IN'), resolved: Locale('hi')),
        (preferred: Locale('fr', 'CA'), resolved: Locale('fr')),
        (preferred: Locale('vi', 'VN'), resolved: Locale('vi')),
        (preferred: Locale('tr', 'TR'), resolved: Locale('tr')),
        (preferred: Locale('ko', 'KR'), resolved: Locale('ko')),
      ]) {
        expect(
          resolveAppLocale([
            locale.preferred,
          ], AppLocalizations.supportedLocales),
          locale.resolved,
        );
      }
      expect(
        resolveAppLocale(const [
          Locale('de', 'DE'),
          Locale('ja', 'JP'),
          Locale('es', 'AR'),
        ], AppLocalizations.supportedLocales),
        const Locale('ja'),
      );
      expect(
        resolveAppLocale(const [
          Locale('de', 'DE'),
        ], AppLocalizations.supportedLocales),
        const Locale('en'),
      );
      expect(
        resolveAppLocale(const [
          Locale('de', 'BR'),
        ], AppLocalizations.supportedLocales),
        const Locale('en'),
        reason: 'An unsupported language must not match pt-BR by country.',
      );
    },
  );

  test('global locale plural policy renders the relevant branches', () {
    final es = AppLocalizationsEs();
    final pt = AppLocalizationsPtBr();
    final ja = AppLocalizationsJa();
    final id = AppLocalizationsId();
    final hi = AppLocalizationsHi();
    final fr = AppLocalizationsFr();
    final vi = AppLocalizationsVi();
    final tr = AppLocalizationsTr();
    final ko = AppLocalizationsKo();
    expect(es.chatCount(0), 'No hay chats');
    expect(es.chatCount(1), '1 chat');
    expect(es.chatCount(2), '2 chats');
    expect(pt.chatCount(0), 'Nenhuma conversa');
    expect(pt.chatCount(1), '1 conversa');
    expect(pt.chatCount(2), '2 conversas');
    expect(ja.chatCount(0), 'チャットはありません');
    expect(ja.chatCount(1), '1件のチャット');
    expect(ja.chatCount(2), '2件のチャット');
    expect(id.chatCount(0), 'Tidak ada percakapan');
    expect(id.chatCount(1), '1 percakapan');
    expect(id.chatCount(2), '2 percakapan');
    expect(hi.chatCount(0), 'कोई चैट नहीं');
    expect(hi.chatCount(1), '1 चैट');
    expect(hi.chatCount(2), '2 चैट');
    expect(fr.chatCount(0), 'Aucune conversation');
    expect(fr.chatCount(1), '1 conversation');
    expect(fr.chatCount(2), '2 conversations');
    expect(fr.chatCount(1000000), '1000000 de conversations');
    expect(vi.chatCount(0), 'Không có cuộc trò chuyện');
    expect(vi.chatCount(1), '1 cuộc trò chuyện');
    expect(vi.chatCount(2), '2 cuộc trò chuyện');
    expect(tr.chatCount(0), 'Sohbet yok');
    expect(tr.chatCount(1), '1 sohbet');
    expect(tr.chatCount(2), '2 sohbet');
    expect(ko.chatCount(0), '대화 없음');
    expect(ko.chatCount(1), '대화 1개');
    expect(ko.chatCount(2), '대화 2개');
    for (final locale in ['es', 'pt_BR']) {
      final raw = _catalog('lib/l10n/app_$locale.arb')['chatCount']! as String;
      expect(raw, contains('one{'), reason: locale);
      expect(raw, contains('many{'), reason: locale);
      expect(raw, contains('other{'), reason: locale);
    }
    final french = _catalog('lib/l10n/app_fr.arb')['chatCount']! as String;
    expect(french, contains('one{'));
    expect(french, contains('many{'));
    expect(french, contains('other{'));
    for (final locale in ['hi', 'tr']) {
      final raw = _catalog('lib/l10n/app_$locale.arb')['chatCount']! as String;
      expect(raw, contains('one{'), reason: locale);
      expect(raw, isNot(contains('many{')), reason: locale);
      expect(raw, contains('other{'), reason: locale);
    }
    for (final locale in ['ja', 'id', 'vi', 'ko']) {
      final raw = _catalog('lib/l10n/app_$locale.arb')['chatCount']! as String;
      expect(raw, isNot(contains('one{')), reason: locale);
      expect(raw, isNot(contains('many{')), reason: locale);
      expect(raw, contains('other{'), reason: locale);
    }
  });

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

  test('every repository refusal has actionable localized copy', () {
    final en = AppLocalizationsEn();
    final translations = [
      AppLocalizationsPl(),
      AppLocalizationsAr(),
      AppLocalizationsEs(),
      AppLocalizationsPtBr(),
      AppLocalizationsJa(),
      AppLocalizationsId(),
      AppLocalizationsHi(),
      AppLocalizationsFr(),
      AppLocalizationsVi(),
      AppLocalizationsTr(),
      AppLocalizationsKo(),
    ];
    for (final reason in RepositoryRejection.values) {
      final english = repositoryRejectionMessage(en, reason);
      expect(english, isNotEmpty, reason: reason.name);
      expect(english, endsWith('.'), reason: reason.name);
      for (final l10n in translations) {
        final translated = repositoryRejectionMessage(l10n, reason);
        expect(translated, isNotEmpty, reason: '${l10n.localeName}:$reason');
        expect(
          translated,
          isNot(english),
          reason: '${l10n.localeName}:$reason',
        );
      }
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
    final es = AppLocalizationsEs();
    final pt = AppLocalizationsPtBr();
    final ja = AppLocalizationsJa();
    final id = AppLocalizationsId();
    final hi = AppLocalizationsHi();
    final fr = AppLocalizationsFr();
    final vi = AppLocalizationsVi();
    final tr = AppLocalizationsTr();
    final ko = AppLocalizationsKo();
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
    expect(
      artifactFailureMessage(es, storage),
      'El modelo necesita \u20662.00 GB\u2069 libres, pero solo hay '
      '\u20660.40 GB\u2069 disponibles.',
    );
    expect(
      artifactFailureMessage(pt, storage),
      'O modelo precisa de \u20662.00 GB\u2069 livres, mas somente '
      '\u20660.40 GB\u2069 estão disponíveis.',
    );
    expect(
      artifactFailureMessage(ja, storage),
      'モデルには\u20662.00 GB\u2069の空き容量が必要ですが、利用できるのは'
      '\u20660.40 GB\u2069のみです。',
    );
    expect(
      artifactFailureMessage(id, storage),
      'Model memerlukan ruang kosong \u20662.00 GB\u2069, tetapi hanya '
      '\u20660.40 GB\u2069 yang tersedia.',
    );
    for (final l10n in [pl, es, pt, ja, id, hi, fr, vi, tr, ko]) {
      expect(
        artifactFailureMessage(l10n, hash),
        contains('\u2066model.gguf\u2069'),
        reason: l10n.localeName,
      );
      expect(
        artifactFailureMessage(l10n, storage),
        isNot(contains('raw')),
        reason: l10n.localeName,
      );
    }
  });

  test('inference failure copy is localized without diagnostic leakage', () {
    final en = AppLocalizationsEn();
    for (final l10n in [
      AppLocalizationsEs(),
      AppLocalizationsPtBr(),
      AppLocalizationsJa(),
      AppLocalizationsId(),
      AppLocalizationsHi(),
      AppLocalizationsFr(),
      AppLocalizationsVi(),
      AppLocalizationsTr(),
      AppLocalizationsKo(),
    ]) {
      expect(l10n.generationFailed, isNot(en.generationFailed));
      expect(l10n.contextExhausted, isNot(en.contextExhausted));
      expect(l10n.outOfMemory, isNot(en.outOfMemory));
      expect(l10n.insufficientMemory, isNot(en.insufficientMemory));
      expect(l10n.budgetExhausted, isNot(en.budgetExhausted));
      expect(l10n.generationFailed, isNot(contains('raw diagnostic')));
    }
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
      const newCodes = <String, AppLanguage>{
        'es': AppLanguage.spanish,
        'pt-BR': AppLanguage.brazilianPortuguese,
        'ja': AppLanguage.japanese,
        'id': AppLanguage.indonesian,
        'hi': AppLanguage.hindi,
        'fr': AppLanguage.french,
        'vi': AppLanguage.vietnamese,
        'tr': AppLanguage.turkish,
        'ko': AppLanguage.korean,
      };
      for (final MapEntry(key: code, value: language) in newCodes.entries) {
        final decoded = AppPreferences.fromJson({
          'schemaVersion': 5,
          'language': code,
        });
        expect(decoded.language, language, reason: code);
        expect(
          AppPreferences(language: language).toJson()['language'],
          code,
          reason: code,
        );
      }
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

    await tester.scrollUntilVisible(
      find.byKey(const Key('language-arabic')),
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('language-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.byKey(const Key('language-arabic')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-arabic')));
    await tester.pumpAndSettle();
    expect((await repository.load()).language, AppLanguage.arabic);
  });
}
