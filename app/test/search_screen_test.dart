import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/chat/application/chat_providers.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/chat/search_screen.dart';

import 'support/harness.dart';

ChatHistorySnapshot _twoChats() {
  ChatConversation chat(String id, String title, String body, DateTime at) =>
      ChatConversation(
        id: id,
        title: title,
        updatedAt: at,
        messages: [
          ChatMessage.text(
            id: '$id-a',
            role: MessageRole.assistant,
            text: body,
            createdAt: at,
          ),
        ],
      );
  return ChatHistorySnapshot(
    activeId: 'lisbon',
    conversations: [
      chat(
        'lisbon',
        'Rainy weekend in Lisbon',
        'Rain in Lisbon is warm, so waterproofs matter more than warmth.',
        DateTime.utc(2026, 8, 5),
      ),
      chat(
        'loops',
        'Refactor a nested loop',
        'Invert the conditions and return early.',
        DateTime.utc(2026, 8, 2),
      ),
    ],
  );
}

void main() {
  testWidgets('typing debounces into highlighted results', (tester) async {
    await pumpSearchScreen(tester, history: _twoChats());
    expect(find.byKey(const Key('search-field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('search-field')), 'lisbon');
    await tester.pump(const Duration(milliseconds: 200));
    // Not yet: the debounce window is 350 ms.
    expect(find.byKey(const Key('search-results')), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search-results')), findsOneWidget);
    expect(find.text('1 CHAT'), findsOneWidget);
    expect(find.byKey(const Key('search-result-lisbon')), findsOneWidget);
    expect(find.byKey(const Key('search-result-loops')), findsNothing);
    expect(find.textContaining('2 matches'), findsOneWidget);
    expect(
      find.textContaining('Search runs against the local database'),
      findsOneWidget,
    );

    // A miss renders the empty message instead of stale cards.
    await tester.enterText(find.byKey(const Key('search-field')), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-empty')), findsOneWidget);
  });

  testWidgets('Korean search result heading suppresses Latin tracking', (
    tester,
  ) async {
    await pumpSearchScreen(
      tester,
      locale: const Locale('ko'),
      history: _twoChats(),
    );
    await tester.enterText(find.byKey(const Key('search-field')), 'lisbon');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final heading = tester.widget<Text>(find.text('대화 1개'));
    expect(heading.style?.letterSpacing, 0);
  });

  testWidgets('a result opens its conversation back on the chat screen', (
    tester,
  ) async {
    await pumpSearchScreen(tester, history: _twoChats());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchScreen)),
    );
    await tester.enterText(find.byKey(const Key('search-field')), 'return');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-result-loops')));
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(
      container.read(chatControllerProvider).requireValue.activeId,
      'loops',
    );
  });

  testWidgets('cancel returns to chat without touching selection', (
    tester,
  ) async {
    await pumpSearchScreen(tester, history: _twoChats());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchScreen)),
    );
    await tester.tap(find.byKey(const Key('search-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(
      container.read(chatControllerProvider).requireValue.activeId,
      'lisbon',
    );
  });
}
