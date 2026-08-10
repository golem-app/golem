import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/launch_composition.dart';
import 'features/chat/widgets/attach_sheet.dart';

Future<void> main() => launch();

/// Composes and launches the app. The picker seam lets the integration
/// journey drive the whole attach flow without an OS photo-library UI; the
/// composer seam lets tests substitute failing compositions for the real one.
Future<void> launch({
  AttachmentPicker picker = const AttachmentPicker(),
  LaunchComposer compose = composeLaunch,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await compose();
  runApp(
    ProviderScope(
      overrides: launchOverrides(dependencies),
      child: GolemApp(picker: picker),
    ),
  );
}
