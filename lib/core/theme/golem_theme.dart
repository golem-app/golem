import 'dart:ui';

import 'package:flutter/cupertino.dart';

abstract final class GolemTheme {
  static const canvas = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF2F1EF),
    darkColor: Color(0xFF0F1524),
  );
  static const surface = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF171F33),
  );
  static const ink = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF2A3140),
    darkColor: Color(0xFFF2F3F5),
  );
  static const mutedInk = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF646C79),
    darkColor: Color(0xFF9CA3AF),
  );
  static const divider = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFE8E7E3),
    darkColor: Color(0xFF26314F),
  );
  static const accent = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF1D63ED),
    darkColor: Color(0xFF5B93FF),
  );
  static const accentSoft = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFEBF1FE),
    darkColor: Color(0xFF1B2740),
  );
  static const assistantBubble = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF161E31),
  );
  static const reasoningSurface = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFCF3DD),
    darkColor: Color(0xFF262012),
  );
  static const reasoningBorder = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFEDD9A4),
    darkColor: Color(0xFF5C4B1E),
  );
  static const userBubble = Color(0xFF1C2A4A);
  static const drawer = Color(0xFF1C2A4A);
  static const splash = Color(0xFF0F1524);
  static const amber = Color(0xFFF6A821);
  static const destructive = Color(0xFFFF3B30);
  // Fixed colors for the always-dark drawer and splash surfaces.
  static const mutedOnDark = Color(0xFFAAB4C9);
  static const faintOnDark = Color(0xFF8FA0C0);
  static const iconOnDark = Color(0xFFCDD0D5);
  static const scrim = Color(0x66000000);
  static const drawerShadow = Color(0x59000000);
  static const splashGlow = Color(0x591D63ED);
  static const errorSurface = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFECEF),
    darkColor: Color(0xFF3A2126),
  );
  // canvas at 84% opacity, kept dynamic: calling withValues() on a
  // CupertinoDynamicColor would collapse it to its light variant and turn
  // the scrolled-under navigation bar white in dark mode.
  static const barBackground = CupertinoDynamicColor.withBrightness(
    color: Color(0xD6F2F1EF),
    darkColor: Color(0xD60F1524),
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

class Glass extends StatelessWidget {
  const Glass({required this.child, this.radius = 22, super.key});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
            GolemTheme.surface,
            context,
          ).withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: CupertinoDynamicColor.resolve(GolemTheme.divider, context),
          ),
        ),
        child: child,
      ),
    ),
  );
}

class GolemCard extends StatelessWidget {
  const GolemCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(GolemTheme.surface, context),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: CupertinoDynamicColor.resolve(GolemTheme.divider, context),
      ),
    ),
    child: child,
  );
}
