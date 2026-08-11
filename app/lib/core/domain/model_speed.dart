import 'models.dart';

/// The most recent decode speed evidenced for [modelKey] in the chat
/// history, or null when no generation has measured it.
///
/// In core rather than a feature since #79: Settings quotes it on the model
/// card and chat quotes it on the picker row, and two readers of one rule mean
/// neither owns it.
///
/// Attribution rides the conversation's effective model: a conversation
/// with no per-chat choice ran [defaultModelKey] (the backend's active
/// artifact). Honesty note for callers: on simulated backends the number
/// is the fake's canned rate and must be labeled simulated, never "on
/// this phone".
double? measuredTokensPerSecond(
  List<ChatConversation> conversations, {
  required String modelKey,
  required String? defaultModelKey,
}) {
  double? best;
  DateTime? bestAt;
  for (final conversation in conversations) {
    final effective = conversation.modelKey ?? defaultModelKey;
    if (effective != modelKey) continue;
    for (final message in conversation.messages) {
      final metrics = message.metrics;
      if (message.role != MessageRole.assistant ||
          message.isStreaming ||
          metrics == null) {
        continue;
      }
      if (bestAt == null || message.createdAt.isAfter(bestAt)) {
        bestAt = message.createdAt;
        best = metrics.decodeTokensPerSecond;
      }
    }
  }
  return best;
}
