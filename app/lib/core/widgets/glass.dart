import 'dart:ui';

import 'package:flutter/cupertino.dart';

import '../theme/golem_theme.dart';

class Glass extends StatelessWidget {
  const Glass({
    required this.child,
    this.radius = 22,
    this.floating = false,
    super.key,
  });
  final Widget child;
  final double radius;

  /// Floating surfaces (nav buttons, the composer, jump-to-latest) carry
  /// the float shadow outside the blur clip.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final core = _clipped(context);
    if (!floating) return core;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: GolemShadow.float(context),
      ),
      child: core,
    );
  }

  Widget _clipped(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
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
