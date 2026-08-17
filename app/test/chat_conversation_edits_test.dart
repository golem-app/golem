import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/chat/application/chat_conversation_edits.dart';

/// The rules behind ChatController's conversation commands (#127): which chat
/// becomes active after a delete, what each recovery action removes, what an
/// edit truncates. All of them used to be inline in the notifier and only
/// reachable by driving a container.

final _now = DateTime.utc(2026, 8, 17);

ChatMessage _message(String id, MessageRole role, String text) =>
    ChatMessage.text(id: id, role: role, text: text, createdAt: _now);

ChatConversation _conversation(
  String id, {
  List<ChatMessage> messages = const [],
  String title = 'title',
}) =>
    ChatConversation(id: id, title: title, messages: messages, updatedAt: _now);

void main() {
  group('placing a conversation', () {
    test('an edited chat moves to the front and becomes active', () {
      final value = ChatState(
        conversations: [_conversation('a'), _conversation('b')],
        activeId: 'a',
      );

      final next = withActiveConversation(
        value,
        _conversation('b', title: 'touched'),
      );

      expect(next.conversations.map((item) => item.id), ['b', 'a']);
      expect(next.activeId, 'b');
      expect(next.active?.title, 'touched');
    });

    test('it keeps the session verdicts, unlike a fresh chat', () {
      // The distinction the two helpers exist for: editing a chat must not
      // silently clear a standing failure or an unsaved draft flag.
      final value = ChatState(
        conversations: [_conversation('a')],
        activeId: 'a',
        failure: const ChatFailure(kind: ChatFailureKind.generic),
        hasUnsavedAssistant: true,
        persistencePhase: ChatPersistencePhase.failed,
      );

      final next = withActiveConversation(value, _conversation('a'));

      expect(next.failure?.kind, ChatFailureKind.generic);
      expect(next.hasUnsavedAssistant, isTrue);
      expect(next.persistencePhase, ChatPersistencePhase.failed);
    });

    test('a new chat clears the last turn s verdict but keeps the notice', () {
      final value = ChatState(
        conversations: [_conversation('a')],
        activeId: 'a',
        failure: const ChatFailure(kind: ChatFailureKind.generic),
        hasUnsavedAssistant: true,
        persistencePhase: ChatPersistencePhase.failed,
      );

      final next = withNewConversation(value, _conversation('new'));

      expect(next.activeId, 'new');
      expect(next.failure, isNull);
      expect(next.hasUnsavedAssistant, isFalse);
      // The durability warning is about the store, not the turn, so it stands.
      expect(next.persistencePhase, ChatPersistencePhase.failed);
    });
  });

  group('removing a conversation', () {
    test('deleting the active one falls through to the newest remaining', () {
      final value = ChatState(
        conversations: [_conversation('a'), _conversation('b')],
        activeId: 'a',
      );

      final next = withoutConversation(value, 'a');

      expect(next.conversations.map((item) => item.id), ['b']);
      expect(next.activeId, 'b');
    });

    test('deleting any other leaves the selection alone', () {
      final value = ChatState(
        conversations: [_conversation('a'), _conversation('b')],
        activeId: 'a',
      );

      expect(withoutConversation(value, 'b').activeId, 'a');
    });

    test('deleting the last one leaves nothing selected', () {
      final value = ChatState(
        conversations: [_conversation('a')],
        activeId: 'a',
      );

      final next = withoutConversation(value, 'a');

      expect(next.conversations, isEmpty);
      expect(next.activeId, isNull);
    });
  });

  group('dropping trailing turns', () {
    test('discard removes the failed draft and keeps the question', () {
      final conversation = _conversation(
        'a',
        messages: [
          _message('u', MessageRole.user, 'question'),
          _message('a', MessageRole.assistant, 'half an answer'),
        ],
      );

      final next = withTrailingTurnsDropped(conversation);

      expect(next.messages.map((item) => item.id), ['u']);
    });

    test('removing the turn takes the question with it', () {
      // For failures a replay can never fix — an attachment that disappeared.
      final conversation = _conversation(
        'a',
        messages: [
          _message('earlier', MessageRole.assistant, 'kept'),
          _message('u', MessageRole.user, 'question'),
          _message('a', MessageRole.assistant, ''),
        ],
      );

      final next = withTrailingTurnsDropped(conversation, alsoUser: true);

      expect(next.messages.map((item) => item.id), ['earlier']);
    });

    test('a conversation ending on a user turn keeps it under discard', () {
      final conversation = _conversation(
        'a',
        messages: [_message('u', MessageRole.user, 'question')],
      );

      expect(withTrailingTurnsDropped(conversation).messages.length, 1);
    });
  });

  group('editing and truncating', () {
    ChatConversation subject() => _conversation(
      'a',
      title: 'Original',
      messages: [
        _message('u1', MessageRole.user, 'first'),
        _message('a1', MessageRole.assistant, 'answer'),
        _message('u2', MessageRole.user, 'second'),
      ],
    );

    test('everything after the edited turn is dropped', () {
      final next = withEditedAndTruncated(
        subject(),
        'u1',
        'rewritten',
        now: _now,
      );

      expect(next!.messages.map((item) => item.id), ['u1']);
      expect(next.messages.single.text, 'rewritten');
    });

    test('editing the first turn renames the chat with it', () {
      final next = withEditedAndTruncated(
        subject(),
        'u1',
        'rewritten',
        now: _now,
      );

      expect(next!.title, normalizeTitle('rewritten'));
    });

    test('editing a later turn leaves the title alone', () {
      final next = withEditedAndTruncated(
        subject(),
        'u2',
        'rewritten',
        now: _now,
      );

      expect(next!.title, 'Original');
      expect(next.messages.map((item) => item.id), ['u1', 'a1', 'u2']);
    });

    test('an assistant turn cannot be edited', () {
      expect(
        withEditedAndTruncated(subject(), 'a1', 'rewritten', now: _now),
        isNull,
      );
    });

    test('an unknown message cannot be edited', () {
      expect(
        withEditedAndTruncated(subject(), 'nope', 'rewritten', now: _now),
        isNull,
      );
    });

    test('an image turn stays an image turn', () {
      // Dropping the part would unlink its bytes on the next save.
      final conversation = _conversation(
        'a',
        messages: [
          ChatMessage(
            id: 'u1',
            role: MessageRole.user,
            parts: const [
              ImagePart(
                attachmentId: 'att',
                mimeType: 'image/png',
                width: 2,
                height: 2,
                byteCount: 4,
              ),
              TextPart('before'),
            ],
            createdAt: _now,
          ),
        ],
      );

      final next = withEditedAndTruncated(
        conversation,
        'u1',
        'after',
        now: _now,
      );

      expect(next!.messages.single.images.single.attachmentId, 'att');
      expect(next.messages.single.text, 'after');
    });
  });

  group('settling a streaming draft', () {
    test('a draft with content stops streaming and stays', () {
      final conversation = _conversation(
        'a',
        messages: [
          ChatMessage.text(
            id: 'draft',
            role: MessageRole.assistant,
            text: 'partial',
            createdAt: _now,
            isStreaming: true,
          ),
        ],
      );

      final next = withStreamingSettled(conversation);

      expect(next.messages.single.isStreaming, isFalse);
      expect(next.messages.single.text, 'partial');
    });

    test('a draft that produced nothing is dropped entirely', () {
      final conversation = _conversation(
        'a',
        messages: [
          ChatMessage.text(
            id: 'draft',
            role: MessageRole.assistant,
            text: '',
            reasoning: '',
            createdAt: _now,
            isStreaming: true,
          ),
        ],
      );

      expect(withStreamingSettled(conversation).messages, isEmpty);
    });

    test('a draft with reasoning only is worth keeping', () {
      final conversation = _conversation(
        'a',
        messages: [
          ChatMessage.text(
            id: 'draft',
            role: MessageRole.assistant,
            text: '',
            reasoning: 'I was getting there',
            createdAt: _now,
            isStreaming: true,
          ),
        ],
      );

      expect(withStreamingSettled(conversation).messages.length, 1);
    });

    test('a settled conversation is returned untouched', () {
      final conversation = _conversation(
        'a',
        messages: [_message('a1', MessageRole.assistant, 'done')],
      );

      expect(withStreamingSettled(conversation), same(conversation));
    });
  });
}
