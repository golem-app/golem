import 'package:flutter/cupertino.dart';

import '../theme/golem_theme.dart';
import 'golem_chrome.dart';

class GolemAlertAction {
  const GolemAlertAction({
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
    this.isDefault = false,
    this.key,
  });

  final String label;

  /// The complete handler — it pops the dialog itself, matching the
  /// existing Cupertino call sites.
  final VoidCallback onPressed;
  final bool isDestructive;
  final bool isDefault;
  final Key? key;
}

/// The adaptive alert. Cupertino shows the native [CupertinoAlertDialog];
/// Android chrome renders a card with right-aligned text actions through
/// the same dialog route, so callers and automation see one behavior.
Future<void> showGolemAlert({
  required BuildContext context,
  required String title,
  required List<GolemAlertAction> actions,
  String? message,
  Widget? content,
  Key? dialogKey,
}) {
  assert(message == null || content == null, 'Pass message or content');
  if (GolemChrome.current == GolemChrome.cupertino) {
    return showCupertinoDialog<void>(
      context: context,
      // Action closures pop with the caller context. Keeping the dialog on
      // that same navigator matters once an all-routes shell owns startup:
      // a root dialog paired with a shell pop would remove the last app page.
      useRootNavigator: false,
      builder: (context) => CupertinoAlertDialog(
        key: dialogKey,
        title: Text(title),
        content: content ?? (message == null ? null : Text(message)),
        actions: [
          for (final action in actions)
            CupertinoDialogAction(
              key: action.key,
              isDestructiveAction: action.isDestructive,
              isDefaultAction: action.isDefault,
              onPressed: action.onPressed,
              child: Text(action.label),
            ),
        ],
      ),
    );
  }
  // Mirrors what CupertinoAlertDialog provides for free: keyboard-inset
  // lifting, a scrollable content section, and actions that never clip at
  // large text scales (they wrap instead of overflowing a fixed row).
  return showCupertinoDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (context) {
      final insets = MediaQuery.viewInsetsOf(context);
      final maxHeight =
          (MediaQuery.sizeOf(context).height - insets.bottom) * 0.8;
      return AnimatedPadding(
        padding: insets,
        duration: GolemMotion.fast,
        curve: GolemMotion.standard,
        child: Center(
          child: Container(
            key: dialogKey,
            margin: const EdgeInsets.symmetric(horizontal: GolemSpace.s10),
            padding: const EdgeInsets.fromLTRB(
              GolemSpace.s6,
              GolemSpace.s5,
              GolemSpace.s4,
              GolemSpace.s3,
            ),
            constraints: BoxConstraints(maxWidth: 320, maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: CupertinoDynamicColor.resolve(
                GolemTheme.surfaceRaised,
                context,
              ),
              borderRadius: BorderRadius.circular(GolemRadius.card),
              boxShadow: GolemShadow.menu,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DefaultTextStyle(
                          style: GolemText.bodyStrong.copyWith(
                            color: CupertinoDynamicColor.resolve(
                              GolemTheme.ink,
                              context,
                            ),
                          ),
                          child: Text(title),
                        ),
                        if (content != null || message != null) ...[
                          const SizedBox(height: GolemSpace.s3),
                          DefaultTextStyle(
                            style: GolemText.footnote.copyWith(
                              color: CupertinoDynamicColor.resolve(
                                GolemTheme.mutedInk,
                                context,
                              ),
                            ),
                            child: content ?? Text(message!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: GolemSpace.s4),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final action in actions)
                        CupertinoButton(
                          key: action.key,
                          padding: const EdgeInsets.symmetric(
                            horizontal: GolemSpace.s3,
                            vertical: GolemSpace.s2,
                          ),
                          minimumSize: const Size(44, 44),
                          onPressed: action.onPressed,
                          child: Text(
                            action.label,
                            style: GolemText.bodyStrong.copyWith(
                              color: action.isDestructive
                                  ? GolemTheme.destructive
                                  : CupertinoDynamicColor.resolve(
                                      GolemTheme.accent,
                                      context,
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
