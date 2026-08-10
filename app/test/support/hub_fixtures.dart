import 'dart:convert';
import 'dart:typed_data';

import 'package:golem_flutter/core/services/hugging_face_api.dart';

/// A scripted [HuggingFaceApi]: no sockets, so every resolution rule is
/// testable offline and the resolver never needs a recorded cassette.
///
/// Responses are keyed by full URL. A [HubException] value is thrown instead of
/// returned, which is how transport failures reach the resolver.
final class ScriptedHuggingFaceApi implements HuggingFaceApi {
  ScriptedHuggingFaceApi([Map<String, Object>? responses])
    : responses = responses ?? {};

  /// URL → `Map` (json), `String` (text), `Uint8List` (bytes), or
  /// `HubException` (thrown).
  final Map<String, Object> responses;

  /// Every URL asked for, in order, so a test can prove what was *not* fetched.
  final List<String> requested = [];

  Object _lookup(Uri url) {
    requested.add(url.toString());
    final response = responses[url.toString()];
    if (response == null) {
      // An unscripted URL is the Hub's answer for a path that is not there.
      throw const HubException(HubErrorKind.notFoundOrPrivate, status: 404);
    }
    if (response is HubException) throw response;
    return response;
  }

  @override
  Future<Map<String, Object?>> json(Uri url) async {
    final response = _lookup(url);
    if (response is Map<String, Object?>) return response;
    if (response is String) {
      return Map<String, Object?>.from(jsonDecode(response) as Map);
    }
    throw const HubException(HubErrorKind.malformed);
  }

  @override
  Future<String> text(Uri url, {int maxBytes = 4 * 1024 * 1024}) async {
    final response = _lookup(url);
    if (response is String) return response;
    if (response is Map) return jsonEncode(response);
    throw const HubException(HubErrorKind.malformed);
  }

  @override
  Future<Uint8List> range(
    Uri url, {
    required int start,
    required int endInclusive,
  }) async {
    final response = _lookup(url);
    if (response is! Uint8List) {
      throw const HubException(HubErrorKind.malformed);
    }
    final end = (endInclusive + 1).clamp(0, response.length);
    return Uint8List.sublistView(response, start.clamp(0, end), end);
  }
}

/// One entry of a `/api/models/.../revision/...?blobs=true` sibling list.
///
/// [sha256] present models an LFS-tracked file; absent models a small metadata
/// file, which the Hub publishes with a size and no hash.
Map<String, Object?> sibling(String path, int bytes, {String? sha256}) => {
  'rfilename': path,
  'size': bytes,
  if (sha256 != null)
    'lfs': {'sha256': sha256, 'size': bytes, 'pointerSize': 135},
};

/// A revision-info body in the shape the Hub actually returns.
Map<String, Object?> revisionInfo({
  required String sha,
  required List<Map<String, Object?>> siblings,
  Object gated = false,
  bool private = false,
  bool disabled = false,
}) => {
  'sha': sha,
  'gated': gated,
  'private': private,
  'disabled': disabled,
  'siblings': siblings,
};

// --------------------------------------------------------------- GGUF bytes

Uint8List _u32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

Uint8List _u64(int value) =>
    Uint8List(8)..buffer.asByteData().setUint64(0, value, Endian.little);

Uint8List _text(String value) {
  final bytes = utf8.encode(value);
  return Uint8List.fromList([..._u64(bytes.length), ...bytes]);
}

/// A valid GGUF v3 metadata block. Only what the resolver reads is populated;
/// byte-level edge cases belong to `gguf_header_test.dart`.
Uint8List ggufHeaderBytes({
  required String architecture,
  String? chatTemplate,
  String? name,
  int embeddingLength = 2048,
  int blockCount = 24,
}) {
  final pairs = <Uint8List>[
    Uint8List.fromList([
      ..._text('general.architecture'),
      ..._u32(8),
      ..._text(architecture),
    ]),
    if (name != null)
      Uint8List.fromList([
        ..._text('general.name'),
        ..._u32(8),
        ..._text(name),
      ]),
    Uint8List.fromList([
      ..._text('$architecture.embedding_length'),
      ..._u32(4),
      ..._u32(embeddingLength),
    ]),
    Uint8List.fromList([
      ..._text('$architecture.block_count'),
      ..._u32(4),
      ..._u32(blockCount),
    ]),
    if (chatTemplate != null)
      Uint8List.fromList([
        ..._text('tokenizer.chat_template'),
        ..._u32(8),
        ..._text(chatTemplate),
      ]),
  ];
  return Uint8List.fromList([
    0x47, 0x47, 0x55, 0x46, // GGUF
    ..._u32(3),
    ..._u64(0),
    ..._u64(pairs.length),
    for (final pair in pairs) ...pair,
  ]);
}
