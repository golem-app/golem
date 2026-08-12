import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/chrome/golem_sheet.dart';
import '../../../core/services/image_intake.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../l10n/l10n.dart';

enum AttachSource { photoLibrary, camera, files }

/// The attachment sheet. Reading the image is the caller's job, so the sheet
/// dismisses first and every rejection is handled in one place.
///
/// Rows are disabled when the chat's model cannot read an image, so the
/// refusal happens before a picker opens rather than after the user has
/// already chosen a photo.
Future<AttachSource?> showAttachSheet(
  BuildContext context, {
  required String modelLabel,
  required bool supportsImages,
}) => showGolemSheet<AttachSource>(
  context: context,
  sheetKey: const Key('attach-sheet'),
  builder: (context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        GolemSpace.gutter,
        GolemSpace.s5,
        GolemSpace.gutter,
        GolemSpace.s5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(context.l10n.addToChat, style: GolemText.cardTitle),
          ),
          const SizedBox(height: GolemSpace.s4),
          _AttachRow(
            rowKey: const Key('attach-photo-library'),
            icon: CupertinoIcons.photo_on_rectangle,
            label: context.l10n.photoLibrary,
            enabled: supportsImages,
            source: AttachSource.photoLibrary,
          ),
          _AttachRow(
            rowKey: const Key('attach-take-photo'),
            icon: CupertinoIcons.camera,
            label: context.l10n.takePhoto,
            enabled: supportsImages,
            source: AttachSource.camera,
          ),
          _AttachRow(
            rowKey: const Key('attach-files'),
            icon: CupertinoIcons.folder,
            label: context.l10n.files,
            enabled: supportsImages,
            source: AttachSource.files,
          ),
          const SizedBox(height: GolemSpace.s3),
          Text(
            supportsImages
                ? context.l10n.imagesPrivateDetail(modelLabel)
                : context.l10n.imagesUnsupportedDetail(modelLabel),
            style: GolemText.footnote.copyWith(
              color: CupertinoDynamicColor.resolve(
                GolemTheme.mutedInk,
                context,
              ),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  ),
);

/// The platform pickers, behind an injectable seam so widget tests drive the
/// sheet without a plugin (handbook v4.2A §2.2 platform adapter).
class AttachmentPicker {
  const AttachmentPicker({this.intake = const ImageIntake()});

  final ImageIntake intake;

  Future<PreparedImage?> pick(
    AttachSource source, {
    String filesLabel = 'Images',
  }) async {
    switch (source) {
      case AttachSource.photoLibrary:
      case AttachSource.camera:
        // The plugin downscales natively and resolves EXIF orientation, so a
        // 48-megapixel photo never crosses into Dart at full size.
        final file = await ImagePicker().pickImage(
          source: source == AttachSource.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: ImageIntake.maxDimension.toDouble(),
          maxHeight: ImageIntake.maxDimension.toDouble(),
          imageQuality: 90,
        );
        if (file == null) return null;
        return intake.prepare(
          await file.readAsBytes(),
          mimeType: _mimeFor(file.name, file.mimeType),
        );
      case AttachSource.files:
        final file = await openFile(
          acceptedTypeGroups: [
            XTypeGroup(
              label: filesLabel,
              extensions: ['jpg', 'jpeg', 'png', 'webp'],
              mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
              uniformTypeIdentifiers: [
                'public.jpeg',
                'public.png',
                'org.webmproject.webp',
              ],
            ),
          ],
        );
        if (file == null) return null;
        return intake.prepare(
          await file.readAsBytes(),
          mimeType: _mimeFor(file.name, file.mimeType),
        );
    }
  }

  /// Platform pickers do not always report a type; the extension is the
  /// fallback, and an unrecognized one is left for the intake to refuse.
  static String _mimeFor(String name, String? reported) {
    if (reported != null && ImageIntake.supportedMimeTypes.contains(reported)) {
      return reported;
    }
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return reported ?? 'application/octet-stream';
  }
}

class _AttachRow extends StatelessWidget {
  const _AttachRow({
    required this.rowKey,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.source,
  });

  final Key rowKey;
  final IconData icon;
  final String label;
  final bool enabled;
  final AttachSource source;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoDynamicColor.resolve(
      GolemTheme.accentIcon,
      context,
    );
    final ink = CupertinoDynamicColor.resolve(GolemTheme.ink, context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: CupertinoButton(
        key: rowKey,
        padding: EdgeInsets.zero,
        minimumSize: const Size.fromHeight(GolemSize.hitTarget),
        alignment: Alignment.centerLeft,
        onPressed: enabled ? () => Navigator.pop(context, source) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Row(
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: GolemSpace.s3),
              // The disabled rows name the model that cannot read pictures, so
              // these labels are long enough to leave the row at an
              // accessibility text size unless they may wrap.
              Expanded(
                child: Text(label, style: GolemText.body.copyWith(color: ink)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
