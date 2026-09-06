import 'package:flutter/cupertino.dart';

import '../../core/chrome/golem_alert.dart';
import '../../core/domain/byte_format.dart';
import '../../core/domain/model_catalog.dart';
import '../../l10n/l10n.dart';

/// The consent every surface that deletes an artifact shows — Models,
/// Storage and the bench. Display names no longer carry a quantization, so
/// two artifacts of one family share one (#79); a destructive dialog must
/// still say which, and what [bytes] it frees.
Future<bool> confirmModelDelete({
  required BuildContext context,
  required ModelCatalogEntry entry,
  required int bytes,
}) async {
  var approved = false;
  await showGolemAlert(
    context: context,
    dialogKey: const Key('model-delete-dialog'),
    title: context.l10n.deleteModelArtifactTitle(
      entry.displayName,
      engineFormat(entry.engine),
    ),
    message: context.l10n.deleteModelStorageMessage(gigabytes(bytes)),
    actions: [
      GolemAlertAction(
        label: context.l10n.keep,
        onPressed: () => Navigator.pop(context),
      ),
      GolemAlertAction(
        key: const Key('confirm-model-delete'),
        label: context.l10n.delete,
        isDestructive: true,
        onPressed: () {
          approved = true;
          Navigator.pop(context);
        },
      ),
    ],
  );
  return approved;
}
