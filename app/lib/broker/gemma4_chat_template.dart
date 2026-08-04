/// Gemma 4 text-chat rendering derived from the pinned model template.
///
/// The broker emits BOS exactly once. Both engines must tokenize this with
/// add-BOS disabled; see `docs/architecture/inferno.md`.
abstract final class Gemma4ChatTemplate {
  static const bos = '<bos>';
  static const turnStart = '<|turn>';
  static const turnEnd = '<turn|>';
  static const thoughtControl = '<|think|>';
  static const eosTokenId = 1;
  static const turnEndTokenId = 106;

  static String render(
    List<Map<String, String>> messages, {
    required bool reasoningEnabled,
  }) {
    if (messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'must not be empty');
    }
    final output = StringBuffer(bos);
    var start = 0;
    final firstRole = messages.first['role'];
    final hasSystem = firstRole == 'system' || firstRole == 'developer';
    if (reasoningEnabled || hasSystem) {
      output.write(
        '$turnStart'
        'system\n',
      );
      if (reasoningEnabled) output.write('$thoughtControl\n');
      if (hasSystem) {
        output.write(sanitize(_content(messages.first)));
        start = 1;
      }
      output.write('$turnEnd\n');
    }

    for (final message in messages.skip(start)) {
      final role = switch (message['role']) {
        'user' => 'user',
        'assistant' => 'model',
        final unsupported => throw ArgumentError.value(
          unsupported,
          'role',
          'must be user or assistant after the optional leading system turn',
        ),
      };
      // Model turns lose their reasoning channels before sanitizing, so the
      // markers are still present to delimit what gets removed.
      output
        ..write('$turnStart$role\n')
        ..write(
          sanitize(
            role == 'model'
                ? stripReasoningChannels(_content(message))
                : _content(message),
          ),
        )
        ..write('$turnEnd\n');
    }
    output.write(
      '$turnStart'
      'model\n',
    );
    return output.toString();
  }

  static const _controlMarkers = [
    bos,
    turnStart,
    turnEnd,
    thoughtControl,
    ReasoningStreamParser.channelStart,
    ReasoningStreamParser.channelEnd,
  ];

  /// Pasted content must not be able to close the current turn or open a new
  /// one, so every control marker is stripped before rendering.
  static String sanitize(String text) {
    var cleaned = text;
    for (final marker in _controlMarkers) {
      cleaned = cleaned.replaceAll(marker, '');
    }
    return cleaned;
  }

  static String _content(Map<String, String> message) =>
      (message['content'] ?? '').trim();

  static String stripReasoningChannels(String text) {
    var remaining = text;
    final visible = StringBuffer();
    while (remaining.isNotEmpty) {
      final start = remaining.indexOf(ReasoningStreamParser.channelStart);
      if (start < 0) {
        visible.write(remaining);
        break;
      }
      visible.write(remaining.substring(0, start));
      final end = remaining.indexOf(
        ReasoningStreamParser.channelEnd,
        start + ReasoningStreamParser.channelStart.length,
      );
      if (end < 0) break;
      remaining = remaining.substring(
        end + ReasoningStreamParser.channelEnd.length,
      );
    }
    return visible.toString().trim();
  }
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
  static const channelStart = '<|channel>';
  static const channelEnd = '<channel|>';

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

      final start = _pending.indexOf(channelStart);
      final end = _pending.indexOf(channelEnd);
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
      final marker = opensLabel ? channelStart : channelEnd;
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
    final maximum = _pending.length < channelStart.length
        ? _pending.length
        : channelStart.length - 1;
    for (var length = maximum; length > 0; length--) {
      final suffix = _pending.substring(_pending.length - length);
      if (channelStart.startsWith(suffix) || channelEnd.startsWith(suffix)) {
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
