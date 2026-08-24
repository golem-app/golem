import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/features/chat/domain/chat_sections.dart';
import 'package:golem_flutter/core/domain/models.dart';

ChatConversation _chat(String id, DateTime updatedAt, {bool pinned = false}) =>
    ChatConversation(
      id: id,
      title: id,
      messages: const [],
      updatedAt: updatedAt,
      pinned: pinned,
    );

void main() {
  final now = DateTime(2026, 8, 6, 15, 30);

  test('groups pinned first, then today, yesterday, and earlier', () {
    final sections = groupConversations([
      _chat('earlier', DateTime(2026, 8, 1, 9)),
      _chat('today-late', DateTime(2026, 8, 6, 14)),
      _chat('pinned-old', DateTime(2026, 7, 1), pinned: true),
      _chat('yesterday', DateTime(2026, 8, 5, 23, 59)),
      _chat('today-early', DateTime(2026, 8, 6, 0, 0)),
      _chat('pinned-new', DateTime(2026, 8, 6, 10), pinned: true),
    ], now);

    expect(sections.pinned.map((c) => c.id), ['pinned-new', 'pinned-old']);
    expect(sections.today.map((c) => c.id), ['today-late', 'today-early']);
    expect(sections.yesterday.map((c) => c.id), ['yesterday']);
    expect(sections.earlier.map((c) => c.id), ['earlier']);
    expect(sections.isEmpty, isFalse);
  });

  test('a pinned chat never appears in a dated section', () {
    final sections = groupConversations([
      _chat('both', DateTime(2026, 8, 6, 12), pinned: true),
    ], now);
    expect(sections.pinned.single.id, 'both');
    expect(sections.today, isEmpty);
  });

  test('presentation order ignores storage order', () {
    // The controller keeps the active conversation at the list head;
    // grouping must sort by recency regardless.
    final sections = groupConversations([
      _chat('older-but-first', DateTime(2026, 8, 6, 8)),
      _chat('newer-but-second', DateTime(2026, 8, 6, 12)),
    ], now);
    expect(sections.today.map((c) => c.id), [
      'newer-but-second',
      'older-but-first',
    ]);
  });

  test('empty input yields empty sections', () {
    expect(groupConversations(const [], now).isEmpty, isTrue);
  });
}
