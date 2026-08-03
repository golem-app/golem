import '../domain/app_state.dart';

enum StartupScenario { ready, failure, timeout, missingModel }

final class StartupSequence {
  const StartupSequence({
    this.minimum = const Duration(milliseconds: 1400),
    this.missingModelDelay = const Duration(seconds: 3),
    this.timeout = const Duration(seconds: 8),
  });

  final Duration minimum;
  final Duration missingModelDelay;
  final Duration timeout;

  Future<StartupState> run(StartupScenario scenario) async {
    final started = DateTime.now();
    if (scenario == StartupScenario.failure) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return const StartupState(phase: StartupPhase.failed, progress: 0.42);
    }
    if (scenario == StartupScenario.timeout) {
      await Future<void>.delayed(timeout);
      return const StartupState(phase: StartupPhase.failed, progress: 0.86);
    }
    if (scenario == StartupScenario.missingModel) {
      await Future<void>.delayed(missingModelDelay);
    }
    final elapsed = DateTime.now().difference(started);
    final remaining = minimum - elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    return const StartupState(phase: StartupPhase.complete, progress: 1);
  }
}
