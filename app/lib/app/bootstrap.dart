import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/chrome/golem_button.dart';
import '../core/domain/app_state.dart';
import '../core/app_identity.dart';
import '../core/theme/golem_theme.dart';
import '../l10n/l10n.dart';
import '../features/chat/widgets/attach_sheet.dart';
import 'app.dart';
import 'launch_composition.dart';

/// Runs the fallible launch composition behind the splash frame. The frame
/// paints for exactly as long as the real work takes — no hold, no loader —
/// then the shell replaces it; on failure the same frame carries a truthful
/// caption and a Try again that reruns the composition. No Riverpod here —
/// the scope does not exist until composition succeeds.
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({
    required this.identity,
    required this.compose,
    this.picker = const AttachmentPicker(),
    super.key,
  });
  final AppIdentity identity;
  final LaunchComposer compose;
  final AttachmentPicker picker;

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp>
    with WidgetsBindingObserver {
  LaunchDependencies? _dependencies;
  LaunchFailure? _failure;
  bool _composing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The pre-scope frames read the platform brightness directly, so they must
  // rebuild when it changes — mirroring GolemApp's observer for the same
  // reason.
  @override
  void didChangePlatformBrightness() => setState(() {});

  Future<void> _run() async {
    // One composition at a time: a double-tap on Try again must not race two
    // compositions and swap the mounted app's repository graph.
    if (_composing || _dependencies != null) return;
    _composing = true;
    if (_failure != null) {
      setState(() => _failure = null);
    }
    try {
      final dependencies = await widget.compose(widget.identity);
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
    } finally {
      _composing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies;
    if (dependencies != null) {
      return ProviderScope(
        overrides: launchOverrides(dependencies),
        child: GolemApp(identity: widget.identity, picker: widget.picker),
      );
    }
    final failure = _failure;
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      theme: GolemTheme.theme(
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
      ),
      home: Builder(
        builder: (context) {
          final l10n = context.l10n;
          // Copy only when there is something to say: a composition in flight
          // is the splash frame alone, not a status line standing in for a
          // loader.
          final message = switch (failure?.kind) {
            LaunchFailureKind.timedOut => l10n.launchTakingLonger,
            LaunchFailureKind.storageUnavailable =>
              l10n.launchStorageUnavailable,
            LaunchFailureKind.invalidConfiguration =>
              l10n.launchInvalidConfiguration,
            LaunchFailureKind.unknown => l10n.launchUnknownFailure,
            null => null,
          };
          return LaunchPane(
            message: message,
            onRetry: (failure?.retryable ?? false) ? _run : null,
          );
        },
      ),
    );
  }
}

/// The splash frame: the native launch screen's navy, the app mark, name and
/// tagline, and — only when there is one — a [message] with an optional Try
/// again. It paints while the composition runs and nothing else: no track, no
/// spinner, no minimum hold (#159). Owns the `launch-splash` and
/// `splash-retry` automation keys; the Try again button exists exactly when
/// [onRetry] is non-null.
class LaunchPane extends StatelessWidget {
  const LaunchPane({this.message, this.onRetry, super.key});
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    final message = this.message;
    return Semantics(
      key: const Key('launch-splash'),
      label: context.l10n.appName,
      value: message ?? context.l10n.startingUp,
      liveRegion: true,
      child: ColoredBox(
        color: GolemTheme.splash,
        child: SafeArea(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: const [
                        BoxShadow(
                          color: GolemTheme.splashGlow,
                          blurRadius: 50,
                          offset: Offset(0, 20),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/golem_splash_icon.png',
                      width: 132,
                      height: 132,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    context.l10n.appName,
                    style: GolemText.hero.copyWith(
                      color: CupertinoColors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.splashTagline,
                    style: GolemText.body.copyWith(
                      color: GolemTheme.mutedOnDark,
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 48,
                right: 48,
                bottom: 66,
                child: Column(
                  children: [
                    if (message != null)
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: GolemText.caption.copyWith(
                          color: GolemTheme.mutedOnDark,
                        ),
                      ),
                    if (retry != null) ...[
                      const SizedBox(height: 14),
                      GolemButton.filled(
                        key: const Key('splash-retry'),
                        label: context.l10n.tryAgain,
                        onPressed: retry,
                        expand: false,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
