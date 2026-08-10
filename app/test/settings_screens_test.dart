import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_profile.dart';
import 'package:golem_flutter/core/app_version.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/domain/resolved_repository.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/services/custom_repository_resolver.dart';
import 'package:golem_flutter/core/services/repository_resolver.dart';
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

/// Replays a scripted resolution so the card's states are reachable without a
/// network. A list, because the weight-choice flow resolves twice.
final class _ScriptedResolver implements CustomRepositoryResolver {
  _ScriptedResolver(this.outcomes);

  final List<RepositoryResolution> outcomes;
  final List<String?> requestedWeights = [];
  int _calls = 0;

  @override
  Future<RepositoryResolution> resolve({
    required String repository,
    required ModelEngine engine,
    String ref = 'main',
    String? weightsFile,
    Set<String> existingKeys = const {},
  }) async {
    requestedWeights.add(weightsFile);
    final index = _calls < outcomes.length ? _calls : outcomes.length - 1;
    _calls++;
    return outcomes[index];
  }
}

ResolvedRepository _resolution({int bytes = 1214873856}) => ResolvedRepository(
  commitSha: 'f' * 40,
  quantization: 'Q4_0',
  displayName: 'Tiny',
  files: [
    ModelArtifactFile(
      path: 'tiny-Q4_0.gguf',
      bytes: bytes,
      role: ModelFileRole.weights,
    ),
  ],
);

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
      find.byKey(const Key('custom-repo-resolve')),
      240,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    // Empty field: nothing to resolve yet.
    expect(
      tester
          .widget<CupertinoButton>(
            find.ancestor(
              of: find.text('Resolve'),
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

    // Nothing is stored by resolving; the user sees what it found first.
    await tester.tap(find.byKey(const Key('custom-repo-resolve')));
    await tester.pumpAndSettle();
    expect(preferences.preferences.customModels, isEmpty);
    expect(find.byKey(const Key('custom-repo-detail')), findsOneWidget);
    expect(find.text('Not recognized'), findsOneWidget);

    await tester.tap(find.byKey(const Key('custom-repo-add')));
    await tester.pumpAndSettle();

    final spec = preferences.preferences.customModels.single;
    expect(spec.repository, 'org/tiny-model-GGUF');
    expect(spec.key, startsWith('custom-org-tiny-model-gguf-'));
    expect(spec.engine, ModelEngine.gguf);
    // The resolution is what got stored, pinned to a commit rather than a ref.
    expect(spec.resolved, isNotNull);
    expect(spec.resolved!.commitSha, hasLength(40));
    expect(spec.resolved!.files, isNotEmpty);
    // A simulation proves no profile, so the entry still cannot be activated.
    expect(spec.profile, isNull);
    expect(spec.toCatalogEntry().profileKey, unresolvedProfileKey);
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

  testWidgets('a llama build hides MLX cards it can never load', (
    tester,
  ) async {
    // Real llama-only builds must not offer multi-gigabyte MLX downloads
    // that `auto` can never load (#63) — the cards disappear entirely.
    await pumpWithRepositories(
      tester,
      backend: const InferenceBackendConfig(
        kind: InferenceBackendKind.llama,
        profileKey: 'gemma4',
        artifactKey: 'gemma4-gguf',
        modelPath: 'documents:models/gemma4-gguf/x.gguf',
        modelPathFromCatalog: true,
      ),
      model: const ModelState(),
      child: const ModelsScreen(),
    );
    expect(find.byKey(const Key('model-card-gemma4-gguf')), findsOneWidget);
    expect(find.byKey(const Key('model-card-gemma4-mlx')), findsNothing);
    expect(find.byKey(const Key('model-card-qwen35-mlx')), findsNothing);

    // An already-installed MLX leftover stays visible for deletion.
    await pumpWithRepositories(
      tester,
      backend: const InferenceBackendConfig(
        kind: InferenceBackendKind.llama,
        profileKey: 'gemma4',
        artifactKey: 'gemma4-gguf',
        modelPath: 'documents:models/gemma4-gguf/x.gguf',
        modelPathFromCatalog: true,
      ),
      model: const ModelState(
        artifacts: {
          'gemma4-mlx': ArtifactStatus(
            phase: ArtifactPhase.installed,
            downloadedBytes: 100,
          ),
        },
      ),
      child: const ModelsScreen(),
    );
    expect(find.byKey(const Key('model-card-gemma4-mlx')), findsOneWidget);
  }, variant: iosChrome);

  testWidgets('the fake backend keeps the whole catalog visible', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      model: const ModelState(simulated: true),
      child: const ModelsScreen(),
    );
    for (final key in const [
      'gemma4-mlx',
      'gemma4-gguf',
      'qwen35-2b-mlx',
      'qwen35-2b-gguf',
      'qwen35-mlx',
      'qwen35-gguf',
    ]) {
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('models-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(Key('model-card-$key')),
        240,
        scrollable: scrollable,
      );
      expect(find.byKey(Key('model-card-$key')), findsOneWidget);
    }
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
      find.byKey(const Key('custom-repo-resolve')),
      240,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('custom-repo-field')),
      'org/some-model',
    );
    await tester.pumpAndSettle();
    // Resolving is offered on a real engine now, and the copy no longer
    // promises a future update.
    expect(
      tester
          .widget<CupertinoButton>(
            find.ancestor(
              of: find.text('Resolve'),
              matching: find.byType(CupertinoButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.textContaining('arrive in a future update'), findsNothing);
    expect(find.textContaining('Only public repositories'), findsOneWidget);
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
    ChatMessage message({required bool streaming}) => ChatMessage.text(
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

  /// Reveals the Advanced-mode custom repository card and types a name into it.
  Future<InMemoryPreferencesRepository> pumpCard(
    WidgetTester tester,
    CustomRepositoryResolver resolver,
  ) async {
    final preferences = InMemoryPreferencesRepository(
      const AppPreferences(advancedMode: true),
    );
    await pumpWithRepositories(
      tester,
      preferences: preferences,
      model: const ModelState(simulated: true),
      resolver: resolver,
      child: const ModelsScreen(),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('custom-repo-resolve')),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('models-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('custom-repo-field')),
      'org/tiny-GGUF',
    );
    await tester.pumpAndSettle();
    return preferences;
  }

  testWidgets('a refused repository says why and stores nothing', (
    tester,
  ) async {
    final preferences = await pumpCard(
      tester,
      _ScriptedResolver([const RepositoryRejected(RepositoryRejection.gated)]),
    );
    await tester.tap(find.byKey(const Key('custom-repo-resolve')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('custom-repo-error')), findsOneWidget);
    expect(find.textContaining('accepting its licence'), findsOneWidget);
    expect(find.byKey(const Key('custom-repo-detail')), findsNothing);
    // Refusal must not leave a half-added entry behind.
    expect(preferences.preferences.customModels, isEmpty);
    // Retry is offered rather than making the user retype.
    expect(find.text('Try again'), findsOneWidget);
  }, variant: iosChrome);

  testWidgets('editing after a refusal clears it', (tester) async {
    await pumpCard(
      tester,
      _ScriptedResolver([
        const RepositoryRejected(RepositoryRejection.notFoundOrPrivate),
      ]),
    );
    await tester.tap(find.byKey(const Key('custom-repo-resolve')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('custom-repo-error')), findsOneWidget);

    // A message about the previous name would be wrong for the new one.
    await tester.enterText(
      find.byKey(const Key('custom-repo-field')),
      'org/other-GGUF',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('custom-repo-error')), findsNothing);
    expect(find.text('Resolve'), findsOneWidget);
  }, variant: iosChrome);

  testWidgets('several weight files ask which, then resolve it', (
    tester,
  ) async {
    final resolver = _ScriptedResolver([
      const RepositoryNeedsWeightChoice([
        ResolvedWeightCandidate('tiny-Q4_0.gguf', 1214873856),
        ResolvedWeightCandidate('tiny-Q8_0.gguf', 2214873856),
      ]),
      RepositoryResolved(
        resolved: _resolution(),
        profile: null,
        templateFingerprint: 'ab' * 32,
      ),
    ]);
    final preferences = await pumpCard(tester, resolver);
    await tester.tap(find.byKey(const Key('custom-repo-resolve')));
    await tester.pumpAndSettle();

    // Nothing is chosen for the user, and nothing is stored yet.
    expect(find.byKey(const Key('custom-repo-detail')), findsNothing);
    expect(preferences.preferences.customModels, isEmpty);
    expect(
      find.byKey(const Key('custom-repo-candidate-tiny-Q8_0.gguf')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('custom-repo-candidate-tiny-Q4_0.gguf')),
    );
    await tester.pumpAndSettle();
    // The choice is carried into the second resolution, not guessed again.
    expect(resolver.requestedWeights, [null, 'tiny-Q4_0.gguf']);
    expect(find.byKey(const Key('custom-repo-detail')), findsOneWidget);
  }, variant: iosChrome);

  testWidgets('a recognized template names the profile and stores it', (
    tester,
  ) async {
    final preferences = await pumpCard(
      tester,
      _ScriptedResolver([
        RepositoryResolved(
          resolved: _resolution(),
          profile: qwen35ProfileSpec,
          templateFingerprint: 'cd' * 32,
        ),
      ]),
    );
    await tester.enterText(
      find.byKey(const Key('custom-repo-revision')),
      'v1.2',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('custom-repo-resolve')));
    await tester.pumpAndSettle();

    expect(find.text('qwen35'), findsOneWidget);
    expect(find.text('Not recognized'), findsNothing);
    // The commit is shown, abbreviated — never the ref that was typed.
    expect(find.text('ffffffffffff'), findsOneWidget);
    expect(find.text('1.21 GB'), findsWidgets);

    await tester.tap(find.byKey(const Key('custom-repo-add')));
    await tester.pumpAndSettle();
    final spec = preferences.preferences.customModels.single;
    expect(spec.revision, 'v1.2', reason: 'the ref the user asked for');
    expect(spec.resolved!.commitSha, 'f' * 40, reason: 'what installs');
    expect(spec.profile?.key, 'qwen35');
    // A proven profile is what lets this entry be activated at all.
    expect(spec.toCatalogEntry().profileKey, 'qwen35');
    await tester.pump(const Duration(milliseconds: 1600));
  }, variant: iosChrome);
}
