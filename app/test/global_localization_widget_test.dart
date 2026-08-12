import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/chat/widgets/attach_sheet.dart';
import 'package:golem_flutter/features/chat/widgets/recovery_banner.dart';
import 'package:golem_flutter/features/onboarding/model_download_consent.dart';
import 'package:golem_flutter/features/settings/language_screen.dart';
import 'package:golem_flutter/features/settings/models_screen.dart';
import 'package:golem_flutter/features/settings/settings_screen.dart';
import 'package:golem_flutter/l10n/generated/app_localizations.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_en.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_es.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_id.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_ja.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_pt.dart';

import 'support/harness.dart';
import 'support/in_memory_preferences_repository.dart';

const _localeCases = [
  (
    name: 'Spanish',
    locale: Locale('es'),
    language: AppLanguage.spanish,
    rowKey: 'language-spanish',
    endonym: 'Español (Latinoamérica)',
  ),
  (
    name: 'Brazilian Portuguese',
    locale: Locale('pt', 'BR'),
    language: AppLanguage.brazilianPortuguese,
    rowKey: 'language-brazilian-portuguese',
    endonym: 'Português (Brasil)',
  ),
  (
    name: 'Japanese',
    locale: Locale('ja'),
    language: AppLanguage.japanese,
    rowKey: 'language-japanese',
    endonym: '日本語',
  ),
  (
    name: 'Indonesian',
    locale: Locale('id'),
    language: AppLanguage.indonesian,
    rowKey: 'language-indonesian',
    endonym: 'Bahasa Indonesia',
  ),
];

AppLocalizations _localizations(Locale locale) => switch (locale.languageCode) {
  'es' => AppLocalizationsEs(),
  'pt' => AppLocalizationsPtBr(),
  'ja' => AppLocalizationsJa(),
  'id' => AppLocalizationsId(),
  _ => throw ArgumentError.value(locale),
};

void main() {
  const progressState = ModelState(
    artifacts: {
      'gemma4-gguf': ArtifactStatus(
        phase: ArtifactPhase.downloading,
        downloadedBytes: 1200000000,
      ),
    },
    simulated: true,
  );

  for (final localeCase in _localeCases) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${localeCase.name} major surfaces at 1.6x ${brightness.name}',
        (tester) async {
          final l10n = _localizations(localeCase.locale);
          final preferences = InMemoryPreferencesRepository(
            AppPreferences(language: localeCase.language),
          );

          await pumpWithRepositories(
            tester,
            brightness: brightness,
            locale: localeCase.locale,
            textScale: 1.6,
            preferences: preferences,
            child: const LanguageScreen(),
          );
          expect(find.text(l10n.settingsLanguage), findsWidgets);
          expect(find.text(localeCase.endonym), findsOneWidget);
          await tester.ensureVisible(find.byKey(Key(localeCase.rowKey)));
          await tester.pumpAndSettle();
          final selectedRows = tester
              .widgetList<Semantics>(find.byType(Semantics))
              .where(
                (widget) =>
                    widget.properties.selected == true &&
                    widget.properties.value ==
                        l10n.languageSelected(localeCase.endonym),
              );
          expect(selectedRows, isNotEmpty);
          expect(tester.takeException(), isNull);

          await pumpWithRepositories(
            tester,
            brightness: brightness,
            locale: localeCase.locale,
            textScale: 1.6,
            preferences: preferences,
            child: const SettingsScreen(identity: AppIdentity.qa),
          );
          expect(find.text(l10n.settingsTitle), findsWidgets);
          await _scrollToKey(
            tester,
            listKey: const Key('settings-list'),
            targetKey: const Key('settings-language-row'),
          );
          expect(find.text(localeCase.endonym), findsOneWidget);
          expect(tester.takeException(), isNull);

          await pumpWithRepositories(
            tester,
            brightness: brightness,
            locale: localeCase.locale,
            textScale: 1.6,
            preferences: preferences,
            model: progressState,
            child: const ModelsScreen(),
          );
          await _scrollToKey(
            tester,
            listKey: const Key('models-list'),
            targetKey: const Key('model-progress-gemma4-gguf'),
          );
          expect(
            find.byKey(const Key('model-progress-gemma4-gguf')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          await pumpWithRepositories(
            tester,
            brightness: brightness,
            locale: localeCase.locale,
            textScale: 1.6,
            child: const CupertinoPageScaffold(
              child: SafeArea(
                child: RecoveryBanner(
                  failure: ChatFailure(
                    kind: ChatFailureKind.outOfMemory,
                    contextTokens: 4096,
                  ),
                ),
              ),
            ),
          );
          expect(find.text(l10n.outOfMemoryAtContext(4096)), findsOneWidget);
          expect(
            find.text(AppLocalizationsEn().outOfMemoryAtContext(4096)),
            findsNothing,
          );
          expect(tester.takeException(), isNull);

          await pumpWithRepositories(
            tester,
            brightness: brightness,
            locale: localeCase.locale,
            textScale: 1.6,
            child: const _OverlayHost(),
          );
          await tester.tap(find.byKey(const Key('open-localized-dialog')));
          await tester.pumpAndSettle();
          expect(find.text(l10n.simulateDownloadTitle), findsOneWidget);
          expect(find.text(l10n.notNow), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('model-download-not-now')));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('open-localized-sheet')));
          await tester.pumpAndSettle();
          expect(find.text(l10n.addToChat), findsOneWidget);
          expect(find.bySemanticsLabel(l10n.photoLibrary), findsWidgets);
          expect(find.bySemanticsLabel(l10n.takePhoto), findsWidgets);
          expect(find.bySemanticsLabel(l10n.files), findsWidgets);
          expect(tester.takeException(), isNull);
        },
        variant: bothChromes,
      );
    }
  }
}

Future<void> _scrollToKey(
  WidgetTester tester, {
  required Key listKey,
  required Key targetKey,
}) async {
  final scrollable = find
      .descendant(of: find.byKey(listKey), matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(
    find.byKey(targetKey),
    220,
    scrollable: scrollable,
  );
  await tester.ensureVisible(find.byKey(targetKey));
  await tester.pumpAndSettle();
}

class _OverlayHost extends StatelessWidget {
  const _OverlayHost();

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              key: const Key('open-localized-dialog'),
              onPressed: () => confirmModelDownload(
                context: context,
                entry: modelCatalog.first,
                simulated: true,
              ),
              child: const Text('dialog'),
            ),
            CupertinoButton(
              key: const Key('open-localized-sheet'),
              onPressed: () => showAttachSheet(
                context,
                modelLabel: modelCatalog.first.displayName,
                supportsImages: true,
              ),
              child: const Text('sheet'),
            ),
          ],
        ),
      ),
    ),
  );
}
