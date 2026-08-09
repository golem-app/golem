import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/file_chat_history_repository.dart';
import 'package:golem_flutter/core/repositories/file_preferences_repository.dart';
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
          ChatMessage.text(
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

  test('a v1 chat history migrates to parts without losing a turn', () async {
    final directory = await Directory.systemTemp.createTemp('golem-chat-v1-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/history.json');
    // Exactly what a pre-#18 install wrote: flat message text, schema v1.
    await file.writeAsString('''
{
  "schemaVersion": 1,
  "activeConversationId": "chat-1",
  "conversations": [
    {
      "id": "chat-1",
      "title": "Old chat",
      "updatedAt": "2026-01-01T00:00:00.000Z",
      "messages": [
        {
          "id": "u1",
          "role": "user",
          "text": "Hello",
          "createdAt": "2026-01-01T00:00:00.000Z"
        },
        {
          "id": "a1",
          "role": "assistant",
          "text": "Hi there",
          "reasoning": "private",
          "createdAt": "2026-01-01T00:00:00.000Z"
        }
      ]
    }
  ]
}
''');

    final repository = FileChatHistoryRepository(file);
    final loaded = await repository.load();
    expect(
      File('${file.path}.corrupt').existsSync(),
      isFalse,
      reason: 'a v1 history must load, not be quarantined',
    );
    final messages = loaded.conversations.single.messages;
    expect(messages.map((m) => m.text), ['Hello', 'Hi there']);
    expect(messages.first.parts.single, isA<TextPart>());
    expect(messages.last.reasoning, 'private');
    expect(loaded.referencedAttachmentIds, isEmpty);

    // The file is rewritten as v2 on the next ordinary save.
    await repository.save(loaded);
    final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    expect(raw['schemaVersion'], 2);
    final rewritten =
        ((raw['conversations']! as List).single as Map)['messages']! as List;
    expect((rewritten.first as Map)['parts'], [
      {'type': 'text', 'text': 'Hello'},
    ]);
    expect((rewritten.first as Map).containsKey('text'), isFalse);
  });

  test('image parts round-trip and expose their references', () {
    final message = ChatMessage(
      id: 'u1',
      role: MessageRole.user,
      parts: const [
        ImagePart(
          attachmentId: 'a1.jpg',
          mimeType: 'image/jpeg',
          width: 640,
          height: 480,
          byteCount: 2048,
        ),
        TextPart('What is this?'),
      ],
      createdAt: DateTime.utc(2026, 8, 9),
    );

    final decoded = ChatMessage.fromJson(
      jsonDecode(jsonEncode(message.toJson())) as Map<String, Object?>,
    );
    expect(decoded.parts, hasLength(2));
    expect(decoded.text, 'What is this?');
    expect(decoded.hasImages, isTrue);
    final image = decoded.images.single;
    expect(image.attachmentId, 'a1.jpg');
    expect(image.mimeType, 'image/jpeg');
    expect(image.width, 640);
    expect(image.height, 480);
    expect(image.byteCount, 2048);

    // The store id is opaque: a bare file name, never a path into the photo
    // library or the container, so a transcript cannot leak where it came from.
    expect(image.attachmentId, isNot(contains('/')));
    expect(image.attachmentId, isNot(contains(r'\')));
    expect(jsonEncode(message.toJson()), isNot(contains('file:')));

    final conversation = ChatConversation(
      id: 'c',
      title: 'T',
      updatedAt: DateTime.utc(2026, 8, 9),
      messages: [decoded],
    );
    expect(conversation.attachmentIds, ['a1.jpg']);
    expect(
      ChatHistorySnapshot(
        conversations: [conversation],
      ).referencedAttachmentIds,
      {'a1.jpg'},
    );
  });

  test('withText keeps images ahead of the replaced text', () {
    final message = ChatMessage(
      id: 'u1',
      role: MessageRole.user,
      parts: const [
        TextPart('first'),
        ImagePart(
          attachmentId: 'a1.png',
          mimeType: 'image/png',
          width: 1,
          height: 1,
          byteCount: 1,
        ),
      ],
      createdAt: DateTime.utc(2026, 8, 9),
    );
    final updated = message.withText('second');
    expect(updated.parts.first, isA<ImagePart>());
    expect(updated.parts.last, isA<TextPart>());
    expect(updated.text, 'second');
    expect(updated.images.single.attachmentId, 'a1.png');
  });

  test('a malformed part fails the file rather than loading half a chat', () {
    expect(
      () => ChatMessage.fromJson({
        'id': 'u1',
        'role': 'user',
        'parts': [
          {'type': 'video', 'url': 'x'},
        ],
        'createdAt': DateTime.utc(2026).toIso8601String(),
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('reasoning is excluded from future prompt context', () {
    final conversation = ChatConversation(
      id: 'chat',
      title: 'Context',
      updatedAt: DateTime.now(),
      messages: [
        ChatMessage.text(
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
    ChatMessage message(String id, MessageRole role) => ChatMessage.text(
      id: id,
      role: role,
      text: 'text-$id',
      createdAt: at(1),
    );
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
        ChatMessage.text(
          id: 'u1',
          role: MessageRole.user,
          text: 'Any ideas?',
          createdAt: DateTime.utc(2026, 8, 2),
        ),
        ChatMessage.text(
          id: 'a1',
          role: MessageRole.assistant,
          text: 'A slow morning walk.',
          reasoning: 'Private chain of thought',
          createdAt: DateTime.utc(2026, 8, 2),
        ),
        ChatMessage.text(
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

  test('app preferences persist sparsely and round-trip', () async {
    final directory = await Directory.systemTemp.createTemp(
      'golem-ui-prefs-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/ui-prefs.json');
    final repository = FilePreferencesRepository(file);

    // A missing file is all defaults, not an error.
    final defaults = await repository.load();
    expect(defaults.theme, ThemeSetting.system);
    expect(defaults.saveHistory, isTrue);
    expect(defaults.advancedMode, isFalse);

    await repository.save(
      const AppPreferences(
        theme: ThemeSetting.dark,
        textScale: 1.15,
        showMetrics: false,
        expandReasoning: true,
        advancedMode: true,
        systemPrompt: 'Answer like a pirate.',
        customModels: [
          CustomModelSpec(
            repository: 'mlx-community/awesome-model',
            engine: ModelEngine.mlx,
          ),
        ],
      ).withStyle('gemma4', ResponseStyle.precise),
    );
    final loaded = await repository.load();
    expect(loaded.theme, ThemeSetting.dark);
    expect(loaded.textScale, 1.15);
    expect(loaded.showMetrics, isFalse);
    expect(loaded.expandReasoning, isTrue);
    expect(loaded.hapticsOnSend, isTrue);
    expect(loaded.advancedMode, isTrue);
    expect(loaded.systemPrompt, 'Answer like a pirate.');
    expect(loaded.styleFor('gemma4'), ResponseStyle.precise);
    expect(loaded.styleFor('qwen35'), ResponseStyle.balanced);
    expect(
      loaded.customModels.single.key,
      startsWith('custom-mlx-community-awesome-model-'),
    );

    // Only non-default values reach disk, so future default changes reach
    // users who never touched a control.
    final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    expect(raw['schemaVersion'], 2);
    expect(raw.containsKey('hapticsOnSend'), isFalse);
    expect(raw.containsKey('saveHistory'), isFalse);
    expect((raw['responseStyles'] as Map).keys, ['gemma4']);

    // Reverting the style to balanced removes its entry entirely.
    await repository.save(loaded.withStyle('gemma4', ResponseStyle.balanced));
    expect((await repository.load()).responseStyles, isEmpty);
  });

  test(
    'schema-v1 app preferences migrate to v2 without losing a repository',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'golem-ui-prefs-v1-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/ui-prefs.json');
      // Exactly what a pre-#43 install wrote: no profile on the repository.
      await file.writeAsString('''
{
  "schemaVersion": 1,
  "advancedMode": true,
  "customModels": [
    {"repository": "mlx-community/awesome-model", "engine": "mlx"}
  ]
}
''');

      final repository = FilePreferencesRepository(file);
      final loaded = await repository.load();
      expect(File('${file.path}.corrupt').existsSync(), isFalse);
      expect(loaded.advancedMode, isTrue);
      final spec = loaded.customModels.single;
      expect(spec.repository, 'mlx-community/awesome-model');
      expect(spec.engine, ModelEngine.mlx);
      expect(spec.revision, 'main');
      // Unresolved: it lists and deletes, but cannot be activated.
      expect(spec.profile, isNull);
      expect(spec.toCatalogEntry().profileKey, unresolvedProfileKey);

      await repository.save(loaded);
      final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      expect(raw['schemaVersion'], 2);
      expect((raw['customModels']! as List).single, {
        'repository': 'mlx-community/awesome-model',
        'engine': 'mlx',
      });
    },
  );

  test(
    'a stored profile that no longer parses degrades to unresolved',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'golem-ui-prefs-bad-profile-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/ui-prefs.json');
      await file.writeAsString('''
{
  "schemaVersion": 2,
  "customModels": [
    {
      "repository": "someone/model",
      "engine": "gguf",
      "profile": {"schemaVersion": 1, "key": "broken", "parser": "thinkTags"}
    }
  ]
}
''');

      final loaded = await FilePreferencesRepository(file).load();
      // The whole file must not be quarantined over one unusable profile.
      expect(File('${file.path}.corrupt').existsSync(), isFalse);
      expect(loaded.customModels.single.repository, 'someone/model');
      expect(loaded.customModels.single.profile, isNull);
    },
  );

  test('unreadable or unknown-schema app preferences recover', () async {
    final directory = await Directory.systemTemp.createTemp(
      'golem-ui-prefs-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    for (final content in ['not json at all', '{"schemaVersion": 99}']) {
      final file = File('${directory.path}/ui-prefs.json');
      await file.writeAsString(content);
      final repository = FilePreferencesRepository(file);
      expect((await repository.load()).saveHistory, isTrue);
      expect(File('${file.path}.corrupt').existsSync(), isTrue);
      await File('${file.path}.corrupt').delete();
    }
  });

  test('a custom repository derives a stable catalog entry', () {
    const spec = CustomModelSpec(
      repository: 'TheBloke/Some_Model-GGUF',
      engine: ModelEngine.gguf,
      revision: 'abc123',
    );
    final entry = spec.toCatalogEntry();
    expect(entry.key, startsWith('custom-thebloke-some-model-gguf-'));
    expect(entry.displayName, 'Some_Model-GGUF');
    expect(entry.engine, ModelEngine.gguf);
    expect(entry.revision, 'abc123');
    // The synthetic size is deterministic (goldens and journeys depend on
    // it) and stays in a plausible on-device range.
    expect(entry.totalBytes, spec.toCatalogEntry().totalBytes);
    expect(entry.totalBytes, greaterThanOrEqualTo(1200 * 1000 * 1000));
    expect(entry.totalBytes, lessThan(3200 * 1000 * 1000));
    // Re-adding the same repository replaces rather than duplicates.
    final prefs = const AppPreferences()
        .withCustomModel(spec)
        .withCustomModel(spec);
    expect(prefs.customModels, hasLength(1));

    // Repositories that differ only in punctuation collapse to the same
    // slug; the hash suffix keeps them distinct instead of silently
    // replacing each other's card and download state.
    const underscore = CustomModelSpec(
      repository: 'org/foo_bar',
      engine: ModelEngine.mlx,
    );
    const dash = CustomModelSpec(
      repository: 'org/foo-bar',
      engine: ModelEngine.mlx,
    );
    expect(underscore.key, isNot(dash.key));
    expect(
      const AppPreferences()
          .withCustomModel(underscore)
          .withCustomModel(dash)
          .customModels,
      hasLength(2),
    );
  });

  test('chat history reports its stored size', () async {
    final directory = await Directory.systemTemp.createTemp(
      'golem-history-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = FileChatHistoryRepository(
      File('${directory.path}/history.json'),
    );
    expect(await repository.storedBytes(), 0);
    await repository.save(const ChatHistorySnapshot(conversations: []));
    expect(await repository.storedBytes(), greaterThan(0));
  });
}
