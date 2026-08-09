import '../core/domain/model_profile_spec.dart';
import '../core/domain/models.dart';
import 'history_strip.dart' as history;

/// The built-in Gemma 4 template description. The literal markers below stay
/// as named constants because tests, the parity fixture, and
/// `docs/architecture/inferno.md` all cite them by name.
const gemma4TemplateSpec = ChatTemplateSpec(
  strategy: ChatTemplateStrategy.gemmaTurns,
  bos: Gemma4ChatTemplate.bos,
  turnOpen: Gemma4ChatTemplate.turnStart,
  turnClose: Gemma4ChatTemplate.turnEnd,
  systemRole: 'system',
  userRole: 'user',
  assistantRole: 'model',
  thoughtControl: Gemma4ChatTemplate.thoughtControl,
  channelStart: ReasoningStreamParser.channelStart,
  channelEnd: ReasoningStreamParser.channelEnd,
  historyStrip: HistoryStripMode.reasoningChannels,
  // libmtmd's default media marker; the native suite asserts it matches
  // `mtmd_default_marker()` so the two can never drift apart.
  mediaMarker: '<__media__>',
);

/// Gemma 4 text-chat rendering derived from the pinned model template.
///
/// The broker emits BOS exactly once. Both engines must tokenize this with
/// add-BOS disabled; see `docs/architecture/inferno.md`.
///
/// Every entry point takes a [ChatTemplateSpec] so a supported custom
/// repository can reuse this proven algorithm with its own markers and role
/// names (#43). The default is the built-in Gemma spec, so existing callers
/// and the recorded fixtures render byte for byte as before.
abstract final class Gemma4ChatTemplate {
  static const bos = '<bos>';
  static const turnStart = '<|turn>';
  static const turnEnd = '<turn|>';
  static const thoughtControl = '<|think|>';
  static const eosTokenId = 1;
  static const turnEndTokenId = 106;

  static String render(
    List<PromptMessage> messages, {
    required bool reasoningEnabled,
    ChatTemplateSpec spec = gemma4TemplateSpec,
  }) {
    if (messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'must not be empty');
    }
    final output = StringBuffer(spec.bos ?? '');
    var start = 0;
    final firstRole = messages.first.role;
    final hasSystem = firstRole == 'system' || firstRole == 'developer';
    if (reasoningEnabled || hasSystem) {
      output.write('${spec.turnOpen}${spec.systemRole}\n');
      if (reasoningEnabled && spec.thoughtControl != null) {
        output.write('${spec.thoughtControl}\n');
      }
      if (hasSystem) {
        output.write(_renderParts(messages.first, spec, isAssistant: false));
        start = 1;
      }
      output.write('${spec.turnClose}\n');
    }

    for (final message in messages.skip(start)) {
      final isAssistant = switch (message.role) {
        'user' => false,
        'assistant' => true,
        final unsupported => throw ArgumentError.value(
          unsupported,
          'role',
          'must be user or assistant after the optional leading system turn',
        ),
      };
      // Model turns lose their reasoning before sanitizing, so the markers are
      // still present to delimit what gets removed.
      output
        ..write(
          '${spec.turnOpen}${isAssistant ? spec.assistantRole : spec.userRole}\n',
        )
        ..write(_renderParts(message, spec, isAssistant: isAssistant))
        ..write('${spec.turnClose}\n');
    }
    output.write('${spec.turnOpen}${spec.assistantRole}\n');
    return output.toString();
  }

  /// Pasted content must not be able to close the current turn or open a new
  /// one, so every control marker is stripped before rendering. Stripping
  /// runs to a fixpoint: removing an inner marker can splice its neighbours
  /// into a live one (`<|turn<turn|>>` → `<|turn>`), so one pass is not
  /// enough.
  static String sanitize(
    String text, [
    ChatTemplateSpec spec = gemma4TemplateSpec,
  ]) {
    final markers = spec.controlMarkers;
    var cleaned = text;
    String previous;
    do {
      previous = cleaned;
      for (final marker in markers) {
        cleaned = cleaned.replaceAll(marker, '');
      }
    } while (cleaned != previous);
    return cleaned;
  }

  /// Renders a turn's ordered parts: text is trimmed, history-stripped for
  /// assistant turns, then sanitized; each image becomes one media marker at
  /// the position it occupies. A marker is followed by a newline so the
  /// question after a picture does not run into it.
  static String _renderParts(
    PromptMessage message,
    ChatTemplateSpec spec, {
    required bool isAssistant,
  }) {
    final buffer = StringBuffer();
    for (final part in message.parts) {
      switch (part) {
        case TextPart():
          final trimmed = part.text.trim();
          buffer.write(
            sanitize(
              isAssistant
                  ? history.stripHistoryReasoning(trimmed, spec)
                  : trimmed,
              spec,
            ),
          );
        case ImagePart():
          // A template with no proven image path renders nothing rather than
          // inventing a marker the engine would not understand.
          if (spec.mediaMarker != null) buffer.write('${spec.mediaMarker}\n');
      }
    }
    return buffer.toString();
  }

  static String stripReasoningChannels(
    String text, [
    ChatTemplateSpec spec = gemma4TemplateSpec,
  ]) => history.stripReasoningChannels(text, spec);
}

final class ReasoningStreamDelta {
  const ReasoningStreamDelta({
    this.reasoning = '',
    this.answer = '',
    this.resetAnswer = false,
  });

  final String reasoning;
  final String answer;
  final bool resetAnswer;
}

enum _Channel { visible, reasoning, label }

/// Parses markers even when a native engine splits them across callbacks.
final class ReasoningStreamParser {
  ReasoningStreamParser({
    this.openMarker = channelStart,
    this.closeMarker = channelEnd,
  });

  static const channelStart = '<|channel>';
  static const channelEnd = '<channel|>';

  /// The channel delimiters this instance parses. Defaulted to the pinned
  /// Gemma markers; a supported custom profile supplies its own.
  final String openMarker;
  final String closeMarker;

  _Channel _channel = _Channel.visible;
  String _pending = '';
  bool _hasVisibleAnswer = false;

  ReasoningStreamDelta consume(String text) {
    if (text.isEmpty) return const ReasoningStreamDelta();
    _pending += text;
    return _drain(isFinal: false);
  }

  ReasoningStreamDelta finish() => _drain(isFinal: true);

  ReasoningStreamDelta _drain({required bool isFinal}) {
    final reasoning = StringBuffer();
    final answer = StringBuffer();
    var resetAnswer = false;
    while (_pending.isNotEmpty) {
      if (_channel == _Channel.label) {
        final newline = _pending.indexOf('\n');
        if (newline < 0) {
          if (isFinal) {
            reasoning.write(_pending);
            _pending = '';
          }
          break;
        }
        final label = _pending.substring(0, newline).trim().toLowerCase();
        _pending = _pending.substring(newline + 1);
        if (label == 'final' || label == 'answer') {
          _channel = _Channel.visible;
        } else {
          _channel = _Channel.reasoning;
          if (_hasVisibleAnswer) {
            resetAnswer = true;
            _hasVisibleAnswer = false;
          }
        }
        continue;
      }

      final start = _pending.indexOf(openMarker);
      final end = _pending.indexOf(closeMarker);
      final markerIndex = switch ((start, end)) {
        (-1, -1) => -1,
        (final value, -1) => value,
        (-1, final value) => value,
        (final left, final right) => left < right ? left : right,
      };
      if (markerIndex < 0) {
        final hold = isFinal ? 0 : _possibleMarkerPrefixLength();
        final emitLength = _pending.length - hold;
        _emit(
          _pending.substring(0, emitLength),
          reasoning: reasoning,
          answer: answer,
        );
        _pending = _pending.substring(emitLength);
        break;
      }

      _emit(
        _pending.substring(0, markerIndex),
        reasoning: reasoning,
        answer: answer,
      );
      final opensLabel = start == markerIndex;
      final marker = opensLabel ? openMarker : closeMarker;
      _pending = _pending.substring(markerIndex + marker.length);
      _channel = opensLabel ? _Channel.label : _Channel.visible;
    }
    return ReasoningStreamDelta(
      reasoning: reasoning.toString(),
      answer: answer.toString(),
      resetAnswer: resetAnswer,
    );
  }

  int _possibleMarkerPrefixLength() {
    final longest = openMarker.length > closeMarker.length
        ? openMarker.length
        : closeMarker.length;
    final maximum = _pending.length < longest ? _pending.length : longest - 1;
    for (var length = maximum; length > 0; length--) {
      final suffix = _pending.substring(_pending.length - length);
      if (openMarker.startsWith(suffix) || closeMarker.startsWith(suffix)) {
        return length;
      }
    }
    return 0;
  }

  void _emit(
    String text, {
    required StringBuffer reasoning,
    required StringBuffer answer,
  }) {
    if (text.isEmpty) return;
    switch (_channel) {
      case _Channel.visible:
        _hasVisibleAnswer = true;
        answer.write(text);
      case _Channel.reasoning:
        reasoning.write(text);
      case _Channel.label:
        throw StateError('Channel labels are consumed before text emission.');
    }
  }
}
