/// Which stop the app commanded for a transfer, and what a platform status
/// update means once that is known.
///
/// Split out of `artifact_downloader.dart` for the reason
/// `artifact_adoption_policy.dart` and `artifact_task_metadata.dart` were: the
/// adapter reaches a static `FileDownloader` over a platform channel and
/// cannot be exercised off a device, while the rules below decide correctness
/// on their own.
library;

import 'package:background_downloader/background_downloader.dart'
    show TaskStatus;

/// The plugin's identifier for one transfer generation.
///
/// A type rather than a bare `String` because the defect this replaces was
/// exactly that: intent was recorded under `task.taskId` and looked up under
/// the file's destination path, both plain strings, so the mismatch compiled
/// and every commanded stop was invisible for the life of the process.
extension type const TaskId(String value) {}

/// What the app asked the platform to do to a transfer, if anything.
enum CommandedStop { none, pause, cancel }

/// The stops the app has commanded and not yet seen through, by generation.
///
/// Keyed by task id, not destination: a commanded stop belongs to the exact
/// generation it was issued for. Keying by destination let an entry survive a
/// pause taken while no stream was attached, and the *next* transfer's
/// uncommanded pause — Android's ~9-minute transfer-service timeout — was then
/// reported as the user's own, so nothing persisted it and the card stranded
/// on "downloading".
final class CommandedStops {
  final Set<TaskId> _paused = {};
  final Set<TaskId> _canceled = {};

  /// Cancel outranks pause: cancelling an already-paused transfer is the
  /// ordinary way to abandon one, and the platform then reports only a cancel.
  CommandedStop of(TaskId id) {
    if (_canceled.contains(id)) return CommandedStop.cancel;
    if (_paused.contains(id)) return CommandedStop.pause;
    return CommandedStop.none;
  }

  void commandPause(TaskId id) => _paused.add(id);

  void commandCancel(TaskId id) => _canceled.add(id);

  /// Rollbacks are per command, not a blanket drop: a pause whose platform
  /// call was refused must not erase a cancel the user issued while it was in
  /// flight.
  void forgetPause(TaskId id) => _paused.remove(id);

  void forgetCancel(TaskId id) => _canceled.remove(id);

  /// The generation is over. Every path that records a stop must reach this or
  /// a rollback, or the entry outlives the process.
  void forget(TaskId id) {
    _paused.remove(id);
    _canceled.remove(id);
  }

  /// Exists so a test can prove the bookkeeping does not leak between
  /// transfers — which a private static set never allowed.
  bool get isEmpty => _paused.isEmpty && _canceled.isEmpty;
}

/// What a status update means for the file's stream, once intent is known.
enum StopVerdict {
  /// End the stream at once as user-initiated; `pause()` already persisted it
  /// out of band.
  userPaused,

  /// A pause nobody commanded — network loss, an OS timeout. Not believed
  /// immediately: the plugin resumes some of these on its own, so the caller
  /// waits out its grace first.
  uncommandedPause,

  userCanceled,
  uncommandedCancel,

  /// Not a stop; completion and failure carry no intent and are mapped by the
  /// caller.
  notAStop,
}

StopVerdict verdictFor({
  required TaskStatus status,
  required CommandedStop commanded,
}) => switch (status) {
  TaskStatus.paused =>
    commanded == CommandedStop.pause
        ? StopVerdict.userPaused
        : StopVerdict.uncommandedPause,
  TaskStatus.canceled =>
    commanded == CommandedStop.cancel
        ? StopVerdict.userCanceled
        : StopVerdict.uncommandedCancel,
  TaskStatus.complete ||
  TaskStatus.failed ||
  TaskStatus.notFound ||
  TaskStatus.enqueued ||
  TaskStatus.running ||
  TaskStatus.waitingToRetry => StopVerdict.notAStop,
};
