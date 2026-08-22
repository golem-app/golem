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

Future<ScrollPosition> _pumpChat(WidgetTester tester, {Size? viewport}) async {
  setViewport(tester);
  if (viewport != null) tester.view.physicalSize = viewport;
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
  testWidgets('the question the reader just asked holds the top of the list', (
    tester,
  ) async {
    // Tall enough that the whole turn fits, so the spacer never runs out and
    // the anchor is the only thing deciding where the view sits.
    await _pumpChat(tester, viewport: const Size(402, 2400));
    await _send(tester, 'Stream and stay put');
    await tester.pump(_delay);
    final question = find.text('Stream and stay put');
    final listTop = tester.getTopLeft(find.byKey(const Key('message-list'))).dy;

    for (var i = 0; i < 40; i++) {
      await tester.pump(_delay);
      // Following the tail would carry the question off the top of the screen
      // within a delta or two; the spacer is what keeps it in place (#147).
      // Following the tail would carry the question off the top of the
      // screen within a delta or two; the spacer is what holds it there.
      expect(
        tester.getTopLeft(question).dy,
        greaterThanOrEqualTo(listTop - 1),
        reason: 'tick $i pushed the question off the top',
      );
    }
    await tester.pumpAndSettle();
    // 16pt of list padding, and nothing else, above the question.
    expect(tester.getTopLeft(question).dy - listTop, lessThan(40));
  });

  testWidgets('an answer taller than the screen hands back to the tail', (
    tester,
  ) async {
    // Short enough that this one answer outgrows the screen, which is what
    // spends the spacer and hands the view back to the tail.
    final position = await _pumpChat(tester, viewport: const Size(402, 420));
    await _send(tester, 'Stream and follow');

    for (var i = 0; i < 40; i++) {
      await tester.pump(_delay);
    }
    await tester.pumpAndSettle();
    // Carried off the top rather than held at it, and the view is on the end
    // of the scrollable again.
    expect(find.text('Stream and follow'), findsNothing);
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
    // The end of the newest answer is on screen again — the arrow returns the
    // reader to the content, not into the blank the spacer holds below it.
    final list = tester.getRect(find.byKey(const Key('message-list')));
    final pill = tester.getRect(find.byKey(const Key('metrics-pill')));
    expect(pill.bottom, lessThanOrEqualTo(list.bottom));
    expect(pill.top, greaterThanOrEqualTo(list.top));
  });

  testWidgets('a short drag detaches just as firmly as a long one', (
    tester,
  ) async {
    final position = await _pumpChat(tester);
    await _send(tester, 'Stream then nudge the history up');
    await tester.pump(_delay);
    await tester.pump(_delay);

    // 30pt — inside the 48pt window the jump affordance uses. Content growth
    // used to re-attach the follow from inside that window, so every delta
    // undid the drag and the reader could never get out (#147).
    // 50 of drag is 30 of scroll once the touch slop is paid — inside the
    // 48 the jump affordance uses, which is where the re-attach used to live.
    await tester.drag(
      find.byKey(const Key('message-list')),
      const Offset(0, 50),
    );
    await tester.pump();
    final detachedOffset = position.pixels;

    for (var i = 0; i < 10; i++) {
      await tester.pump(_delay);
    }
    expect(position.pixels, moreOrLessEquals(detachedOffset, epsilon: 1));
  });
}
