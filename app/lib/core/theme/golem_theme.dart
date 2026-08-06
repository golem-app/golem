import 'package:flutter/cupertino.dart';

export '../widgets/glass.dart';
export '../widgets/golem_card.dart';
export 'golem_effects.dart';
export 'golem_geometry.dart';
export 'golem_typography.dart';

/// Golem Navy color tokens (design handoff `tokens/colors.css`).
abstract final class GolemTheme {
  static const canvas = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF2F1F0),
    darkColor: Color(0xFF101930),
  );
  static const surface = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF14223E),
  );
  static const surfaceRaised = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF1D2C4C),
  );
  static const field = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF2F1F0),
    darkColor: Color(0xFF1B2744),
  );
  static const ink = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF242C3C),
    darkColor: Color(0xFFF2F4F8),
  );
  static const mutedInk = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF606877),
    darkColor: Color(0xFF9BA2AF),
  );
  // Large or decorative text only: 3.4:1 on dark cards.
  static const tertiaryInk = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF858B95),
    darkColor: Color(0xFF6B7688),
  );
  static const divider = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFE7E6E4),
    darkColor: Color(0xFF1B2744),
  );
  static const borderStrong = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFD9D8D5),
    darkColor: Color(0xFF2C3A58),
  );
  static const accent = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF1763EE),
    darkColor: Color(0xFF5B94FF),
  );
  static const accentIcon = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF0A5BED),
    darkColor: Color(0xFF5B94FF),
  );
  static const accentSoft = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFEDF1FD),
    darkColor: Color(0x245B94FF),
  );
  static const segmentTrack = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFECECEE),
    darkColor: Color(0x14FFFFFF),
  );
  static const fillQuiet = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFE9E9E7),
    darkColor: Color(0x1AFFFFFF),
  );
  static const assistantBubble = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF14223E),
  );
  static const reasoningSurface = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFCF3DE),
    darkColor: Color(0xFF2C2415),
  );
  static const reasoningBorder = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFEEDCAA),
    darkColor: Color(0xFF4A3B18),
  );
  static const userBubble = Color(0xFF152549);
  static const drawer = Color(0xFF152549);
  static const splash = Color(0xFF0F1524);
  static const amber = Color(0xFFF6AA1B);
  static const destructive = Color(0xFFFF382C);
  // Fixed colors for the always-dark drawer and splash surfaces.
  static const textOnDark = Color(0xFFF7F8FA);
  static const mutedOnDark = Color(0xFFAAB4C9);
  static const faintOnDark = Color(0xFF8FA0C0);
  static const iconOnDark = Color(0xFFCDD0D5);
  static const scrim = Color(0x66000000);
  static const drawerShadow = Color(0x59000000);
  static const splashGlow = Color(0x591D63ED);
  static const errorSurface = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFEDF0),
    darkColor: Color(0xFF33161C),
  );
  static const errorIcon = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFF382C),
    darkColor: Color(0xFFFF5A4E),
  );
  // canvas at 84% opacity, kept dynamic: calling withValues() on a
  // CupertinoDynamicColor would collapse it to its light variant and turn
  // the scrolled-under navigation bar white in dark mode.
  static const barBackground = CupertinoDynamicColor.withBrightness(
    color: Color(0xD6F2F1F0),
    darkColor: Color(0xD6101930),
  );

  static CupertinoThemeData theme(Brightness brightness) => CupertinoThemeData(
    brightness: brightness,
    primaryColor: accent,
    scaffoldBackgroundColor: canvas,
    barBackgroundColor: barBackground,
    textTheme: const CupertinoTextThemeData(
      textStyle: TextStyle(
        inherit: false,
        fontFamily: '.SF Pro Text',
        fontSize: 17,
        color: ink,
      ),
      navTitleTextStyle: TextStyle(
        inherit: false,
        fontFamily: '.SF Pro Display',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
  );
}
