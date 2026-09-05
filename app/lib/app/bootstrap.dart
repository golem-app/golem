import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/chrome/golem_button.dart';
import '../core/domain/app_state.dart';
import '../core/app_identity.dart';
import '../core/theme/golem_theme.dart';
import '../l10n/l10n.dart';
import '../features/chat/widgets/attach_sheet.dart';
import 'app.dart';
import 'lab_app.dart';
import 'launch_composition.dart';

/// Runs the fallible launch composition before the first frame. The frame is
/// deferred while it runs and until the composed app has read its preferences,
/// so the native launch screen stays up for exactly as long as the real work
/// takes and the shell — in the stored theme, language and text size — is the
/// first thing Flutter draws; on failure the first frame is a truthful pane
/// whose Try again reruns the composition. No Riverpod here — the scope does
/// not exist until composition succeeds.
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
  bool _firstFrameDeferred = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.deferFirstFrame();
    _firstFrameDeferred = true;
    _run();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _allowFirstFrame();
    super.dispose();
  }

  /// Exactly once: the binding counts deferrals, and a second allow would
  /// release a deferral that belongs to someone else.
  void _allowFirstFrame() {
    if (!_firstFrameDeferred) return;
    _firstFrameDeferred = false;
    WidgetsBinding.instance.allowFirstFrame();
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
      // The frame stays deferred: GolemApp releases it once the preferences
      // store has answered, so the first frame is already in the user's theme.
      setState(() => _dependencies = dependencies);
      return;
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
    // A failed composition is what the first frame should show.
    _allowFirstFrame();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies;
    if (dependencies != null) {
      // A constant condition: every other flavor compiles without the lab
      // root behind it (ADR 0021).
      if (kLabBuild) {
        return ProviderScope(
          overrides: labLaunchOverrides(dependencies),
          child: LabApp(
            identity: widget.identity,
            onPreferencesSettled: _allowFirstFrame,
          ),
        );
      }
      return ProviderScope(
        overrides: launchOverrides(dependencies),
        child: GolemApp(
          identity: widget.identity,
          picker: widget.picker,
          onPreferencesSettled: _allowFirstFrame,
        ),
      );
    }
    final failure = _failure;
    // Nothing is composited while the frame is deferred, so nothing is built
    // for it either: a first composition in flight is the launch screen's
    // navy and no more — not a pane, its layout, and a full-size icon decode
    // that would only ever be thrown away.
    if (failure == null && _firstFrameDeferred) {
      return const ColoredBox(
        key: Key('launch-splash'),
        color: GolemTheme.splash,
      );
    }
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
          final message = switch (failure?.kind) {
            LaunchFailureKind.timedOut => l10n.launchTakingLonger,
            LaunchFailureKind.storageUnavailable =>
              l10n.launchStorageUnavailable,
            LaunchFailureKind.invalidConfiguration =>
              l10n.launchInvalidConfiguration,
            LaunchFailureKind.unknown => l10n.launchUnknownFailure,
            null => l10n.startingUp,
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

/// The pre-scope launch frame: the same solid navy as the native launch
/// screen, the app mark, and one status line. It is visible only when a
/// composition failed (with Try again) or is being retried — a successful
/// first composition never draws it. Owns the `launch-splash` and
/// `splash-retry` automation keys; the Try again button exists exactly when
/// [onRetry] is non-null.
class LaunchPane extends StatelessWidget {
  const LaunchPane({required this.message, this.onRetry, super.key});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    return Semantics(
      key: const Key('launch-splash'),
      label: context.l10n.appName,
      value: message,
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
                      // Decoded at the size it is drawn, not the 528 px source.
                      cacheWidth: 396,
                      cacheHeight: 396,
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
