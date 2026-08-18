import 'package:flutter/cupertino.dart';

import 'golem_tappable.dart';

/// A glyph with a real hit box.
///
/// The visual may stay as small as the handoff draws it; the target around it
/// is always the platform minimum. Composed on [GolemTappable] so there is one
/// statement of that rule in the app.
class GolemIconButton extends StatelessWidget {
  const GolemIconButton({
    required this.icon,
    required this.onPressed,
    this.semanticLabel,
    this.size = 22,
    this.color,
    this.background,
    this.borderRadius,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// The glyph itself, for the common case.
  final IconData icon;
  final VoidCallback? onPressed;

  /// What the glyph is, for a screen reader. Null where an ancestor already
  /// labels the control.
  final String? semanticLabel;

  final double size;
  final Color? color;

  /// A filled chip behind the glyph, where the design calls for one.
  final Color? background;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => GolemTappable(
    padding: padding,
    color: background,
    borderRadius: borderRadius,
    onPressed: onPressed,
    child: Icon(icon, size: size, color: color, semanticLabel: semanticLabel),
  );
}
