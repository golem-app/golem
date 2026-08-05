// ReasoningStreamDelta is the broker-wide stream currency; it lives with the
// first parser that produced it.
import 'gemma4_chat_template.dart' show ReasoningStreamDelta;

/// The pinned Qwen 3.5 `chat_template.jinja` subset used by v0 text chat:
/// ChatML turns with no BOS anywhere, an optional leading system turn, and a
/// generation primer that opens a `<think>` block when reasoning is enabled
/// or closes an empty one when it is not — so streamed output begins inside
/// the think block and `</think>` is the channel boundary.
final class Qwen35ChatTemplate {
  static const imStart = '<|im_start|>';
  static const imEnd = '<|im_end|>';
  static const thinkStart = '<think>';
  static const thinkEnd = '</think>';
  static const imEndTokenId = 248046;
  static const endOfTextTokenId = 248044;

  static String render(
    List<Map<String, String>> messages, {
    required bool reasoningEnabled,
  }) {
    if (messages.isEmpty) {
      throw ArgumentError('messages must not be empty.');
    }
    final buffer = StringBuffer();
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      switch (message['role']) {
        case 'system' || 'developer':
          if (i != 0) {
            throw ArgumentError('A system message must come first.');
          }
          buffer.write('${imStart}system\n${_content(message)}$imEnd\n');
        case 'user':
          buffer.write('${imStart}user\n${_content(message)}$imEnd\n');
        case 'assistant':
          // Upstream strips reasoning from every assistant turn at or before
          // the latest user query; chat history always precedes it, so
          // history turns carry the visible answer only.
          buffer.write(
            '${imStart}assistant\n'
            '${sanitize(stripThinkBlocks(message['content'] ?? '')).trim()}'
            '$imEnd\n',
          );
        default:
          throw ArgumentError('Unsupported role: ${message['role']}');
      }
    }
    buffer.write('${imStart}assistant\n');
    buffer.write(
      reasoningEnabled ? '$thinkStart\n' : '$thinkStart\n\n$thinkEnd\n\n',
    );
    return buffer.toString();
  }

  static String _content(Map<String, String> message) =>
      sanitize(message['content'] ?? '').trim();

  /// Removes every control marker, to a fixpoint so removals cannot splice
  /// two fragments into a live marker.
  static String sanitize(String text) {
    var current = text;
    while (true) {
      final next = current
          .replaceAll(imStart, '')
          .replaceAll(imEnd, '')
          .replaceAll(thinkStart, '')
          .replaceAll(thinkEnd, '');
      if (next == current) return current;
      current = next;
    }
  }

  /// Removes complete `<think>…</think>` spans; stray unmatched markers are
  /// left for [sanitize].
  static String stripThinkBlocks(String text) => text.replaceAll(
    RegExp(
      '${RegExp.escape(thinkStart)}.*?${RegExp.escape(thinkEnd)}',
      dotAll: true,
    ),
    '',
  );
}

/// Splits a streamed Qwen generation into reasoning and answer channels.
///
/// With reasoning enabled the prompt primer already opened a `<think>` block,
/// so the stream starts in the reasoning channel with no opening marker;
/// `</think>` switches to the visible answer. A `<think>` appearing in the
/// visible channel (the model thinking despite a closed primer, or thinking
/// again late) switches back — and resets a prematurely surfaced answer,
/// mirroring the Gemma parser's contract. Markers split across engine
/// callbacks are held back until they resolve.
final class Qwen35StreamParser {
  Qwen35StreamParser({required bool reasoningEnabled})
    : _inReasoning = reasoningEnabled;

  static const _markers = [
    Qwen35ChatTemplate.thinkStart,
    Qwen35ChatTemplate.thinkEnd,
  ];

  bool _inReasoning;
  bool _sawAnswer = false;
  bool _trimAnswerLead = false;
  String _pending = '';

  ReasoningStreamDelta consume(String text) {
    _pending += text;
    final reasoning = StringBuffer();
    final answer = StringBuffer();
    var resetAnswer = false;

    void emitAnswer(String piece) {
      var visible = piece;
      if (_trimAnswerLead) {
        visible = visible.replaceFirst(RegExp(r'^\s+'), '');
        if (visible.isEmpty) return;
        _trimAnswerLead = false;
      }
      if (visible.isEmpty) return;
      answer.write(visible);
      _sawAnswer = true;
    }

    var remaining = _pending;
    while (true) {
      if (_inReasoning) {
        final end = remaining.indexOf(Qwen35ChatTemplate.thinkEnd);
        if (end < 0) break;
        reasoning.write(remaining.substring(0, end));
        remaining = remaining.substring(
          end + Qwen35ChatTemplate.thinkEnd.length,
        );
        _inReasoning = false;
        // The template emits '\n\n' between the think close and the answer.
        _trimAnswerLead = true;
      } else {
        final start = remaining.indexOf(Qwen35ChatTemplate.thinkStart);
        final end = remaining.indexOf(Qwen35ChatTemplate.thinkEnd);
        if (start < 0 && end < 0) break;
        if (end >= 0 && (start < 0 || end < start)) {
          // A stray close without an open: drop the marker, stay visible.
          emitAnswer(remaining.substring(0, end));
          remaining = remaining.substring(
            end + Qwen35ChatTemplate.thinkEnd.length,
          );
        } else {
          emitAnswer(remaining.substring(0, start));
          remaining = remaining.substring(
            start + Qwen35ChatTemplate.thinkStart.length,
          );
          _inReasoning = true;
          if (_sawAnswer) {
            resetAnswer = true;
            answer.clear();
            _sawAnswer = false;
          }
        }
      }
    }

    final hold = _possibleMarkerPrefixLength(remaining);
    final emit = remaining.substring(0, remaining.length - hold);
    if (_inReasoning) {
      reasoning.write(emit);
    } else {
      emitAnswer(emit);
    }
    _pending = remaining.substring(remaining.length - hold);

    return ReasoningStreamDelta(
      reasoning: reasoning.toString(),
      answer: answer.toString(),
      resetAnswer: resetAnswer,
    );
  }

  ReasoningStreamDelta finish() {
    final held = _pending;
    _pending = '';
    if (held.isEmpty) return const ReasoningStreamDelta();
    if (_inReasoning) return ReasoningStreamDelta(reasoning: held);
    if (_trimAnswerLead) {
      final visible = held.replaceFirst(RegExp(r'^\s+'), '');
      if (visible.isEmpty) return const ReasoningStreamDelta();
      _trimAnswerLead = false;
      return ReasoningStreamDelta(answer: visible);
    }
    return ReasoningStreamDelta(answer: held);
  }

  /// The length of the longest suffix of [text] that could still grow into
  /// one of the markers; that tail is held back until the next callback.
  static int _possibleMarkerPrefixLength(String text) {
    var longest = 0;
    for (final marker in _markers) {
      final max = marker.length - 1;
      for (var length = max.clamp(0, text.length); length > longest; length--) {
        if (text.endsWith(marker.substring(0, length))) {
          longest = length;
          break;
        }
      }
    }
    return longest;
  }
}
