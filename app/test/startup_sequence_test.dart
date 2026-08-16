import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/startup/startup_sequence.dart';

void main() {
  const sequence = StartupSequence(
    minimum: Duration(milliseconds: 10),
    missingModelDelay: Duration(milliseconds: 20),
    timeout: Duration(milliseconds: 15),
  );

  test('ready respects minimum splash time', () async {
    final watch = Stopwatch()..start();
    final result = await sequence.run(StartupScenario.ready);
    expect(result.phase, StartupPhase.complete);
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(8));
  });

  test('the shipped splash floor is 1.4 seconds', () {
    // Not the harness's shortened one: this is the figure the splash actually
    // holds for, and shortening or negating it is invisible to every other
    // assertion here because they all bound from below.
    expect(const StartupSequence().minimum, const Duration(milliseconds: 1400));
  });

  test('failure recovers into explicit failed state', () async {
    final result = await sequence.run(StartupScenario.failure);
    expect(result.phase, StartupPhase.failed);
    // The bar stops where the failure found it; a negative fraction would draw
    // an empty groove and read as "nothing happened" rather than "it broke".
    expect(result.progress, 0.42);
  });

  test('timeout caps loading with failure', () async {
    final result = await sequence.run(StartupScenario.timeout);
    expect(result.phase, StartupPhase.failed);
    expect(result.progress, 0.86);
  });

  test('missing model holds for injected delay', () async {
    final watch = Stopwatch()..start();
    final result = await sequence.run(StartupScenario.missingModel);
    expect(result.phase, StartupPhase.complete);
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(18));
  });

  test('production ignores every scripted startup scenario', () {
    expect(
      startupScenarioFor(
        identity: AppIdentity.production,
        missingModel: true,
        injectedFailure: true,
        injectedTimeout: true,
      ),
      StartupScenario.ready,
    );
  });

  test('qa and dev retain scripted startup scenarios', () {
    for (final identity in [AppIdentity.qa, AppIdentity.dev]) {
      expect(
        startupScenarioFor(
          identity: identity,
          missingModel: false,
          injectedFailure: true,
          injectedTimeout: false,
        ),
        StartupScenario.failure,
      );
    }
  });
}
