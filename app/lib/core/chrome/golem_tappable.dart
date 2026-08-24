import 'package:flutter/cupertino.dart';

import 'golem_chrome.dart';

/// The shape a tap target takes when its child is not a label or an icon: a
/// row, a card, a chip.
///
/// It exists to own one rule. Every interactive surface owes the platform
/// minimum — 44 on cupertino, 48 on android — and that minimum was written by
/// hand at three dozen call sites, where it was twice written as a number
/// instead (#118, #131). Nothing else here is new: every parameter is passed
/// straight through, so a site that moves onto it does not move a pixel.
class GolemTappable extends StatelessWidget {
  const GolemTappable({
    required this.child,
    required this.onPressed,
    this.padding,
    this.color,
    this.borderRadius,
    this.alignment = Alignment.center,
    this.shape = GolemTapShape.square,
    this.minimumHeight,
    super.key,
  }) : assert(
         minimumHeight == null || shape == GolemTapShape.wide,
         'a row height only means something on a target that owns its width; '
         'a square one is sized by its content',
       );

  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BorderRadius? borderRadius;
  final AlignmentGeometry alignment;

  /// Whether the minimum covers both axes or only the height.
  final GolemTapShape shape;

  /// A deliberate row height *above* the platform minimum — a settings row, a
  /// conversation row. Null takes the minimum itself.
  final double? minimumHeight;

  @override
  Widget build(BuildContext context) {
    final minimum = GolemChrome.current.minimumTapTarget;
    return CupertinoButton(
      padding: padding,
      color: color,
      borderRadius: borderRadius,
      alignment: alignment,
      minimumSize: switch (shape) {
        GolemTapShape.square => Size.square(minimum),
        GolemTapShape.wide => Size.fromHeight(minimumHeight ?? minimum),
      },
      onPressed: onPressed,
      child: child,
    );
  }
}

/// Whether a target claims its minimum on both axes or only vertically.
enum GolemTapShape {
  /// An inline action, sized by its own content but never below the minimum
  /// in either direction.
  square,

  /// A row or a full-width action, which owns its width already.
  wide,
}
