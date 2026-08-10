import '../core/domain/models.dart';
import '../core/repositories/contracts.dart';

/// The prompt reserve the windowing budget always leaves free — the same 512
/// the settings UI clamps `maxTokens` to (ADR 0003), promoted from a UI-only
/// clamp to an enforced invariant.
const int contextPromptReserveTokens = 512;

/// ~4 chars/token, the repo's convention. Deliberately cheap: the engines
/// enforce the real budget, so drift degrades to a typed failure, never a lie.
int estimatedTokenCount(String text) => (text.length / 4).ceil();

/// Estimated tokens plus a 25% drift margin and a per-turn control allowance.
int _messageCost(String content) =>
    (estimatedTokenCount(content) * 5 + 3) ~/ 4 + 8;

/// A turn's cost. An image's price is unrelated to string length (a vision
/// encoder emits a fixed count per picture), so the profile supplies it.
int _promptMessageCost(PromptMessage message, int imageTokenCost) =>
    _messageCost(message.text) + message.images.length * imageTokenCost;

/// The newest suffix of [context] whose estimated cost fits the window.
///
/// Throws [InferenceFailureKind.contextExhausted] when the final message alone
/// cannot fit — the one case no window can save, and why that failure's banner
/// action is never Retry.
List<PromptMessage> windowedContext({
  required List<PromptMessage> context,
  required int contextLength,
  required int maxTokens,
  String? systemPrompt,
  int imageTokenCost = 0,
}) {
  if (context.isEmpty) return context;
  var budget = contextLength - maxTokens - contextPromptReserveTokens;
  if (systemPrompt != null && systemPrompt.isNotEmpty) {
    budget -= _messageCost(systemPrompt);
  }

  final last = context.last;
  final lastCost = _promptMessageCost(last, imageTokenCost);
  if (lastCost > budget) {
    throw const InferenceException(
      InferenceFailureKind.contextExhausted,
      'This message is too long to fit the model’s context window. '
      'Shorten it and try again.',
    );
  }

  var start = context.length - 1;
  var used = lastCost;
  while (start > 0) {
    final cost = _promptMessageCost(context[start - 1], imageTokenCost);
    if (used + cost > budget) break;
    used += cost;
    start--;
  }
  // The conversation the model sees must still open with the user speaking.
  while (start < context.length - 1 && context[start].role == 'assistant') {
    start++;
  }
  return start == 0 ? context : context.sublist(start);
}
