import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/golem_theme.dart';
import '../lab_theme.dart';

/// The pointer treatment every bench control shares (#58): a hover wash, a
/// focus ring, keyboard activation on Enter and Space, and a button node for
/// a screen reader — the things a touch product never needed and a desktop
/// tool cannot do without. Composed once so every chip, row and button gets
/// the same treatment, and the minimum a pointer target owes lives here.
class LabFocusable extends StatefulWidget {
  const LabFocusable({
    required this.child,
    required this.onPressed,
    required this.semanticLabel,
    this.semanticValue,
    this.selected = false,
    this.borderRadius = LabRadius.control,
    this.hover = true,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final String? semanticValue;
  final bool selected;
  final double borderRadius;
  final bool hover;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<LabFocusable> createState() => _LabFocusableState();
}

class _LabFocusableState extends State<LabFocusable> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final radius = BorderRadius.circular(widget.borderRadius);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      value: widget.semanticValue,
      onTap: widget.onPressed,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: LabSize.tapMinimum,
              minHeight: LabSize.tapMinimum,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                color: widget.hover && _hovered && enabled
                    ? labResolve(LabColors.hover, context)
                    : null,
                boxShadow: _focused
                    ? [
                        BoxShadow(
                          color: labResolve(LabColors.focusRing, context),
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: ExcludeSemantics(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

enum LabButtonStyle { filled, outlined, quiet }

/// A labelled desktop button: 28 pt, filled for the primary action of a
/// surface, outlined beside it, quiet for the rest.
class LabButton extends StatelessWidget {
  const LabButton({
    required this.label,
    required this.onPressed,
    this.style = LabButtonStyle.outlined,
    this.icon,
    this.shortcut,
    this.height = LabSize.control,
    this.destructive = false,
    this.semanticLabel,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final LabButtonStyle style;
  final IconData? icon;

  /// A keyboard shortcut hint drawn after the label (`⌘↩`), never spoken.
  final String? shortcut;
  final double height;
  final bool destructive;
  final String? semanticLabel;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final filled = style == LabButtonStyle.filled;
    // A disabled button keeps a readable ink on a quiet fill rather than
    // fading: faded label text is what fails the contrast sweep.
    final ink = !enabled
        ? context.mutedInk
        : destructive
        ? labResolve(GolemTheme.destructiveText, context)
        : filled
        ? labResolve(LabColors.textOnAccent, context)
        : context.ink;
    return LabFocusable(
      onPressed: onPressed,
      semanticLabel: semanticLabel ?? label,
      borderRadius: LabRadius.field,
      hover: !filled,
      autofocus: autofocus,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: LabSpace.s5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? (enabled ? context.accent : context.field) : null,
          borderRadius: BorderRadius.circular(LabRadius.field),
          border: style == LabButtonStyle.outlined
              ? Border.all(
                  color: enabled ? context.borderStrong : context.divider,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: ink),
              const SizedBox(width: LabSpace.s2),
            ],
            Text(label, style: LabText.label.copyWith(color: ink)),
            if (shortcut != null) ...[
              const SizedBox(width: LabSpace.s2),
              Text(shortcut!, style: LabText.detail.copyWith(color: ink)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A static chip: a dot, a strong lead, a detail. Not interactive.
class LabChip extends StatelessWidget {
  const LabChip({
    required this.text,
    this.lead,
    this.dotColor,
    this.icon,
    this.fill,
    this.border,
    this.textColor,
    this.height = LabSize.chip,
    this.ellipsize = false,
    super.key,
  });

  final String text;
  final String? lead;
  final Color? dotColor;
  final IconData? icon;
  final Color? fill;
  final Color? border;
  final Color? textColor;
  final double height;

  /// Truncate a long text on one line. Only for a chip laid out under a
  /// bounded width — a flexible child needs one, and the Rig is where a
  /// chip's text can outgrow the window.
  final bool ellipsize;

  @override
  Widget build(BuildContext context) {
    final color = textColor ?? context.mutedInk;
    final leadStyle = LabText.chip.copyWith(color: context.ink);
    final textStyle = LabText.detail.copyWith(color: color);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: LabSpace.s4),
      decoration: BoxDecoration(
        color: fill ?? context.field,
        borderRadius: BorderRadius.circular(LabRadius.chip),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: LabSpace.s2),
          ],
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: LabSpace.s2),
          ],
          if (ellipsize)
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (lead != null)
                      TextSpan(text: '$lead ', style: leadStyle),
                    TextSpan(text: text, style: textStyle),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else ...[
            if (lead != null) ...[
              Text(lead!, style: leadStyle),
              const SizedBox(width: LabSpace.s1),
            ],
            Text(text, style: textStyle),
          ],
        ],
      ),
    );
  }
}
