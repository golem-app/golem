/// Reads a GGUF file's metadata block without downloading the weights (#52).
///
/// A GGUF puts its whole metadata key/value block at the head of the file, so
/// an HTTP range request over the first few mebibytes answers what a custom
/// repository actually contains: its architecture, its dimensions, and the chat
/// template embedded by whoever converted the weights. Downloading gigabytes
/// only to reject the model is not an acceptable alternative.
///
/// The block is not small, and the useful keys are not adjacent. Measured on
/// `unsloth/Qwen3.5-2B-GGUF`: `general.architecture` sits at byte 40, while
/// `tokenizer.chat_template` is the fortieth pair and lands past 10 MiB, behind
/// roughly ten mebibytes of token and merge arrays. So [parseGgufHeader]
/// returns what it found *and* how many bytes it would need to continue, which
/// lets a caller reject an unsupported architecture after one cheap mebibyte
/// and only widen the window for a model still worth considering.
///
/// Nothing here trusts the file: every declared length is checked against the
/// bytes actually present and against a sanity ceiling before it is used, so a
/// truncated or hostile header cannot drive a huge allocation.
library;

import 'dart:convert';
import 'dart:typed_data';

/// GGUF metadata value types, in the spec's numbering.
enum _GgufType {
  uint8(0, 1),
  int8(1, 1),
  uint16(2, 2),
  int16(3, 2),
  uint32(4, 4),
  int32(5, 4),
  float32(6, 4),
  boolean(7, 1),
  string(8, null),
  array(9, null),
  uint64(10, 8),
  int64(11, 8),
  float64(12, 8);

  const _GgufType(this.code, this.width);

  final int code;

  /// Fixed encoded width, or null for the two variable-length types.
  final int? width;

  static _GgufType? of(int code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

/// Ceilings that separate a plausible header from a corrupt or hostile one.
/// Real files sit far below all three; exceeding one means the bytes are not
/// describing a GGUF we should keep parsing.
const _maxPairs = 4096;
const _maxStringBytes = 64 * 1024 * 1024;
const _maxArrayElements = 8 * 1000 * 1000;

/// What the metadata block said, as far as it was read. Every field is nullable
/// because a partial read is a normal outcome, not a failure.
final class GgufMetadata {
  const GgufMetadata({
    this.version,
    this.tensorCount,
    this.pairCount,
    this.architecture,
    this.chatTemplate,
    this.embeddingLength,
    this.blockCount,
    this.fileType,
    this.name,
  });

  final int? version;
  final int? tensorCount;
  final int? pairCount;

  /// `general.architecture`, the key llama.cpp itself dispatches on.
  final String? architecture;

  /// `tokenizer.chat_template`, the string a profile fingerprint is taken from.
  final String? chatTemplate;

  /// `<architecture>.embedding_length` — the language projection width a
  /// multimodal projector has to match.
  final int? embeddingLength;

  /// `<architecture>.block_count`.
  final int? blockCount;

  /// `general.file_type`, the quantization enum. Kept raw: it is display
  /// metadata, and mapping it to a label is the caller's business.
  final int? fileType;

  final String? name;
}

/// The outcome of reading a window of bytes from the head of a GGUF.
sealed class GgufProbe {
  const GgufProbe();
}

/// The metadata block was read to its end; [metadata] is everything it held.
final class GgufComplete extends GgufProbe {
  const GgufComplete(this.metadata);

  final GgufMetadata metadata;
}

/// The window ended mid-block. [partial] is what was already readable — often
/// enough to reject the file — and [atLeastBytes] is a *lower* bound on the
/// window needed to get further, never a promise that it will be enough.
final class GgufIncomplete extends GgufProbe {
  const GgufIncomplete({required this.atLeastBytes, required this.partial});

  final int atLeastBytes;
  final GgufMetadata partial;
}

/// The bytes are not a GGUF header this reader will parse. [reason] is for
/// logs and typed failure mapping, never for display.
final class GgufUnreadable extends GgufProbe {
  const GgufUnreadable(this.reason);

  final String reason;
}

/// Versions whose key/value encoding this reader implements. v1 sized its
/// strings and arrays with 32-bit counts; nothing this app would load still
/// ships it.
const _supportedVersions = {2, 3};

/// Parses the metadata block at the head of [window].
///
/// [window] must start at byte zero of the file. Passing more bytes than the
/// block needs is fine and normal.
GgufProbe parseGgufHeader(Uint8List window) {
  final data = ByteData.sublistView(window);
  var offset = 0;

  // Set by the first read that runs past the window, to the exact number of
  // bytes from the start of the file that read would have needed. It is a
  // lower bound on progress, not on completion: a shortfall reached partway
  // through a quarter-million-element token array names that element's end, so
  // a caller that grew by this alone would creep. See [ggufProbeWindows].
  int? shortfall;

  /// True when [need] more bytes are not available; records the shortfall.
  bool short(int need) {
    if (offset + need <= window.length) return false;
    shortfall ??= offset + need;
    return true;
  }

  if (window.length < 24) {
    return const GgufIncomplete(atLeastBytes: 24, partial: GgufMetadata());
  }
  if (window[0] != 0x47 ||
      window[1] != 0x47 ||
      window[2] != 0x55 ||
      window[3] != 0x46) {
    return const GgufUnreadable('not a GGUF file');
  }
  offset = 4;
  final version = data.getUint32(offset, Endian.little);
  offset += 4;
  if (!_supportedVersions.contains(version)) {
    return GgufUnreadable('unsupported GGUF version $version');
  }
  final tensorCount = data.getUint64(offset, Endian.little);
  offset += 8;
  final pairCount = data.getUint64(offset, Endian.little);
  offset += 8;
  if (pairCount > _maxPairs) {
    return GgufUnreadable('implausible metadata pair count $pairCount');
  }

  String? architecture;
  String? chatTemplate;
  String? name;
  int? embeddingLength;
  int? blockCount;
  int? fileType;

  GgufMetadata snapshot() => GgufMetadata(
    version: version,
    tensorCount: tensorCount,
    pairCount: pairCount,
    architecture: architecture,
    chatTemplate: chatTemplate,
    embeddingLength: embeddingLength,
    blockCount: blockCount,
    fileType: fileType,
    name: name,
  );

  // A malformed value short-circuits here, because more bytes cannot help.
  GgufUnreadable? failure;

  /// Null when the window is short (see [shortfall]) or the value is refused
  /// (see [failure]).
  String? readString() {
    if (short(8)) return null;
    final length = data.getUint64(offset, Endian.little);
    if (length > _maxStringBytes) {
      failure = GgufUnreadable('implausible string length $length');
      return null;
    }
    offset += 8;
    if (short(length)) {
      offset -= 8;
      return null;
    }
    final bytes = Uint8List.sublistView(window, offset, offset + length);
    offset += length;
    try {
      return utf8.decode(bytes);
    } on FormatException {
      failure = const GgufUnreadable('metadata string is not valid UTF-8');
      return null;
    }
  }

  /// Advances past one value of [type], materializing only strings. Returns
  /// false when the value could not be consumed.
  bool skipValue(_GgufType type, {void Function(Object value)? capture}) {
    switch (type) {
      case _GgufType.string:
        final value = readString();
        if (value == null) return false;
        capture?.call(value);
        return true;
      case _GgufType.array:
        final start = offset;
        if (short(12)) return false;
        final elementCode = data.getUint32(offset, Endian.little);
        final element = _GgufType.of(elementCode);
        if (element == null) {
          failure = GgufUnreadable('unknown array element type $elementCode');
          return false;
        }
        if (element == _GgufType.array) {
          // Permitted by the spec, never emitted by llama.cpp. Refusing beats
          // opening an unbounded recursion on a hostile file.
          failure = const GgufUnreadable('nested metadata arrays are refused');
          return false;
        }
        final count = data.getUint64(offset + 4, Endian.little);
        if (count > _maxArrayElements) {
          failure = GgufUnreadable('implausible array length $count');
          return false;
        }
        offset += 12;
        if (element == _GgufType.string) {
          // Every element carries its own length, so the only way past a
          // string array is to walk it. This is what puts the chat template
          // ten mebibytes into a real tokenizer's header.
          for (var index = 0; index < count; index++) {
            if (readString() == null) {
              if (failure == null) offset = start;
              return false;
            }
          }
          return true;
        }
        final span = element.width! * count;
        if (short(span)) {
          offset = start;
          return false;
        }
        offset += span;
        return true;
      default:
        final width = type.width!;
        if (short(width)) return false;
        final value = switch (type) {
          _GgufType.uint8 => data.getUint8(offset),
          _GgufType.int8 => data.getInt8(offset),
          _GgufType.uint16 => data.getUint16(offset, Endian.little),
          _GgufType.int16 => data.getInt16(offset, Endian.little),
          _GgufType.uint32 => data.getUint32(offset, Endian.little),
          _GgufType.int32 => data.getInt32(offset, Endian.little),
          _GgufType.float32 => data.getFloat32(offset, Endian.little),
          _GgufType.boolean => data.getUint8(offset) != 0,
          _GgufType.uint64 => data.getUint64(offset, Endian.little),
          _GgufType.int64 => data.getInt64(offset, Endian.little),
          _GgufType.float64 => data.getFloat64(offset, Endian.little),
          _GgufType.string ||
          _GgufType.array => throw StateError('unreachable'),
        };
        offset += width;
        capture?.call(value);
        return true;
    }
  }

  GgufProbe stopped() {
    if (failure != null) return failure!;
    // Every short read records its own requirement, so a bound is always
    // available by the time this is reached.
    return GgufIncomplete(
      atLeastBytes: shortfall ?? window.length + 8,
      partial: snapshot(),
    );
  }

  for (var pair = 0; pair < pairCount; pair++) {
    final key = readString();
    if (key == null) return stopped();
    if (short(4)) return stopped();
    final typeCode = data.getUint32(offset, Endian.little);
    final type = _GgufType.of(typeCode);
    if (type == null) {
      return GgufUnreadable('unknown metadata value type $typeCode for "$key"');
    }
    offset += 4;
    Object? captured;
    if (!skipValue(type, capture: (value) => captured = value)) {
      return stopped();
    }
    final value = captured;
    switch (key) {
      case 'general.architecture':
        if (value is String) architecture = value;
      case 'general.name':
        if (value is String) name = value;
      case 'general.file_type':
        if (value is int) fileType = value;
      case 'tokenizer.chat_template':
        if (value is String) chatTemplate = value;
      default:
        // Dimension keys are namespaced by architecture, which the file
        // declares in its first pair rather than in the key itself.
        if (architecture != null && value is int) {
          if (key == '$architecture.embedding_length') {
            embeddingLength = value;
          } else if (key == '$architecture.block_count') {
            blockCount = value;
          }
        }
    }
  }
  return GgufComplete(snapshot());
}

/// Window sizes to try in order when probing a remote GGUF.
///
/// The first is deliberately tiny: `general.architecture` is the first pair, so
/// an unsupported model costs one mebibyte instead of the sixteen a template
/// read needs. The ceiling bounds a hostile or unusually large header.
///
/// A caller should request `max(next window, atLeastBytes)`. The ladder is what
/// guarantees convergence — growing by [GgufIncomplete.atLeastBytes] alone can
/// crawl one token at a time through a large array — while the reported bound
/// lets a single long value be skipped straight past.
///
/// Measured KV block sizes for the artifacts this app ships: 10.44 MiB for both
/// Qwen 3.5 GGUFs and 15.05 MiB for Gemma 4 E2B QAT. The 16 MiB step covers all
/// three; the last step exists for headers with larger vocabularies.
const ggufProbeWindows = [
  1024 * 1024,
  4 * 1024 * 1024,
  16 * 1024 * 1024,
  48 * 1024 * 1024,
];
