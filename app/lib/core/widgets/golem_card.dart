import 'package:flutter/cupertino.dart';

import '../theme/golem_theme.dart';

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
      borderRadius: BorderRadius.circular(GolemRadius.card),
      border: Border.all(
        color: CupertinoDynamicColor.resolve(GolemTheme.divider, context),
      ),
      boxShadow: GolemShadow.card(context),
    ),
    child: child,
  );
}
