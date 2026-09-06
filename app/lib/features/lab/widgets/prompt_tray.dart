import 'package:flutter/cupertino.dart';

import '../../../l10n/l10n.dart';
import '../../eval/domain/eval_spec.dart';
import '../lab_theme.dart';
import 'lab_controls.dart';

/// A prompt the tray offers: the eval suite's text prompts, read-only (#58),
/// each with the check count grading would apply (#59).
final class TrayPrompt {
  const TrayPrompt({
    required this.id,
    required this.text,
    required this.checks,
  });

  final String id;
  final String text;
  final int checks;
}

/// The default suite's single-turn text prompts. Multi-turn and image
/// prompts stay out: the bench types one prompt at a time.
List<TrayPrompt> trayPrompts() => [
  for (final prompt in defaultEvalPrompts)
    if (prompt.messages.length == 1 && prompt.messages.single['role'] == 'user')
      TrayPrompt(
        id: prompt.id,
        text: prompt.messages.single['content']!,
        checks: prompt.checks.length,
      ),
];

/// The tray as the empty state's hero: two columns of prompts.
class PromptTrayGrid extends StatelessWidget {
  const PromptTrayGrid({
    required this.prompts,
    required this.onPick,
    super.key,
  });

  final List<TrayPrompt> prompts;
  final ValueChanged<TrayPrompt>? onPick;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 560 ? 2 : 1;
      final width =
          (constraints.maxWidth - (columns - 1) * LabSpace.s3) / columns;
      return Wrap(
        spacing: LabSpace.s3,
        runSpacing: LabSpace.s3,
        children: [
          for (final prompt in prompts)
            SizedBox(
              width: width,
              child: _TrayRow(prompt: prompt, onPick: onPick),
            ),
        ],
      );
    },
  );
}

class _TrayRow extends StatelessWidget {
  const _TrayRow({required this.prompt, required this.onPick});

  final TrayPrompt prompt;
  final ValueChanged<TrayPrompt>? onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LabFocusable(
      key: Key('lab-tray-${prompt.id}'),
      semanticLabel: prompt.text,
      semanticValue: l10n.labChecks(prompt.checks),
      onPressed: onPick == null ? null : () => onPick!(prompt),
      borderRadius: LabRadius.field,
      child: Container(
        height: LabSize.trayRow,
        padding: const EdgeInsets.symmetric(horizontal: LabSpace.s5),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(LabRadius.field),
          border: Border.all(color: context.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                prompt.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LabText.row.copyWith(color: context.ink),
              ),
            ),
            const SizedBox(width: LabSpace.s4),
            Text(
              l10n.labChecks(prompt.checks),
              style: LabText.chip.copyWith(color: context.mutedInk),
            ),
          ],
        ),
      ),
    );
  }
}

/// The compact tray above the composer once the transcript has turns: the
/// first few prompts as pills and a way to the rest.
class PromptTrayRow extends StatelessWidget {
  const PromptTrayRow({
    required this.prompts,
    required this.onPick,
    required this.onShowAll,
    this.visible = 4,
    super.key,
  });

  final List<TrayPrompt> prompts;
  final ValueChanged<TrayPrompt>? onPick;
  final VoidCallback? onShowAll;
  final int visible;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: LabSpace.s2,
      runSpacing: LabSpace.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final prompt in prompts.take(visible))
          LabFocusable(
            key: Key('lab-tray-${prompt.id}'),
            semanticLabel: prompt.text,
            onPressed: onPick == null ? null : () => onPick!(prompt),
            borderRadius: LabRadius.pill,
            child: Container(
              height: LabSize.tapMinimum,
              padding: const EdgeInsets.symmetric(horizontal: LabSpace.s4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(LabRadius.pill),
                border: Border.all(color: context.divider),
              ),
              alignment: Alignment.center,
              child: Text(
                prompt.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LabText.detail.copyWith(color: context.mutedInk),
              ),
            ),
          ),
        LabButton(
          key: const Key('lab-tray-all'),
          label: l10n.labAllPrompts(prompts.length),
          onPressed: onShowAll,
          style: LabButtonStyle.quiet,
          height: LabSize.tapMinimum,
        ),
      ],
    );
  }
}
