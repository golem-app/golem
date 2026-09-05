import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/model_speed.dart';
import 'package:golem_flutter/core/domain/models.dart';

/// The attribution rule behind every "N tok/s on this phone" the app shows.
///
/// Settings quotes it on the model card and chat quotes it on the picker row,
/// so the two surfaces agreeing depends entirely on this one walk. It was only
/// ever reached through those surfaces, which asserted the sentence and not the
/// rule (#120).
InferenceMetrics _metrics(double decode, {int tokens = 4}) => InferenceMetrics(
  promptTokensPerSecond: 13,
  decodeTokensPerSecond: decode,
  tokenCount: tokens,
  elapsedSeconds: 0.2,
);

ChatMessage _answer(
  String id,
  DateTime at, {
  double? decode,
  int tokens = 4,
  MessageRole role = MessageRole.assistant,
  bool streaming = false,
}) => ChatMessage.text(
  id: id,
  role: role,
  text: 'hi',
  createdAt: at,
  metrics: decode == null ? null : _metrics(decode, tokens: tokens),
  isStreaming: streaming,
);

ChatConversation _chat(
  String id,
  List<ChatMessage> messages, {
  String? modelKey,
}) => ChatConversation(
  id: id,
  title: id,
  updatedAt: DateTime.utc(2026),
  modelKey: modelKey,
  messages: messages,
);

void main() {
  group('which artifact a measurement belongs to', () {
    test('a conversation without a choice ran the build default', () {
      final rates = measuredTokensPerSecondByModel([
        _chat('c1', [_answer('m1', DateTime.utc(2026), decode: 21.4)]),
      ], defaultModelKey: 'gemma4-gguf');

      expect(rates, {'gemma4-gguf': 21.4});
    });

    test('no choice and no default attributes to nothing', () {
      final rates = measuredTokensPerSecondByModel([
        _chat('c1', [_answer('m1', DateTime.utc(2026), decode: 21.4)]),
      ], defaultModelKey: null);

      expect(rates, isEmpty);
    });

    // Asking for one key must walk to the same answer as building the whole
    // map: a narrowing that skipped the wrong side would quote one artifact's
    // rate on another artifact's row.
    test('asking for one key answers for that key, not its neighbour', () {
      final conversations = [
        _chat('c1', [
          _answer('m1', DateTime.utc(2026), decode: 24.6),
        ], modelKey: 'qwen35-2b-gguf'),
        _chat('c2', [
          _answer('m2', DateTime.utc(2026), decode: 14.2),
        ], modelKey: 'qwen35-gguf'),
      ];

      expect(
        measuredTokensPerSecond(
          conversations,
          modelKey: 'qwen35-2b-gguf',
          defaultModelKey: null,
        ),
        24.6,
      );
      expect(
        measuredTokensPerSecond(
          conversations,
          modelKey: 'qwen35-gguf',
          defaultModelKey: null,
        ),
        14.2,
      );
      expect(
        measuredTokensPerSecondByModel(conversations, defaultModelKey: null),
        {'qwen35-2b-gguf': 24.6, 'qwen35-gguf': 14.2},
      );
    });
  });

  group('which turns count as a measurement', () {
    test('a turn still streaming has not been measured yet', () {
      final rates = measuredTokensPerSecondByModel([
        _chat('c1', [
          _answer('m1', DateTime.utc(2026), decode: 21.4, streaming: true),
        ], modelKey: 'gemma4-gguf'),
      ], defaultModelKey: null);

      expect(rates, isEmpty);
    });

    test('only the model is timed, never the person typing', () {
      final rates = measuredTokensPerSecondByModel([
        _chat('c1', [
          _answer('m1', DateTime.utc(2026), decode: 99, role: MessageRole.user),
        ], modelKey: 'gemma4-gguf'),
      ], defaultModelKey: null);

      expect(rates, isEmpty);
    });

    test('a turn with no metrics is not a measurement', () {
      final rates = measuredTokensPerSecondByModel([
        _chat('c1', [_answer('m1', DateTime.utc(2026))], modelKey: 'g'),
      ], defaultModelKey: null);

      expect(rates, isEmpty);
    });

    // The newest, not the first or the fastest: a model that got slower after
    // a thermal throttle must say so rather than keep quoting its best run.
    test('the most recent measurement is the one quoted', () {
      final rates = measuredTokensPerSecondByModel([
        _chat('c1', [
          _answer('m1', DateTime.utc(2026, 1, 1), decode: 30),
          _answer('m2', DateTime.utc(2026, 1, 2), decode: 12),
        ], modelKey: 'gemma4-gguf'),
      ], defaultModelKey: null);

      expect(rates, {'gemma4-gguf': 12});
    });

    // Under timing semantics v2 a one-token reply has no inter-token interval
    // and reports no rate (ADR 0020); quoting its zero would read as a stall.
    test('a one-token reply is not a measurement', () {
      final rates = measuredTokensPerSecondByModel([
        _chat('c1', [
          _answer('m1', DateTime.utc(2026, 1, 1), decode: 30),
          _answer('m2', DateTime.utc(2026, 1, 2), decode: 0, tokens: 1),
        ], modelKey: 'gemma4-gguf'),
      ], defaultModelKey: null);

      expect(rates, {'gemma4-gguf': 30});
    });

    test('order in the history does not decide, the timestamp does', () {
      final rates = measuredTokensPerSecondByModel([
        _chat('c1', [
          _answer('m1', DateTime.utc(2026, 1, 2), decode: 12),
          _answer('m2', DateTime.utc(2026, 1, 1), decode: 30),
        ], modelKey: 'gemma4-gguf'),
      ], defaultModelKey: null);

      expect(rates, {'gemma4-gguf': 12});
    });
  });
}
