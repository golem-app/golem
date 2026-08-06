import 'dart:ui';

import 'package:flutter/cupertino.dart';

import '../theme/golem_theme.dart';

class Glass extends StatelessWidget {
  const Glass({required this.child, this.radius = 22, super.key});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
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
