import 'dart:convert';

/// FNV-1a over the UTF-8 bytes, 64-bit, hex — dependency-free and stable
/// across platforms; equality is all the probe needs. Rendered as two
/// 32-bit halves because Dart's signed ints would otherwise print a
/// leading minus for hashes with the top bit set.
String fnv1a64(String text) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    hash = hash * 0x100000001b3;
  }
  final high = (hash >>> 32).toRadixString(16).padLeft(8, '0');
  final low = (hash & 0xffffffff).toRadixString(16).padLeft(8, '0');
  return '$high$low';
}
