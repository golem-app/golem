import 'package:flutter/cupertino.dart';

/// Elevation, resolved per brightness: light leans on soft shadows,
/// dark drops them (navy borders carry the structure instead).
abstract final class GolemShadow {
  static bool _dark(BuildContext context) =>
      CupertinoTheme.brightnessOf(context) == Brightness.dark;

  /// Floating circular nav buttons and the composer.
  static List<BoxShadow> float(BuildContext context) => _dark(context)
      ? const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x1A101930),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
          BoxShadow(
            color: Color(0x0F101930),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ];

  /// A whisper under cards; nothing in dark (border-only elevation).
  static List<BoxShadow> card(BuildContext context) => _dark(context)
      ? const []
      : const [
          BoxShadow(
            color: Color(0x0F101930),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ];

  /// The active segment thumb.
  static List<BoxShadow> segment(BuildContext context) => _dark(context)
      ? const []
      : const [
          BoxShadow(
            color: Color(0x1F101930),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ];

  /// Bottom sheets.
  static const sheet = [
    BoxShadow(color: Color(0x38060D1F), blurRadius: 40, offset: Offset(0, -12)),
  ];

  /// Context menus and dialogs.
  static const menu = [
    BoxShadow(color: Color(0x42060D1F), blurRadius: 48, offset: Offset(0, 16)),
  ];

  /// The conversation drawer, cast sideways onto the scrimmed chat. Navy
  /// like the other overlay shadows rather than the flat black it replaced,
  /// which smeared grey over the light drawer's rounded edge.
  static const drawer = [
    BoxShadow(color: Color(0x38060D1F), blurRadius: 40, offset: Offset(12, 0)),
  ];
}

/// Motion is iOS-native: short, standard-eased, no overshoot.
abstract final class GolemMotion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const standard = Cubic(0.4, 0, 0.2, 1);
}
