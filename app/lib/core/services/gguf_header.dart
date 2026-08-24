/// Reads a GGUF file's metadata block from a window of leading bytes (#52), so
/// a range request answers what a repository contains without fetching
/// gigabytes of weights. Declared lengths are checked against the bytes present
/// and against a ceiling — nothing here trusts the file.
///
/// The useful keys are not adjacent: measured on `unsloth/Qwen3.5-2B-GGUF`,
/// `general.architecture` sits at byte 40 while `tokenizer.chat_template` is
/// the fortieth pair, past 10 MiB behind the token and merge arrays. So a probe
/// reports what it found *and* what it would need to continue.
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

/// Real files sit far below all three; exceeding one means this is not a GGUF.
const _maxPairs = 4096;
const _maxStringBytes = 64 * 1024 * 1024;
const _maxArrayElements = 8 * 1000 * 1000;

/// Every field is nullable because a partial read is a normal outcome.
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

  /// `general.architecture`, the key llama.cpp dispatches on.
  final String? architecture;

  final String? chatTemplate;

  /// The language projection width a multimodal projector has to match.
  final int? embeddingLength;

  final int? blockCount;

  /// `general.file_type`, raw — mapping the enum to a label is the caller's.
  final int? fileType;

  final String? name;
}

sealed class GgufProbe {
  const GgufProbe();
}

final class GgufComplete extends GgufProbe {
  const GgufComplete(this.metadata);

  final GgufMetadata metadata;
}

/// [atLeastBytes] is a *lower* bound on the window needed to get further,
/// never a promise that it will be enough.
final class GgufIncomplete extends GgufProbe {
  const GgufIncomplete({required this.atLeastBytes, required this.partial});

  final int atLeastBytes;
  final GgufMetadata partial;
}

/// [reason] is for logs and failure mapping, never for display.
final class GgufUnreadable extends GgufProbe {
  const GgufUnreadable(this.reason);

  final String reason;
}

/// v1 sized its strings with 32-bit counts; nothing this app loads ships it.
const _supportedVersions = {2, 3};

/// [window] must start at byte zero; passing more than the block needs is fine.
GgufProbe parseGgufHeader(Uint8List window) {
  final data = ByteData.sublistView(window);
  var offset = 0;

  // A lower bound on progress, not completion: a shortfall inside a
  // quarter-million-element token array names only that element's end, so
  // growing by it alone would creep. See [ggufProbeWindows].
  int? shortfall;

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

  // Set when more bytes cannot help.
  GgufUnreadable? failure;

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

  /// Advances past one value of [type], materializing only strings.
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
          // Each element carries its own length, so the only way past is to
          // walk it — which is what pushes the chat template ten mebibytes in.
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
        // Dimension keys are namespaced by the declared architecture.
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

/// Window sizes to try in order, smallest first so an unsupported architecture
/// costs one mebibyte rather than the sixteen a template read needs. A caller
/// should request `max(next window, atLeastBytes)`: the ladder guarantees
/// convergence, the bound only skips a single long value. Measured blocks:
/// 10.44 MiB for both Qwen 3.5 GGUFs, 15.05 MiB for Gemma 4 E2B QAT.
const ggufProbeWindows = [
  1024 * 1024,
  4 * 1024 * 1024,
  16 * 1024 * 1024,
  48 * 1024 * 1024,
];
