import 'models.dart';

/// One conversation's hit in cross-chat search.
///
/// [snippet] carries the text shown on the result card; [matchStart] and
/// [matchLength] locate the highlighted range inside it. [matchCount]
/// counts every occurrence across the title and all message bodies.
final class ChatSearchResult {
  const ChatSearchResult({
    required this.conversationId,
    required this.title,
    required this.snippet,
    required this.matchStart,
    required this.matchLength,
    required this.matchCount,
    required this.updatedAt,
  });

  final String conversationId;
  final String title;
  final String snippet;
  final int matchStart;
  final int matchLength;
  final int matchCount;
  final DateTime updatedAt;
}

/// Case-insensitive contains over titles and message bodies. Reasoning is
/// deliberately excluded — it never leaves the bubble it was streamed
/// into, matching [ChatConversation.promptContext].
List<ChatSearchResult> searchConversations(
  List<ChatConversation> conversations,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];

  final results = <ChatSearchResult>[];
  for (final conversation in conversations) {
    var matchCount = _countOccurrences(
      conversation.title.toLowerCase(),
      needle,
    );
    String? snippetSource;
    for (final message in conversation.messages) {
      if (message.isStreaming) continue;
      final occurrences = _countOccurrences(message.text.toLowerCase(), needle);
      matchCount += occurrences;
      if (occurrences > 0) snippetSource ??= message.text;
    }
    if (matchCount == 0) continue;

    // A title-only match still needs card text: fall back to the first
    // message so the card never renders an empty snippet.
    snippetSource ??= conversation.messages
        .where((message) => !message.isStreaming)
        .map((message) => message.text)
        .firstOrNull;

    final snippet = _buildSnippet(snippetSource ?? '', needle);
    results.add(
      ChatSearchResult(
        conversationId: conversation.id,
        title: conversation.title,
        snippet: snippet.text,
        matchStart: snippet.start,
        matchLength: snippet.start < 0 ? 0 : needle.length,
        matchCount: matchCount,
        updatedAt: conversation.updatedAt,
      ),
    );
  }

  results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return results;
}

int _countOccurrences(String haystack, String needle) {
  var count = 0;
  var index = haystack.indexOf(needle);
  while (index >= 0) {
    count++;
    index = haystack.indexOf(needle, index + needle.length);
  }
  return count;
}

typedef _Snippet = ({String text, int start});

/// Roughly ±40 characters around the first match, ellipsised on cut edges.
_Snippet _buildSnippet(String source, String needle) {
  final flattened = source.replaceAll(RegExp(r'\s+'), ' ').trim();
  final matchIndex = flattened.toLowerCase().indexOf(needle);
  if (matchIndex < 0) {
    final text = flattened.length <= 90
        ? flattened
        : '${flattened.substring(0, 89)}…';
    return (text: text, start: -1);
  }

  const margin = 40;
  final from = matchIndex <= margin ? 0 : matchIndex - margin;
  final to = matchIndex + needle.length + margin >= flattened.length
      ? flattened.length
      : matchIndex + needle.length + margin;
  final prefix = from > 0 ? '…' : '';
  final suffix = to < flattened.length ? '…' : '';
  final text = '$prefix${flattened.substring(from, to)}$suffix';
  return (text: text, start: matchIndex - from + prefix.length);
}
