import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_benchmark_repository.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/core/theme/golem_theme.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';

import 'in_memory_chat_history_repository.dart';
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

ProviderContainer buildContainer({
  ChatHistorySnapshot? history,
  ModelState model = const ModelState(),
  InferenceBackendConfig? backend,
  SettingsRepository? settings,
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
}
