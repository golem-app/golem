import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';

import 'support/harness.dart';
import 'package:golem_flutter/features/chat/application/chat_providers.dart';

void main() {
  testWidgets('the action row copies with a toast and branches', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      child: const ChatScreen(),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    // The ghost action row renders under the settled assistant message.
    await tester.tap(find.byKey(const Key('message-copy-assistant-md')));
    await tester.pump();
    expect(copied.single, contains('csv'));
    expect(find.byKey(const Key('golem-toast')), findsOneWidget);
    expect(find.text('Copied to clipboard'), findsOneWidget);
    // The toast dismisses itself; drain its timer before moving on.
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byKey(const Key('golem-toast')), findsNothing);

    // Branch from the overflow menu: a new conversation holds the prefix.
    await tester.tap(find.byKey(const Key('message-menu-assistant-md')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-message-branch')));
    await tester.pumpAndSettle();
    final chat = container.read(chatControllerProvider).requireValue;
    expect(chat.conversations, hasLength(2));
    expect(chat.active!.id, isNot('chat-md'));
    expect(chat.active!.messages, hasLength(2));
    expect(find.text('New branch started'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
  });

  testWidgets('the menu deletes a single message in place', (tester) async {
    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      child: const ChatScreen(),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await tester.tap(find.byKey(const Key('message-menu-assistant-md')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-message-delete')));
    await tester.pumpAndSettle();
    final active = container.read(chatControllerProvider).requireValue.active!;
    expect(active.messages.single.id, 'user-md');
    expect(find.byKey(const Key('message-assistant-md')), findsNothing);
  });

  testWidgets('an OOM failure shows the stopped caption and banner', (
    tester,
  ) async {
    await pumpWithRepositories(tester, child: const ChatScreen());
    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'please [oom] now',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery-banner')), findsOneWidget);
    expect(
      find.textContaining('Ran out of memory at 4,096 tokens'),
      findsOneWidget,
    );
    // Ephemeral by design: the caption reads the failed generation's
    // metrics; discarding clears it with the failure.
    expect(find.byKey(const Key('stopped-caption')), findsOneWidget);
    expect(find.text('Stopped after 41 tokens'), findsOneWidget);

    await tester.tap(find.byKey(const Key('discard-generation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stopped-caption')), findsNothing);
  });
}
