import '../core/domain/models.dart';
import '../core/repositories/contracts.dart';

/// The prompt reserve the windowing budget always leaves free, promoted
/// from the UI-only slider clamp to an enforced invariant (ADR 0003: the
/// settings UI keeps `maxTokens ≤ contextLength − 512`; this module makes
/// the same 512 hold for the rendered prompt).
const int contextPromptReserveTokens = 512;

/// Character-based token estimate (~4 chars/token, the repo's existing
/// convention). Deliberately cheap: the engines still enforce the real
/// budget, so estimation errors degrade to a typed failure, never a lie.
int estimatedTokenCount(String text) => (text.length / 4).ceil();

/// A message's budget cost: its estimated tokens with a 25% safety margin
/// for estimation drift plus a fixed allowance for the chat template's
/// per-turn control tokens.
int _messageCost(String content) =>
    (estimatedTokenCount(content) * 5 + 3) ~/ 4 + 8;

/// A turn's cost, counting each image at the profile's declared token price.
///
/// An image's cost has nothing to do with any string length — a vision
/// encoder emits a fixed number of tokens per picture — so it is data the
/// profile carries, not something this file can estimate.
int _promptMessageCost(PromptMessage message, int imageTokenCost) =>
    _messageCost(message.text) + message.images.length * imageTokenCost;

/// The newest suffix of [context] whose estimated cost fits the window:
/// `contextLength − maxTokens − 512`, minus the system prompt's cost when
/// present. Whole messages are evicted oldest-first, the final message is
/// always kept, and a leading assistant turn left behind by eviction is
/// dropped so the rendered conversation still opens with the user.
///
/// Throws a typed [InferenceException] with
/// [InferenceFailureKind.contextExhausted] when the final message alone
/// cannot fit — the one case no window can save, and the reason this
/// failure's banner action is never Retry.
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
  // Eviction can leave an assistant turn in front; the conversation the
  // model sees should still open with the user speaking.
  while (start < context.length - 1 && context[start].role == 'assistant') {
    start++;
  }
  return start == 0 ? context : context.sublist(start);
}
