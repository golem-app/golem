import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/app_identity.dart';
import '../../../core/domain/app_state.dart';
import '../../../core/providers/retry.dart';
import '../../../core/startup/startup_sequence.dart';

part 'startup_providers.g.dart';

/// KeepAlive: the startup outcome is process-lifetime. This is the scripted
/// splash theatre (minimum hold, progress ticks, injected demo scenarios);
/// real launch failures and their retry live before this scope exists, in
/// the bootstrap gate (docs/decisions/0006-launch-bootstrap.md).
@Riverpod(keepAlive: true, retry: noRetry)
class StartupController extends _$StartupController {
  static const missingModel = bool.fromEnvironment('GOLEM_MISSING_MODEL');
  static const injectedFailure = bool.fromEnvironment('GOLEM_SPLASH_FAILURE');
  static const injectedTimeout = bool.fromEnvironment('GOLEM_SPLASH_TIMEOUT');

  @override
  Future<StartupState> build() async {
    state = const AsyncData(StartupState(progress: 0.18));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    state = const AsyncData(
      StartupState(phase: StartupPhase.preloading, progress: 0.72),
    );
    final scenario = startupScenarioFor(
      identity: AppIdentity.current,
      missingModel: missingModel,
      injectedFailure: injectedFailure,
      injectedTimeout: injectedTimeout,
    );
    if (scenario == StartupScenario.missingModel) {
      state = const AsyncData(
        StartupState(phase: StartupPhase.missingModel, progress: 0.86),
      );
    }
    return const StartupSequence().run(scenario);
  }

  Future<void> retry() async {
    state = const AsyncData(StartupState(progress: 0.2));
    // Recovery deliberately succeeds: the injected failure exists to show the
    // failure UI, retry the recovery path — with real StartupSequence timing.
    final result = await const StartupSequence().run(StartupScenario.ready);
    if (!ref.mounted) return;
    state = AsyncData(result);
  }
}
