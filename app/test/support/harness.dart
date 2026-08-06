import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_benchmark_repository.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/core/services/cache_probe.dart';
import 'package:golem_flutter/core/services/device_storage.dart';
import 'package:golem_flutter/core/theme/golem_theme.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/chat/search_screen.dart';

import 'in_memory_chat_history_repository.dart';
import 'in_memory_preferences_repository.dart';
import 'in_memory_settings_repository.dart';

/// The iPhone 17 logical viewport every widget/golden suite renders in.
const viewport = Size(402, 874);

Future<String> fixtureAsset(String key) async =>
    '[{"role": "user", "content": "${'x' * 400}"}]';

void setViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

/// Widget tests report `TargetPlatform.android` unless overridden, and the
/// chrome layer branches on the platform — golden tests pin the axis with
/// these framework-managed variants (a bare override trips the foundation
/// debug-variable invariant at test end).
const iosChrome = TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS});
const bothChromes = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.iOS,
  TargetPlatform.android,
});

/// Filename suffix for the current variant run of a golden matrix test.
String chromeSuffix() =>
    debugDefaultTargetPlatformOverride == TargetPlatform.android
    ? '-android'
    : '';

Widget wrapApp({
  required Widget child,
  Brightness brightness = Brightness.light,
}) => CupertinoApp(
  debugShowCheckedModeBanner: false,
  theme: GolemTheme.theme(brightness),
  home: child,
);

/// 64 decimal GB, matching the handoff's "… of 64 GB" storage meter.
final class FakeDiskCapacity implements DiskCapacityProbe {
  const FakeDiskCapacity([this.bytes = 64 * 1000 * 1000 * 1000]);
  final int? bytes;

  @override
  Future<int?> totalBytes(String path) async => bytes;
}

/// 61.2 decimal GB free, matching the handoff's Storage headline.
final class FakeDiskSpace implements DiskSpaceProbe {
  const FakeDiskSpace([this.bytes = 61200 * 1000 * 1000]);
  final int? bytes;

  @override
  Future<int?> freeBytes(String path) async => bytes;
}

ProviderContainer buildContainer({
  ChatHistorySnapshot? history,
  ModelState model = const ModelState(),
  InferenceBackendConfig? backend,
  SettingsRepository? settings,
  PreferencesRepository? preferences,
}) {
  final directory = Directory.systemTemp.createTempSync('golem-widget-test-');
  return ProviderContainer(
    overrides: [
      if (backend != null) inferenceBackendProvider.overrideWithValue(backend),
      deviceCapacityProbeProvider.overrideWithValue(const FakeDiskCapacity()),
      diskFreeSpaceProbeProvider.overrideWithValue(const FakeDiskSpace()),
      cacheProbeProvider.overrideWithValue(FakeCacheProbe()),
      documentsPathProvider.overrideWithValue(directory.path),
      preferencesRepositoryProvider.overrideWithValue(
        preferences ?? InMemoryPreferencesRepository(),
      ),
      chatHistoryRepositoryProvider.overrideWithValue(
        InMemoryChatHistoryRepository(
          history ?? const ChatHistorySnapshot(conversations: []),
        ),
      ),
      inferenceRepositoryProvider.overrideWithValue(
        FakeInferenceRepository(eventDelay: Duration.zero),
      ),
      settingsRepositoryProvider.overrideWithValue(
        settings ?? InMemorySettingsRepository(),
      ),
      modelCatalogEntriesProvider.overrideWithValue(modelCatalog),
      modelManagementRepositoryProvider.overrideWithValue(StaticModels(model)),
      benchmarkRepositoryProvider.overrideWithValue(
        FakeBenchmarkRepository(
          directory,
          readAsset: fixtureAsset,
          delay: Duration.zero,
        ),
      ),
    ],
  );
}

Future<void> pumpWithRepositories(
  WidgetTester tester, {
  required Widget child,
  Brightness brightness = Brightness.light,
  ChatHistorySnapshot? history,
  ModelState model = const ModelState(),
  InferenceBackendConfig? backend,
}) async {
  setViewport(tester);
  final container = buildContainer(
    history: history,
    model: model,
    backend: backend,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: wrapApp(brightness: brightness, child: child),
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

/// Pumps a routed app (chat at `/`, search at `/search`) already
/// navigated to the search screen — it pops back to chat, so it needs a
/// real router underneath.
Future<void> pumpSearchScreen(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  ChatHistorySnapshot? history,
}) async {
  setViewport(tester);
  final container = buildContainer(history: history);
  addTearDown(container.dispose);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const ChatScreen()),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp.router(
        debugShowCheckedModeBanner: false,
        theme: GolemTheme.theme(brightness),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/search');
  await tester.pumpAndSettle();
}

/// A markdown-rich transcript for renderer goldens: inline code, a
/// fenced block, and a list, kept separate from [seedHistory] so drawer
/// and rename goldens don't re-record when this seed evolves.
///
/// The date sits firmly in the past on purpose: search-result cards
/// print it relative to the wall clock, and a seed near "now" would bake
/// Today/Yesterday into goldens that break the next day.
ChatHistorySnapshot markdownHistory() {
  final conversation = ChatConversation(
    id: 'chat-md',
    title: 'Read a CSV without pandas',
    updatedAt: DateTime.utc(2026, 8, 2),
    messages: [
      ChatMessage(
        id: 'user-md',
        role: MessageRole.user,
        text: 'Read a CSV in Python without pandas.',
        createdAt: DateTime.utc(2026, 8, 2),
      ),
      ChatMessage(
        id: 'assistant-md',
        role: MessageRole.assistant,
        text:
            'Use the built-in `csv` module. It streams row by row.\n\n'
            '```python\nimport csv\n\ndef rows(path):\n'
            '    with open(path, newline="") as file:\n'
            '        yield from csv.reader(file)\n```\n\n'
            'Two things worth knowing:\n\n'
            '- `newline=""` stops Python mangling quoted line breaks.\n'
            '- Swap in **DictReader** if the file has a header row.',
        metrics: const InferenceMetrics(
          promptTokensPerSecond: 144,
          decodeTokensPerSecond: 24.6,
          tokenCount: 182,
          elapsedSeconds: 7.4,
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

ChatHistorySnapshot seedHistory() {
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

/// A frozen model repository: every operation reports the same state.
final class StaticModels implements ModelManagementRepository {
  const StaticModels(this.state);
  final ModelState state;

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
  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => state;
}
