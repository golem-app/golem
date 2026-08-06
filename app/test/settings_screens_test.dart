import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/app_version.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/chat/widgets/message_bubble.dart';
import 'package:golem_flutter/features/settings/appearance_screen.dart';
import 'package:golem_flutter/features/settings/models_screen.dart';
import 'package:golem_flutter/features/settings/privacy_screen.dart';
import 'package:golem_flutter/features/settings/settings_screen.dart';
import 'package:golem_flutter/features/settings/system_prompt_screen.dart';

import 'support/harness.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_preferences_repository.dart';

void main() {
  test('the About version constant matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.firstWhere((l) => l.startsWith('version:'));
    expect(
      line.split(':')[1].trim().split('+').first,
      appVersion,
      reason: 'core/app_version.dart is hand-owned; bump both together',
    );
  });

  testWidgets('the metrics toggle hides the settled chip in chat', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      child: const ChatScreen(),
    );
    expect(find.byKey(const Key('metrics-pill')), findsOneWidget);

    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      preferences: InMemoryPreferencesRepository(
        const AppPreferences(showMetrics: false),
      ),
      child: const ChatScreen(),
    );
    expect(find.byKey(const Key('metrics-pill')), findsNothing);
  }, variant: iosChrome);

  testWidgets(
    'settled reasoning collapses unless the preference expands it',
    (tester) async {
      await pumpWithRepositories(
        tester,
        history: seedHistory(),
        child: const ChatScreen(),
      );
      final reasoningText = find.textContaining('one small delight');
      expect(reasoningText, findsNothing, reason: 'collapsed by default');
      await tester.tap(find.byKey(const Key('reasoning-card')));
      await tester.pumpAndSettle();
      expect(reasoningText, findsOneWidget, reason: 'tap still discloses');

      // Dismantle the tree first: an identical re-pump would reuse the
      // card's State and mask the initial-expansion behavior under test.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpWithRepositories(
        tester,
        history: seedHistory(),
        preferences: InMemoryPreferencesRepository(
          const AppPreferences(expandReasoning: true),
        ),
        child: const ChatScreen(),
      );
      expect(reasoningText, findsOneWidget);
    },
    variant: iosChrome,
  );

  testWidgets('appearance commits theme, and toggles persist', (tester) async {
    final preferences = InMemoryPreferencesRepository();
    await pumpWithRepositories(
      tester,
      preferences: preferences,
      child: const AppearanceScreen(),
    );
    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pumpAndSettle();
    expect(preferences.preferences.theme, ThemeSetting.dark);

    await tester.tap(find.byKey(const Key('toggle-metrics')));
    await tester.pumpAndSettle();
    expect(preferences.preferences.showMetrics, isFalse);
    await tester.tap(find.byKey(const Key('toggle-haptics')));
    await tester.pumpAndSettle();
    expect(preferences.preferences.hapticsOnSend, isFalse);
  }, variant: iosChrome);

  testWidgets('turning history off confirms, wipes disk, and persists', (
    tester,
  ) async {
    final preferences = InMemoryPreferencesRepository();
    await pumpWithRepositories(
      tester,
      history: seedHistory(),
      preferences: preferences,
      child: const PrivacyScreen(),
    );
    final history =
        ProviderScope.containerOf(
              tester.element(find.byType(PrivacyScreen)),
            ).read(chatHistoryRepositoryProvider)
            as InMemoryChatHistoryRepository;
    await tester.tap(find.byKey(const Key('toggle-save-history')));
    await tester.pumpAndSettle();
    // The alert is the consent gate; declining changes nothing.
    expect(find.text('Keep saving'), findsOneWidget);
    await tester.tap(find.text('Keep saving'));
    await tester.pumpAndSettle();
    expect(preferences.preferences.saveHistory, isTrue);
    expect(history.snapshot.conversations, isNotEmpty);

    await tester.tap(find.byKey(const Key('toggle-save-history')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-history-off')));
    await tester.pumpAndSettle();
    expect(preferences.preferences.saveHistory, isFalse);
    expect(history.snapshot.conversations, isEmpty);
  }, variant: iosChrome);

  testWidgets('delete all chats confirms, clears, and toasts', (tester) async {
    await pumpWithRepositories(
      tester,
      history: seedHistory(),
      child: const PrivacyScreen(),
    );
    final history =
        ProviderScope.containerOf(
              tester.element(find.byType(PrivacyScreen)),
            ).read(chatHistoryRepositoryProvider)
            as InMemoryChatHistoryRepository;
    await tester.tap(find.byKey(const Key('delete-all-chats')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-all')));
    await tester.pumpAndSettle();
    expect(history.snapshot.conversations, isEmpty);
    expect(find.byKey(const Key('golem-toast')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
  }, variant: iosChrome);

  testWidgets('a custom repository adds through the Advanced card', (
    tester,
  ) async {
    final preferences = InMemoryPreferencesRepository(
      const AppPreferences(advancedMode: true),
    );
    await pumpWithRepositories(
      tester,
      preferences: preferences,
      // Simulated downloads — the only backend that accepts custom repos.
      model: const ModelState(simulated: true),
      child: const ModelsScreen(),
    );
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('models-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('custom-repo-add')),
      240,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    // Empty field: nothing to add yet.
    expect(
      tester
          .widget<CupertinoButton>(
            find.ancestor(
              of: find.text('Add model'),
              matching: find.byType(CupertinoButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('custom-repo-engine-gguf')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('custom-repo-field')),
      'org/tiny-model-GGUF',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('custom-repo-add')));
    await tester.pumpAndSettle();

    final spec = preferences.preferences.customModels.single;
    expect(spec.repository, 'org/tiny-model-GGUF');
    expect(spec.key, startsWith('custom-org-tiny-model-gguf-'));
    expect(spec.engine, ModelEngine.gguf);
    expect(find.byKey(const Key('golem-toast')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
    // The derived card joins the catalog list.
    await tester.scrollUntilVisible(
      find.byKey(Key('model-card-${spec.key}')),
      240,
      scrollable: scrollable,
    );
    expect(find.text('tiny-model-GGUF'), findsOneWidget);
  }, variant: iosChrome);

  testWidgets('a real download backend keeps custom repositories inert', (
    tester,
  ) async {
    // A custom spec persisted under the fake backend survives a rebuild
    // against the real downloader; its card must not offer a download
    // the pinned-catalog repository would reject.
    const spec = CustomModelSpec(
      repository: 'org/left-over-model',
      engine: ModelEngine.mlx,
    );
    await pumpWithRepositories(
      tester,
      preferences: InMemoryPreferencesRepository(
        const AppPreferences(advancedMode: true).withCustomModel(spec),
      ),
      // simulated: false — the real downloader stays pinned-catalog-only.
      model: const ModelState(),
      child: const ModelsScreen(),
    );
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('models-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(Key('model-download-${spec.key}')),
      240,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CupertinoButton>(
            find.descendant(
              of: find.byKey(Key('model-download-${spec.key}')),
              matching: find.byType(CupertinoButton),
            ),
          )
          .onPressed,
      isNull,
      reason: 'the real repository would throw on the unknown key',
    );
    expect(
      find.textContaining('can\'t download on this engine yet'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('custom-repo-add')),
      240,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('custom-repo-field')),
      'org/some-model',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CupertinoButton>(
            find.ancestor(
              of: find.text('Add model'),
              matching: find.byType(CupertinoButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('arrive in a future update'), findsOneWidget);
  }, variant: iosChrome);

  testWidgets('the system prompt editor commits and resets', (tester) async {
    final preferences = InMemoryPreferencesRepository(
      const AppPreferences(advancedMode: true),
    );
    await pumpWithRepositories(
      tester,
      preferences: preferences,
      child: const SystemPromptScreen(),
    );
    await tester.enterText(
      find.byKey(const Key('system-prompt-field')),
      '  Answer like a pirate.  ',
    );
    // Commits are debounced (every text change would otherwise republish
    // the root-watched preferences and fsync a file).
    await tester.pump(const Duration(milliseconds: 500));
    expect(preferences.preferences.systemPrompt, 'Answer like a pirate.');

    await tester.tap(find.byKey(const Key('system-prompt-reset')));
    await tester.pumpAndSettle();
    expect(
      preferences.preferences.systemPrompt,
      isNull,
      reason: 'reset flushes',
    );
  }, variant: iosChrome);

  testWidgets('reasoning opened by streaming latches when it settles', (
    tester,
  ) async {
    setViewport(tester);
    final container = buildContainer();
    addTearDown(container.dispose);
    ChatMessage message({required bool streaming}) => ChatMessage(
      id: 'a1',
      role: MessageRole.assistant,
      text: 'The answer.',
      reasoning: 'a private mid-read thought',
      createdAt: DateTime.utc(2026, 8, 2),
      isStreaming: streaming,
    );
    Widget pump(ChatMessage m) => UncontrolledProviderScope(
      container: container,
      child: wrapApp(
        child: CupertinoPageScaffold(
          child: MessageBubble(
            message: m,
            canRegenerate: false,
            idle: false,
            stoppedTokens: null,
          ),
        ),
      ),
    );
    await tester.pumpWidget(pump(message(streaming: true)));
    await tester.pump();
    final reasoning = find.text('a private mid-read thought');
    expect(reasoning, findsOneWidget, reason: 'streaming shows live');

    // The run settles with the reader mid-thought: the card must stay
    // open, not snap shut with the default expand preference off.
    await tester.pumpWidget(pump(message(streaming: false)));
    await tester.pumpAndSettle();
    expect(reasoning, findsOneWidget);
  }, variant: iosChrome);

  testWidgets('the root reflects the active style and advanced rows', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      preferences: InMemoryPreferencesRepository(
        const AppPreferences(
          advancedMode: true,
          systemPrompt: 'Short answers.',
        ).withStyle('gemma4', ResponseStyle.precise),
      ),
      child: const SettingsScreen(),
    );
    expect(find.text('Precise'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    // The About row can sit below the fold once rows grow with the wide
    // test font.
    await tester.scrollUntilVisible(
      find.byKey(const Key('about-row')),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('settings-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text(appVersion), findsOneWidget);
  }, variant: iosChrome);
}
