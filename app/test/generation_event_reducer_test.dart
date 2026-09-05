import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/chat/application/generation_event_reducer.dart';

/// How a streaming event lands on the assistant draft. Extracted from
/// ChatController's `await for` (#127), where each arm was only ever exercised
/// through a full container-driven generation.

final _now = DateTime.utc(2026, 8, 17);

ChatMessage _draft({String text = '', String? reasoning}) => ChatMessage.text(
  id: 'assistant',
  role: MessageRole.assistant,
  text: text,
  reasoning: reasoning,
  createdAt: _now,
  isStreaming: true,
);

List<ChatMessage> _turn(ChatMessage draft) => [
  ChatMessage.text(
    id: 'user',
    role: MessageRole.user,
    text: 'question',
    createdAt: _now,
  ),
  draft,
];

void main() {
  test('an answer delta appends to the draft, leaving the turn above it', () {
    final result = applyGenerationEvent(
      _turn(_draft(text: 'Half ')),
      const AnswerDelta('an answer'),
    );

    expect(result, isNotNull);
    expect(result!.length, 2);
    expect(result.first.id, 'user');
    expect(result.last.text, 'Half an answer');
  });

  test('a reasoning delta appends to reasoning, never to the answer', () {
    // Private reasoning and the visible answer are separate channels; crossing
    // them would leak the model's scratchpad into the transcript.
    final result = applyGenerationEvent(
      _turn(_draft(text: 'visible', reasoning: 'I will ')),
      const ReasoningDelta('think first.'),
    );

    expect(result!.last.reasoning, 'I will think first.');
    expect(result.last.text, 'visible');
  });

  test('the first reasoning delta starts from nothing, not from "null"', () {
    final result = applyGenerationEvent(
      _turn(_draft()),
      const ReasoningDelta('opening thought'),
    );

    expect(result!.last.reasoning, 'opening thought');
  });

  test('a reset clears the answer and keeps the reasoning', () {
    // The broker retracts an answer it began before the reasoning channel
    // closed. Re-deriving the reasoning would cost the whole preamble.
    final result = applyGenerationEvent(
      _turn(_draft(text: 'retracted', reasoning: 'kept')),
      const AnswerResetEvent(),
    );

    expect(result!.last.text, isEmpty);
    expect(result.last.reasoning, 'kept');
  });

  test('metrics attach without disturbing the text', () {
    const metrics = InferenceMetrics(
      promptTokensPerSecond: 30,
      decodeTokensPerSecond: 40,
      tokenCount: 20,
      elapsedSeconds: 1.5,
    );

    final result = applyGenerationEvent(
      _turn(_draft(text: 'answer')),
      const MetricsEvent(metrics),
    );

    expect(result!.last.metrics, metrics);
    expect(result.last.text, 'answer');
  });

  test('completion changes nothing — finalization owns that transition', () {
    expect(
      applyGenerationEvent(_turn(_draft(text: 'done')), const CompletedEvent()),
      isNull,
    );
  });

  test('observation events change nothing in a transcript', () {
    final messages = _turn(_draft(text: 'so far'));
    for (final event in const <InferenceEvent>[
      RunPhaseEvent(InferencePhase.generating),
      LoadProgressEvent(0.5),
      PromptProgressEvent(completed: 1, total: 2),
      TokenTimingEvent(
        kind: ObservationKind.token,
        firstIndex: 0,
        timesMs: [1],
      ),
    ]) {
      expect(applyGenerationEvent(messages, event), isNull, reason: '$event');
    }
  });

  test('an empty conversation has no draft to fold into', () {
    expect(applyGenerationEvent(const [], const AnswerDelta('x')), isNull);
  });

  test('the draft is replaced, not mutated in place', () {
    // ChatState is identity-compared, so a reducer that edited the existing
    // list would leave the UI on a stale frame.
    final messages = _turn(_draft(text: 'before'));
    final result = applyGenerationEvent(messages, const AnswerDelta('after'));

    expect(messages.last.text, 'before');
    expect(result!.last.text, 'beforeafter');
  });
}
