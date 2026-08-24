import '../core/domain/model_profile_spec.dart';

/// Reasoning is never fed back to the model, so every template strips it from
/// history; the form is the spec's [ChatTemplateSpec.historyStrip] decision,
/// not the strategy's. Both modes live here so neither renderer imports the
/// other.
String stripHistoryReasoning(String text, ChatTemplateSpec spec) =>
    switch (spec.historyStrip) {
      HistoryStripMode.none => text,
      HistoryStripMode.reasoningChannels => stripReasoningChannels(text, spec),
      HistoryStripMode.thinkBlocks => stripThinkBlocks(text, spec),
    };

/// Drops `<|channel>label … <channel|>` segments; an unterminated channel
/// swallows the remainder, so a truncated tail cannot leak into the next
/// prompt.
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

/// Complete spans only: stray markers are left to the caller's sanitize pass,
/// and the result is deliberately not trimmed — the ChatML renderer trims last.
String stripThinkBlocks(String text, ChatTemplateSpec spec) {
  final open = spec.thinkStart;
  final close = spec.thinkEnd;
  if (open == null || close == null) return text;
  return text.replaceAll(
    RegExp('${RegExp.escape(open)}.*?${RegExp.escape(close)}', dotAll: true),
    '',
  );
}
