import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/benchmark/benchmark_screen.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/chat/search_screen.dart';
import 'package:golem_flutter/features/chat/widgets/composer.dart';
import 'package:golem_flutter/features/chat/widgets/message_bubble.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/features/settings/appearance_screen.dart';
import 'package:golem_flutter/features/settings/models_screen.dart';
import 'package:golem_flutter/features/settings/privacy_screen.dart';
import 'package:golem_flutter/features/settings/response_style_screen.dart';
import 'package:golem_flutter/features/settings/settings_screen.dart';
import 'package:golem_flutter/features/settings/storage_screen.dart';
import 'package:golem_flutter/features/settings/system_prompt_screen.dart';
import 'package:golem_flutter/features/splash/splash_screen.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';

import 'support/harness.dart';
import 'support/in_memory_preferences_repository.dart';

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
            isLoading: true,
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

  for (final brightness in Brightness.values) {
    testWidgets('composer sheet ${brightness.name} goldens', (tester) async {
      // Like the rename sheet, these record android in BOTH appearances:
      // the drag handle is the android-only element whose tint differs.
      await pumpWithRepositories(
        tester,
        brightness: brightness,
        history: markdownHistory(),
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
        child: const SettingsScreen(),
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

  testWidgets('settings advanced root and custom repository golden', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      model: settingsModelSeed,
      preferences: InMemoryPreferencesRepository(
        const AppPreferences(advancedMode: true),
      ),
      child: const SettingsScreen(),
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
      const Key('custom-repo-add'),
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

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: viewport,
          textScaler: TextScaler.linear(1.6),
        ),
        child: UncontrolledProviderScope(
          container: buildContainer(),
          child: wrapApp(child: const SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: iosChrome);

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
    // The runtime rows: an honest bare state and no simulated qualifier
    // on the empty active-model row.
    expect(find.text('Unloaded'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.textContaining('None · simulated'), findsNothing);

    await pumpWithRepositories(
      tester,
      backend: backend,
      model: const ModelState(simulated: true),
      child: const SettingsScreen(),
    );
    expect(find.byKey(const Key('simulation-banner')), findsNothing);
    expect(find.textContaining('SIMULATED'), findsNothing);
    // About composes per-axis honesty: the real inference sentence next
    // to the simulated-downloads sentence. Ordered after the models
    // scroll on purpose: an opened sheet leaves later re-pumped trees
    // un-hit-testable, so no segment past this one taps or scrolls.
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
        isLoading: true,
        retry: () {},
      ),
    );
    expect(find.text('Loading model on this device'), findsOneWidget);
    expect(find.textContaining('simulated'), findsNothing);
  }, variant: iosChrome);

  testWidgets('the disabled composer keeps a transparent field', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    // Every non-idle phase disables the field, so each one would repaint
    // Flutter's built-in near-black fill over the Glass pill without the
    // explicit empty decoration (issue #34).
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
      expect(field.enabled, isFalse, reason: phase.name);
      expect(field.decoration, isNotNull, reason: phase.name);
      expect(field.decoration!.color, isNull, reason: phase.name);
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
      final ghost = ChatMessage(
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
}
