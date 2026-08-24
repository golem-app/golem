import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/context_window.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';

PromptMessage _turn(String role, int chars) =>
    PromptMessage.text(role, 'x' * chars);

// One message of 1000 chars estimates to 250 tokens and costs
// ceil(250 * 5 / 4) + 8 = 321 in the budget math below.
const _chars = 1000;

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
    expect(windowed.first.role, 'user');
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

  // The budgets above all sit exactly on a multiple of the per-message cost,
  // so a cost that drifts by a few tokens still evicts the same number of
  // messages. One token under the exact fit does not — and the roles are
  // arranged so the leading-assistant trim cannot absorb the difference.
  test('one token under the exact fit evicts another message', () {
    final context = [
      for (var i = 0; i < 6; i++) _turn(i.isOdd ? 'user' : 'assistant', _chars),
    ];
    expect(
      windowedContext(
        context: context,
        contextLength: 962 + 512 + 2048,
        maxTokens: 2048,
      ),
      // 3·321 = 963 no longer fits. Two turns survive the budget, and the
      // older of the two is the assistant's, so the trim drops it too.
      context.sublist(5),
    );
    expect(
      windowedContext(
        context: context,
        contextLength: 963 + 512 + 2048,
        maxTokens: 2048,
      ),
      // One token more and three fit, opening with the user: no trim.
      context.sublist(3),
    );
  });

  test('an image is charged on top of the words beside it', () {
    final picture = PromptMessage(
      role: 'user',
      parts: [
        const TextPart('look'),
        ImagePart(
          attachmentId: 'a1',
          mimeType: 'image/png',
          width: 8,
          height: 8,
          byteCount: 64,
        ),
      ],
    );
    // The words alone are trivially affordable; the picture is not, so a
    // window that subtracted its cost instead of adding it would accept a
    // turn the engine cannot fit.
    expect(
      () => windowedContext(
        context: [picture],
        contextLength: 8192,
        maxTokens: 2048,
        imageTokenCost: 6000,
      ),
      throwsA(isA<InferenceException>()),
    );
    expect(
      windowedContext(
        context: [picture],
        contextLength: 8192,
        maxTokens: 2048,
        imageTokenCost: 1280,
      ),
      hasLength(1),
    );
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
    // A tiny system prompt costs a little, not everything: it is subtracted
    // from the budget, and a budget *replaced* by that cost would leave no
    // room for the final message and refuse the turn outright.
    expect(
      windowedContext(
        context: context,
        contextLength: 963 + 512 + 2048,
        maxTokens: 2048,
        systemPrompt: 'xxxx',
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
