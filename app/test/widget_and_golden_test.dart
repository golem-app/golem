import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_benchmark_repository.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_settings_repository.dart';
import 'package:golem_flutter/core/theme/golem_theme.dart';
import 'package:golem_flutter/features/benchmark/benchmark_screen.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/chat/widgets/composer.dart';
import 'package:golem_flutter/features/chat/widgets/message_bubble.dart';
import 'package:golem_flutter/features/settings/settings_screen.dart';
import 'package:golem_flutter/features/splash/splash_screen.dart';

const viewport = Size(402, 874);

Future<String> _fixtureAsset(String key) async =>
    '[{"role": "user", "content": "${'x' * 400}"}]';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('splash golden', (tester) async {
    _setViewport(tester);
    await tester.pumpWidget(
      // The splash now reads the backend signal for honest copy; the
      // default scope resolves to the fake, matching the recorded golden.
      ProviderScope(
        child: _app(
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
  });

  for (final brightness in Brightness.values) {
    testWidgets('empty chat ${brightness.name} golden', (tester) async {
      await _pumpWithRepositories(
        tester,
        brightness: brightness,
        child: const ChatScreen(),
      );
      await expectLater(
        find.byType(ChatScreen),
        matchesGoldenFile('goldens/empty-chat-${brightness.name}.png'),
      );
    });

    testWidgets('populated reasoning ${brightness.name} golden', (
      tester,
    ) async {
      await _pumpWithRepositories(
        tester,
        brightness: brightness,
        history: _seedHistory(),
        child: const ChatScreen(),
      );
      await expectLater(
        find.byType(ChatScreen),
        matchesGoldenFile('goldens/populated-reasoning-${brightness.name}.png'),
      );
    });
  }

  testWidgets('drawer and rename overlay goldens', (tester) async {
    await _pumpWithRepositories(
      tester,
      history: _seedHistory(),
      child: const ChatScreen(),
    );
    await tester.tap(find.byKey(const Key('open-drawer')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ChatScreen),
      matchesGoldenFile('goldens/drawer.png'),
    );
    await tester.tap(find.byKey(const Key('conversation-menu-chat-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('rename-sheet')),
      matchesGoldenFile('goldens/rename-sheet.png'),
    );
  });

  testWidgets('settings states dark golden', (tester) async {
    await _pumpWithRepositories(
      tester,
      brightness: Brightness.dark,
      // 42% of the pinned Gemma MLX artifact, mid-pause, with the Qwen GGUF
      // installed — exercises progress, resume, and delete affordances.
      model: const ModelState(
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
      ),
      child: const SettingsScreen(),
    );
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings-dark.png'),
    );

    // The generation section lives below the fold; capture it scrolled
    // into view so the per-model controls keep visual coverage.
    await tester.scrollUntilVisible(
      find.byKey(const Key('gen-context-gemma4')),
      260,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('settings-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings-generation-dark.png'),
    );
  });

  testWidgets('benchmark result golden', (tester) async {
    await _pumpWithRepositories(tester, child: const BenchmarkScreen());
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
      matchesGoldenFile('goldens/benchmark.png'),
    );
  });

  testWidgets('iOS targets, labels, contrast, and enlarged text', (
    tester,
  ) async {
    await _pumpWithRepositories(tester, child: const ChatScreen());
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
          container: _container(),
          child: _app(child: const SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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

    await _pumpWithRepositories(
      tester,
      backend: backend,
      // Simulated downloads with real inference: the mixed state a dev
      // build can genuinely be in.
      model: const ModelState(simulated: true),
      child: const SettingsScreen(),
    );
    expect(find.byKey(const Key('simulation-banner')), findsNothing);
    expect(find.textContaining('SIMULATED'), findsNothing);
    // The download axis stays honestly simulated under the fake
    // repository; asserted before scrolling because the ListView
    // virtualizes the header away.
    expect(
      find.textContaining('deterministic download simulation'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('runtime-toggle-button')),
      260,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('settings-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Load Runtime'), findsOneWidget);
    expect(find.textContaining('Simulated Runtime'), findsNothing);
    // The runtime rows: an honest bare state and no simulated qualifier
    // on the empty active-model row.
    expect(find.text('Unloaded'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.textContaining('None · simulated'), findsNothing);

    await tester.scrollUntilVisible(
      find.textContaining('Inference runs the local engine'),
      260,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('settings-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    // About composes per-axis honesty: real inference sentence next to
    // the simulated-downloads sentence.
    expect(
      find.textContaining('deterministic simulation of the pinned catalog'),
      findsOneWidget,
    );
    expect(find.textContaining('UI evaluation build'), findsNothing);

    await _pumpWithRepositories(
      tester,
      backend: backend,
      child: const ChatScreen(),
    );
    expect(
      find.textContaining('generates with a local on-device model'),
      findsOneWidget,
    );
    expect(find.textContaining('simulated model'), findsNothing);

    await _pumpWithRepositories(
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
  });

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
          child: _app(
            brightness: Brightness.dark,
            child: Composer(
              controller: controller,
              focus: focus,
              reasoningEnabled: false,
              generation: phase,
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
  });

  testWidgets('an empty failed assistant message renders no ghost bubble', (
    tester,
  ) async {
    Widget wrap(ChatMessage message) => ProviderScope(
      child: _app(child: MessageBubble(message: message, canRegenerate: false)),
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

    // While streaming, the same empty message is the typing indicator and
    // must stay visible.
    await tester.pumpWidget(wrap(ghost.copyWith(isStreaming: true)));
    expect(find.byKey(const Key('message-assistant-ghost')), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
  });
}

Widget _app({
  required Widget child,
  Brightness brightness = Brightness.light,
}) => CupertinoApp(
  debugShowCheckedModeBanner: false,
  theme: GolemTheme.theme(brightness),
  home: child,
);

ProviderContainer _container({
  ChatHistorySnapshot? history,
  ModelState model = const ModelState(),
  InferenceBackendConfig? backend,
}) {
  final directory = Directory.systemTemp.createTempSync('golem-widget-test-');
  return ProviderContainer(
    overrides: [
      if (backend != null) inferenceBackendProvider.overrideWithValue(backend),
      chatHistoryRepositoryProvider.overrideWithValue(
        InMemoryChatHistoryRepository(
          history ?? const ChatHistorySnapshot(conversations: []),
        ),
      ),
      inferenceRepositoryProvider.overrideWithValue(
        FakeInferenceRepository(eventDelay: Duration.zero),
      ),
      settingsRepositoryProvider.overrideWithValue(
        InMemorySettingsRepository(),
      ),
      modelCatalogEntriesProvider.overrideWithValue(modelCatalog),
      modelManagementRepositoryProvider.overrideWithValue(_ModelFake(model)),
      benchmarkRepositoryProvider.overrideWithValue(
        FakeBenchmarkRepository(
          directory,
          readAsset: _fixtureAsset,
          delay: Duration.zero,
        ),
      ),
    ],
  );
}

Future<void> _pumpWithRepositories(
  WidgetTester tester, {
  required Widget child,
  Brightness brightness = Brightness.light,
  ChatHistorySnapshot? history,
  ModelState model = const ModelState(),
  InferenceBackendConfig? backend,
}) async {
  _setViewport(tester);
  final container = _container(
    history: history,
    model: model,
    backend: backend,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _app(brightness: brightness, child: child),
    ),
  );
  if (find.byType(ChatScreen).evaluate().isNotEmpty) {
    final context = tester.element(find.byType(ChatScreen));
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/golem_mascot.png'),
        context,
      ),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void _setViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

ChatHistorySnapshot _seedHistory() {
  final conversation = ChatConversation(
    id: 'chat-1',
    title: 'Plan a quiet weekend',
    updatedAt: DateTime.utc(2026, 8, 2),
    reasoningEnabled: true,
    messages: [
      ChatMessage(
        id: 'user-1',
        role: MessageRole.user,
        text: 'Suggest a calm weekend plan close to home.',
        createdAt: DateTime.utc(2026, 8, 2),
      ),
      ChatMessage(
        id: 'assistant-1',
        role: MessageRole.assistant,
        text:
            'Start slowly: coffee, a long walk, and an afternoon with a good book.',
        reasoning: 'I’ll balance rest, movement, and one small delight.',
        metrics: const InferenceMetrics(
          promptTokensPerSecond: 144,
          decodeTokensPerSecond: 21.4,
          tokenCount: 18,
          elapsedSeconds: 0.84,
        ),
        createdAt: DateTime.utc(2026, 8, 2),
      ),
    ],
  );
  return ChatHistorySnapshot(
    conversations: [conversation],
    activeId: conversation.id,
  );
}

final class _ModelFake implements ModelManagementRepository {
  _ModelFake(this.state);
  ModelState state;

  @override
  Future<ModelState> load() async => state;
  @override
  Future<ModelState> loadRuntime() async => state;
  @override
  Future<ModelState> unloadRuntime() async => state;
  @override
  Stream<ModelState> download(String artifactKey) => Stream.value(state);
  @override
  Future<ModelState> pause(String artifactKey) async => state;
  @override
  Future<ModelState> cancel(String artifactKey) async => state;
  @override
  Future<ModelState> delete(String artifactKey) async => state;
}
