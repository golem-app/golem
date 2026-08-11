import 'package:flutter/cupertino.dart';

import '../theme/golem_theme.dart';
import 'golem_chrome.dart';

/// The adaptive bottom sheet container: card surface, 16pt top radius,
/// the sheet shadow, and — on Android chrome — a drag handle. The builder
/// supplies the content, including its own padding and keyboard insets.
Future<T?> showGolemSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Key? sheetKey,
}) => showCupertinoModalPopup<T>(
  context: context,
  builder: (context) => GestureDetector(
    // The Android drag handle must deliver what it advertises: a firm
    // downward fling dismisses the sheet (barrier tap and system back
    // still work on both chromes).
    onVerticalDragEnd: GolemChrome.current == GolemChrome.android
        ? (details) {
            if ((details.primaryVelocity ?? 0) > 300) {
              Navigator.of(context).maybePop();
            }
          }
        : null,
    child: ConstrainedBox(
      // Every sheet here is bottom-anchored and grown by its content, and the
      // enclosing Column offers no bound — so the ceiling belongs to the one
      // place that knows what a sheet is, rather than to each caller that
      // outgrows the screen. Content past this scrolls inside its own body.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Container(
        key: sheetKey,
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(GolemTheme.surface, context),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(GolemRadius.card),
          ),
          boxShadow: GolemShadow.sheet,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (GolemChrome.current == GolemChrome.android)
              Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(top: GolemSpace.s3),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.tertiaryInk,
                    context,
                  ).withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            // Flexible so the ceiling above actually reaches the content: a
            // Column hands its children unbounded main-axis space otherwise,
            // and a body that scrolls internally would never learn its bound.
            Flexible(child: builder(context)),
          ],
        ),
      ),
    ),
  ),
);

class GolemSheetAction {
  const GolemSheetAction({
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
    this.key,
  });

  final String label;

  /// The complete handler — it pops the sheet itself, matching the
  /// existing Cupertino call sites.
  final VoidCallback onPressed;
  final bool isDestructive;
  final Key? key;
}

/// The adaptive action list. Cupertino uses the native action sheet with
/// a cancel button; Android chrome uses a [showGolemSheet] list of 44pt
/// rows dismissed by the scrim.
Future<void> showGolemActions({
  required BuildContext context,
  required List<GolemSheetAction> actions,
  String? title,
  String cancelLabel = 'Cancel',
}) {
  if (GolemChrome.current == GolemChrome.cupertino) {
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        actions: [
          for (final action in actions)
            CupertinoActionSheetAction(
              key: action.key,
              isDestructiveAction: action.isDestructive,
              onPressed: action.onPressed,
              child: Text(action.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(cancelLabel),
        ),
      ),
    );
  }
  return showGolemSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GolemSpace.gutter,
                GolemSpace.s4,
                GolemSpace.gutter,
                GolemSpace.s1,
              ),
              child: Text(
                title,
                style: GolemText.footnote.copyWith(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                ),
              ),
            ),
          for (final action in actions)
            CupertinoButton(
              key: action.key,
              padding: const EdgeInsets.symmetric(
                horizontal: GolemSpace.gutter,
              ),
              minimumSize: const Size.fromHeight(GolemSize.hitTarget),
              alignment: Alignment.centerLeft,
              onPressed: action.onPressed,
              child: Text(
                action.label,
                style: GolemText.body.copyWith(
                  color: action.isDestructive
                      ? GolemTheme.destructive
                      : CupertinoDynamicColor.resolve(GolemTheme.ink, context),
                ),
              ),
            ),
          const SizedBox(height: GolemSpace.s2),
        ],
      ),
    ),
  );
}
