import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/domain/app_state.dart';
import '../core/theme/golem_theme.dart';
import '../features/chat/widgets/attach_sheet.dart';
import '../features/splash/splash_screen.dart';
import 'app.dart';
import 'launch_composition.dart';

/// Runs the fallible launch composition behind mounted Flutter UI. While it
/// runs the splash frame paints; on failure a truthful pane offers Try again,
/// which reruns the real composition; on success the one ProviderScope mounts
/// with the composed overrides, and the startup gate's theatre takes over
/// under identical visuals. No Riverpod here — the scope does not exist until
/// composition succeeds.
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({
    required this.compose,
    this.picker = const AttachmentPicker(),
    super.key,
  });
  final LaunchComposer compose;
  final AttachmentPicker picker;

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  LaunchDependencies? _dependencies;
  LaunchFailure? _failure;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (_failure != null) {
      setState(() => _failure = null);
    }
    try {
      final dependencies = await widget.compose();
      if (!mounted) return;
      setState(() => _dependencies = dependencies);
    } catch (error, stackTrace) {
      // The cause is diagnostics, never surface copy: report it once at the
      // boundary, then render the classified pane.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'golem bootstrap',
          context: ErrorDescription('while composing launch dependencies'),
        ),
      );
      if (!mounted) return;
      setState(() => _failure = classifyLaunchFailure(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies;
    if (dependencies != null) {
      return ProviderScope(
        overrides: launchOverrides(dependencies),
        child: GolemApp(picker: widget.picker),
      );
    }
    final failure = _failure;
    // The backend is not resolved yet, so this layer claims nothing about a
    // model: its copy is about starting Golem. The gate's SplashScreen takes
    // over the same scaffold once the scope exists.
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: GolemTheme.theme(
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
      ),
      home: failure == null
          ? const SplashScaffold(
              semanticValue: 'Starting up',
              caption: 'Starting up',
              progress: 0,
            )
          : SplashScaffold(
              semanticValue: failure.message,
              caption: failure.message,
              progress: 0,
              onRetry: failure.retryable ? _run : null,
            ),
    );
  }
}
