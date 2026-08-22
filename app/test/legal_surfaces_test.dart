import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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

/// The keys of `app/pubspec.yaml`'s `dependencies:` block, read as text
/// rather than through a yaml parser the app does not otherwise need.
Set<String> _directDependencies() {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final start = lines.indexOf('dependencies:');
  final end = lines.indexOf('dev_dependencies:');
  // Without this, a restructured pubspec silently parses the wrong block —
  // `environment:`'s own keys match the same indent — and the guard reports a
  // bogus dependency set instead of naming the parse.
  expect(
    start >= 0 && end > start,
    isTrue,
    reason: 'pubspec.yaml has no dependencies: block before dev_dependencies:',
  );
  return {
    for (final line in lines.sublist(start + 1, end))
      if (RegExp(r'^  ([a-z0-9_]+):').firstMatch(line) case final match?)
        match.group(1)!,
  };
}

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
    for (final declaration in bundledLicenseDeclarationsFor(apple: true)) {
      expect(declaration.assetPaths, isNotEmpty, reason: declaration.identity);
      for (final path in declaration.assetPaths) {
        final asset = File(path);
        expect(asset.existsSync(), isTrue, reason: path);
        expect(asset.readAsStringSync().trim(), isNotEmpty, reason: path);
      }
    }
  });

  test('pinned artifacts produce complete family attribution', () {
    final families = modelAttributionsFor(modelCatalog);

    expect(families.map((family) => family.title), ['Gemma 4 E2B', 'Qwen 3.5']);
    expect(
      families.every((family) => family.licenseName == 'Apache-2.0'),
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

  test('the declared list accounts for every direct dependency', () {
    // Neither exclusion reaches Flutter's collector: `inferno` is first-party
    // and ships no LICENSE file (its notices are the bundled declarations),
    // and `flutter_localizations` is an SDK package whose notice is filed
    // under `flutter`. Both were verified against a built NOTICES bundle.
    expect(
      directRuntimeLicensePackages.toSet(),
      _directDependencies()
        ..remove('inferno')
        ..remove('flutter_localizations'),
    );
    expect(
      directRuntimeLicensePackages,
      hasLength(directRuntimeLicensePackages.toSet().length),
    );
  });

  test('the declared list opens on the engine and covers every manifest', () {
    final declared = declaredLicensePackagesFor(apple: true);

    expect(declared.take(4), [
      'llama.cpp',
      'nlohmann/json',
      'stb_image',
      'miniaudio',
    ]);
    for (final declaration in bundledLicenseDeclarationsFor(apple: true)) {
      expect(
        declared,
        contains(declaration.displayName),
        reason: declaration.identity,
      );
    }
    expect(
      declared,
      hasLength(
        bundledLicenseDeclarationsFor(apple: true).length +
            directRuntimeLicensePackages.length,
      ),
    );
  });

  test('the Swift graph is disclosed only where the MLX carrier is built', () {
    // The gate is held to the build system rather than restated beside it: if
    // the carrier ever builds for another OS, this fails and the licenses
    // decision has to be revisited (#144).
    // Matched on the condition's parts rather than its exact spelling, so a
    // reformat or a renamed local does not fail while a dropped half does.
    final hook = File(
      '../packages/inferno/hook/build.dart',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
    final carrierGate = RegExp(
      r'if \([^)]*OS\.iOS[^)]*OS\.macOS[^{]*Architecture\.arm64[^{]*\) \{',
    ).firstMatch(hook);

    expect(
      carrierGate,
      isNotNull,
      reason:
          'The MLX carrier is no longer gated on Apple *and* arm64. The '
          'licenses screen mirrors that condition in runningOnApplePlatform; '
          'both have to move together or a build discloses a graph it does '
          'not link.',
    );

    final apple = declaredLicensePackagesFor(apple: true);
    final portable = declaredLicensePackagesFor(apple: false);
    for (final declaration in swiftPackageLicenseDeclarations) {
      expect(apple, contains(declaration.displayName));
      expect(
        portable,
        isNot(contains(declaration.displayName)),
        reason: declaration.identity,
      );
    }
    for (final declaration in llamaLicenseDeclarations) {
      expect(portable, contains(declaration.displayName));
    }
    expect(portable, containsAll(directRuntimeLicensePackages));
  });

  test('each declaration states the license its own asset carries', () {
    // Restores and generalizes the Swift-exception guard: text-sniffing reads
    // every one of these as a bare family, and six of them are not.
    for (final declaration in bundledLicenseDeclarationsFor(apple: true)) {
      final text = declaration.assetPaths
          .map((path) => File(path).readAsStringSync())
          .join('\n\n');
      final reason = declaration.identity;

      expect(
        text.contains('Runtime Library Exception'),
        declaration.kind.contains('WITH Swift-exception'),
        reason: reason,
      );

      // Every operand of the expression is checked, and an expression this
      // does not recognize fails rather than passing silently — otherwise a
      // swapped or invented kind sails through every branch.
      for (final operand in declaration.kind.split(' OR ')) {
        switch (operand) {
          case 'MIT' || 'MIT-0':
            expect(
              text,
              contains('Permission is hereby granted'),
              reason: reason,
            );
          case 'Unlicense':
            expect(text, contains('public domain'), reason: reason);
          case final apache when apache.startsWith('Apache-2.0'):
            expect(text, contains('Apache License'), reason: reason);
            expect(text, contains('Version 2.0'), reason: reason);
          default:
            fail('$reason declares an unrecognized kind: $operand');
        }
      }
      if (declaration.kind.contains(' OR ')) {
        expect(text, contains('ALTERNATIVE'), reason: reason);
      }
    }
  });

  test('model weights are attributed, not disclosed as bundled software', () {
    // Golem downloads weights after consent instead of redistributing them,
    // so no bundled-notice obligation attaches; the Model attribution screen
    // names the license and links the canonical text (ADR 0009).
    for (final name in ['Gemma 4 E2B model', 'Qwen 3.5 models']) {
      expect(declaredLicensePackagesFor(apple: true), isNot(contains(name)));
    }
    expect(
      bundledLicenseDeclarationsFor(apple: true).map((entry) => entry.identity),
      isNot(contains('gemma-4-e2b')),
    );
    expect(
      File('assets/licenses/model-apache-2.0-license.txt').existsSync(),
      isFalse,
    );
  });

  group('the loader', () {
    // A transitive pub package, an engine third-party entry, a model
    // declaration and an Apple-only package — everything the screen must not
    // render off Apple. Injected, so the process-wide registry is untouched.
    Stream<LicenseEntry> registry() async* {
      yield const LicenseEntryWithLineBreaks(['petitparser'], 'transitive');
      yield const LicenseEntryWithLineBreaks(['skia'], 'engine');
      yield const LicenseEntryWithLineBreaks(['Gemma 4 E2B model'], 'weights');
      yield const LicenseEntryWithLineBreaks(['mlx-swift'], 'apple only');
      yield const LicenseEntryWithLineBreaks(['go_router'], 'direct');
      yield const LicenseEntryWithLineBreaks(['llama.cpp'], 'bundled');
    }

    test('renders the declared manifests and nothing else', () async {
      final licenses = await loadRegisteredLicenses(
        licenses: registry(),
        apple: true,
      );

      expect(licenses.map((license) => license.title), [
        'llama.cpp',
        'mlx-swift',
        'go_router',
      ]);
    });

    test('drops the Swift graph off Apple', () async {
      final licenses = await loadRegisteredLicenses(
        licenses: registry(),
        apple: false,
      );

      expect(licenses.map((license) => license.title), [
        'llama.cpp',
        'go_router',
      ]);
    });

    test('defaults to the process registry and this platform', () async {
      // The only coverage of both `??` arms: every other test injects them,
      // so a mis-wired default would otherwise reach a device unnoticed.
      addTearDown(LicenseRegistry.reset);
      LicenseRegistry.reset();
      registerGolemLicenses(apple: false);

      final licenses = await loadRegisteredLicenses();

      expect(
        licenses.map((license) => license.title),
        llamaLicenseDeclarations.map((entry) => entry.displayName),
        reason:
            'The suite runs on an arm64 Mac, so the default gate is Apple '
            'and the registry holds only what registerGolemLicenses added.',
      );
      expect(licenses.first.kind, 'MIT');
    });

    test('states the authored kind and withholds a contested one', () async {
      Stream<LicenseEntry> mixed() async* {
        // `stb_image` sniffs as bare MIT and is actually dual-licensed;
        // `flutter` files several documents that do not agree.
        yield const LicenseEntryWithLineBreaks([
          'stb_image',
        ], 'Permission is hereby granted');
        yield const LicenseEntryWithLineBreaks([
          'flutter',
        ], 'Redistribution and use ... Neither the name');
        yield const LicenseEntryWithLineBreaks([
          'flutter',
        ], 'Permission is hereby granted');
        yield const LicenseEntryWithLineBreaks([
          'go_router',
        ], 'Redistribution and use ... Neither the name');
      }

      final byTitle = {
        for (final license in await loadRegisteredLicenses(
          licenses: mixed(),
          apple: false,
        ))
          license.title: license.kind,
      };

      expect(byTitle['stb_image'], 'MIT OR Unlicense');
      expect(byTitle['flutter'], isNull);
      expect(byTitle['go_router'], 'BSD-3-Clause');
    });
  });

  test('license kinds are read from the clauses that distinguish them', () {
    expect(
      licenseKind('Apache License\n\nVersion 2.0, January 2004'),
      'Apache-2.0',
    );
    expect(
      licenseKind('Redistribution and use ...\nNeither the name of the'),
      'BSD-3-Clause',
    );
    expect(licenseKind('Redistribution and use in source'), 'BSD-2-Clause');
    expect(licenseKind('Permission is hereby granted, free of charge'), 'MIT');
    expect(licenseKind('All rights reserved.'), isNull);
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

  testWidgets('licenses expand inline beside their kind', (tester) async {
    await pumpWithRepositories(
      tester,
      child: OpenSourceLicensesScreen(
        loadLicenses: () async => [
          OpenSourceLicense(
            packages: const ['Example package'],
            text: 'Permission is hereby granted, free of charge',
            kind: 'MIT',
          ),
        ],
      ),
    );

    expect(find.text('Example package'), findsOneWidget);
    expect(find.text('MIT'), findsOneWidget);
    expect(
      find.text('Permission is hereby granted, free of charge'),
      findsNothing,
    );
    await tester.tap(find.text('Example package'));
    await tester.pumpAndSettle();
    expect(
      find.text('Permission is hereby granted, free of charge'),
      findsOneWidget,
    );
  }, variant: iosChrome);

  testWidgets('the longest kind and name share a row without overflowing', (
    tester,
  ) async {
    // The widest pair the list can produce: an SPDX expression with a runtime
    // exception beside the longest declared package name. An overflowing
    // RenderFlex throws, so takeException is the assertion.
    await pumpWithRepositories(
      tester,
      child: OpenSourceLicensesScreen(
        loadLicenses: () async => [
          OpenSourceLicense(
            packages: const ['background_downloader'],
            text: 'Apache License',
            kind: 'Apache-2.0 WITH Swift-exception',
          ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Apache-2.0 WITH Swift-exception'), findsOneWidget);
    expect(find.text('background_downloader'), findsOneWidget);
  }, variant: bothChromes);

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
          text: 'Permission is hereby granted, free of charge',
          kind: 'MIT',
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
