import 'package:flutter/cupertino.dart';

import 'app/bootstrap.dart';
import 'app/launch_composition.dart';
import 'core/app_identity.dart';
import 'features/chat/widgets/attach_sheet.dart';
import 'features/legal/license_registry.dart';

Future<void> main() => launch();

/// Launches the app with `runApp` immediately and the first frame deferred:
/// the fallible composition runs behind the bootstrap gate, so a launch
/// failure renders as a retryable pane instead of the native launch screen
/// forever, and a success draws the shell as its first frame (ADR 0018). The
/// picker seam lets the integration journey drive the whole attach flow
/// without an OS photo-library UI; the composer seam lets tests substitute
/// failing compositions for the real one.
Future<void> launch({
  AttachmentPicker picker = const AttachmentPicker(),
  LaunchComposer compose = composeLaunchWithInjectedFailures,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  registerGolemLicenses();
  final identity = AppIdentity.current;
  runApp(BootstrapApp(identity: identity, compose: compose, picker: picker));
}
