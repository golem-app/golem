import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/fake_model_management_repository.dart';
import 'package:golem_flutter/features/chat/widgets/recovery_banner.dart';

import 'support/harness.dart';
import 'support/in_memory_chat_history_repository.dart';

const _catalog = [
  ModelCatalogEntry(
    key: 'test-gguf',
    displayName: 'Test Model',
    engine: ModelEngine.gguf,
    quantization: 'Q4_0',
    repository: 'example/test-gguf',
    revision: 'fedcba9876543210',
    profileKey: 'gemma4',
    files: [
      ModelArtifactFile(path: 'model.gguf', bytes: 2600000000, sha256: 'bb'),
    ],
  ),
];

void main() {
  testWidgets('the missing-model banner offers the sized download CTA', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('golem-banner-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final models = FakeModelManagementRepository(
      File('${directory.path}/model.json'),
      catalog: _catalog,
      activeArtifactKey: 'test-gguf',
      stepDelay: Duration.zero,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const CupertinoPageScaffold(
            child: RecoveryBanner(
              failure: ChatFailure(
                kind: ChatFailureKind.missingModel,
                artifactKey: 'test-gguf',
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/models',
          builder: (context, state) => const CupertinoPageScaffold(
            child: SizedBox(key: Key('settings-stub')),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWithValue(_catalog),
          modelManagementRepositoryProvider.overrideWithValue(models),
        ],
        child: CupertinoApp.router(routerConfig: router),
      ),
    );
    // The fake repository does real file IO, which cannot complete inside
    // the widget test's fake-async zone — give it real-async windows.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Download \u2066Test Model\u2069 (\u20662.6 GB\u2069)'),
      findsOneWidget,
    );

    // The tap starts the simulated download and lands on Settings, where
    // the model card owns progress.
    await tester.tap(find.byKey(const Key('download-active-model')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-download-consent')), findsOneWidget);
    await tester.tap(find.byKey(const Key('model-download-confirm')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-stub')), findsOneWidget);
    // The CTA's job is to start the download (completion timing belongs to
    // the fake repository's own tests).
    final status = await tester.runAsync(() => models.load());
    expect(
      status!.statusOf('test-gguf').phase,
      isNot(ArtifactPhase.notDownloaded),
    );
  });

  testWidgets('an ordinary failure shows no download CTA', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: RecoveryBanner(
              failure: ChatFailure(kind: ChatFailureKind.generic),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('download-active-model')), findsNothing);
    expect(find.byKey(const Key('retry-generation')), findsOneWidget);
    expect(find.byKey(const Key('start-new-chat')), findsNothing);
  });

  testWidgets('memory failures keep Retry — retrying can succeed', (
    tester,
  ) async {
    for (final kind in [
      ChatFailureKind.outOfMemory,
      ChatFailureKind.insufficientMemory,
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: RecoveryBanner(failure: ChatFailure(kind: kind)),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('retry-generation')), findsOneWidget);
      expect(find.byKey(const Key('start-new-chat')), findsNothing);
    }
  });

  testWidgets('context exhaustion offers New chat and never Retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: RecoveryBanner(
              failure: ChatFailure(kind: ChatFailureKind.contextExhausted),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('retry-generation')), findsNothing);
    expect(find.byKey(const Key('start-new-chat')), findsOneWidget);
    expect(find.byKey(const Key('discard-generation')), findsOneWidget);
  });

  testWidgets('a missing attachment offers removal, never a futile retry', (
    tester,
  ) async {
    final conversation = ChatConversation(
      id: 'chat',
      title: 'Image',
      updatedAt: DateTime.utc(2026, 8, 12),
      messages: [
        ChatMessage.text(
          id: 'user',
          role: MessageRole.user,
          text: 'Describe this',
          createdAt: DateTime.utc(2026, 8, 12),
        ),
        ChatMessage.text(
          id: 'draft',
          role: MessageRole.assistant,
          text: '',
          createdAt: DateTime.utc(2026, 8, 12),
        ),
      ],
    );
    final history = InMemoryChatHistoryRepository(
      ChatHistorySnapshot(
        conversations: [conversation],
        activeId: conversation.id,
      ),
    );
    await pumpWithRepositories(
      tester,
      chatHistory: history,
      child: const CupertinoPageScaffold(
        child: RecoveryBanner(
          failure: ChatFailure(kind: ChatFailureKind.attachmentUnavailable),
        ),
      ),
    );

    expect(find.byKey(const Key('retry-generation')), findsNothing);
    expect(find.byKey(const Key('remove-failed-turn')), findsOneWidget);
    expect(
      find.textContaining('image in this conversation is no longer available'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('remove-failed-turn')));
    await tester.pumpAndSettle();
    expect(history.snapshot.conversations.single.messages, isEmpty);
  });

  testWidgets('an unavailable model opens the per-chat model picker', (
    tester,
  ) async {
    final conversation = ChatConversation(
      id: 'chat',
      title: 'Persisted',
      updatedAt: DateTime.utc(2026, 8, 12),
      messages: const [],
    );
    await pumpWithRepositories(
      tester,
      history: ChatHistorySnapshot(
        conversations: [conversation],
        activeId: conversation.id,
      ),
      child: const CupertinoPageScaffold(
        child: RecoveryBanner(
          failure: ChatFailure(kind: ChatFailureKind.modelUnavailable),
        ),
      ),
    );

    expect(find.byKey(const Key('retry-generation')), findsNothing);
    expect(find.byKey(const Key('choose-recovery-model')), findsOneWidget);
    await tester.tap(find.byKey(const Key('choose-recovery-model')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-picker-sheet')), findsOneWidget);
  });
}
