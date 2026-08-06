import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:integration_test/integration_test.dart';

import 'package:golem_flutter/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('complete fake-only Golem journey', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    if (find.byKey(const Key('empty-chat')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('new-chat-header')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('empty-chat')), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat-composer')));
    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'A private simulated hello',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-button')));
    await _pumpUntilFound(tester, find.byKey(const Key('stop-button')));
    expect(find.byKey(const Key('stop-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('stop-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reasoning-toggle')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(
      container
          .read(chatControllerProvider)
          .requireValue
          .active!
          .reasoningEnabled,
      isTrue,
    );
    await container
        .read(chatControllerProvider.notifier)
        .send('A complete answer');
    await tester.pump();
    expect(
      container
          .read(chatControllerProvider)
          .requireValue
          .active!
          .messages
          .last
          .reasoning,
      isNotEmpty,
    );

    final chatCommands = container.read(chatControllerProvider.notifier);
    await chatCommands.regenerate();
    var active = container.read(chatControllerProvider).requireValue.active!;
    expect(active.messages.last.role, MessageRole.assistant);
    final editedUser = active.messages.lastWhere(
      (message) => message.role == MessageRole.user,
    );
    await chatCommands.editAndTruncate(
      editedUser.id,
      'Edited during the integration journey',
    );
    active = container.read(chatControllerProvider).requireValue.active!;
    expect(
      active.messages.any(
        (message) => message.text == 'Edited during the integration journey',
      ),
      isTrue,
    );

    // Branch from the settled assistant tail: a new conversation holds
    // the prefix, becomes active, and confirms with a toast. The edit ran
    // through the controller, so settle the rebuilt transcript first.
    await tester.pumpAndSettle();
    final branchSource = active.messages.last;
    expect(branchSource.role, MessageRole.assistant);
    final sourceConversationId = active.id;
    await tester.ensureVisible(
      find.byKey(Key('message-menu-${branchSource.id}')),
    );
    await tester.tap(find.byKey(Key('message-menu-${branchSource.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-message-branch')));
    await tester.pumpAndSettle();
    active = container.read(chatControllerProvider).requireValue.active!;
    expect(active.id, isNot(sourceConversationId));
    expect(find.text('New branch started'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));

    // Cross-chat search is a full screen now: the drawer button opens
    // it, the query debounces, and Cancel returns to the chat.
    await tester.tap(find.byKey(const Key('open-drawer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), 'private');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-results')), findsOneWidget);
    expect(find.textContaining('private', findRichText: true), findsWidgets);
    await tester.tap(find.byKey(const Key('search-cancel')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-drawer')));
    await tester.pumpAndSettle();
    final firstConversation = _conversationId(tester);
    await tester.tap(find.byKey(Key('conversation-menu-$firstConversation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-pin-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Pinned'), findsWidgets);
    expect(
      container
          .read(chatControllerProvider)
          .requireValue
          .conversations
          .singleWhere((item) => item.id == firstConversation)
          .pinned,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 1600));

    await tester.tap(find.byKey(Key('conversation-menu-$firstConversation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('rename-field')),
      'Renamed locally',
    );
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('conversation-menu-$firstConversation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.tap(find.byKey(const Key('new-chat-drawer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-drawer')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('simulation-banner')), findsOneWidget);
    final settingsScrollable = find.descendant(
      of: find.byKey(const Key('settings-list')),
      matching: find.byType(Scrollable),
    );
    final modelCommands = container.read(modelControllerProvider.notifier);
    var model = container.read(modelControllerProvider).requireValue;
    if (model.statusOf('gemma4-mlx').phase != ArtifactPhase.installed) {
      await tester.scrollUntilVisible(
        find.byKey(const Key('model-download-gemma4-mlx')),
        240,
        scrollable: settingsScrollable,
      );
      await tester.tap(find.byKey(const Key('model-download-gemma4-mlx')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('model-pause-gemma4-mlx')),
      );
      await tester.pump(const Duration(milliseconds: 220));
      await tester.tap(find.byKey(const Key('model-pause-gemma4-mlx')));
      await tester.pumpAndSettle();
      expect(
        container
            .read(modelControllerProvider)
            .requireValue
            .statusOf('gemma4-mlx')
            .phase,
        ArtifactPhase.paused,
      );
      await modelCommands.download('gemma4-mlx');
      await tester.pump();
      model = container.read(modelControllerProvider).requireValue;
      expect(model.statusOf('gemma4-mlx').phase, ArtifactPhase.installed);
    }

    await tester.scrollUntilVisible(
      find.byKey(const Key('runtime-toggle-button')),
      260,
      scrollable: settingsScrollable,
    );
    await tester.tap(find.byKey(const Key('runtime-toggle-button')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('open-benchmark')),
      260,
      scrollable: settingsScrollable,
    );
    await tester.tap(find.byKey(const Key('open-benchmark')));
    await tester.pumpAndSettle();
    final benchmarkRunButton = find.byKey(const Key('benchmark-run-button'));
    await tester.ensureVisible(benchmarkRunButton);
    await tester.pumpAndSettle();
    expect(benchmarkRunButton.hitTestable(), findsOneWidget);
    await tester.tap(benchmarkRunButton);
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('benchmark-stop-button')),
    );
    await tester.tap(find.byKey(const Key('benchmark-stop-button')));
    await tester.pump();
    expect(container.read(benchmarkControllerProvider).result, isNull);
    await tester.tap(find.byKey(const Key('benchmark-run-button')));
    await _pumpUntilBenchmarkResult(tester, container);
    expect(container.read(benchmarkControllerProvider).result, isNotNull);
    final exportPath = await container
        .read(benchmarkControllerProvider.notifier)
        .export();
    expect(exportPath, isNotNull);

    // Persistence is exercised by the file repository during every mutation;
    // a subsequent app launch reads the same app-support file.
  });
}

Future<void> _pumpUntilBenchmarkResult(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final watch = Stopwatch()..start();
  while (container.read(benchmarkControllerProvider).result == null &&
      watch.elapsed < const Duration(seconds: 4)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final watch = Stopwatch()..start();
  while (finder.evaluate().isEmpty && watch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

String _conversationId(WidgetTester tester) {
  final candidates = tester.widgetList<CupertinoMenuAnchor>(
    find.byType(CupertinoMenuAnchor),
  );
  for (final anchor in candidates) {
    final key = anchor.key;
    if (key is ValueKey<String> && key.value.startsWith('conversation-menu-')) {
      return key.value.substring('conversation-menu-'.length);
    }
  }
  throw StateError('Conversation menu was not found');
}
