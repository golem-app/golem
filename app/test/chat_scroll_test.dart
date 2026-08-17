import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';

import 'support/harness.dart';
import 'support/in_memory_attachment_repository.dart';
import 'support/in_memory_chat_history_repository.dart';

const _delay = Duration(milliseconds: 40);

ChatHistorySnapshot _longHistory() => ChatHistorySnapshot(
  activeId: 'seed',
  conversations: [
    ChatConversation(
      id: 'seed',
      title: 'Seed',
      updatedAt: DateTime(2026),
      messages: [
        for (var i = 0; i < 10; i++) ...[
          ChatMessage.text(
            id: 'u$i',
            role: MessageRole.user,
            createdAt: DateTime(2026),
            text:
                'Seed question $i, padded so every bubble wraps across '
                'several lines and the list is comfortably scrollable.',
          ),
          ChatMessage.text(
            id: 'a$i',
            role: MessageRole.assistant,
            createdAt: DateTime(2026),
            text:
                'Seed answer $i with enough repeated filler text to take '
                'multiple lines in the transcript. More filler. More filler.',
          ),
        ],
      ],
    ),
  ],
);

Future<ScrollPosition> _pumpChat(WidgetTester tester) async {
  setViewport(tester);
  final container = ProviderContainer(
    overrides: [
      attachmentRepositoryProvider.overrideWithValue(
        InMemoryAttachmentRepository(),
      ),
      chatHistoryRepositoryProvider.overrideWithValue(
        InMemoryChatHistoryRepository(_longHistory()),
      ),
      inferenceRepositoryProvider.overrideWithValue(
        FakeInferenceRepository(eventDelay: _delay),
      ),
      // The nav subtitle and composer chip resolve their model label
      // through the catalog.
      modelCatalogEntriesProvider.overrideWithValue(modelCatalog),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: wrapApp(child: const ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('message-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('chat-composer')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('send-button')));
  await tester.pump();
}

void main() {
  testWidgets('the list follows a streaming response to its end', (
    tester,
  ) async {
    final position = await _pumpChat(tester);
    await _send(tester, 'Stream and follow');

    var sawGrowth = false;
    for (var i = 0; i < 40; i++) {
      await tester.pump(_delay);
      final distance = position.maxScrollExtent - position.pixels;
      if (position.maxScrollExtent > 0 && distance <= 1) sawGrowth = true;
      // While following, the view must never trail the tail by a visible
      // amount even as deltas land between frames.
      expect(distance, lessThan(120), reason: 'tick $i trailed the tail');
    }
    await tester.pumpAndSettle();
    expect(sawGrowth, isTrue);
    expect(position.pixels, moreOrLessEquals(position.maxScrollExtent));
  });

  testWidgets('an upward drag detaches following until jump is tapped', (
    tester,
  ) async {
    final position = await _pumpChat(tester);
    await _send(tester, 'Stream then browse history');
    await tester.pump(_delay);
    await tester.pump(_delay);

    await tester.drag(
      find.byKey(const Key('message-list')),
      const Offset(0, 600),
    );
    await tester.pump();
    final detachedOffset = position.pixels;

    for (var i = 0; i < 10; i++) {
      await tester.pump(_delay);
    }
    // Still streaming, but the view stays where the reader put it.
    expect(position.pixels, moreOrLessEquals(detachedOffset, epsilon: 1));

    await tester.tap(find.byKey(const Key('jump-to-latest')));
    await tester.pumpAndSettle();
    expect(position.pixels, moreOrLessEquals(position.maxScrollExtent));
  });
}
