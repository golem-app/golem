import 'package:flutter/cupertino.dart';

import '../theme/golem_theme.dart';
import 'golem_chrome.dart';
import 'golem_tappable.dart';

enum _GolemButtonVariant { filled, tinted, plain, destructive }

/// The app's label buttons.
///
/// [GolemButton.filled] and [GolemButton.tinted] are the primaries: 50pt tall,
/// filled blue or soft-blue tinted, rounded on cupertino chrome and
/// pill-shaped on Android. [GolemButton.plain] and [GolemButton.destructive]
/// are the secondaries beneath them — no fill, no radius, and the platform
/// minimum for a height, which is the number a card here used to write as a
/// literal 48 (#131).
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

  /// A secondary action under a primary one, in the surface's own ink.
  const GolemButton.plain({
    required this.label,
    required this.onPressed,
    this.expand = true,
    super.key,
  }) : _variant = _GolemButtonVariant.plain;

  /// The same shape for an action that discards something. Uses
  /// [GolemTheme.destructiveText], not the brand red: standalone red text
  /// reads 3.6:1 on white, under the enforced 4.5:1.
  const GolemButton.destructive({
    required this.label,
    required this.onPressed,
    this.expand = true,
    super.key,
  }) : _variant = _GolemButtonVariant.destructive;

  final String label;
  final VoidCallback? onPressed;
  final bool expand;
  final _GolemButtonVariant _variant;

  @override
  Widget build(BuildContext context) {
    if (_variant case final variant
        when variant == _GolemButtonVariant.plain ||
            variant == _GolemButtonVariant.destructive) {
      return GolemTappable(
        shape: GolemTapShape.wide,
        onPressed: onPressed,
        child: Text(
          label,
          style: variant == _GolemButtonVariant.destructive
              ? TextStyle(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.destructiveText,
                    context,
                  ),
                )
              : null,
        ),
      );
    }
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
