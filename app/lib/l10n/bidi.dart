import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Bidi;

/// Resolves user- or model-authored content independently of the app chrome.
///
/// The first strong character decides, matching the Unicode bidi paragraph
/// rule. Neutral-only content keeps the caller's explicit fallback.
TextDirection contentTextDirection(
  String text, {
  TextDirection fallback = TextDirection.ltr,
}) {
  if (Bidi.startsWithRtl(text)) return TextDirection.rtl;
  if (Bidi.startsWithLtr(text)) return TextDirection.ltr;
  return fallback;
}

/// Keeps a technical LTR value intact when it is interpolated into RTL copy.
/// This is a presentation-only wrapper and must never be persisted.
String ltrIsolate(Object value) => '\u2066$value\u2069';
