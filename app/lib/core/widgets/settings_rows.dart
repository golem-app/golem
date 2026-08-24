import 'package:flutter/cupertino.dart';

import '../chrome/golem_chrome.dart';
import '../theme/golem_theme.dart';

/// The grouped settings card: surface fill, card radius, hairline border,
/// and children separated by inset dividers — the handoff's list card.
class SettingsCard extends StatelessWidget {
  const SettingsCard({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(GolemTheme.surface, context),
      borderRadius: BorderRadius.circular(GolemRadius.card),
      border: Border.all(
        color: CupertinoDynamicColor.resolve(GolemTheme.divider, context),
      ),
      boxShadow: GolemShadow.card(context),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Column(
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0)
            Container(
              height: 1,
              color: CupertinoDynamicColor.resolve(GolemTheme.divider, context),
            ),
          child,
        ],
      ],
    ),
  );
}

/// A disclosure row: label, muted value, chevron. The whole row is the
/// tap target and clears the platform guideline.
class SettingsNavRow extends StatelessWidget {
  const SettingsNavRow({
    required this.label,
    required this.onTap,
    this.value,
    this.destructive = false,
    super.key,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    onPressed: onTap,
    child: ConstrainedBox(
      // A minimum, not a fixed height: device font scaling can wrap the
      // label onto two lines, and a fixed 50pt row crams them against
      // the centered value.
      constraints: const BoxConstraints(minHeight: 50),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Text(
                label,
                style: GolemText.body.copyWith(
                  color: CupertinoDynamicColor.resolve(
                    destructive ? GolemTheme.destructiveText : GolemTheme.ink,
                    context,
                  ),
                ),
              ),
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GolemText.body.copyWith(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                ),
              ),
            ),
          ],
          if (onTap != null && !destructive) ...[
            const SizedBox(width: 6),
            Icon(
              CupertinoIcons.forward,
              size: 18,
              color: CupertinoDynamicColor.resolve(
                GolemTheme.tertiaryInk,
                context,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// A switch row with an optional explanatory footnote underneath.
class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.footnote,
    this.toggleKey,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? footnote;
  final Key? toggleKey;

  @override
  // Label, switch, and footnote are one control, not three fragments: split
  // up, the label was read twice (once as prose, once as the switch) and the
  // footnote landed on the card's node, which neither screen reader stops on.
  Widget build(BuildContext context) => MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: GolemText.body)),
              const SizedBox(width: 12),
              // A platform-minimum box so the switch clears the tap-target guideline (its
              // own chrome is 39pt tall).
              SizedBox(
                height: GolemChrome.current.minimumTapTarget,
                child: Center(
                  child: CupertinoSwitch(
                    key: toggleKey,
                    value: value,
                    onChanged: onChanged,
                    activeTrackColor: CupertinoDynamicColor.resolve(
                      GolemTheme.accent,
                      context,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (footnote != null) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                footnote!,
                style: GolemText.footnote.copyWith(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// The full-width segmented control (theme picker, catalog tabs), on the
/// shared segment tokens.
class GolemSegmented<T extends Object> extends StatelessWidget {
  const GolemSegmented({
    required this.segments,
    required this.groupValue,
    required this.onChanged,
    super.key,
  });

  /// Ordered value → label; each segment's key is derived by the caller
  /// wrapping labels when needed.
  final Map<T, Widget> segments;
  final T groupValue;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: CupertinoSlidingSegmentedControl<T>(
      backgroundColor: CupertinoDynamicColor.resolve(
        GolemTheme.segmentTrack,
        context,
      ),
      thumbColor: CupertinoDynamicColor.resolve(GolemTheme.surface, context),
      groupValue: groupValue,
      onValueChanged: (value) {
        if (value != null) onChanged(value);
      },
      children: {
        for (final entry in segments.entries)
          // Sized so each segment clears the platform tap-target guideline —
          // the repo picks full hit areas over the handoff's 36pt visual
          // (the #47 precedent).
          entry.key: SizedBox(
            height: GolemChrome.current.minimumTapTarget,
            child: Center(child: entry.value),
          ),
      },
    ),
  );
}

/// A muted centered footnote under a section or screen. Muted rather
/// than tertiary ink: tertiary lands at ~3:1 on the canvas and fails
/// the WCAG contrast gate the widget suite enforces.
class SettingsFootnote extends StatelessWidget {
  const SettingsFootnote(this.text, {this.centered = true, super.key});
  final String text;
  final bool centered;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      text,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: GolemText.footnote.copyWith(
        color: CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context),
      ),
    ),
  );
}
