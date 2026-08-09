import '../core/domain/model_profile_spec.dart';

/// Removes a model's own reasoning from an assistant turn already in the
/// transcript, before that turn is rendered back into the prompt.
///
/// Reasoning is never fed back to the model, so every template needs this;
/// which form it takes is the spec's [ChatTemplateSpec.historyStrip] decision,
/// not the template strategy's. Both implementations live here so the two
/// renderers can honour any declared mode without importing each other.
String stripHistoryReasoning(String text, ChatTemplateSpec spec) =>
    switch (spec.historyStrip) {
      HistoryStripMode.none => text,
      HistoryStripMode.reasoningChannels => stripReasoningChannels(text, spec),
      HistoryStripMode.thinkBlocks => stripThinkBlocks(text, spec),
    };

/// Drops `<|channel>label … <channel|>` segments, keeping the visible text.
/// An unterminated channel swallows the remainder: a truncated reasoning tail
/// must not leak into the next prompt. Trims, matching the Gemma contract.
String stripReasoningChannels(String text, ChatTemplateSpec spec) {
  final open = spec.channelStart;
  final close = spec.channelEnd;
  if (open == null || close == null) return text.trim();
  var remaining = text;
  final visible = StringBuffer();
  while (remaining.isNotEmpty) {
    final start = remaining.indexOf(open);
    if (start < 0) {
      visible.write(remaining);
      break;
    }
    visible.write(remaining.substring(0, start));
    final end = remaining.indexOf(close, start + open.length);
    if (end < 0) break;
    remaining = remaining.substring(end + close.length);
  }
  return visible.toString().trim();
}

/// Removes complete `<think>…</think>` spans. Stray unmatched markers are left
/// to the caller's sanitize pass, and the result is deliberately not trimmed —
/// the ChatML renderer trims after sanitizing.
String stripThinkBlocks(String text, ChatTemplateSpec spec) {
  final open = spec.thinkStart;
  final close = spec.thinkEnd;
  if (open == null || close == null) return text;
  return text.replaceAll(
    RegExp('${RegExp.escape(open)}.*?${RegExp.escape(close)}', dotAll: true),
    '',
  );
}
