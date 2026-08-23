import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_profile.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/app_version.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/domain/repository_resolution.dart';
import 'package:golem_flutter/core/domain/resolved_repository.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_repository_resolver.dart';
import 'package:golem_flutter/core/services/cache_probe.dart';
import 'package:golem_flutter/core/widgets/settings_rows.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';
import 'package:golem_flutter/features/settings/appearance_screen.dart';
import 'package:golem_flutter/features/settings/storage_screen.dart';
import 'package:golem_flutter/features/settings/models_screen.dart';
import 'package:golem_flutter/features/settings/privacy_screen.dart';
import 'package:golem_flutter/features/settings/settings_screen.dart';
import 'package:golem_flutter/features/settings/system_prompt_screen.dart';
import 'package:golem_flutter/l10n/generated/app_localizations.dart';

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
    // tool/device_install.sh stamps the commit so a tester can tell which
    // build is in hand; a trailing + marks an uncommitted tree.
    expect(aboutVersionLabel(version: '1.0.0', stamp: ''), '1.0.0');
    expect(
      aboutVersionLabel(version: '1.0.0', stamp: 'f722edc+'),
      '1.0.0 · f722edc+',
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

  testWidgets('settled reasoning collapses unless the preference expands it', (
    tester,
  ) async {
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
  }, variant: iosChrome);

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

  testWidgets('a cache the probe cannot measure can still be cleared', (
    tester,
  ) async {
    // Unknown is not zero (#154): a failed probe used to print 0 MB and, on
    // that zero, disable the one action that would have freed the space.
    await pumpWithRepositories(
      tester,
      cache: _ThrowingCacheProbe(),
      child: const StorageScreen(),
    );
    await tester.pumpAndSettle();
    expect(find.text('0 MB'), findsNothing);
    expect(
      tester.widget<SettingsNavRow>(find.byKey(const Key('clear-cache'))).onTap,
      isNotNull,
    );
  }, variant: iosChrome);

  testWidgets('a running download shows the dismissible note in its card', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      model: const ModelState(
        simulated: true,
        artifacts: {
          'gemma4-mlx': ArtifactStatus(
            phase: ArtifactPhase.downloading,
            downloadedBytes: 900000000,
          ),
        },
      ),
      child: const ModelsScreen(),
    );
    expect(
      find.byKey(const Key('model-download-note-gemma4-mlx')),
      findsOneWidget,
    );
    expect(find.textContaining('Keep Golem open'), findsOneWidget);
    expect(find.byKey(const Key('download-note-dismiss')), findsNothing);
  });

  for (final (locale, scale) in [
    (const Locale('en'), 1.0),
    (const Locale('pl'), 1.6),
  ]) {
    testWidgets('a verifying card names the phase once and offers Cancel '
        '(${locale.languageCode} @ $scale)', (tester) async {
      // Three "Verifying" on one card — status row, bar caption, chip —
      // overflowed the row by 58 px in Polish.
      await pumpWithRepositories(
        tester,
        locale: locale,
        textScale: scale,
        model: const ModelState(
          simulated: true,
          artifacts: {
            'gemma4-mlx': ArtifactStatus(
              phase: ArtifactPhase.verifying,
              downloadedBytes: 3583086498,
              verifiedBytes: 900000000,
            ),
          },
        ),
        child: const ModelsScreen(),
      );
      expect(tester.takeException(), isNull);
      final card = find.byKey(const Key('model-card-gemma4-mlx'));
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining(RegExp('Verif|Weryf')),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('model-progress-gemma4-mlx')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('model-cancel-gemma4-mlx')), findsOneWidget);
      expect(find.byKey(const Key('model-pause-gemma4-mlx')), findsNothing);
    });
  }

  testWidgets('a paused card quotes the amount left under its bar', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      model: const ModelState(
        simulated: true,
        artifacts: {
          'gemma4-mlx': ArtifactStatus(
            phase: ArtifactPhase.paused,
            downloadedBytes: 1505735776,
          ),
        },
      ),
      child: const ModelsScreen(),
    );
    // Mounted but rendering nothing: the mount guard is deliberately wider
    // than the note's own visibility rule, so what the user sees is decided in
    // one place (#125).
    expect(
      find.byKey(const Key('model-download-note-gemma4-mlx')),
      findsOneWidget,
    );
    expect(find.textContaining('Keep Golem open'), findsNothing);
    expect(find.textContaining(' left'), findsOneWidget);
  });

  testWidgets('the two model badges are told apart by more than their words', (
    tester,
  ) async {
    // One of these was a private copy of GolemBadge that had already drifted a
    // padding point from the shared one (#131). Both are on screen at once, so
    // "which fact is this" has to survive not reading the label.
    await pumpWithRepositories(
      tester,
      model: const ModelState(
        simulated: true,
        activeArtifactKey: 'gemma4-mlx',
        runtime: RuntimePhase.loaded,
        artifacts: {
          'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
        },
      ),
      overrides: [
        // Residency is the engine's, not the store's, and a simulated backend
        // never holds weights — so it is stated rather than staged.
        inferenceResidencyProvider.overrideWithValue(
          const InferenceResidency(loaded: true, catalogKey: 'gemma4-mlx'),
        ),
      ],
      child: const ModelsScreen(),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(ModelsScreen)));
    Color badgeColor(String label) {
      final badge = tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
      return (badge.decoration! as BoxDecoration).color!;
    }

    expect(find.text(l10n.activeBadge), findsOneWidget);
    expect(find.text(l10n.loadedBadge), findsOneWidget);
    expect(
      badgeColor(l10n.activeBadge),
      isNot(badgeColor(l10n.loadedBadge)),
      reason: 'the selected badge leads; the resident one sits quietly beside',
    );
  });

  testWidgets('pausing a card leaves the card itself where it was', (
    tester,
  ) async {
    // Found on device: the foreground-speed note used to sit above every card,
    // so the moment a transfer stopped being `downloading` — a pause, or any
    // file boundary of a multi-file artifact — its height left the list and
    // yanked every card up under a reader watching one (#125). In its card the
    // note can only move that card's own contents.
    await pumpWithRepositories(
      tester,
      models: _PausableModels(
        const ModelState(
          simulated: true,
          artifacts: {
            'gemma4-mlx': ArtifactStatus(
              phase: ArtifactPhase.downloading,
              downloadedBytes: 900000000,
            ),
          },
        ),
      ),
      child: const ModelsScreen(),
    );
    expect(find.textContaining('Keep Golem open'), findsOneWidget);
    final before = tester.getTopLeft(
      find.byKey(const Key('model-card-gemma4-mlx')),
    );

    // Through the controller rather than the card's Pause button: at this
    // viewport the button sits below the fold, and scrolling to it puts the
    // card's top — the thing that must not move — off screen.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ModelsScreen)),
    );
    await container.read(modelControllerProvider.notifier).pause('gemma4-mlx');
    await tester.pumpAndSettle();

    expect(find.textContaining('Keep Golem open'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('model-card-gemma4-mlx'))),
      before,
    );
  });

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
    // The draft is spent: both fields empty and the resolution gone, so the
    // card reads as ready for the next repository rather than as the last
    // one still pending. Persisting the spec grows the list this card sits
    // in, which is what used to leave the added name typed in (#129).
    expect(
      tester
          .widget<CupertinoTextField>(
            find.byKey(const Key('custom-repo-field')),
          )
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byKey(const Key('custom-repo-detail')), findsNothing);
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
    // Unresolved is now the reason it cannot be fetched, not the engine: its
    // file list is synthesized, so there is nothing to request.
    expect(find.textContaining('has not been resolved'), findsOneWidget);

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

  testWidgets('the root model row names the chat\'s model, not the boot one', (
    tester,
  ) async {
    // The visible half of the one-derivation rule (#129). The row used to
    // resolve from residency alone, so with nothing loaded yet it named the
    // build's boot artifact while chat, the picker and the Models screen all
    // named the conversation's choice.
    await pumpWithRepositories(
      tester,
      backend: const InferenceBackendConfig(
        kind: InferenceBackendKind.mlx,
        profileKey: 'gemma4',
        artifactKey: 'gemma4-mlx',
        modelPath: '/models/gemma',
        modelPathFromCatalog: true,
      ),
      model: const ModelState(
        artifacts: {
          'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
          'qwen35-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
        },
      ),
      history: ChatHistorySnapshot(
        activeId: 'chat',
        conversations: [
          ChatConversation(
            id: 'chat',
            title: 'Switched',
            updatedAt: DateTime.utc(2026, 8, 18),
            messages: const [],
            modelKey: 'qwen35-mlx',
          ),
        ],
      ),
      child: const SettingsScreen(identity: AppIdentity.dev),
    );
    expect(find.text('Qwen 3.5 4B'), findsOneWidget);
    expect(find.text('Gemma 4 E2B'), findsNothing);
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
      child: const SettingsScreen(identity: AppIdentity.dev),
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
    CustomRepositoryResolver resolver, {
    List<CustomModelSpec> customModels = const [],
  }) async {
    final preferences = InMemoryPreferencesRepository(
      AppPreferences(advancedMode: true, customModels: customModels),
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

  testWidgets('a resolution survives scrolling the card out of view', (
    tester,
  ) async {
    // Found on device: the models list disposes off-screen children, so a
    // resolution held inside the card vanished when the user scrolled up to
    // look at something and came back, silently sending them round again.
    await pumpCard(
      tester,
      _ScriptedResolver([
        RepositoryResolved(
          resolved: _resolution(),
          profile: qwen35ProfileSpec,
          templateFingerprint: 'ef' * 32,
        ),
      ]),
    );
    await tester.tap(find.byKey(const Key('custom-repo-resolve')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('custom-repo-detail')), findsOneWidget);

    final scrollable = find
        .descendant(
          of: find.byKey(const Key('models-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('models-tab-all')),
      -240,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('custom-repo-detail')), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('custom-repo-add')),
      240,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    // Still resolved, and still the same resolution.
    expect(find.byKey(const Key('custom-repo-detail')), findsOneWidget);
    expect(find.text('qwen35'), findsOneWidget);
    expect(find.text('ffffffffffff'), findsOneWidget);
  }, variant: iosChrome);

  testWidgets('an unresolved entry resolves when it is added again', (
    tester,
  ) async {
    // A repository persisted before resolutions existed loads unresolved, and
    // its card says to add it again. The duplicate guard used to refuse exactly
    // that, and no code path removes a spec — a permanent dead end.
    await pumpCard(
      tester,
      const DeterministicRepositoryResolver(),
      customModels: const [
        CustomModelSpec(repository: 'org/tiny-GGUF', engine: ModelEngine.gguf),
      ],
    );
    await tester.tap(find.byKey(const Key('custom-repo-resolve')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('custom-repo-detail')), findsOneWidget);
    expect(find.byKey(const Key('custom-repo-error')), findsNothing);
    expect(find.textContaining('already been added'), findsNothing);
  }, variant: iosChrome);

  testWidgets('a resolved entry with no recognized template can be added '
      'again', (tester) async {
    // Resolution can succeed while the chat template matches no profile;
    // such an entry never activates, and its card says to add it again. The
    // duplicate guard must not count it, or the advised repair dead-ends.
    await pumpCard(
      tester,
      const DeterministicRepositoryResolver(),
      customModels: [
        CustomModelSpec(
          repository: 'org/tiny-GGUF',
          engine: ModelEngine.gguf,
          resolved: _resolution(),
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('custom-repo-resolve')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('custom-repo-detail')), findsOneWidget);
    expect(find.byKey(const Key('custom-repo-error')), findsNothing);
    expect(find.textContaining('already been added'), findsNothing);
  }, variant: iosChrome);

  testWidgets('an outcome landing after dispose touches nothing', (
    tester,
  ) async {
    // Resolving is tens of seconds of network and Back is one tap, so the
    // outcome can land after the screen is gone. The draft state and its two
    // controllers belong to that screen: only it can decide whether the result
    // still matters.
    final gate = Completer<RepositoryResolution>();
    await pumpCard(tester, _HangingResolver(gate.future));
    await tester.tap(find.byKey(const Key('custom-repo-resolve')));
    await tester.pump();
    expect(find.textContaining('Reading the repository'), findsOneWidget);

    // Dismantling the tree disposes the screen exactly as leaving the route
    // does, without a second screen to lay out.
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(
      RepositoryResolved(
        resolved: _resolution(),
        profile: null,
        templateFingerprint: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  }, variant: iosChrome);
}

/// A resolver that answers only when the test says so, so the gap between the
/// request and its outcome is under the test's control.
final class _HangingResolver implements CustomRepositoryResolver {
  const _HangingResolver(this.outcome);

  final Future<RepositoryResolution> outcome;

  @override
  Future<RepositoryResolution> resolve({
    required String repository,
    required ModelEngine engine,
    String ref = 'main',
    String? weightsFile,
    Set<String> existingKeys = const {},
  }) => outcome;
}

/// The one thing `StaticModels` cannot do: change phase. Only `pause` moves,
/// because that is the transition this file's scroll regression turns on.
final class _PausableModels implements ModelManagementRepository {
  _PausableModels(this._state);

  ModelState _state;

  @override
  Future<ModelState> load() async => _state;

  @override
  Future<ModelState> pause(String artifactKey) async =>
      _state = _state.withArtifact(
        artifactKey,
        _state.statusOf(artifactKey).copyWith(phase: ArtifactPhase.paused),
      );

  @override
  Stream<ModelState> download(String artifactKey) => Stream.value(_state);

  @override
  Future<ModelState> recordRuntime(
    RuntimePhase phase, {
    RuntimeFailureKind? failure,
  }) async => _state;

  @override
  Future<ModelState> cancel(String artifactKey) async => _state;

  @override
  Future<ModelState> delete(String artifactKey) async => _state;

  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => _state;
}

final class _ThrowingCacheProbe implements CacheProbe {
  @override
  Future<int> sizeBytes() async => throw StateError('probe down');
  @override
  Future<void> clear() async {}
}
