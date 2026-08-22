import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/model_catalog.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../l10n/l10n.dart';
import '../application/download_note_providers.dart';

/// One muted line under a running transfer: keep Golem open, downloads are
/// fastest in the foreground. The #36 evidence behind it (measured
/// background pacing, minute figures, a dismiss control) used to be quoted in
/// full and read as a warning nobody finished; the advice is the whole note
/// now. Renders nothing outside a transfer in flight, so surfaces embed it
/// unconditionally.
class DownloadNoteBanner extends ConsumerWidget {
  const DownloadNoteBanner({required this.entry, this.margin, super.key});

  final ModelCatalogEntry entry;

  /// Applied only while visible, so hidden notes leave no stray spacing in
  /// the surfaces that embed the banner unconditionally.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(downloadNoteVisibleProvider(entry.key))) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Text(
        context.l10n.downloadNote,
        style: GolemText.caption.copyWith(
          color: CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context),
        ),
      ),
    );
  }
}
