import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/backend_policy.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/theme/golem_theme.dart';
import 'package:golem_flutter/core/chrome/golem_button.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/device_eligibility.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/benchmark/benchmark_screen.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/chat/search_screen.dart';
import 'package:golem_flutter/features/chat/widgets/composer.dart';
import 'package:golem_flutter/features/chat/widgets/message_bubble.dart';
import 'package:golem_flutter/features/chat/widgets/recovery_banner.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/features/legal/model_attribution_screen.dart';
import 'package:golem_flutter/features/legal/open_source_licenses_screen.dart';
import 'package:golem_flutter/features/settings/appearance_screen.dart';
import 'package:golem_flutter/features/settings/language_screen.dart';
import 'package:golem_flutter/features/settings/models_screen.dart';
import 'package:golem_flutter/features/settings/privacy_screen.dart';
import 'package:golem_flutter/features/settings/response_style_screen.dart';
import 'package:golem_flutter/features/settings/settings_screen.dart';
import 'package:golem_flutter/features/settings/storage_screen.dart';
import 'package:golem_flutter/features/settings/system_prompt_screen.dart';
import 'package:golem_flutter/features/splash/splash_screen.dart';
import 'package:golem_flutter/features/onboarding/first_run_screen.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/features/benchmark/application/benchmark_providers.dart';

import 'support/harness.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_preferences_repository.dart';

Future<List<OpenSourceLicense>> _goldenLicenses() async => [
  OpenSourceLicense(
    packages: const ['llama.cpp'],
    text: 'MIT License\n\nCopyright the ggml authors',
  ),
  OpenSourceLicense(
    packages: const ['mlx-swift'],
    text: 'MIT License\n\nCopyright ml-explore',
  ),
  OpenSourceLicense(
    packages: const ['Qwen 3.5 models'],
    text: 'Apache License\n\nVersion 2.0, January 2004',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('splash golden', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(
      // The splash now reads the backend signal for honest copy; the
      // default scope resolves to the fake, matching the recorded golden.
      ProviderScope(
        child: wrapApp(
          brightness: Brightness.light,
          child: SplashScreen(
            state: const StartupState(
              phase: StartupPhase.preloading,
              progress: 0.72,
            ),
            retry: () {},
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SplashScreen),
      matchesGoldenFile('goldens/splash.png'),
    );
  }, variant: iosChrome);

  testWidgets('splash scaffold failure renders its copy and retry', (
    tester,
  ) async {
    setViewport(tester);
    var retried = 0;
    await tester.pumpWidget(
      wrapApp(
        brightness: Brightness.light,
        child: SplashScaffold(
          semanticValue: 'Loading failed',
          caption: 'Golem could not finish starting.',
          progress: 0.4,
          onRetry: () => retried++,
        ),
      ),
    );
    expect(find.text('Golem could not finish starting.'), findsOneWidget);
    expect(find.byKey(const Key('launch-splash')), findsOneWidget);
    await tester.tap(find.byKey(const Key('splash-retry')));
    expect(retried, 1);
  });

  testWidgets('splash scaffold without a retry offers no button', (
    tester,
  ) async {
    setViewport(tester);
    await tester.pumpWidget(
      wrapApp(
        brightness: Brightness.light,
        child: const SplashScaffold(
          semanticValue: 'Loading model on this device',
          caption: 'Loading model on this device',
          progress: 0.2,
        ),
      ),
    );
    expect(find.byKey(const Key('splash-retry')), findsNothing);
  });

  testWidgets('first run welcome light golden', (tester) async {
    await pumpWithRepositories(
      tester,
      eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
      model: const ModelState(simulated: true),
      child: const FirstRunScreen(),
    );
    final context = tester.element(find.byType(FirstRunScreen));
    await tester.runAsync(
      () => precacheImage(AssetImage(AppIdentity.current.iconAsset), context),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(FirstRunScreen),
      matchesGoldenFile('goldens/first-run-welcome-light${chromeSuffix()}.png'),
    );
  }, variant: bothChromes);

  testWidgets('first run model dark golden', (tester) async {
    await pumpWithRepositories(
      tester,
      brightness: Brightness.dark,
      eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
      model: const ModelState(simulated: true),
      child: const FirstRunScreen(),
    );
    await tester.tap(find.byKey(const Key('first-run-get-started')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(FirstRunScreen),
      matchesGoldenFile('goldens/first-run-model-dark${chromeSuffix()}.png'),
    );
  }, variant: bothChromes);

  for (final brightness in Brightness.values) {
    testWidgets('empty chat ${brightness.name} golden', (tester) async {
      // Chrome deltas are geometry, not color: android renders light only.
      if (chromeSuffix().isNotEmpty && brightness == Brightness.dark) return;
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        child: const ChatScreen(),
      );
      await expectLater(
        find.byType(ChatScreen),
        matchesGoldenFile(
          'goldens/empty-chat-${brightness.name}${chromeSuffix()}.png',
        ),
      );
    }, variant: bothChromes);

    testWidgets('dual recovery ${brightness.name} golden', (tester) async {
      if (chromeSuffix().isNotEmpty && brightness == Brightness.dark) return;
      setViewport(tester);
      final history = InMemoryChatHistoryRepository(seedHistory())
        ..failingSaves = 1;
      final container = buildContainer(chatHistory: history);
      addTearDown(container.dispose);
      await container.read(chatControllerProvider.future);
      // The fake backend uses zero-duration timers. Let those timers run on
      // the real async queue before installing the already-failed state.
      await tester.runAsync(
        () => container.read(chatControllerProvider.notifier).send('[fail]'),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: wrapApp(brightness: brightness, child: const ChatScreen()),
        ),
      );
      final context = tester.element(find.byType(ChatScreen));
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/images/golem_mascot.png'),
          context,
        );
        await precacheImage(AssetImage(AppIdentity.current.iconAsset), context);
      });
      // Advance one deterministic frame after asset decoding and record the
      // static failed state.
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byType(ChatScreen),
        matchesGoldenFile(
          'goldens/chat-dual-recovery-${brightness.name}${chromeSuffix()}.png',
        ),
      );
    }, variant: bothChromes);

    testWidgets('populated reasoning ${brightness.name} golden', (
      tester,
    ) async {
      if (chromeSuffix().isNotEmpty && brightness == Brightness.dark) return;
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        history: seedHistory(),
        child: const ChatScreen(),
      );
      await expectLater(
        find.byType(ChatScreen),
        matchesGoldenFile(
          'goldens/populated-reasoning-${brightness.name}${chromeSuffix()}.png',
        ),
      );
    }, variant: bothChromes);
  }

  for (final brightness in Brightness.values) {
    testWidgets('markdown transcript ${brightness.name} golden', (
      tester,
    ) async {
      // The code card is deliberately identical in both chromes; iOS-only.
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        history: markdownHistory(),
        child: const ChatScreen(),
      );
      await expectLater(
        find.byType(ChatScreen),
        matchesGoldenFile('goldens/markdown-transcript-${brightness.name}.png'),
      );
    }, variant: iosChrome);
  }

  for (final brightness in Brightness.values) {
    testWidgets('search ${brightness.name} golden', (tester) async {
      // Search chrome is shared geometry; iOS records both appearances.
      await pumpSearchScreen(
        tester,
        brightness: brightness,
        history: markdownHistory(),
      );
      await tester.enterText(find.byKey(const Key('search-field')), 'csv');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(SearchScreen),
        matchesGoldenFile('goldens/search-${brightness.name}.png'),
      );
    }, variant: iosChrome);
  }

  // One seed, four of the picker's row states (#79): the recommended artifact
  // installed and selected, a second mid-download, a third offering its
  // download, and the rest not downloaded.
  const pickerSeed = ModelState(
    artifacts: {
      'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
      'gemma4-gguf': ArtifactStatus(
        phase: ArtifactPhase.downloading,
        downloadedBytes: 1200000000,
      ),
    },
    activeArtifactKey: 'gemma4-mlx',
    simulated: true,
  );

  for (final brightness in Brightness.values) {
    testWidgets('composer sheet ${brightness.name} goldens', (tester) async {
      // Like the rename sheet, these record android in BOTH appearances:
      // the drag handle is the android-only element whose tint differs.
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        history: markdownHistory(),
        model: pickerSeed,
        child: const ChatScreen(),
      );
      await tester.tap(find.byKey(const Key('composer-model-chip')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const Key('model-picker-sheet')),
        matchesGoldenFile(
          'goldens/model-picker-sheet-${brightness.name}${chromeSuffix()}.png',
        ),
      );
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('composer-attach')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const Key('attach-sheet')),
        matchesGoldenFile(
          'goldens/attach-sheet-${brightness.name}${chromeSuffix()}.png',
        ),
      );
    }, variant: bothChromes);
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'model picker on a real backend ${brightness.name} golden',
      (tester) async {
        // The states only a real engine can produce (#79): the recommendation
        // and its device-tier reason, an installed artifact of the *other*
        // engine explaining why it cannot be chosen, the count of what is not
        // listed, and — with Advanced on — the exact artifact behind each name.
        // Geometry is chrome-independent here, so iOS records it.
        await pumpWithRepositories(
          tester,
          brightness: brightness,
          history: markdownHistory(),
          // Resolved by the real policy, not hand-built: a literal config
          // leaves artifactFromDevicePolicy false, and the device-tier
          // sentence this golden exists to record would quietly degrade to
          // the generic fallback without a test noticing.
          backend: resolveBackendPolicy(
            backendName: 'auto',
            profileDefine: '',
            artifactDefine: '',
            modelPathDefine: '',
            tier: DeviceTier.preferred,
          ),
          eligibility: const DeviceEligibility(tier: DeviceTier.preferred),
          preferences: InMemoryPreferencesRepository(
            const AppPreferences(advancedMode: true),
          ),
          model: const ModelState(
            artifacts: {
              'gemma4-gguf': ArtifactStatus(phase: ArtifactPhase.installed),
              'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
              'qwen35-2b-gguf': ArtifactStatus(
                phase: ArtifactPhase.paused,
                downloadedBytes: 620000000,
              ),
            },
            activeArtifactKey: 'gemma4-gguf',
          ),
          child: const ChatScreen(),
        );
        await tester.tap(find.byKey(const Key('composer-model-chip')));
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const Key('model-picker-sheet')),
          matchesGoldenFile('goldens/model-picker-real-${brightness.name}.png'),
        );
      },
      variant: iosChrome,
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets('drawer and rename overlay ${brightness.name} goldens', (
      tester,
    ) async {
      // Unlike the other surfaces, the rename sheet records android in BOTH
      // appearances: the drag handle is the one android-only painted element
      // whose tint (tertiaryInk) differs between light and dark.
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        history: seedHistory(),
        child: const ChatScreen(),
      );
      await tester.tap(find.byKey(const Key('open-drawer')));
      await tester.pumpAndSettle();
      // The drawer is deliberately identical on both chromes; only the
      // iOS variant records it. The rename sheet differs (drag handle).
      if (chromeSuffix().isEmpty) {
        await expectLater(
          find.byType(ChatScreen),
          matchesGoldenFile('goldens/drawer-${brightness.name}.png'),
        );
      }
      await tester.tap(find.byKey(const Key('conversation-menu-chat-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const Key('rename-sheet')),
        matchesGoldenFile(
          'goldens/rename-sheet-${brightness.name}${chromeSuffix()}.png',
        ),
      );
    }, variant: bothChromes);
  }

  // 42% of the pinned Gemma MLX artifact, mid-pause, with the Qwen GGUF
  // installed — exercises progress, resume, delete, and the storage
  // breakdown from one seed.
  const settingsModelSeed = ModelState(
    artifacts: {
      'gemma4-mlx': ArtifactStatus(
        phase: ArtifactPhase.paused,
        downloadedBytes: 1505735776,
      ),
      'qwen35-gguf': ArtifactStatus(
        phase: ArtifactPhase.installed,
        downloadedBytes: 2543899040,
      ),
    },
    runtime: RuntimePhase.unloaded,
    activeArtifactKey: 'gemma4-mlx',
    simulated: true,
  );

  Future<void> revealIn(WidgetTester tester, Key listKey, Key target) async {
    await tester.scrollUntilVisible(
      find.byKey(target),
      260,
      scrollable: find
          .descendant(
            of: find.byKey(listKey),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets('settings root ${brightness.name} golden', (tester) async {
      if (chromeSuffix().isNotEmpty && brightness == Brightness.dark) return;
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        model: settingsModelSeed,
        child: const SettingsScreen(identity: AppIdentity.dev),
      );
      await expectLater(
        find.byType(SettingsScreen),
        matchesGoldenFile(
          'goldens/settings-${brightness.name}${chromeSuffix()}.png',
        ),
      );
    }, variant: bothChromes);

    testWidgets('settings models ${brightness.name} golden', (tester) async {
      if (chromeSuffix().isNotEmpty && brightness == Brightness.dark) return;
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        model: settingsModelSeed,
        child: const ModelsScreen(),
      );
      await expectLater(
        find.byType(ModelsScreen),
        matchesGoldenFile(
          'goldens/settings-models-${brightness.name}${chromeSuffix()}.png',
        ),
      );
    }, variant: bothChromes);

    testWidgets('settings style ${brightness.name} golden', (tester) async {
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        child: const ResponseStyleScreen(),
      );
      await expectLater(
        find.byType(ResponseStyleScreen),
        matchesGoldenFile('goldens/settings-style-${brightness.name}.png'),
      );
    }, variant: iosChrome);

    testWidgets('settings style advanced ${brightness.name} golden', (
      tester,
    ) async {
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        preferences: InMemoryPreferencesRepository(
          const AppPreferences(advancedMode: true),
        ),
        child: const ResponseStyleScreen(),
      );
      await revealIn(
        tester,
        const Key('style-list'),
        const Key('gen-context-gemma4'),
      );
      await expectLater(
        find.byType(ResponseStyleScreen),
        matchesGoldenFile(
          'goldens/settings-style-advanced-${brightness.name}.png',
        ),
      );
    }, variant: iosChrome);

    testWidgets('settings appearance ${brightness.name} golden', (
      tester,
    ) async {
      if (chromeSuffix().isNotEmpty && brightness == Brightness.dark) return;
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        child: const AppearanceScreen(),
      );
      await expectLater(
        find.byType(AppearanceScreen),
        matchesGoldenFile(
          'goldens/settings-appearance-${brightness.name}${chromeSuffix()}.png',
        ),
      );
    }, variant: bothChromes);

    if (brightness == Brightness.light) {
      testWidgets('settings language Polish golden', (tester) async {
        await pumpWithRepositories(
          tester,
          brightness: brightness,
          locale: const Locale('pl'),
          preferences: InMemoryPreferencesRepository(
            const AppPreferences(language: AppLanguage.polish),
          ),
          child: const LanguageScreen(),
        );
        await expectLater(
          find.byType(LanguageScreen),
          matchesGoldenFile(
            'goldens/settings-language-polish${chromeSuffix()}.png',
          ),
        );
      }, variant: bothChromes);
    }

    testWidgets('settings privacy ${brightness.name} golden', (tester) async {
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        child: const PrivacyScreen(),
      );
      await expectLater(
        find.byType(PrivacyScreen),
        matchesGoldenFile('goldens/settings-privacy-${brightness.name}.png'),
      );
    }, variant: iosChrome);

    testWidgets('model attribution ${brightness.name} golden', (tester) async {
      if (chromeSuffix().isNotEmpty && brightness == Brightness.dark) return;
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        child: const ModelAttributionScreen(),
      );
      await expectLater(
        find.byType(ModelAttributionScreen),
        matchesGoldenFile(
          'goldens/settings-model-attribution-${brightness.name}'
          '${chromeSuffix()}.png',
        ),
      );
    }, variant: bothChromes);

    testWidgets('open-source licenses ${brightness.name} golden', (
      tester,
    ) async {
      if (chromeSuffix().isNotEmpty && brightness == Brightness.dark) return;
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        child: OpenSourceLicensesScreen(loadLicenses: _goldenLicenses),
      );
      await expectLater(
        find.byType(OpenSourceLicensesScreen),
        matchesGoldenFile(
          'goldens/settings-licenses-${brightness.name}'
          '${chromeSuffix()}.png',
        ),
      );
    }, variant: bothChromes);

    testWidgets('settings storage ${brightness.name} golden', (tester) async {
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        model: settingsModelSeed,
        child: const StorageScreen(),
      );
      await expectLater(
        find.byType(StorageScreen),
        matchesGoldenFile('goldens/settings-storage-${brightness.name}.png'),
      );
    }, variant: iosChrome);

    testWidgets('settings system prompt ${brightness.name} golden', (
      tester,
    ) async {
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        preferences: InMemoryPreferencesRepository(
          const AppPreferences(advancedMode: true),
        ),
        child: const SystemPromptScreen(),
      );
      await expectLater(
        find.byType(SystemPromptScreen),
        matchesGoldenFile(
          'goldens/settings-system-prompt-${brightness.name}.png',
        ),
      );
    }, variant: iosChrome);
  }

  testWidgets('production settings root golden', (tester) async {
    await pumpWithRepositories(
      tester,
      model: settingsModelSeed,
      child: const SettingsScreen(identity: AppIdentity.production),
    );
    expect(find.byKey(const Key('open-benchmark')), findsNothing);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings-production-light.png'),
    );
  }, variant: iosChrome);

  testWidgets('settings advanced root and custom repository golden', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      model: settingsModelSeed,
      preferences: InMemoryPreferencesRepository(
        const AppPreferences(advancedMode: true),
      ),
      child: const SettingsScreen(identity: AppIdentity.dev),
    );
    // Advanced on: the root grows the System prompt row.
    expect(find.byKey(const Key('settings-system-prompt-row')), findsOneWidget);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings-advanced-light.png'),
    );

    await pumpWithRepositories(
      tester,
      model: settingsModelSeed,
      preferences: InMemoryPreferencesRepository(
        const AppPreferences(advancedMode: true),
      ),
      child: const ModelsScreen(),
    );
    await revealIn(
      tester,
      const Key('models-list'),
      const Key('custom-repo-resolve'),
    );
    await expectLater(
      find.byType(ModelsScreen),
      matchesGoldenFile('goldens/settings-models-advanced-light.png'),
    );
  }, variant: iosChrome);

  for (final brightness in Brightness.values) {
    testWidgets('benchmark result ${brightness.name} golden', (tester) async {
      if (chromeSuffix().isNotEmpty && brightness == Brightness.dark) return;
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        child: const BenchmarkScreen(),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BenchmarkScreen)),
      );
      await tester.runAsync(
        () => container.read(benchmarkControllerProvider.notifier).run(),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('benchmark-result-card')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(BenchmarkScreen),
        matchesGoldenFile(
          'goldens/benchmark-${brightness.name}${chromeSuffix()}.png',
        ),
      );
    }, variant: bothChromes);
  }

  testWidgets('iOS targets, labels, contrast, and enlarged text', (
    tester,
  ) async {
    await pumpWithRepositories(tester, child: const ChatScreen());
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    // An empty chat has no code card, so the transcript enrolls again with
    // one on screen, in both appearances. Note this covers the card's
    // chrome only: `textContrastGuideline` measures a text node's two
    // modal colors, so the minority syntax hues never reach it —
    // `code_block_test.dart` asserts those ratios against the tokens.
    for (final brightness in Brightness.values) {
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        history: markdownHistory(),
        child: const ChatScreen(),
      );
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }

    // The open drawer enrolls too — it stopped being a fixed-navy surface,
    // so its light column is new and unproven. The chat behind it never
    // reaches the contrast check even though the scrim dims it: the canvas
    // is ExcludeSemantics while the drawer is open, and the guideline walks
    // the semantics tree.
    //
    // Contrast is asserted in light only. Dark trips on the filled "New
    // chat" button — white on the dark accent is 2.95:1 — which is neither
    // new nor local: every GolemButton.filled in the app has it, because
    // the accent lightens to #5B94FF in dark while its label stays white.
    // Restyling filled buttons app-wide is its own change; the drawer's own
    // dark inks are covered by the palette group below instead.
    for (final brightness in Brightness.values) {
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        history: seedHistory(),
        // Keyed per appearance so the second pass gets a fresh state:
        // _drawerOpen lives in the element, which pumpWidget reuses when
        // the widget type matches, and the tap would land on the drawer
        // this loop already opened.
        child: ChatScreen(key: ValueKey(brightness)),
      );
      await tester.tap(find.byKey(const Key('open-drawer')));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      if (brightness == Brightness.light) {
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
    }

    // The redesigned settings surfaces enroll in the same guidelines.
    for (final screen in const <Widget>[
      SettingsScreen(identity: AppIdentity.dev),
      AppearanceScreen(),
      PrivacyScreen(),
    ]) {
      await pumpWithRepositories(tester, child: screen);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }
  }, variant: iosChrome);

  // A phone at an accessibility text size is a supported configuration, not an
  // edge case: the app's own slider reaches 1.3x and the platform's factor
  // multiplies on top of it. An overflow throws in debug, so a clean pump is
  // the assertion.
  testWidgets('every surface survives a 1.6x text scale', (tester) async {
    for (final screen in const <Widget>[
      SettingsScreen(identity: AppIdentity.dev),
      AppearanceScreen(),
      PrivacyScreen(),
      StorageScreen(),
      ModelsScreen(),
      SystemPromptScreen(),
      ResponseStyleScreen(),
      BenchmarkScreen(),
    ]) {
      await pumpWithRepositories(tester, textScale: 1.6, child: screen);
      expect(tester.takeException(), isNull, reason: '${screen.runtimeType}');
    }

    // Chat carries the densest rows in the app — the composer's power strip,
    // the metrics pills, and a code card that cannot wrap.
    for (final (name, history) in <(String, ChatHistorySnapshot?)>[
      ('empty', null),
      ('seeded', seedHistory()),
      ('markdown', markdownHistory()),
    ]) {
      await pumpWithRepositories(
        tester,
        textScale: 1.6,
        history: history,
        child: const ChatScreen(),
      );
      expect(tester.takeException(), isNull, reason: 'chat: $name');
    }

    await pumpWithRepositories(
      tester,
      textScale: 1.6,
      history: seedHistory(),
      child: const ChatScreen(),
    );
    await tester.tap(find.byKey(const Key('open-drawer')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'drawer');

    // The sheets size themselves to their content, so they are the surfaces
    // most likely to run out of room; each is opened rather than pumped.
    // pumpWidget reuses the element tree, so both halves of the state have to
    // be reset by hand: the key gives each pass a chat with the drawer shut,
    // and the pop clears the route a standing sheet would otherwise leave over
    // the next iteration's tap. Each sheet is found by key so a pass that
    // opened nothing fails instead of asserting nothing.
    const sheets = <(Key, Key)>[
      (Key('composer-model-chip'), Key('model-picker-sheet')),
      (Key('composer-attach'), Key('attach-sheet')),
    ];
    for (final (opener, sheet) in sheets) {
      await pumpWithRepositories(
        tester,
        textScale: 1.6,
        history: seedHistory(),
        child: ChatScreen(key: ValueKey(opener)),
      );
      await tester.tap(find.byKey(opener));
      await tester.pumpAndSettle();
      expect(find.byKey(sheet), findsOneWidget, reason: '$opener opened');
      expect(tester.takeException(), isNull, reason: '$opener');
      Navigator.of(tester.element(find.byKey(sheet))).pop();
      await tester.pumpAndSettle();
    }
  }, variant: iosChrome);

  testWidgets('the storage meter paints a track and a used fill', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      history: seedHistory(),
      child: const ChatScreen(),
    );
    await tester.tap(find.byKey(const Key('open-drawer')));
    await tester.pumpAndSettle();
    // Both bars are childless ColoredBoxes inside a 4pt Stack. Without a
    // tight constraint each takes constraints.smallest and lays out 0×0,
    // painting nothing — and a re-blessed golden records the absence as if
    // it were intended, which is exactly how this shipped unnoticed.
    final bars = find.descendant(
      of: find.byKey(const Key('storage-meter')),
      matching: find.byType(ColoredBox),
    );
    expect(bars, findsNWidgets(2));
    final sizes = bars
        .evaluate()
        .map((element) => (element.renderObject! as RenderBox).size)
        .toList();
    for (final size in sizes) {
      expect(size.height, 4);
      expect(size.width, greaterThan(0));
    }
    // The fill is Golem's own share of the volume, not the disk's used
    // space: 0.10 of the fake 64 GB, so it is a sliver of the 290pt track
    // and too narrow to show in a golden. Its width regressing to zero is
    // exactly the failure this guards.
    expect(sizes.last.width, lessThan(sizes.first.width));
  }, variant: iosChrome);

  // The drawer's own inks, asserted against the tokens the way
  // code_block_test.dart asserts the syntax palette. This is what keeps the
  // dark column honest while `textContrastGuideline` runs light-only above,
  // and it is the guard on the handoff's alpha values, which read 4.07 and
  // 2.92 in light and 4.83 and 4.18 in dark — four of five under the bar.
  group('drawer palette contrast', () {
    // Color.computeLuminance is already the WCAG relative-luminance
    // formula, so the ratio is all that is left to spell out.
    double ratio(Color fg, Color bg) {
      final a = fg.computeLuminance();
      final b = bg.computeLuminance();
      return (max(a, b) + 0.05) / (min(a, b) + 0.05);
    }

    for (final brightness in Brightness.values) {
      test('every ink clears 4.5:1 in ${brightness.name}', () {
        Color pick(CupertinoDynamicColor c) =>
            brightness == Brightness.dark ? c.darkColor : c.color;
        final surface = pick(GolemTheme.drawer);
        for (final entry in <String, CupertinoDynamicColor>{
          'drawerInk': GolemTheme.drawerInk,
          'drawerMutedInk': GolemTheme.drawerMutedInk,
          'drawerFaintInk': GolemTheme.drawerFaintInk,
        }.entries) {
          expect(
            ratio(pick(entry.value), surface),
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} on the drawer surface',
          );
        }
        // The search placeholder sits on the field fill, and the active
        // conversation's title on the selected row — both washes over the
        // same surface, so neither is covered by the loop above.
        final fill = Color.alphaBlend(pick(GolemTheme.drawerFill), surface);
        expect(
          ratio(pick(GolemTheme.drawerFaintInk), fill),
          greaterThanOrEqualTo(4.5),
          reason: 'drawerFaintInk on the search field',
        );
        final selected = Color.alphaBlend(
          pick(GolemTheme.drawerSelected),
          surface,
        );
        expect(
          ratio(pick(GolemTheme.drawerInk), selected),
          greaterThanOrEqualTo(4.5),
          reason: 'drawerInk on the selected conversation row',
        );
      });
    }
  });

  testWidgets('a real backend renders honest copy on every surface', (
    tester,
  ) async {
    // The five simulated-copy surfaces branch on the backend signal; this
    // pumps the direction that ships to users (real inference, with the
    // download simulation still active — the two axes are independent).
    const backend = InferenceBackendConfig(
      kind: InferenceBackendKind.llama,
      profileKey: 'gemma4',
      artifactKey: 'gemma4-gguf',
      modelPath: 'documents:models/gemma4-gguf/model.gguf',
      modelPathFromCatalog: true,
    );

    await pumpWithRepositories(
      tester,
      backend: backend,
      // Simulated downloads with real inference: the mixed state a dev
      // build can genuinely be in.
      model: const ModelState(simulated: true),
      child: const ModelsScreen(),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('runtime-toggle-button')),
      260,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('models-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    // The download axis stays honestly simulated under the fake
    // repository (the screen footer, virtualized until scrolled near).
    expect(find.textContaining('deterministic simulation'), findsWidgets);
    expect(find.text('Load Runtime'), findsOneWidget);
    expect(find.textContaining('Simulated Runtime'), findsNothing);
    // The runtime rows: the artifact this build would load, an honest bare
    // state beside it, and no simulated qualifier anywhere on them. Naming the
    // model while it is unloaded is the point — "active" is which model, and
    // "state" is whether the engine holds it (#20).
    expect(find.text('Unloaded'), findsOneWidget);
    expect(find.text('Gemma 4 E2B'), findsWidgets);
    expect(find.textContaining('· simulated'), findsNothing);

    await pumpWithRepositories(
      tester,
      backend: backend,
      model: const ModelState(simulated: true),
      child: const SettingsScreen(identity: AppIdentity.dev),
    );
    expect(find.byKey(const Key('simulation-banner')), findsNothing);
    expect(find.textContaining('SIMULATED'), findsNothing);
    // About composes per-axis honesty: the real inference sentence next
    // to the simulated-downloads sentence. Ordered after the models
    // scroll on purpose: an opened sheet leaves later re-pumped trees
    // un-hit-testable, so no segment past this one taps or scrolls.
    await revealIn(tester, const Key('settings-list'), const Key('about-row'));
    await tester.tap(find.byKey(const Key('about-row')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Inference runs the local engine'),
      findsOneWidget,
    );
    expect(
      find.textContaining('deterministic simulation of the pinned catalog'),
      findsOneWidget,
    );
    expect(find.textContaining('UI evaluation build'), findsNothing);

    await pumpWithRepositories(
      tester,
      backend: backend,
      child: const ChatScreen(),
    );
    expect(
      find.textContaining('is loaded and running on this phone'),
      findsOneWidget,
    );
    expect(find.textContaining('preview simulates'), findsNothing);

    await pumpWithRepositories(
      tester,
      backend: backend,
      child: SplashScreen(
        state: const StartupState(
          phase: StartupPhase.preloading,
          progress: 0.72,
        ),
        retry: () {},
      ),
    );
    expect(find.text('Getting things ready'), findsOneWidget);
    expect(find.textContaining('simulated'), findsNothing);
  }, variant: iosChrome);

  testWidgets('a busy composer is read-only, never disabled', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    // A disabled borderless field repaints Flutter's built-in near-black fill
    // over the card (issue #34) and announces itself as disabled to a screen
    // reader (issue #28). Read-only blocks input without doing either, so
    // every non-idle phase must reach for it instead.
    for (final phase in GenerationPhase.values) {
      if (phase == GenerationPhase.idle) continue;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelCatalogEntriesProvider.overrideWithValue(modelCatalog),
          ],
          child: wrapApp(
            brightness: Brightness.dark,
            child: Composer(
              controller: controller,
              focus: focus,
              reasoningEnabled: false,
              generation: phase,
              activeId: null,
              modelKey: null,
            ),
          ),
        ),
      );
      final field = tester.widget<CupertinoTextField>(
        find.byKey(const Key('chat-composer')),
      );
      expect(field.enabled, isTrue, reason: phase.name);
      expect(field.readOnly, isTrue, reason: phase.name);
    }
  }, variant: iosChrome);

  testWidgets(
    'an empty failed assistant message renders no ghost bubble',
    (tester) async {
      Widget wrap(ChatMessage message) => ProviderScope(
        child: wrapApp(
          child: MessageBubble(
            message: message,
            canRegenerate: false,
            idle: false,
          ),
        ),
      );
      final ghost = ChatMessage.text(
        id: 'assistant-ghost',
        role: MessageRole.assistant,
        text: '',
        createdAt: DateTime.utc(2026, 8, 5),
      );
      // A failure can strand an assistant message with no text, reasoning, or
      // metrics; it must vanish instead of painting an empty bubble shell.
      await tester.pumpWidget(wrap(ghost));
      expect(find.byKey(const Key('message-assistant-ghost')), findsNothing);

      // While streaming, the same empty message is the typing indicator
      // (the blinking caret) and must stay visible.
      await tester.pumpWidget(wrap(ghost.copyWith(isStreaming: true)));
      expect(find.byKey(const Key('message-assistant-ghost')), findsOneWidget);
    },
    variant: iosChrome,
  );

  group('an unsupported device (#27)', () {
    const backend = InferenceBackendConfig(
      kind: InferenceBackendKind.llama,
      profileKey: 'gemma4',
      artifactKey: 'gemma4-gguf',
      modelPath: 'documents:models/gemma4-gguf/model.gguf',
      modelPathFromCatalog: true,
    );
    const refused = DeviceEligibility(
      tier: DeviceTier.unsupported,
      reason: DeviceIneligibilityReason.belowMemoryFloor,
      message:
          'This device has less memory than the smallest model Golem ships '
          'needs to run, so downloads are turned off here. Your chats and '
          'settings are unaffected.',
    );

    for (final brightness in Brightness.values) {
      testWidgets('chat says so ${brightness.name} golden', (tester) async {
        await pumpWithRepositories(
          tester,
          brightness: brightness,
          backend: backend,
          eligibility: refused,
          child: const ChatScreen(),
        );
        expect(
          find.byKey(const Key('device-unsupported-notice')),
          findsOneWidget,
        );
        // No starter chip may invite a prompt this device cannot answer.
        expect(find.byKey(const Key('starter-chip-explain')), findsNothing);
        await expectLater(
          find.byType(ChatScreen),
          matchesGoldenFile(
            'goldens/device-unsupported-chat-${brightness.name}.png',
          ),
        );
      }, variant: iosChrome);

      testWidgets('models refuse ${brightness.name} golden', (tester) async {
        await pumpWithRepositories(
          tester,
          brightness: brightness,
          backend: backend,
          eligibility: refused,
          child: const ModelsScreen(),
        );
        expect(
          find.byKey(const Key('model-device-refusal-gemma4-gguf')),
          findsOneWidget,
        );
        await expectLater(
          find.byType(ModelsScreen),
          matchesGoldenFile(
            'goldens/device-unsupported-models-${brightness.name}.png',
          ),
        );
      }, variant: iosChrome);
    }

    testWidgets('every model affordance is disabled, not merely honest', (
      tester,
    ) async {
      await pumpWithRepositories(
        tester,
        backend: backend,
        eligibility: refused,
        child: const ModelsScreen(),
      );
      // Withheld, not merely inert: a disabled GolemButton still paints its
      // full accent fill, which would read as an offer.
      expect(find.byKey(const Key('model-download-gemma4-gguf')), findsNothing);
      await revealIn(
        tester,
        const Key('models-list'),
        const Key('runtime-device-refusal'),
      );
      expect(find.byKey(const Key('runtime-toggle-button')), findsNothing);
    }, variant: iosChrome);

    testWidgets('the banner offers no recovery it cannot deliver', (
      tester,
    ) async {
      await pumpWithRepositories(
        tester,
        child: const RecoveryBanner(
          failure: ChatFailure(kind: ChatFailureKind.unsupportedDevice),
        ),
      );
      expect(find.byKey(const Key('retry-generation')), findsNothing);
      expect(find.byKey(const Key('start-new-chat')), findsNothing);
      expect(find.byKey(const Key('download-active-model')), findsNothing);
      // Dismissing the banner is the one thing that still works.
      expect(find.byKey(const Key('discard-generation')), findsOneWidget);
    }, variant: iosChrome);

    testWidgets('the explanation survives a populated transcript', (
      tester,
    ) async {
      // Discard trims a trailing assistant message, so a refused send leaves
      // the user's turn behind and the empty state — which carried the only
      // explanation — never renders again.
      await pumpWithRepositories(
        tester,
        backend: backend,
        eligibility: refused,
        history: seedHistory(),
        child: const ChatScreen(),
      );
      expect(find.byKey(const Key('empty-chat')), findsNothing);
      expect(
        find.byKey(const Key('device-unsupported-notice')),
        findsOneWidget,
      );
    }, variant: iosChrome);

    testWidgets('a runtime left loaded can still be unloaded', (tester) async {
      // An earlier build could have persisted `loaded` on a device this one
      // refuses; withholding both directions would strand it there forever.
      await pumpWithRepositories(
        tester,
        backend: backend,
        eligibility: refused,
        model: const ModelState(runtime: RuntimePhase.loaded),
        child: const ModelsScreen(),
      );
      await revealIn(
        tester,
        const Key('models-list'),
        const Key('runtime-toggle-button'),
      );
      final toggle = tester.widget<GolemButton>(
        find.byKey(const Key('runtime-toggle-button')),
      );
      expect(toggle.label, startsWith('Unload'));
      expect(toggle.onPressed, isNotNull);
    }, variant: iosChrome);

    testWidgets('a supported device keeps every affordance', (tester) async {
      await pumpWithRepositories(
        tester,
        backend: backend,
        child: const ModelsScreen(),
      );
      await revealIn(
        tester,
        const Key('models-list'),
        const Key('runtime-toggle-button'),
      );
      expect(find.byKey(const Key('runtime-device-refusal')), findsNothing);
      expect(
        tester
            .widget<GolemButton>(find.byKey(const Key('runtime-toggle-button')))
            .onPressed,
        isNotNull,
      );
    }, variant: iosChrome);
  });
}
