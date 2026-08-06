import 'package:flutter/cupertino.dart';

import '../theme/golem_theme.dart';
import 'golem_chrome.dart';

enum _GolemButtonVariant { filled, tinted }

/// The primary button: 50pt tall, filled blue or soft-blue tinted,
/// rounded on cupertino chrome and pill-shaped on Android.
class GolemButton extends StatelessWidget {
  const GolemButton.filled({
    required this.label,
    required this.onPressed,
    this.expand = true,
    super.key,
  }) : _variant = _GolemButtonVariant.filled;

  const GolemButton.tinted({
    required this.label,
    required this.onPressed,
    this.expand = true,
    super.key,
  }) : _variant = _GolemButtonVariant.tinted;

  final String label;
  final VoidCallback? onPressed;
  final bool expand;
  final _GolemButtonVariant _variant;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoDynamicColor.resolve(GolemTheme.accent, context);
    final filled = _variant == _GolemButtonVariant.filled;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        height: GolemSize.button,
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: GolemSpace.s6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled
              ? accent
              : CupertinoDynamicColor.resolve(GolemTheme.accentSoft, context),
          borderRadius: BorderRadius.circular(
            GolemChrome.current == GolemChrome.android
                ? GolemRadius.pill
                : GolemRadius.button,
          ),
        ),
        child: Text(
          label,
          style: GolemText.bodyStrong.copyWith(
            color: filled ? GolemTheme.textOnDark : accent,
          ),
        ),
      ),
    );
  }
}
