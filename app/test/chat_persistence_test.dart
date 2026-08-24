import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/features/chat/application/chat_persistence.dart';

import 'support/in_memory_attachment_repository.dart';
import 'support/in_memory_chat_history_repository.dart';

/// ChatController's history, privacy gate and attachment retention, extracted
/// (#127) so the snapshot rule and the write-failure classification are
/// reachable without a container. The epoch and mounted choreography stays with
/// the notifier and is exercised in controllers_test.dart.

final _now = DateTime.utc(2026, 8, 17);

ChatMessage _message(String id, MessageRole role, {List<MessagePart>? parts}) =>
    ChatMessage(
      id: id,
      role: role,
      parts: parts ?? [TextPart('text of $id')],
      createdAt: _now,
    );

ChatConversation _conversation(String id, List<ChatMessage> messages) =>
    ChatConversation(id: id, title: id, messages: messages, updatedAt: _now);

final class _FailingHistory implements ChatHistoryRepository {
  _FailingHistory(this.kind);

  final PersistenceFailureKind kind;
  int saves = 0;

  @override
  Future<ChatHistorySnapshot> load() async =>
      const ChatHistorySnapshot(conversations: []);

  @override
  Future<void> save(ChatHistorySnapshot snapshot) async {
    saves++;
    throw PersistenceException(kind, 'no room at the inn');
  }

  @override
  Future<int> storedBytes() async => 0;
}

final class _ThrowingAttachments implements AttachmentRepository {
  @override
  Future<StoredAttachment> store(List<int> bytes, {required String mimeType}) =>
      throw UnimplementedError();

  @override
  Future<List<int>?> read(String attachmentId) async => null;

  @override
  Future<void> retainOnly(Set<String> attachmentIds) async =>
      throw const PersistenceException(
        PersistenceFailureKind.write,
        'collection failed',
      );

  @override
  Future<int> storedBytes() async => 0;
}

ChatPersistence _persistence({
  ChatHistoryRepository? history,
  AttachmentRepository? attachments,
}) => ChatPersistence(
  history: history ?? InMemoryChatHistoryRepository(),
  attachments: attachments ?? InMemoryAttachmentRepository(),
);

void main() {
  group('the persistence-eligible snapshot', () {
    test('a streaming draft is withheld, its question is not', () {
      // Until Stop or finalization marks it durable, the half-written answer is
      // not something a restart should resurrect.
      final value = ChatState(
        conversations: [
          _conversation('a', [
            _message('u', MessageRole.user),
            _message('draft', MessageRole.assistant),
          ]),
        ],
        activeId: 'a',
        hasUnsavedAssistant: true,
      );

      final snapshot = ChatPersistence.snapshotOf(value);

      expect(snapshot.conversations.single.messages.map((item) => item.id), [
        'u',
      ]);
      expect(snapshot.activeId, 'a');
    });

    test('a settled assistant turn is kept', () {
      final value = ChatState(
        conversations: [
          _conversation('a', [
            _message('u', MessageRole.user),
            _message('answer', MessageRole.assistant),
          ]),
        ],
        activeId: 'a',
      );

      expect(
        ChatPersistence.snapshotOf(value).conversations.single.messages.length,
        2,
      );
    });

    test('only the active chat is trimmed', () {
      final value = ChatState(
        conversations: [
          _conversation('a', [_message('draft', MessageRole.assistant)]),
          _conversation('b', [_message('kept', MessageRole.assistant)]),
        ],
        activeId: 'a',
        hasUnsavedAssistant: true,
      );

      final snapshot = ChatPersistence.snapshotOf(value);

      expect(snapshot.conversations.first.messages, isEmpty);
      expect(snapshot.conversations.last.messages.length, 1);
    });

    test('a flagged draft whose last turn is the user is left alone', () {
      // Stop already removed an empty draft; the flag can outlive it by a beat.
      final value = ChatState(
        conversations: [
          _conversation('a', [_message('u', MessageRole.user)]),
        ],
        activeId: 'a',
        hasUnsavedAssistant: true,
      );

      expect(
        ChatPersistence.snapshotOf(value).conversations.single.messages.length,
        1,
      );
    });
  });

  group('saving', () {
    test('a write failure is reported, not thrown', () {
      // The notifier turns this into the standing recovery notice; throwing
      // would abort the send that triggered it.
      final history = _FailingHistory(PersistenceFailureKind.write);

      expect(
        _persistence(
          history: history,
        ).save(const ChatHistorySnapshot(conversations: [])),
        completion(ChatSaveOutcome.writeFailed),
      );
    });

    test('any other persistence failure keeps propagating', () {
      // A read fault at write time is not an operational hiccup; swallowing it
      // would hide a real fault behind a retry button that cannot help.
      expect(
        _persistence(
          history: _FailingHistory(PersistenceFailureKind.read),
        ).save(const ChatHistorySnapshot(conversations: [])),
        throwsA(isA<PersistenceException>()),
      );
    });

    test('a committed write reports success', () {
      expect(
        _persistence().save(const ChatHistorySnapshot(conversations: [])),
        completion(ChatSaveOutcome.saved),
      );
    });
  });

  group('attachment retention', () {
    test('exactly the referenced ids survive', () async {
      final attachments = InMemoryAttachmentRepository();
      final kept = await attachments.store(const [1, 2], mimeType: 'image/png');
      final orphan = await attachments.store(const [3], mimeType: 'image/png');

      await _persistence(attachments: attachments).retainReferenced([
        _conversation('a', [
          _message(
            'u',
            MessageRole.user,
            parts: [
              ImagePart(
                attachmentId: kept.id,
                mimeType: kept.mimeType,
                width: 1,
                height: 1,
                byteCount: kept.byteCount,
              ),
            ],
          ),
        ]),
      ]);

      expect(await attachments.read(kept.id), isNotNull);
      expect(await attachments.read(orphan.id), isNull);
    });

    test('a failed collection is swallowed', () {
      // An orphan costs disk; an aborted send costs the user their message.
      expect(
        _persistence(attachments: _ThrowingAttachments()).retainReferenced([]),
        completes,
      );
    });
  });

  group('the wipe behind Delete All', () {
    test('a committed wipe reports true', () {
      expect(_persistence().wipe(), completion(isTrue));
    });

    test('a failed wipe reports false rather than throwing', () {
      // "Deleted" must never be presented while the store still holds them.
      expect(
        _persistence(
          history: _FailingHistory(PersistenceFailureKind.write),
        ).wipe(),
        completion(isFalse),
      );
    });

    test('the wipe goes straight to the store', () async {
      // Not through save(): the bytes must leave disk even when the privacy
      // gate is closed and nothing new would be written to it. The gate lives
      // on the controller, so the only guarantee available here is that a wipe
      // always reaches the store.
      final history = _FailingHistory(PersistenceFailureKind.write);

      expect(await _persistence(history: history).wipe(), isFalse);
      expect(history.saves, 1);
    });
  });
}
