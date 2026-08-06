import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/chat_search.dart';
import 'package:golem_flutter/core/domain/models.dart';

ChatConversation _chat(
  String id, {
  required String title,
  List<String> messages = const [],
  String? reasoning,
  DateTime? updatedAt,
  bool streamingLast = false,
}) => ChatConversation(
  id: id,
  title: title,
  updatedAt: updatedAt ?? DateTime.utc(2026, 8, 1),
  messages: [
    for (final (index, text) in messages.indexed)
      ChatMessage(
        id: '$id-$index',
        role: index.isEven ? MessageRole.user : MessageRole.assistant,
        text: text,
        reasoning: index.isOdd ? reasoning : null,
        createdAt: DateTime.utc(2026, 8, 1),
        isStreaming: streamingLast && index == messages.length - 1,
      ),
  ],
);

void main() {
  test('matches titles and bodies case-insensitively with counts', () {
    final results = searchConversations([
      _chat(
        'lisbon',
        title: 'Rainy weekend in Lisbon',
        messages: [
          'What should I pack for Lisbon?',
          'Rain in Lisbon is warm, so waterproofs matter more than warmth.',
        ],
        updatedAt: DateTime.utc(2026, 8, 5),
      ),
      _chat(
        'loops',
        title: 'Refactor a nested loop',
        messages: ['Rewrite this loop so it doesn’t nest three ifs deep.'],
        updatedAt: DateTime.utc(2026, 8, 2),
      ),
    ], 'LISBON');

    expect(results, hasLength(1));
    final hit = results.single;
    expect(hit.conversationId, 'lisbon');
    // One in the title, one in each message body.
    expect(hit.matchCount, 3);
    expect(hit.snippet.toLowerCase(), contains('lisbon'));
    expect(
      hit.snippet
          .substring(hit.matchStart, hit.matchStart + hit.matchLength)
          .toLowerCase(),
      'lisbon',
    );
  });

  test('results sort by recency and empty queries return nothing', () {
    final chats = [
      _chat(
        'old',
        title: 'walk the tram line',
        updatedAt: DateTime.utc(2026, 7, 1),
      ),
      _chat(
        'new',
        title: 'walk to the miradouro',
        updatedAt: DateTime.utc(2026, 8, 5),
      ),
    ];
    expect(searchConversations(chats, 'walk').map((r) => r.conversationId), [
      'new',
      'old',
    ]);
    expect(searchConversations(chats, '   '), isEmpty);
  });

  test('title-only matches fall back to the first message as snippet', () {
    final results = searchConversations([
      _chat(
        'packing',
        title: 'Weekend packing list',
        messages: ['Two merino layers instead of four cotton ones.'],
      ),
    ], 'packing list');
    final hit = results.single;
    expect(hit.snippet, contains('merino'));
    expect(hit.matchLength, 0, reason: 'no highlight range inside the body');
  });

  test('reasoning and streaming drafts never match', () {
    final chats = [
      _chat(
        'private',
        title: 'A settled chat',
        messages: ['Hello there', 'A public answer'],
        reasoning: 'secret waterproofs reasoning',
      ),
      _chat(
        'draft',
        title: 'Streaming now',
        messages: ['Ask something', 'half-written waterproofs draft'],
        streamingLast: true,
      ),
    ];
    expect(searchConversations(chats, 'waterproofs'), isEmpty);
  });

  test('long bodies clamp to a window around the first match', () {
    final filler = List.filled(60, 'word').join(' ');
    final results = searchConversations([
      _chat('long', title: 'Long chat', messages: ['$filler needle $filler']),
    ], 'needle');
    final hit = results.single;
    expect(hit.snippet.length, lessThan(120));
    expect(hit.snippet, startsWith('…'));
    expect(hit.snippet, endsWith('…'));
    expect(
      hit.snippet.substring(hit.matchStart, hit.matchStart + hit.matchLength),
      'needle',
    );
  });
}
