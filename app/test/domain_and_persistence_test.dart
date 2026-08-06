import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/file_chat_history_repository.dart';
import 'package:golem_flutter/core/repositories/file_settings_repository.dart';

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

  test('pinned and modelKey round-trip and default on legacy JSON', () async {
    final conversation = ChatConversation(
      id: 'chat-1',
      title: 'Pinned chat',
      messages: const [],
      updatedAt: DateTime.utc(2026, 8, 1),
      pinned: true,
      modelKey: 'qwen35-gguf',
    );
    final decoded = ChatConversation.fromJson(
      jsonDecode(jsonEncode(conversation.toJson())) as Map<String, Object?>,
    );
    expect(decoded.pinned, isTrue);
    expect(decoded.modelKey, 'qwen35-gguf');

    // A pre-#47 history has neither key: both must default, not throw —
    // the loader renames unreadable files to `.corrupt` and silently
    // empties history, so this default path is what protects users.
    final legacy = ChatConversation.fromJson({
      'id': 'old',
      'title': 'Old chat',
      'messages': const <Object?>[],
      'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
    });
    expect(legacy.pinned, isFalse);
    expect(legacy.modelKey, isNull);
  });

  test('branchUpTo copies the prefix and withoutMessage removes by id', () {
    DateTime at(int day) => DateTime.utc(2026, 8, day);
    ChatMessage message(String id, MessageRole role) =>
        ChatMessage(id: id, role: role, text: 'text-$id', createdAt: at(1));
    final conversation = ChatConversation(
      id: 'chat',
      title: 'Branch me',
      updatedAt: at(1),
      reasoningEnabled: true,
      pinned: true,
      modelKey: 'gemma4-mlx',
      messages: [
        message('u1', MessageRole.user),
        message('a1', MessageRole.assistant),
        message('u2', MessageRole.user),
      ],
    );

    final branch = conversation.branchUpTo('a1', id: 'branch', now: at(2))!;
    expect(branch.id, 'branch');
    expect(branch.messages.map((m) => m.id), ['u1', 'a1']);
    expect(branch.title, 'Branch me');
    expect(branch.modelKey, 'gemma4-mlx');
    expect(branch.reasoningEnabled, isTrue);
    expect(branch.pinned, isFalse, reason: 'a branch starts unpinned');
    expect(branch.updatedAt, at(2));
    expect(conversation.branchUpTo('missing', id: 'x', now: at(2)), isNull);

    final trimmed = conversation.withoutMessage('a1');
    expect(trimmed.messages.map((m) => m.id), ['u1', 'u2']);
    expect(conversation.withoutMessage('missing').messages.length, 3);
  });

  test('transcriptMarkdown names speakers and keeps reasoning private', () {
    final conversation = ChatConversation(
      id: 'chat',
      title: 'Weekend plans',
      updatedAt: DateTime.utc(2026, 8, 2),
      messages: [
        ChatMessage(
          id: 'u1',
          role: MessageRole.user,
          text: 'Any ideas?',
          createdAt: DateTime.utc(2026, 8, 2),
        ),
        ChatMessage(
          id: 'a1',
          role: MessageRole.assistant,
          text: 'A slow morning walk.',
          reasoning: 'Private chain of thought',
          createdAt: DateTime.utc(2026, 8, 2),
        ),
        ChatMessage(
          id: 'draft',
          role: MessageRole.assistant,
          text: 'Unfinished',
          createdAt: DateTime.utc(2026, 8, 2),
          isStreaming: true,
        ),
      ],
    );
    final transcript = conversation.transcriptMarkdown();
    expect(transcript, contains('## Weekend plans'));
    expect(transcript, contains('**You:** Any ideas?'));
    expect(transcript, contains('**Golem:** A slow morning walk.'));
    expect(transcript, isNot(contains('Private')));
    expect(transcript, isNot(contains('Unfinished')));
  });

  test('generation settings persist sparsely and round-trip', () async {
    final directory = await Directory.systemTemp.createTemp(
      'golem-settings-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/prefs.json');
    final repository = FileSettingsRepository(file);

    // A missing file is all defaults, not an error.
    expect((await repository.load()).models, isEmpty);

    await repository.save(
      const GenerationSettings().withModel(
        'qwen35',
        const SamplingOverrides(temperature: 0.8, topK: 20),
      ),
    );
    final loaded = await repository.load();
    expect(loaded.overridesFor('qwen35').temperature, 0.8);
    expect(loaded.overridesFor('qwen35').topK, 20);
    // Unset knobs stay null — recommended defaults are never persisted, so
    // future default changes reach users who never touched a control.
    expect(loaded.overridesFor('qwen35').topP, isNull);
    expect(loaded.overridesFor('gemma4').isEmpty, isTrue);
    final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    expect(raw['schemaVersion'], 1);
    expect((raw['models'] as Map).keys, ['qwen35']);
    expect((raw['models'] as Map)['qwen35'], {'temperature': 0.8, 'topK': 20});

    // Clearing every override removes the model entry entirely.
    await repository.save(
      loaded.withModel('qwen35', const SamplingOverrides()),
    );
    expect((await repository.load()).models, isEmpty);
  });

  test('unreadable or unknown-schema settings recover to defaults', () async {
    final directory = await Directory.systemTemp.createTemp(
      'golem-settings-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    for (final content in ['not json at all', '{"schemaVersion": 99}']) {
      final file = File('${directory.path}/prefs.json');
      await file.writeAsString(content);
      final repository = FileSettingsRepository(file);
      expect((await repository.load()).models, isEmpty);
      // The damaged file is preserved for inspection, never overwritten.
      expect(File('${file.path}.corrupt').existsSync(), isTrue);
      await File('${file.path}.corrupt').delete();
    }
  });
}
