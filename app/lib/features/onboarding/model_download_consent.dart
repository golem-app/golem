import 'package:flutter/cupertino.dart';

import '../../core/chrome/golem_alert.dart';
import '../../core/domain/model_catalog.dart';
import '../../core/domain/byte_format.dart';
import '../../l10n/l10n.dart';

/// Kept as a name the onboarding copy reads well with; the formatting itself
/// has one owner, so the size in this dialog and the size on the button that
/// opened it cannot round differently.
String formatModelBytes(int bytes) => gigabytes(bytes);

/// Consent shared by onboarding, Settings, and the chat recovery path. It is
/// intentionally static: Golem requests no connectivity permission and makes
/// no claim that it can distinguish Wi-Fi from cellular reliably.
Future<bool> confirmModelDownload({
  required BuildContext context,
  required ModelCatalogEntry entry,
  required bool simulated,
}) async {
  var approved = false;
  await showGolemAlert(
    context: context,
    dialogKey: const Key('model-download-consent'),
    title: simulated
        ? context.l10n.simulateDownloadTitle
        : context.l10n.downloadModelTitle,
    message: simulated
        ? context.l10n.simulateDownloadMessage(
            entry.displayName,
            formatModelBytes(entry.totalBytes),
          )
        : context.l10n.downloadModelMessage(
            entry.displayName,
            formatModelBytes(entry.totalBytes),
          ),
    actions: [
      GolemAlertAction(
        key: const Key('model-download-not-now'),
        label: context.l10n.notNow,
        onPressed: () => Navigator.pop(context),
      ),
      GolemAlertAction(
        key: const Key('model-download-confirm'),
        label: simulated ? context.l10n.simulate : context.l10n.download,
        isDefault: true,
        onPressed: () {
          approved = true;
          Navigator.pop(context);
        },
      ),
    ],
  );
  return approved;
}
