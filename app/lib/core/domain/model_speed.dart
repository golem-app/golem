import 'inference_backend.dart';
import 'models.dart';

/// Decode speeds evidenced in the chat history, per catalog key.
///
/// In core rather than a feature since #79: Settings quotes these on the model
/// card and chat quotes them on the picker row, and two readers of one rule
/// mean neither owns it. Both must also *ask* it the same way, which is what
/// [defaultMeasuredModelKey] is for — attribution that differed by one
/// fallback had the same artifact showing a rate on one surface and none on
/// the other.
///
/// Attribution rides the conversation's effective model: a conversation with
/// no per-chat choice ran the build's default artifact. Honesty note for
/// callers: on simulated backends the number is the fake's canned rate and
/// must be labelled simulated, never "on this phone".
Map<String, double> measuredTokensPerSecondByModel(
  List<ChatConversation> conversations, {
  required String? defaultModelKey,
}) => _scan(conversations, defaultModelKey: defaultModelKey, only: null);

/// One key, without building the whole map: a caller asking per row would
/// otherwise walk the entire history once per row and throw the rest away.
double? measuredTokensPerSecond(
  List<ChatConversation> conversations, {
  required String modelKey,
  required String? defaultModelKey,
}) => _scan(
  conversations,
  defaultModelKey: defaultModelKey,
  only: modelKey,
)[modelKey];

/// The attribution rule itself, stated once. [only] narrows the walk without
/// changing what it decides — a second copy of this loop is how the two
/// surfaces would come to quote different numbers for one artifact.
Map<String, double> _scan(
  List<ChatConversation> conversations, {
  required String? defaultModelKey,
  required String? only,
}) {
  final best = <String, double>{};
  final bestAt = <String, DateTime>{};
  for (final conversation in conversations) {
    final effective = conversation.modelKey ?? defaultModelKey;
    if (effective == null) continue;
    if (only != null && effective != only) continue;
    for (final message in conversation.messages) {
      final metrics = message.metrics;
      if (message.role != MessageRole.assistant ||
          message.isStreaming ||
          metrics == null) {
        continue;
      }
      final seen = bestAt[effective];
      if (seen == null || message.createdAt.isAfter(seen)) {
        bestAt[effective] = message.createdAt;
        best[effective] = metrics.decodeTokensPerSecond;
      }
    }
  }
  return best;
}

/// What a conversation with no per-chat choice actually ran, which is what
/// unattributed metrics belong to. The fake names no boot artifact, so the
/// stamped active key stands in — the same value the picker badges and the
/// chrome labels.
String? defaultMeasuredModelKey(
  InferenceBackendConfig backend,
  ModelState? models,
) => backend.artifactKey ?? models?.activeArtifactKey;
