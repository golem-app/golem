import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/context_window.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';

Map<String, String> _turn(String role, int chars) => {
  'role': role,
  'content': 'x' * chars,
};

// One message of 1000 chars estimates to 250 tokens, costs
// ceil(250 * 5 / 4) + 8 = 321 within the budget math below.
const _chars = 1000;
const _cost = 321;

void main() {
  test('a conversation inside the budget passes through untouched', () {
    final context = [
      _turn('user', _chars),
      _turn('assistant', _chars),
      _turn('user', _chars),
    ];
    final windowed = windowedContext(
      context: context,
      contextLength: 8192,
      maxTokens: 2048,
    );
    expect(windowed, same(context));
  });

  test('eviction drops oldest whole messages exactly at the budget', () {
    // Budget = contextLength − maxTokens − 512. Choose it to fit exactly
    // three messages: 3·321 = 963 ≤ 963 < 4·321.
    final context = [
      for (var i = 0; i < 6; i++)
        _turn(i.isEven ? 'user' : 'assistant', _chars),
    ];
    final windowed = windowedContext(
      context: context,
      contextLength: 963 + 512 + 2048,
      maxTokens: 2048,
    );
    // Three fit, but the suffix of three would open with an assistant
    // turn (index 3) — the leading-assistant trim drops it.
    expect(windowed, hasLength(2));
    expect(windowed.first['role'], 'user');
    expect(windowed, context.sublist(4));
  });

  test('a suffix opening with the user keeps all fitting messages', () {
    final context = [
      for (var i = 0; i < 5; i++)
        _turn(i.isEven ? 'user' : 'assistant', _chars),
    ];
    final windowed = windowedContext(
      context: context,
      contextLength: 963 + 512 + 2048,
      maxTokens: 2048,
    );
    // Indices 2,3,4 fit and index 2 is a user turn: no trim needed.
    expect(windowed, context.sublist(2));
  });

  test('the system prompt costs budget', () {
    final context = [
      _turn('user', _chars),
      _turn('assistant', _chars),
      _turn('user', _chars),
    ];
    // Three messages fit without a system prompt…
    expect(
      windowedContext(
        context: context,
        contextLength: 963 + 512 + 2048,
        maxTokens: 2048,
      ),
      hasLength(3),
    );
    // …but a system prompt of the same size evicts one (and the trim
    // then drops the leading assistant turn).
    expect(
      windowedContext(
        context: context,
        contextLength: 963 + 512 + 2048,
        maxTokens: 2048,
        systemPrompt: 'x' * _chars,
      ),
      context.sublist(2),
    );
  });

  test('an oversized final message throws the typed failure', () {
    expect(
      () => windowedContext(
        context: [_turn('user', _chars), _turn('user', 100 * _chars)],
        contextLength: 8192,
        maxTokens: 2048,
      ),
      throwsA(
        isA<InferenceException>()
            .having(
              (error) => error.kind,
              'kind',
              InferenceFailureKind.contextExhausted,
            )
            .having((error) => error.message, 'message', contains('too long')),
      ),
    );
  });

  test('estimation follows the ~4 chars/token convention', () {
    expect(estimatedTokenCount(''), 0);
    expect(estimatedTokenCount('abcd'), 1);
    expect(estimatedTokenCount('abcde'), 2);
  });
}
