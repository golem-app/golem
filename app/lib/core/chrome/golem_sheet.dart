import 'package:flutter/cupertino.dart';

import '../../l10n/l10n.dart';
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
  useRootNavigator: false,
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
      // Four fifths of the space *above* the keyboard, plus the keyboard
      // itself: bodies pad for viewInsets inside this box (rename does), so a
      // cap that merely subtracted the inset would charge for it twice and
      // clip the button off the bottom of the sheet.
      constraints: BoxConstraints(
        maxHeight:
            (MediaQuery.sizeOf(context).height - _keyboard(context)) * 0.8 +
            _keyboard(context),
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
            // The keyboard inset is applied here rather than by each body:
            // the ceiling already reserves room for it, and four of the five
            // sheets never padded for it at all, so their last row sat behind
            // the keyboard whenever one was up.
            Flexible(
              child: Padding(
                padding: EdgeInsets.only(bottom: _keyboard(context)),
                child: builder(context),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

double _keyboard(BuildContext context) =>
    MediaQuery.viewInsetsOf(context).bottom;

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
/// a cancel button; Android chrome uses a [showGolemSheet] list of
/// rows dismissed by the scrim.
///
/// The cancel label is resolved here rather than taken from a caller: it used
/// to default to the English word and no caller ever passed anything else, so
/// twelve locales read "Cancel" on the one button every action sheet has
/// (#130).
Future<void> showGolemActions({
  required BuildContext context,
  required List<GolemSheetAction> actions,
  String? title,
}) {
  if (GolemChrome.current == GolemChrome.cupertino) {
    return showCupertinoModalPopup<void>(
      context: context,
      useRootNavigator: false,
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
          // sheetContext, not the caller's: this closure re-runs whenever the
          // route rebuilds, and the caller's element may be gone by then.
          child: Text(sheetContext.l10n.cancel),
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
              minimumSize: Size.fromHeight(
                GolemChrome.current.minimumTapTarget,
              ),
              alignment: AlignmentDirectional.centerStart,
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
