import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/app_state.dart';
import '../../core/chrome/golem_button.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/progress_track.dart';

class StartupGate extends ConsumerWidget {
  const StartupGate({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupControllerProvider);
    final value = startup.hasValue ? startup.requireValue : null;
    final complete = value?.phase == StartupPhase.complete;
    return Stack(
      children: [
        ExcludeSemantics(excluding: !complete, child: child),
        if (!complete)
          Positioned.fill(
            child: SplashScreen(
              state: value ?? const StartupState(),
              retry: () => ref.read(startupControllerProvider.notifier).retry(),
            ),
          ),
      ],
    );
  }
}

/// Maps the startup theatre's [StartupState] onto the splash visuals, with
/// copy that is honest in both directions: only a simulated backend may claim
/// to be one, and a real-engine build must never say "simulated".
class SplashScreen extends ConsumerWidget {
  const SplashScreen({required this.state, required this.retry, super.key});
  final StartupState state;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simulated = ref.watch(inferenceBackendProvider).simulatedInference;
    final model = simulated ? 'simulated model' : 'model';
    final (semanticValue, caption) = switch (state.phase) {
      StartupPhase.failed => (
        simulated ? 'Simulated loading failed' : 'Loading failed',
        'The $model could not be prepared',
      ),
      StartupPhase.missingModel => (
        'No $model selected; preparing setup',
        'Preparing $model setup',
      ),
      _ => ('Loading $model on this device', 'Loading $model on this device'),
    };
    return SplashScaffold(
      semanticValue: semanticValue,
      caption: caption,
      progress: state.progress,
      onRetry: state.phase == StartupPhase.failed ? retry : null,
    );
  }
}

/// The splash visuals, free of providers so the pre-scope bootstrap can paint
/// the identical frame. Owns the `launch-splash` and `splash-retry` keys; the
/// Try again button exists exactly when [onRetry] is non-null.
class SplashScaffold extends StatelessWidget {
  const SplashScaffold({
    required this.semanticValue,
    required this.caption,
    required this.progress,
    this.onRetry,
    super.key,
  });
  final String semanticValue;
  final String caption;
  final double progress;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    return Semantics(
      key: const Key('launch-splash'),
      label: 'Golem',
      value: semanticValue,
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
                    'Golem',
                    style: GolemText.hero.copyWith(
                      color: CupertinoColors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Private, local, and ready when you are.',
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
                    ProgressTrack(
                      value: progress,
                      height: 4,
                      trackColor: CupertinoColors.white.withValues(alpha: 0.12),
                      fillColor: GolemTheme.accent.darkColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      caption,
                      textAlign: TextAlign.center,
                      style: GolemText.caption.copyWith(
                        color: GolemTheme.mutedOnDark,
                      ),
                    ),
                    if (retry != null) ...[
                      const SizedBox(height: 14),
                      GolemButton.filled(
                        key: const Key('splash-retry'),
                        label: 'Try again',
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
