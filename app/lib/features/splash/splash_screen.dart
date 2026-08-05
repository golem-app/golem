import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/app_state.dart';
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
              isLoading: startup.isLoading,
              retry: () => ref.read(startupControllerProvider.notifier).retry(),
            ),
          ),
      ],
    );
  }
}

class SplashScreen extends ConsumerWidget {
  const SplashScreen({
    required this.state,
    required this.isLoading,
    required this.retry,
    super.key,
  });
  final StartupState state;
  final bool isLoading;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = state.phase == StartupPhase.failed;
    final missing = state.phase == StartupPhase.missingModel;
    // Honest in both directions: only a simulated backend may claim to be
    // one, and a real-engine build must never say "simulated".
    final simulated = ref.watch(inferenceBackendProvider).simulatedInference;
    final model = simulated ? 'simulated model' : 'model';
    return Semantics(
      key: const Key('launch-splash'),
      label: 'Golem',
      value: failed
          ? (simulated ? 'Simulated loading failed' : 'Loading failed')
          : missing
          ? 'No $model selected; preparing setup'
          : 'Loading $model on this device',
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
                  const Text(
                    'Golem',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Private, local, and ready when you are.',
                    style: TextStyle(
                      color: GolemTheme.mutedOnDark,
                      fontSize: 17,
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
                      value: state.progress,
                      height: 4,
                      trackColor: CupertinoColors.white.withValues(alpha: 0.12),
                      fillColor: GolemTheme.accent.darkColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      failed
                          ? 'The $model could not be prepared'
                          : missing
                          ? 'Preparing $model setup'
                          : 'Loading $model on this device',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: GolemTheme.mutedOnDark,
                        fontSize: 13,
                      ),
                    ),
                    if (failed) ...[
                      const SizedBox(height: 14),
                      CupertinoButton.filled(
                        key: const Key('splash-retry'),
                        onPressed: retry,
                        child: const Text('Try again'),
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
