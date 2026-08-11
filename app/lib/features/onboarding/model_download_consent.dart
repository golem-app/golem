import 'package:flutter/cupertino.dart';

import '../../core/chrome/golem_alert.dart';
import '../../core/domain/model_catalog.dart';

String formatModelBytes(int bytes) =>
    '${(bytes / 1000000000).toStringAsFixed(2)} GB';

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
    title: simulated ? 'Simulate this download?' : 'Download this model?',
    message: simulated
        ? '${entry.displayName} is shown as a '
              '${formatModelBytes(entry.totalBytes)} download. This QA '
              'simulation uses no network and stores no model weights.'
        : '${entry.displayName} downloads ${formatModelBytes(entry.totalBytes)} '
              'from Hugging Face. Keep that space plus 500 MiB free. Wi-Fi '
              'is recommended; cellular data charges may apply.',
    actions: [
      GolemAlertAction(
        key: const Key('model-download-not-now'),
        label: 'Not now',
        onPressed: () => Navigator.pop(context),
      ),
      GolemAlertAction(
        key: const Key('model-download-confirm'),
        label: simulated ? 'Simulate' : 'Download',
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
