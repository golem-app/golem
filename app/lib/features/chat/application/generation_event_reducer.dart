import '../../../core/domain/models.dart';

/// Folds one streaming [InferenceEvent] into the assistant draft, which is
/// always the last message of the active conversation.
///
/// Returns null when the event changes nothing, so the caller can skip the
/// state reassignment rather than publish an identical list. Extracted from
/// ChatController (#127): the per-event field rule is a decision, and it was
/// previously reachable only by driving a whole generation through a container.
List<ChatMessage>? applyGenerationEvent(
  List<ChatMessage> messages,
  InferenceEvent event,
) {
  if (messages.isEmpty) return null;
  final draft = messages.last;
  final ChatMessage updated;
  switch (event) {
    case ReasoningDelta():
      // Reasoning starts null and is appended to, so the null coalesce is the
      // first delta's case rather than a defensive one.
      updated = draft.copyWith(
        reasoning: '${draft.reasoning ?? ''}${event.text}',
      );
    case AnswerDelta():
      updated = draft.withText('${draft.text}${event.text}');
    case AnswerResetEvent():
      // The broker retracts an answer it began before the reasoning channel
      // closed. Reasoning and metrics survive; only the answer is dropped.
      updated = draft.withText('');
    case MetricsEvent():
      updated = draft.copyWith(metrics: event.metrics);
    case CompletedEvent():
      return null;
    case RunPhaseEvent() ||
        LoadProgressEvent() ||
        PromptProgressEvent() ||
        TokenTimingEvent():
      // Observation is the bench's channel; a transcript has no field for it.
      return null;
  }
  return [...messages.take(messages.length - 1), updated];
}
