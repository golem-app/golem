import 'package:flutter/cupertino.dart';

/// The Golem Navy type ramp. Styles are partial (they merge over the
/// ambient `DefaultTextStyle`, which carries the ink color from the
/// theme) so call sites keep resolving color exactly as before.
abstract final class GolemText {
  static const _display = '.SF Pro Display';

  /// Splash wordmark.
  static const hero = TextStyle(
    fontFamily: _display,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.6,
  );

  /// Empty-state headline, settings section headers.
  static const display = TextStyle(
    fontFamily: _display,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.5,
  );

  /// Navigation bar title.
  static const title = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Model card name.
  static const cardTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  /// Message bubbles, rows, buttons.
  static const body = TextStyle(fontSize: 17, height: 1.45);
  static const bodyStrong = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  /// Helper copy, reasoning body, banners.
  static const footnote = TextStyle(fontSize: 15, height: 1.4);

  /// The "Reasoning" label.
  static const footnoteStrong = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.4,
  );

  static const caption = TextStyle(fontSize: 13, height: 1.35);
  static const captionStrong = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  /// Metrics chip: "21.4 tok/s · 27 tokens".
  static const metrics = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Tiny badges ("ACTIVE") — uppercase at the call site.
  static const badge = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.72,
  );

  /// Tiny section labels ("RECENT") — uppercase at the call site.
  static const overline = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.96,
  );

  static const _mono = 'Menlo';
  static const _monoFallback = ['Courier', 'monospace'];

  /// Inline code chips inside transcript markdown.
  static const code = TextStyle(
    fontFamily: _mono,
    fontFamilyFallback: _monoFallback,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Fenced code block bodies. The card tracks the appearance, so any
  /// color paired with this style needs a light and a dark value.
  static const codeBlock = TextStyle(
    fontFamily: _mono,
    fontFamilyFallback: _monoFallback,
    fontSize: 12.5,
    height: 1.65,
  );

  /// The code card's uppercase language label.
  static const codeLanguage = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1,
    letterSpacing: 0.99,
  );
}
