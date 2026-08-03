import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/file_chat_history_repository.dart';

void main() {
  test(
    'title normalization trims, collapses whitespace, and limits length',
    () {
      expect(
        normalizeTitle('  hello   private   world  '),
        'hello private world',
      );
      expect(normalizeTitle('   '), 'New chat');
      final longTitle = List.filled(80, 'x').join();
      expect(normalizeTitle(longTitle).length, 48);
      expect(normalizeTitle(longTitle).endsWith('…'), isTrue);
    },
  );

  test(
    'versioned persistence reloads and falls back from stale selection',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'golem-history-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = FileChatHistoryRepository(
        File('${directory.path}/history.json'),
      );
      final conversation = ChatConversation(
        id: 'chat-1',
        title: 'Saved chat',
        messages: [
          ChatMessage(
            id: 'message-1',
            role: MessageRole.user,
            text: 'Hello',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      await repository.save(
        ChatHistorySnapshot(conversations: [conversation], activeId: 'missing'),
      );
      final loaded = await repository.load();
      expect(loaded.activeId, 'chat-1');
      expect(loaded.conversations.single.messages.single.text, 'Hello');
    },
  );

  test('reasoning is excluded from future prompt context', () {
    final conversation = ChatConversation(
      id: 'chat',
      title: 'Context',
      updatedAt: DateTime.now(),
      messages: [
        ChatMessage(
          id: 'assistant',
          role: MessageRole.assistant,
          text: 'Public answer',
          reasoning: 'Private chain of thought',
          createdAt: DateTime.now(),
        ),
      ],
    );
    expect(conversation.promptContext, [
      {'role': 'assistant', 'content': 'Public answer'},
    ]);
    expect(conversation.promptContext.toString(), isNot(contains('Private')));
  });
}
