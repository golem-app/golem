import 'package:flutter/cupertino.dart';

import '../../../l10n/l10n.dart';
import '../lab_theme.dart';
import 'lab_controls.dart';

/// The bench's prompt field with Run, Stop and New conversation beside it.
/// The field stays focused across a run: status changes must not steal it
/// (#58), so the buttons never take focus on press and the field is only
/// read-only, never disabled, while a run is in flight.
class LabComposer extends StatelessWidget {
  const LabComposer({
    required this.controller,
    required this.focusNode,
    required this.locked,
    required this.canSend,
    required this.onSend,
    required this.onStop,
    required this.onNewConversation,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool locked;
  final bool canSend;
  final VoidCallback? onSend;
  final VoidCallback? onStop;
  final VoidCallback? onNewConversation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Semantics(
            textField: true,
            readOnly: locked,
            label: l10n.labComposerHint,
            child: CupertinoTextField(
              key: const Key('lab-composer'),
              controller: controller,
              focusNode: focusNode,
              readOnly: locked,
              minLines: 1,
              maxLines: 6,
              placeholder: locked
                  ? l10n.labComposerLocked
                  : l10n.labComposerHint,
              placeholderStyle: LabText.body.copyWith(color: context.mutedInk),
              style: LabText.body.copyWith(color: context.ink),
              padding: const EdgeInsets.symmetric(
                horizontal: LabSpace.s5,
                vertical: LabSpace.s3,
              ),
              decoration: BoxDecoration(
                color: context.field,
                borderRadius: BorderRadius.circular(LabRadius.field),
                border: Border.all(color: context.divider),
              ),
            ),
          ),
        ),
        const SizedBox(width: LabSpace.s3),
        if (locked)
          LabButton(
            key: const Key('lab-stop-button'),
            label: l10n.stop,
            icon: CupertinoIcons.stop_fill,
            onPressed: onStop,
            style: LabButtonStyle.filled,
            height: LabSize.composer,
          )
        else
          // Run needs something armed and something typed; the button says
          // so rather than swallowing an empty send.
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => LabButton(
              key: const Key('lab-run-button'),
              label: l10n.labRun,
              shortcut: '⌘↩',
              onPressed: canSend && controller.text.trim().isNotEmpty
                  ? onSend
                  : null,
              style: LabButtonStyle.filled,
              height: LabSize.composer,
            ),
          ),
        const SizedBox(width: LabSpace.s2),
        LabButton(
          key: const Key('lab-new-conversation'),
          label: l10n.labNewConversation,
          onPressed: locked ? null : onNewConversation,
          height: LabSize.composer,
        ),
      ],
    );
  }
}
