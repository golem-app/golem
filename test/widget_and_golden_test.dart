import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_benchmark_repository.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'package:golem_flutter/core/theme/golem_theme.dart';
import 'package:golem_flutter/features/benchmark/benchmark_screen.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
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
      _app(
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
      model: const ModelState(
        backend: BackendId.mlx,
        mlxPhase: DownloadPhase.paused,
        mlxProgress: 0.42,
        runtime: RuntimePhase.unloaded,
      ),
      child: const SettingsScreen(),
    );
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings-dark.png'),
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
}) {
  final directory = Directory.systemTemp.createTempSync('golem-widget-test-');
  return ProviderContainer(
    overrides: [
      chatHistoryRepositoryProvider.overrideWithValue(
        InMemoryChatHistoryRepository(
          history ?? const ChatHistorySnapshot(conversations: []),
        ),
      ),
      inferenceRepositoryProvider.overrideWithValue(
        FakeInferenceRepository(eventDelay: Duration.zero),
      ),
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
}) async {
  _setViewport(tester);
  final container = _container(history: history, model: model);
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
  Future<ModelState> pauseMlx() async => state;
  @override
  Future<ModelState> selectBackend(BackendId backend) async => state;
  @override
  Future<ModelState> unloadRuntime() async => state;
  @override
  Stream<ModelState> downloadMlx() => Stream.value(state);
  @override
  Stream<ModelState> importTurboFieldfare() => Stream.value(state);
}
