import 'package:flutter/cupertino.dart';

import 'golem_chrome.dart';

class GolemMenuItem {
  const GolemMenuItem({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isDestructive = false,
    this.itemKey,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isDestructive;

  /// Automation key for the rendered menu row.
  final Key? itemKey;
}

/// The adaptive overflow menu. Both chromes anchor a [CupertinoMenuAnchor]
/// (automation walks that widget type by key); the chrome decides the
/// trigger glyph — `···` on cupertino, `⋮` on Android.
class GolemMenu extends StatelessWidget {
  const GolemMenu({
    required this.items,
    required this.triggerSemanticLabel,
    this.anchorKey,
    this.enabled = true,
    this.triggerColor,
    super.key,
  });

  final List<GolemMenuItem> items;
  final String triggerSemanticLabel;
  final Key? anchorKey;
  final bool enabled;
  final Color? triggerColor;

  @override
  Widget build(BuildContext context) => CupertinoMenuAnchor(
    key: anchorKey,
    menuChildren: [
      for (final item in items)
        CupertinoMenuItem(
          key: item.itemKey,
          leading: item.icon == null ? null : Icon(item.icon),
          isDestructiveAction: item.isDestructive,
          onPressed: item.onPressed,
          child: Text(item.label),
        ),
    ],
    builder: (context, controller, child) => CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.square(GolemChrome.current.minimumTapTarget),
      onPressed: !enabled
          ? null
          : () => controller.isOpen ? controller.close() : controller.open(),
      child: Icon(
        GolemChrome.current == GolemChrome.android
            ? CupertinoIcons.ellipsis_vertical
            : CupertinoIcons.ellipsis,
        semanticLabel: triggerSemanticLabel,
        color: triggerColor,
        size: 20,
      ),
    ),
  );
}
