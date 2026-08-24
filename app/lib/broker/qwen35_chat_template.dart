// ReasoningStreamDelta is the broker-wide currency, so it stays with the first
// parser that produced it — hence the cross-template import.
import '../core/domain/model_profile_spec.dart';
import '../core/domain/models.dart';
import 'gemma4_chat_template.dart' show ReasoningStreamDelta;
import 'history_strip.dart' as history;

const qwen35TemplateSpec = ChatTemplateSpec(
  strategy: ChatTemplateStrategy.chatMl,
  turnOpen: Qwen35ChatTemplate.imStart,
  turnClose: Qwen35ChatTemplate.imEnd,
  systemRole: 'system',
  userRole: 'user',
  assistantRole: 'assistant',
  thinkStart: Qwen35ChatTemplate.thinkStart,
  thinkEnd: Qwen35ChatTemplate.thinkEnd,
  reasoningPrimer: '${Qwen35ChatTemplate.thinkStart}\n',
  directPrimer:
      '${Qwen35ChatTemplate.thinkStart}\n\n${Qwen35ChatTemplate.thinkEnd}\n\n',
  mediaMarker: '<__media__>',
  historyStrip: HistoryStripMode.thinkBlocks,
);

/// The pinned Qwen 3.5 `chat_template.jinja` subset: ChatML turns with no BOS
/// anywhere, an optional leading system turn, and a primer that opens a
/// `<think>` block when reasoning is on or closes an empty one when it is not —
/// so output begins inside the block and `</think>` is the channel boundary.
/// Entry points take a [ChatTemplateSpec] for custom repositories (#43).
final class Qwen35ChatTemplate {
  static const imStart = '<|im_start|>';
  static const imEnd = '<|im_end|>';
  static const thinkStart = '<think>';
  static const thinkEnd = '</think>';
  static const imEndTokenId = 248046;
  static const endOfTextTokenId = 248044;

  static String render(
    List<PromptMessage> messages, {
    required bool reasoningEnabled,
    ChatTemplateSpec spec = qwen35TemplateSpec,
  }) {
    if (messages.isEmpty) {
      throw ArgumentError('messages must not be empty.');
    }
    final buffer = StringBuffer(spec.bos ?? '');
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      switch (message.role) {
        case 'system' || 'developer':
          if (i != 0) {
            throw ArgumentError('A system message must come first.');
          }
          buffer.write(
            '${spec.turnOpen}${spec.systemRole}\n'
            '${_renderParts(message, spec, isAssistant: false)}'
            '${spec.turnClose}\n',
          );
        case 'user':
          buffer.write(
            '${spec.turnOpen}${spec.userRole}\n'
            '${_renderParts(message, spec, isAssistant: false)}'
            '${spec.turnClose}\n',
          );
        case 'assistant':
          // Upstream strips reasoning from every assistant turn at or before
          // the latest user query, and history always precedes it.
          buffer.write(
            '${spec.turnOpen}${spec.assistantRole}\n'
            '${_renderParts(message, spec, isAssistant: true)}'
            '${spec.turnClose}\n',
          );
        default:
          throw ArgumentError('Unsupported role: ${message.role}');
      }
    }
    buffer.write('${spec.turnOpen}${spec.assistantRole}\n');
    final primer = reasoningEnabled ? spec.reasoningPrimer : spec.directPrimer;
    if (primer != null) buffer.write(primer);
    return buffer.toString();
  }

  /// ChatML sanitizes before trimming — the opposite order to the Gemma
  /// strategy, and preserved exactly.
  static String _renderParts(
    PromptMessage message,
    ChatTemplateSpec spec, {
    required bool isAssistant,
  }) {
    final buffer = StringBuffer();
    for (final part in message.parts) {
      switch (part) {
        case TextPart():
          final text = isAssistant
              ? history.stripHistoryReasoning(part.text, spec)
              : part.text;
          buffer.write(sanitize(text, spec).trim());
        case ImagePart():
          if (spec.mediaMarker != null) buffer.write('${spec.mediaMarker}\n');
      }
    }
    return buffer.toString();
  }

  /// Removes every control marker, to a fixpoint so removals cannot splice
  /// two fragments into a live marker.
  static String sanitize(
    String text, [
    ChatTemplateSpec spec = qwen35TemplateSpec,
  ]) {
    final markers = spec.controlMarkers;
    var current = text;
    while (true) {
      var next = current;
      for (final marker in markers) {
        next = next.replaceAll(marker, '');
      }
      if (next == current) return current;
      current = next;
    }
  }

  /// Complete spans only; stray unmatched markers are left for [sanitize].
  static String stripThinkBlocks(
    String text, [
    ChatTemplateSpec spec = qwen35TemplateSpec,
  ]) => history.stripThinkBlocks(text, spec);
}

/// With reasoning enabled the primer already opened a `<think>` block, so the
/// stream starts in the reasoning channel with no opening marker. A `<think>` in
/// the visible channel — thinking despite a closed primer, or thinking again
/// late — switches back and resets a prematurely surfaced answer.
final class Qwen35StreamParser {
  Qwen35StreamParser({
    required bool reasoningEnabled,
    this.openMarker = Qwen35ChatTemplate.thinkStart,
    this.closeMarker = Qwen35ChatTemplate.thinkEnd,
  }) : _inReasoning = reasoningEnabled;

  final String openMarker;
  final String closeMarker;

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
        final end = remaining.indexOf(closeMarker);
        if (end < 0) break;
        reasoning.write(remaining.substring(0, end));
        remaining = remaining.substring(end + closeMarker.length);
        _inReasoning = false;
        // The template emits '\n\n' between the think close and the answer.
        _trimAnswerLead = true;
      } else {
        final start = remaining.indexOf(openMarker);
        final end = remaining.indexOf(closeMarker);
        if (start < 0 && end < 0) break;
        if (end >= 0 && (start < 0 || end < start)) {
          // A stray close without an open: drop the marker, stay visible.
          emitAnswer(remaining.substring(0, end));
          remaining = remaining.substring(end + closeMarker.length);
        } else {
          emitAnswer(remaining.substring(0, start));
          remaining = remaining.substring(start + openMarker.length);
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

  /// The longest suffix that could still grow into a marker; that tail is held
  /// back until the next engine callback.
  int _possibleMarkerPrefixLength(String text) {
    var longest = 0;
    for (final marker in [openMarker, closeMarker]) {
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
