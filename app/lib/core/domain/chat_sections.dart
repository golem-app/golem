import 'models.dart';

/// Drawer presentation grouping: pinned first, then calendar buckets.
///
/// Grouping is pure and derived at render time, so the storage order the
/// controller maintains (active-first) never leaks into presentation.
final class ChatSections {
  const ChatSections({
    required this.pinned,
    required this.today,
    required this.yesterday,
    required this.earlier,
  });

  final List<ChatConversation> pinned;
  final List<ChatConversation> today;
  final List<ChatConversation> yesterday;
  final List<ChatConversation> earlier;

  bool get isEmpty =>
      pinned.isEmpty && today.isEmpty && yesterday.isEmpty && earlier.isEmpty;
}

ChatSections groupConversations(
  List<ChatConversation> conversations,
  DateTime now,
) {
  final pinned = <ChatConversation>[];
  final today = <ChatConversation>[];
  final yesterday = <ChatConversation>[];
  final earlier = <ChatConversation>[];

  final startOfToday = DateTime(now.year, now.month, now.day);
  final startOfYesterday = startOfToday.subtract(const Duration(days: 1));

  for (final conversation in conversations) {
    if (conversation.pinned) {
      pinned.add(conversation);
    } else if (!conversation.updatedAt.isBefore(startOfToday)) {
      today.add(conversation);
    } else if (!conversation.updatedAt.isBefore(startOfYesterday)) {
      yesterday.add(conversation);
    } else {
      earlier.add(conversation);
    }
  }

  int newestFirst(ChatConversation a, ChatConversation b) =>
      b.updatedAt.compareTo(a.updatedAt);
  pinned.sort(newestFirst);
  today.sort(newestFirst);
  yesterday.sort(newestFirst);
  earlier.sort(newestFirst);

  return ChatSections(
    pinned: pinned,
    today: today,
    yesterday: yesterday,
    earlier: earlier,
  );
}
