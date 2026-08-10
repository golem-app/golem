import 'package:flutter/cupertino.dart';

import 'app/bootstrap.dart';
import 'app/launch_composition.dart';
import 'features/chat/widgets/attach_sheet.dart';

Future<void> main() => launch();

/// Launches the app with the first frame up immediately: the fallible
/// composition runs behind the bootstrap gate, so a launch failure renders
/// as a retryable pane instead of the native launch screen forever. The
/// picker seam lets the integration journey drive the whole attach flow
/// without an OS photo-library UI; the composer seam lets tests substitute
/// failing compositions for the real one.
Future<void> launch({
  AttachmentPicker picker = const AttachmentPicker(),
  LaunchComposer compose = composeLaunchWithInjectedFailures,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(BootstrapApp(compose: compose, picker: picker));
}
