import 'package:flutter/cupertino.dart';

import '../../../core/chrome/golem_sheet.dart';
import '../../../core/theme/golem_theme.dart';

/// The "Add to this chat" sheet. Deliberately inert: the rows dismiss
/// without acting — attachment behavior belongs to the image-input
/// ticket (#18) — but the surface and its honesty copy ship now.
Future<void> showAttachSheet(
  BuildContext context, {
  required String modelLabel,
}) => showGolemSheet<void>(
  context: context,
  sheetKey: const Key('attach-sheet'),
  builder: (context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        GolemSpace.gutter,
        GolemSpace.s4,
        GolemSpace.gutter,
        GolemSpace.s3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add to this chat',
            textAlign: TextAlign.center,
            style: GolemText.cardTitle,
          ),
          const SizedBox(height: GolemSpace.s3),
          const _AttachRow(
            rowKey: Key('attach-photo-library'),
            icon: CupertinoIcons.photo_on_rectangle,
            label: 'Photo library',
          ),
          const _AttachRow(
            rowKey: Key('attach-take-photo'),
            icon: CupertinoIcons.camera,
            label: 'Take a photo',
          ),
          const _AttachRow(
            rowKey: Key('attach-files'),
            icon: CupertinoIcons.folder,
            label: 'Files',
          ),
          const SizedBox(height: GolemSpace.s2),
          Text(
            'Attachments are read on device. $modelLabel handles text; '
            'images need a vision model.',
            style: GolemText.caption.copyWith(
              color: CupertinoDynamicColor.resolve(
                GolemTheme.mutedInk,
                context,
              ),
            ),
          ),
          const SizedBox(height: GolemSpace.s2),
        ],
      ),
    ),
  ),
);

final class _AttachRow extends StatelessWidget {
  const _AttachRow({
    required this.rowKey,
    required this.icon,
    required this.label,
  });
  final Key rowKey;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    key: rowKey,
    padding: EdgeInsets.zero,
    minimumSize: const Size.fromHeight(GolemSize.hitTarget),
    alignment: Alignment.centerLeft,
    onPressed: () => Navigator.pop(context),
    child: Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: CupertinoDynamicColor.resolve(GolemTheme.accentIcon, context),
        ),
        const SizedBox(width: GolemSpace.s3),
        Text(
          label,
          style: GolemText.body.copyWith(
            color: CupertinoDynamicColor.resolve(GolemTheme.ink, context),
          ),
        ),
      ],
    ),
  );
}
