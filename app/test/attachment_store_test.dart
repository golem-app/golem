import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/core/repositories/file_attachment_repository.dart';

import 'support/in_memory_attachment_repository.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_preferences_repository.dart';

ImagePart _imagePart(String id) => ImagePart(
  attachmentId: id,
  mimeType: 'image/jpeg',
  width: 8,
  height: 8,
  byteCount: 3,
);

void main() {
  group('FileAttachmentRepository', () {
    late Directory directory;
    late FileAttachmentRepository repository;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('golem-attachments-');
      repository = FileAttachmentRepository(
        Directory('${directory.path}/attachments'),
      );
    });
    tearDown(() => directory.delete(recursive: true));

    test('stores bytes, reads them back, and reports its size', () async {
      final stored = await repository.store(const [
        1,
        2,
        3,
        4,
      ], mimeType: 'image/png');
      expect(stored.id, endsWith('.png'));
      expect(stored.byteCount, 4);
      expect(await repository.read(stored.id), [1, 2, 3, 4]);
      expect(await repository.storedBytes(), 4);
    });

    test('an empty store reports nothing rather than failing', () async {
      expect(await repository.storedBytes(), 0);
      expect(await repository.read('nothing.jpg'), isNull);
    });

    test('refuses an image type no engine path accepts', () async {
      expect(
        () => repository.store(const [1], mimeType: 'image/tiff'),
        throwsArgumentError,
      );
    });

    test('ids address this directory and nothing outside it', () async {
      for (final hostile in [
        '../escape.jpg',
        'nested/child.jpg',
        r'..\escape.jpg',
        '',
      ]) {
        expect(await repository.read(hostile), isNull, reason: hostile);
      }
    });

    test('retainOnly keeps referenced bytes and drops the rest', () async {
      final keep = await repository.store(const [1, 2], mimeType: 'image/jpeg');
      final drop = await repository.store(const [3], mimeType: 'image/jpeg');
      expect(await repository.storedBytes(), 3);

      await repository.retainOnly({keep.id});

      expect(await repository.read(keep.id), [1, 2]);
      expect(await repository.read(drop.id), isNull);
      expect(await repository.storedBytes(), 2);
    });

    test('retainOnly on a store that was never written is harmless', () async {
      await repository.retainOnly({'anything.jpg'});
      expect(await repository.storedBytes(), 0);
    });

    test('ids are unique across rapid stores', () async {
      final ids = <String>{};
      for (var i = 0; i < 25; i++) {
        ids.add((await repository.store(const [0], mimeType: 'image/jpeg')).id);
      }
      expect(ids, hasLength(25));
    });
  });

  group('attachment lifecycle follows the conversations', () {
    ProviderContainer containerWith(
      InMemoryAttachmentRepository attachments, {
      ChatHistorySnapshot? history,
      InMemoryPreferencesRepository? preferences,
    }) => ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(
            history ?? const ChatHistorySnapshot(conversations: []),
          ),
        ),
        attachmentRepositoryProvider.overrideWithValue(attachments),
        preferencesRepositoryProvider.overrideWithValue(
          preferences ?? InMemoryPreferencesRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(
          FakeInferenceRepository(eventDelay: Duration.zero),
        ),
      ],
    );

    ChatHistorySnapshot historyWith(List<String> attachmentIds) =>
        ChatHistorySnapshot(
          activeId: 'chat',
          conversations: [
            ChatConversation(
              id: 'chat',
              title: 'With pictures',
              updatedAt: DateTime.utc(2026, 8, 9),
              messages: [
                ChatMessage(
                  id: 'u1',
                  role: MessageRole.user,
                  parts: [
                    for (final id in attachmentIds) _imagePart(id),
                    const TextPart('What is this?'),
                  ],
                  createdAt: DateTime.utc(2026, 8, 9),
                ),
              ],
            ),
          ],
        );

    test('deleting a message drops only its attachments', () async {
      final attachments = InMemoryAttachmentRepository();
      final kept = await attachments.store(const [1], mimeType: 'image/jpeg');
      final dropped = await attachments.store(const [
        2,
        3,
      ], mimeType: 'image/jpeg');

      final container = containerWith(
        attachments,
        history: ChatHistorySnapshot(
          activeId: 'chat',
          conversations: [
            ChatConversation(
              id: 'chat',
              title: 'Two pictures',
              updatedAt: DateTime.utc(2026, 8, 9),
              messages: [
                ChatMessage(
                  id: 'keep',
                  role: MessageRole.user,
                  parts: [_imagePart(kept.id)],
                  createdAt: DateTime.utc(2026, 8, 9),
                ),
                ChatMessage(
                  id: 'drop',
                  role: MessageRole.user,
                  parts: [_imagePart(dropped.id)],
                  createdAt: DateTime.utc(2026, 8, 9),
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(container.dispose);
      await container.read(chatControllerProvider.future);

      await container
          .read(chatControllerProvider.notifier)
          .deleteMessage('drop');

      expect(await attachments.read(kept.id), isNotNull);
      expect(await attachments.read(dropped.id), isNull);
    });

    test('deleting every chat collects every attachment', () async {
      final attachments = InMemoryAttachmentRepository();
      final stored = await attachments.store(const [1], mimeType: 'image/png');
      final container = containerWith(
        attachments,
        history: historyWith([stored.id]),
      );
      addTearDown(container.dispose);
      await container.read(chatControllerProvider.future);

      await container.read(chatControllerProvider.notifier).deleteAllChats();

      expect(await attachments.storedBytes(), 0);
    });

    test('with history off the session keeps its pictures readable', () async {
      final attachments = InMemoryAttachmentRepository();
      final stored = await attachments.store(const [7], mimeType: 'image/png');
      final preferences = InMemoryPreferencesRepository(
        const AppPreferences(saveHistory: false),
      );
      final container = containerWith(
        attachments,
        history: historyWith([stored.id]),
        preferences: preferences,
      );
      addTearDown(container.dispose);
      await container.read(chatControllerProvider.future);
      await container.read(preferencesControllerProvider.future);

      // A mutation runs the cascade even though nothing reaches disk.
      await container
          .read(chatControllerProvider.notifier)
          .renameConversation('chat', 'Renamed');

      expect(
        await attachments.read(stored.id),
        isNotNull,
        reason: 'in-memory conversations still reference it',
      );
    });

    test('an unwired attachment seam never breaks a chat mutation', () async {
      // Label-only containers omit the seam; persistence must still work.
      final container = ProviderContainer(
        overrides: [
          chatHistoryRepositoryProvider.overrideWithValue(
            InMemoryChatHistoryRepository(),
          ),
          inferenceRepositoryProvider.overrideWithValue(
            FakeInferenceRepository(eventDelay: Duration.zero),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(chatControllerProvider.future);
      await container.read(chatControllerProvider.notifier).newChat();
      expect(
        container.read(chatControllerProvider).requireValue.conversations,
        hasLength(1),
      );
    });
  });
}
