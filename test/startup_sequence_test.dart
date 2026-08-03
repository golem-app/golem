import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
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

  test('failure recovers into explicit failed state', () async {
    final result = await sequence.run(StartupScenario.failure);
    expect(result.phase, StartupPhase.failed);
  });

  test('timeout caps loading with failure', () async {
    final result = await sequence.run(StartupScenario.timeout);
    expect(result.phase, StartupPhase.failed);
  });

  test('missing model holds for injected delay', () async {
    final watch = Stopwatch()..start();
    final result = await sequence.run(StartupScenario.missingModel);
    expect(result.phase, StartupPhase.complete);
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(18));
  });
}
