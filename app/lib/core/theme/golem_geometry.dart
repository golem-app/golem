/// Radii measured off the design handoff (pt).
abstract final class GolemRadius {
  static const double bubble = 18;
  static const double bubbleAssistant = 16;
  static const double bubbleTail = 6;
  static const double card = 16;
  static const double button = 14;
  static const double field = 12;
  static const double notice = 12;
  static const double segment = 10;
  static const double badge = 8;
  static const double pill = 999;

  /// The conversation drawer's free edge; its hinged edge stays square.
  static const double drawer = 28;
}

/// The 4pt spacing scale plus the shared screen gutter.
abstract final class GolemSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double gutter = 16;
}

/// Control sizes shared across surfaces. The interactive minimum is
/// deliberately absent: it is platform-owned and lives on
/// `GolemChrome.minimumTapTarget` (44 on cupertino, 48 on android). A blind
/// 44 token here is what put the shared chrome 4dp under the Android floor
/// (#118).
abstract final class GolemSize {
  static const double iconButton = 36;
  static const double composer = 56;
  static const double send = 42;
  static const double button = 50;
  static const double segment = 36;

  /// Bubbles span at most this fraction of the transcript width…
  static const double bubbleMaxFraction = 0.88;

  /// …capped absolutely for the iPad-shaped macOS window.
  static const double bubbleMaxWidth = 640;
}
