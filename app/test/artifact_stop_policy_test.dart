import 'package:background_downloader/background_downloader.dart'
    show TaskStatus;
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/services/artifact_stop_policy.dart';

/// The intent half of the downloader adapter.
///
/// Nothing else could reach it: `BackgroundArtifactDownloader` talks to a
/// static `FileDownloader` over a platform channel, so the whole adapter sits
/// off-limits to a host test and this rule — which decides whether a stop was
/// commanded by the app — was inside that shadow. It was also wrong, for the life of
/// #125: recorded under a task id and read back under a destination path.
void main() {
  const one = TaskId('task-1');
  const two = TaskId('task-2');

  group('the ledger', () {
    test('a commanded stop is visible to its own generation only', () {
      final stops = CommandedStops()..commandPause(one);

      expect(stops.of(one).pause, isTrue);
      expect(stops.of(two).pause, isFalse);
    });

    test('a pause and a cancel on one generation are both remembered', () {
      // Not a ranking: a cancel issued while the pause is still confirming
      // must not make the platform's answer to the pause look uncommanded.
      final stops = CommandedStops()
        ..commandPause(one)
        ..commandCancel(one);

      expect(stops.of(one).pause, isTrue);
      expect(stops.of(one).cancel, isTrue);
    });

    test('a rolled-back pause leaves a cancel issued beside it', () {
      final stops = CommandedStops()
        ..commandPause(one)
        ..commandCancel(one)
        ..forgetPause(one);

      expect(stops.of(one).pause, isFalse);
      expect(stops.of(one).cancel, isTrue);
    });

    test('a stop of either kind left behind is still a leak', () {
      final stops = CommandedStops()..commandCancel(one);
      expect(stops.isEmpty, isFalse);

      // The rollback for the other command must not be mistaken for cleanup.
      stops.forgetPause(one);
      expect(stops.isEmpty, isFalse);

      stops.forgetCancel(one);
      expect(stops.isEmpty, isTrue);
    });

    test('nothing outlives its generation', () {
      final stops = CommandedStops()
        ..commandPause(one)
        ..commandCancel(two);
      expect(stops.isEmpty, isFalse);

      stops
        ..forget(one)
        ..forget(two);

      expect(stops.isEmpty, isTrue);
      expect(stops.of(one).pause, isFalse);
      expect(stops.of(two).cancel, isFalse);
    });
  });

  group('the verdict', () {
    test('a pause the app commanded ends the stream at once', () {
      expect(
        verdictFor(
          status: TaskStatus.paused,
          commanded: const CommandedStop(pause: true),
        ),
        StopVerdict.userPaused,
      );
    });

    test('a pause nobody commanded waits out its grace', () {
      expect(
        verdictFor(status: TaskStatus.paused, commanded: CommandedStop.none),
        StopVerdict.uncommandedPause,
      );
    });

    test('a cancel the app commanded is reported as user-initiated', () {
      expect(
        verdictFor(
          status: TaskStatus.canceled,
          commanded: const CommandedStop(cancel: true),
        ),
        StopVerdict.userCanceled,
      );
    });

    test(
      'a cancel nobody commanded is the platform discarding the partial',
      () {
        expect(
          verdictFor(
            status: TaskStatus.canceled,
            commanded: CommandedStop.none,
          ),
          StopVerdict.uncommandedCancel,
        );
      },
    );

    test('a pause command does not claim a cancel the platform made', () {
      expect(
        verdictFor(
          status: TaskStatus.canceled,
          commanded: const CommandedStop(pause: true),
        ),
        StopVerdict.uncommandedCancel,
      );
    });

    test('completion and progress carry no intent', () {
      for (final status in [
        TaskStatus.complete,
        TaskStatus.failed,
        TaskStatus.notFound,
        TaskStatus.enqueued,
        TaskStatus.running,
        TaskStatus.waitingToRetry,
      ]) {
        expect(
          verdictFor(
            status: status,
            commanded: const CommandedStop(cancel: true),
          ),
          StopVerdict.notAStop,
          reason: '$status is not a stop whatever was commanded',
        );
      }
    });
  });
}
