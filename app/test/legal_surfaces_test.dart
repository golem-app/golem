import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/features/legal/license_registry.dart';
import 'package:golem_flutter/features/legal/model_attribution_screen.dart';
import 'package:golem_flutter/features/legal/open_source_licenses_screen.dart';
import 'package:golem_flutter/features/onboarding/first_run_screen.dart';
import 'package:golem_flutter/features/settings/settings_screen.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_en.dart';

import 'support/harness.dart';

void main() {
  test('every pinned Swift package has an exact bundled declaration', () {
    final resolved =
        jsonDecode(
              File(
                '../packages/inferno/native/apple/Package.resolved',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final pins = resolved['pins']! as List<Object?>;
    final actual = <String, String>{
      for (final pin in pins.cast<Map<String, Object?>>())
        pin['identity']! as String:
            (pin['state']! as Map<String, Object?>)['revision']! as String,
    };
    final declared = <String, String>{
      for (final license in swiftPackageLicenseDeclarations)
        license.identity: license.revision,
    };

    expect(declared, actual);
  });

  test('the llama declaration follows the build pin and compiled graph', () {
    final manifest = File(
      '../packages/inferno/lib/src/model_manifest.dart',
    ).readAsStringSync();
    final cmake = File(
      '../packages/inferno/native/llama/CMakeLists.txt',
    ).readAsStringSync();
    final shim = File(
      '../packages/inferno/native/src/llama_shim.cpp',
    ).readAsStringSync();

    expect(manifest, contains("const llamaCppRevision = '$llamaCppRevision'"));
    expect(cmake, contains('set(LLAMA_BUILD_MTMD ON'));
    expect(cmake, contains('set(MTMD_VIDEO OFF'));
    expect(cmake, contains('set(LLAMA_CURL OFF'));
    expect(shim, contains('#include "nlohmann/json.hpp"'));
    expect(llamaLicenseDeclarations.map((entry) => entry.identity).toSet(), {
      'llama.cpp',
      'nlohmann-json',
      'stb',
      'miniaudio',
    });
    for (final declaration in llamaLicenseDeclarations) {
      expect(declaration.revision, llamaCppRevision);
    }
  });

  test('every declared license asset exists and contains text', () {
    for (final declaration in bundledLicenseDeclarations) {
      expect(declaration.assetPaths, isNotEmpty, reason: declaration.identity);
      for (final path in declaration.assetPaths) {
        final asset = File(path);
        expect(asset.existsSync(), isTrue, reason: path);
        expect(asset.readAsStringSync().trim(), isNotEmpty, reason: path);
      }
    }
  });

  test('the model license is Apache 2.0 without a Swift exception', () {
    final license = File(
      'assets/licenses/model-apache-2.0-license.txt',
    ).readAsStringSync();

    expect(license, contains('Apache License'));
    expect(license, contains('Version 2.0, January 2004'));
    expect(license, isNot(contains('Runtime Library Exception')));
    expect(license.trim(), endsWith('limitations under the License.'));
  });

  test('pinned artifacts produce complete family attribution', () {
    final families = modelAttributionsFor(modelCatalog);

    expect(families.map((family) => family.title), ['Gemma 4 E2B', 'Qwen 3.5']);
    expect(
      families.every((family) => family.licenseName == 'Apache 2.0'),
      isTrue,
    );
    expect(families.first.sources, hasLength(3));
    expect(families.last.sources, hasLength(6));
    expect(
      families
          .expand((family) => family.sources)
          .every((source) => source.revision.length == 40),
      isTrue,
    );
  });

  testWidgets('the disclaimer is visible before setup and in Settings', (
    tester,
  ) async {
    await pumpWithRepositories(tester, child: const FirstRunScreen());
    expect(find.byKey(const Key('first-run-ai-disclaimer')), findsOneWidget);
    expect(find.text(AppLocalizationsEn().aiDisclaimer), findsOneWidget);

    await pumpWithRepositories(
      tester,
      child: const SettingsScreen(identity: AppIdentity.dev),
    );
    expect(find.byKey(const Key('settings-ai-disclaimer')), findsOneWidget);
    expect(find.text(AppLocalizationsEn().aiDisclaimer), findsOneWidget);
    final list = find
        .descendant(
          of: find.byKey(const Key('settings-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('model-attribution-row')),
      240,
      scrollable: list,
    );
    expect(find.byKey(const Key('model-attribution-row')), findsOneWidget);
    expect(find.byKey(const Key('open-source-licenses-row')), findsOneWidget);
  }, variant: iosChrome);

  testWidgets('model attribution opens the official sources', (tester) async {
    final opened = <Uri>[];
    await pumpWithRepositories(
      tester,
      child: ModelAttributionScreen(
        openUri: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );

    expect(find.text('GEMMA 4 E2B'), findsOneWidget);
    expect(find.text('Google DeepMind'), findsOneWidget);
    await tester.tap(find.text('Official model card').first);
    await tester.pump();
    expect(opened.single.host, 'huggingface.co');
    expect(opened.single.path, '/google/gemma-4-E2B-it');
  }, variant: iosChrome);

  testWidgets('licenses expand inline', (tester) async {
    await pumpWithRepositories(
      tester,
      child: OpenSourceLicensesScreen(
        loadLicenses: () async => [
          OpenSourceLicense(
            packages: const ['Example package'],
            text: 'Example license body',
          ),
        ],
      ),
    );

    expect(find.text('Example package'), findsOneWidget);
    expect(find.text('Example license body'), findsNothing);
    await tester.tap(find.text('Example package'));
    await tester.pumpAndSettle();
    expect(find.text('Example license body'), findsOneWidget);
  }, variant: iosChrome);

  testWidgets('a license load failure retries', (tester) async {
    var attempts = 0;
    Future<List<OpenSourceLicense>> load() async {
      attempts++;
      if (attempts == 1) throw StateError('injected');
      return [
        OpenSourceLicense(
          packages: const ['Recovered package'],
          text: 'Recovered license',
        ),
      ];
    }

    await pumpWithRepositories(
      tester,
      child: OpenSourceLicensesScreen(loadLicenses: load),
    );
    expect(find.byKey(const Key('licenses-error')), findsOneWidget);
    await tester.tap(find.byKey(const Key('licenses-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Recovered package'), findsOneWidget);
    expect(attempts, 2);
  }, variant: iosChrome);

  testWidgets('legal screens meet accessibility and scaling baselines', (
    tester,
  ) async {
    final licenses = OpenSourceLicensesScreen(
      loadLicenses: () async => [
        OpenSourceLicense(
          packages: const ['Example package'],
          text: 'Example license body',
        ),
      ],
    );
    for (final screen in <Widget>[const ModelAttributionScreen(), licenses]) {
      await pumpWithRepositories(tester, child: screen);
      await expectLater(tester, meetsGuideline(tapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await pumpWithRepositories(
        tester,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: const MediaQueryData(
              size: viewport,
              textScaler: TextScaler.linear(1.3),
            ),
            child: screen,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  }, variant: bothChromes);
}
