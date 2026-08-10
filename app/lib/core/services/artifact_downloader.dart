import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';

import 'artifact_adoption_policy.dart';

export 'artifact_adoption_policy.dart';

/// Identifies one artifact file's transfer, in app terms only.
///
/// Deliberately carries no task id: the plugin's identifiers are an adapter
/// concern, and a stable one would be actively harmful (see
/// [BackgroundArtifactDownloader]). [sourceUrl] is the resolved
/// `resolve/<revision>/` URL, which already accounts for a file's per-file
/// repository and revision overrides, so it identifies both the bytes wanted
/// and the commit they come from.
final class ArtifactFileRef {
  const ArtifactFileRef({
    required this.artifactKey,
    required this.sourceUrl,
    required this.directory,
    required this.filename,
    required this.expectedBytes,
  });

  final String artifactKey;
  final String sourceUrl;

  /// Relative to the app documents directory.
  final String directory;
  final String filename;
  final int expectedBytes;

  String get destination => '$directory/$filename';
}

/// Events emitted while one artifact file downloads.
sealed class ArtifactFileEvent {
  const ArtifactFileEvent();
}

final class ArtifactFileProgress extends ArtifactFileEvent {
  const ArtifactFileProgress(this.bytesReceived);
  final int bytesReceived;
}

final class ArtifactFileComplete extends ArtifactFileEvent {
  const ArtifactFileComplete();
}

final class ArtifactFilePaused extends ArtifactFileEvent {
  const ArtifactFilePaused({this.userInitiated = true, this.resumable = true});

  /// False when the OS or plugin paused the task uncommanded (network loss,
  /// Android's transfer-service timeout) — the repository must then persist
  /// the paused state itself, since no out-of-band pause() call did.
  final bool userInitiated;

  /// False when no partial data survives, so the repository must report only
  /// the bytes it has already verified rather than crediting a lost partial.
  final bool resumable;
}

final class ArtifactFileCanceled extends ArtifactFileEvent {
  const ArtifactFileCanceled({this.userInitiated = true});
  final bool userInitiated;
}

final class ArtifactFileFailed extends ArtifactFileEvent {
  const ArtifactFileFailed(this.message);
  final String message;
}

/// Downloads one file at a time into the app documents directory. The
/// repository sequences files, verifies hashes, and owns all state; this
/// seam only moves bytes and reports what the platform knows, so tests can
/// script both.
abstract interface class ArtifactFileDownloader {
  /// Prepares the process-wide downloader: attaches the update listener,
  /// enables task tracking, and drains updates delivered while Dart was gone.
  /// Idempotent, and every other method calls it, so a caller that forgets
  /// cannot get a half-initialized downloader.
  Future<void> initialize();

  /// Streams progress until the file completes, pauses, cancels, or fails.
  /// Adopts an existing transfer for [ref] rather than starting a second one.
  Stream<ArtifactFileEvent> download(ArtifactFileRef ref);

  /// Pauses [ref]'s transfer, keeping partial data for a later [download].
  /// True only when the platform confirmed it — a false answer means bytes may
  /// still be moving, and the caller must not claim the transfer is paused.
  Future<bool> pause(ArtifactFileRef ref);

  /// Cancels [ref]'s transfer and discards its partial data. True only once
  /// the platform no longer holds the task, so a caller may safely delete the
  /// destination directory afterwards.
  Future<bool> cancel(ArtifactFileRef ref);

  /// What the platform still knows about [ref]. Starts, resumes, cancels and
  /// verifies nothing.
  Future<ArtifactTransferSnapshot> inspect(ArtifactFileRef ref);
}

/// background_downloader implementation: URLSession on iOS/macOS and
/// DownloadWorker on Android, so multi-gigabyte downloads survive screen lock
/// and backgrounding. allowPause is mandatory — Android hard-stops plain
/// downloads after ~9 minutes, and with allowPause the plugin auto-pauses and
/// resumes to complete the file.
///
/// Identity is carried in [Task.metaData] and a dedicated group, never in the
/// task id. A stable task id looks like the obvious reconciliation key and is
/// a trap: enqueue is not unique-by-id on either platform, enqueueing an id
/// clears its pending cancel flag, cancel is by-id across generations, and
/// `Task ==` is id-only — so reusing an id lets a dying transfer un-cancel
/// itself, lets a late cancel kill its successor, and lets a stale terminal
/// update tear down a healthy stream.
final class BackgroundArtifactDownloader implements ArtifactFileDownloader {
  BackgroundArtifactDownloader({
    this.uncommandedPauseGrace = const Duration(seconds: 15),
    this.stallTimeout = const Duration(minutes: 5),
    this.platformCallTimeout = const Duration(seconds: 20),
    this.confirmationTimeout = const Duration(seconds: 10),
    this.temporaryDirectories = const [],
  });

  /// Group for every model transfer. Never the plugin's default group (which
  /// would collect unrelated tasks) and never its reserved chunk group.
  static const _group = 'golem-models';

  /// Constructed here rather than reached through `FileDownloader()` so this
  /// process keeps a reference to the store holding paused tasks and resume
  /// data. The plugin asserts if storage is supplied after its singleton
  /// exists, so this chain — storage, then downloader, then updates — is the
  /// only construction path in the app.
  static final PersistentStorage _storage = LocalStorePersistentStorage();
  static final FileDownloader _downloader = FileDownloader(
    persistentStorage: _storage,
  );

  // FileDownloader().updates is single-subscription; every per-file await-for
  // must tap one shared broadcast of it, created once per process.
  static final Stream<TaskUpdate> _updates = _downloader.updates
      .asBroadcastStream();

  static Future<void>? _ready;
  static StreamSubscription<TaskUpdate>? _permanent;

  /// Terminal statuses seen while no per-file stream was attached, keyed by
  /// destination. Broadcast streams do not replay, and startup fires the whole
  /// backlog of `trackTasks` and `resumeFromBackground` before any download()
  /// exists — without this, a file that finished in the background would
  /// produce no event and stall until the watchdog gave up on it.
  static final Map<String, TaskStatusUpdate> _terminal = {};

  /// How long an uncommanded pause may sit before it is surfaced as a real
  /// pause. Android's ~9-minute transfer-service timeout pauses the task and
  /// the plugin resumes it moments later; finalizing on the first pause event
  /// would flip the card to "Paused" every cycle on slow connections.
  final Duration uncommandedPauseGrace;

  /// Silence after which the platform is re-probed. Never itself a verdict:
  /// the transfer is only reported stopped once a probe proves the platform
  /// holds nothing. The floor is deliberately well above iOS's own 60s request
  /// timeout and the plugin's 2/4/8s retry ladder, and above the stretches
  /// where Android's WorkManager legitimately sits silent on a network
  /// constraint — firing early would report Paused over a live writer.
  final Duration stallTimeout;

  /// Bound on any single method-channel call. Without it a stuck platform call
  /// holds the controller's busy flag forever, which disables the memory-relief
  /// path and the user's own escape hatch.
  final Duration platformCallTimeout;

  /// How long to wait for the platform to confirm a pause or cancel. Android's
  /// native pause returns true unconditionally, so the boolean is not proof.
  final Duration confirmationTimeout;

  /// Directories that may hold the plugin's partial-transfer files, swept for
  /// orphans at startup. Empty disables the sweep; the composition root passes
  /// the real paths.
  final List<String> temporaryDirectories;

  @override
  Future<void> initialize() => _ready ??= _initialize();

  Future<void> _initialize() async {
    // Attached before start() and never cancelled: the plugin drops updates
    // outright when its stream has no listener, so this subscription is what
    // makes the database and the replay map trustworthy.
    _permanent ??= _updates.listen(_recordTerminal);
    await _downloader.start(
      doTrackTasks: true,
      markDownloadedComplete: true,
      // The app decides what restarts. rescheduleKilledTasks re-enqueues
      // killed tasks on its own, producing a writer the repository never
      // sequenced and no hash gate governs.
      doRescheduleKilledTasks: false,
      // Its defaults drop records older than ten days, which is exactly the
      // record a long-paused multi-gigabyte download is recovered through.
      autoCleanDatabase: false,
    );
    await _sweepOrphanedPartials();
  }

  static void _recordTerminal(TaskUpdate update) {
    if (update is! TaskStatusUpdate || !update.status.isFinalState) return;
    final destination = _destinationOf(update.task);
    if (destination != null) _terminal[destination] = update;
  }

  static String? _destinationOf(Task task) {
    try {
      final meta = jsonDecode(task.metaData) as Map<String, Object?>;
      return meta['path'] as String?;
    } catch (_) {
      return null;
    }
  }

  DownloadTask _taskFor(ArtifactFileRef ref) => DownloadTask(
    url: ref.sourceUrl,
    directory: ref.directory,
    filename: ref.filename,
    baseDirectory: BaseDirectory.applicationDocuments,
    group: _group,
    metaData: jsonEncode({
      'key': ref.artifactKey,
      'path': ref.destination,
      'url': ref.sourceUrl,
    }),
    updates: Updates.statusAndProgress,
    allowPause: true,
    retries: 3,
  );

  /// The live or paused task targeting [ref]'s destination, whichever the
  /// platform holds. Matched on metaData, so generations never alias.
  Future<Task?> _platformTask(ArtifactFileRef ref) async {
    for (final task in await _guard(
      () => _downloader.allTasks(group: _group),
      const <Task>[],
    )) {
      if (_destinationOf(task) == ref.destination) return task;
    }
    for (final task in await _guard(
      () => _downloader.database.allRecords(group: _group),
      const <TaskRecord>[],
    ).then((records) => records.map((record) => record.task))) {
      if (_destinationOf(task) == ref.destination) return task;
    }
    return null;
  }

  Future<T> _guard<T>(Future<T> Function() call, T fallback) async {
    try {
      return await call().timeout(platformCallTimeout);
    } catch (_) {
      return fallback;
    }
  }

  @override
  Future<ArtifactTransferSnapshot> inspect(ArtifactFileRef ref) async {
    await initialize();
    return _snapshot(ref);
  }

  /// Unions the plugin's four stores. Any one alone gives a wrong answer: after
  /// a force-stop the database still reports `running` while the only surviving
  /// state is the resume data, and a long-paused task outlives its record.
  Future<ArtifactTransferSnapshot> _snapshot(ArtifactFileRef ref) async {
    final task = await _platformTask(ref);
    if (task == null) return const ArtifactTransferSnapshot();

    final resumeData = await _guard(
      () => _storage.retrieveResumeData(task.taskId),
      null,
    );
    final resumable = resumeData != null;
    final record = await _guard(
      () => _downloader.database.recordForId(task.taskId),
      null,
    );

    var received = resumeData?.requiredStartByte;
    if (received == null && record != null && record.progress > 0) {
      received = (record.progress * ref.expectedBytes).round();
    }

    final live = await _guard(
      () => _downloader.allTasks(group: _group),
      const <Task>[],
    );
    final isLive = live.any((each) => each.taskId == task.taskId);
    final paused = (await _guard(
      () => _storage.retrieveAllPausedTasks(),
      const <Task>[],
    )).any((each) => each.taskId == task.taskId);

    final presence = switch (record?.status) {
      _ when paused => ArtifactTransferPresence.paused,
      TaskStatus.waitingToRetry => ArtifactTransferPresence.waitingToRetry,
      _ when isLive => ArtifactTransferPresence.running,
      TaskStatus.complete ||
      TaskStatus.failed ||
      TaskStatus.canceled ||
      TaskStatus.notFound => ArtifactTransferPresence.finished,
      _ => ArtifactTransferPresence.absent,
    };

    return ArtifactTransferSnapshot(
      presence: presence,
      receivedBytes: received,
      resumable: resumable,
    );
  }

  Future<bool> _destinationComplete(ArtifactFileRef ref) async {
    final path = await _documentsPath(ref);
    if (path == null) return false;
    final file = File(path);
    return await file.exists() && await file.length() == ref.expectedBytes;
  }

  /// The plugin owns the mapping from [BaseDirectory.applicationDocuments] to
  /// a real path, so the destination is resolved through its own join rather
  /// than re-derived here.
  Future<String?> _documentsPath(ArtifactFileRef ref) async {
    try {
      return await _taskFor(ref).filePath();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<ArtifactFileEvent> download(ArtifactFileRef ref) async* {
    // Subscribed before any await: broadcast streams do not replay, and the
    // decision below makes several method-channel round trips a terminal
    // update could otherwise slip through.
    final buffer = StreamController<Object>();
    final subscription = _updates.listen(buffer.add);
    Timer? watchdog;
    Timer? pauseFinalize;
    try {
      await initialize();

      final decision = decideArtifactTransfer(
        platform: await _snapshot(ref),
        destinationComplete: await _destinationComplete(ref),
      );

      final existing = await _platformTask(ref);
      Task task;
      switch (decision.action) {
        case ArtifactTransferAction.alreadyComplete:
          // Residue from a previous generation would keep writing over a file
          // that is already whole.
          if (existing != null) {
            await _guard(
              () => _downloader.cancelTaskWithId(existing.taskId),
              false,
            );
          }
          yield const ArtifactFileComplete();
          return;

        case ArtifactTransferAction.adopt:
          if (existing == null) {
            yield const ArtifactFileFailed('The download could not be found.');
            return;
          }
          task = existing;
          if (decision.bytesOnPlatform > 0) {
            yield ArtifactFileProgress(decision.bytesOnPlatform);
          }

        case ArtifactTransferAction.resume:
          // A resume the platform refuses is not a failure: the partial is
          // simply gone, and a fresh transfer is the correct fallback.
          if (existing is DownloadTask &&
              await _guard(() => _downloader.resume(existing), false)) {
            task = existing;
            if (decision.bytesOnPlatform > 0) {
              yield ArtifactFileProgress(decision.bytesOnPlatform);
            }
          } else {
            final started = await _restart(ref, existing);
            if (started == null) {
              yield const ArtifactFileFailed('Could not start the download.');
              return;
            }
            task = started;
          }

        case ArtifactTransferAction.replace:
        case ArtifactTransferAction.start:
          final started = await _restart(ref, existing);
          if (started == null) {
            yield const ArtifactFileFailed('Could not start the download.');
            return;
          }
          task = started;
      }

      final taskId = task.taskId;
      // A terminal status recorded before this stream attached — a background
      // completion, or one replayed by resumeFromBackground at startup.
      final replayed = _terminal.remove(ref.destination);
      if (replayed != null && replayed.task.taskId == taskId) {
        final event = _terminalEvent(replayed, userPause: false);
        if (event != null) {
          yield event;
          return;
        }
      }

      void arm() {
        watchdog?.cancel();
        watchdog = Timer(stallTimeout, () => buffer.add(_probe));
      }

      arm();
      await for (final update in buffer.stream) {
        if (identical(update, _probe)) {
          // The file may have landed while the update that said so was lost —
          // a terminal delivered to a listener that no longer existed, which is
          // exactly what silence over a finished transfer looks like.
          if (await _destinationComplete(ref)) {
            yield const ArtifactFileComplete();
            return;
          }
          final snapshot = await _snapshot(ref);
          if (snapshot.presence == ArtifactTransferPresence.absent) {
            // Proven gone rather than merely quiet: the only point at which
            // silence becomes an actionable state.
            yield ArtifactFilePaused(
              userInitiated: false,
              resumable: snapshot.resumable,
            );
            return;
          }
          arm();
          continue;
        }
        if (identical(update, _finalizePause)) {
          final snapshot = await _snapshot(ref);
          yield ArtifactFilePaused(
            userInitiated: false,
            resumable: snapshot.resumable,
          );
          return;
        }
        if (update is! TaskUpdate || update.task.taskId != taskId) continue;

        // Any real update supersedes a pending uncommanded pause — the plugin
        // resumed it on its own — and proves the transfer is not stalled.
        pauseFinalize?.cancel();
        pauseFinalize = null;
        arm();

        // Read per update, not carried between them: an out-of-band pause or
        // cancel lands between iterations, and the platform event it causes is
        // the very next one — a stale flag would report the user's own stop as
        // uncommanded and strand the card.
        final userPause = _userPaused.contains(ref.destination);
        final userCancel = _userCanceled.contains(ref.destination);

        switch (update) {
          case TaskProgressUpdate(:final progress) when progress >= 0:
            yield ArtifactFileProgress((progress * ref.expectedBytes).round());
          case TaskProgressUpdate():
            break;
          case TaskStatusUpdate():
            switch (update.status) {
              case TaskStatus.paused:
                if (userPause) {
                  yield const ArtifactFilePaused();
                  return;
                }
                pauseFinalize = Timer(
                  uncommandedPauseGrace,
                  () => buffer.add(_finalizePause),
                );
              case TaskStatus.canceled:
                yield ArtifactFileCanceled(userInitiated: userCancel);
                return;
              default:
                final event = _terminalEvent(update, userPause: userPause);
                if (event != null) {
                  yield event;
                  return;
                }
            }
        }
      }
    } finally {
      watchdog?.cancel();
      pauseFinalize?.cancel();
      _userPaused.remove(ref.destination);
      _userCanceled.remove(ref.destination);
      await subscription.cancel();
      await buffer.close();
    }
  }

  ArtifactFileEvent? _terminalEvent(
    TaskStatusUpdate update, {
    required bool userPause,
  }) => switch (update.status) {
    TaskStatus.complete => const ArtifactFileComplete(),
    TaskStatus.canceled => const ArtifactFileCanceled(userInitiated: false),
    TaskStatus.paused => ArtifactFilePaused(userInitiated: userPause),
    TaskStatus.failed || TaskStatus.notFound => ArtifactFileFailed(
      update.exception?.description ?? 'The download failed.',
    ),
    TaskStatus.enqueued ||
    TaskStatus.running ||
    TaskStatus.waitingToRetry => null,
  };

  /// Cancels whatever the platform holds for this destination, waits for the
  /// cancellation to land, then enqueues fresh. The wait is what keeps a dying
  /// task from writing over the new one's file.
  Future<DownloadTask?> _restart(ArtifactFileRef ref, Task? existing) async {
    if (existing != null) {
      await _cancelAndConfirm(ref, existing);
    }
    final task = _taskFor(ref);
    return await _guard(() => _downloader.enqueue(task), false) ? task : null;
  }

  Future<bool> _cancelAndConfirm(ArtifactFileRef ref, Task task) async {
    await _guard(() => _downloader.cancelTaskWithId(task.taskId), false);
    final deadline = DateTime.now().add(confirmationTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _platformTask(ref) == null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return await _platformTask(ref) == null;
  }

  /// Destinations whose stop was commanded by the app, so the resulting
  /// platform event is reported as user-initiated. Keyed by destination
  /// because task ids change between generations.
  static final Set<String> _userPaused = {};
  static final Set<String> _userCanceled = {};

  static const _finalizePause = Object();
  static const _probe = Object();

  @override
  Future<bool> pause(ArtifactFileRef ref) async {
    await initialize();
    final task = await _platformTask(ref);
    if (task is! DownloadTask) return false;
    _userPaused.add(ref.destination);
    if (!await _guard(() => _downloader.pause(task), false)) {
      _userPaused.remove(ref.destination);
      return false;
    }
    // Android's native pause returns true even for a task it does not hold, and
    // a task that is enqueued but not yet running consumes the request without
    // ever emitting a paused status. Only the store is proof.
    final deadline = DateTime.now().add(confirmationTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final paused = await _guard(
        () => _storage.retrieveAllPausedTasks(),
        const <Task>[],
      );
      if (paused.any((each) => each.taskId == task.taskId)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _userPaused.remove(ref.destination);
    return false;
  }

  @override
  Future<bool> cancel(ArtifactFileRef ref) async {
    await initialize();
    final task = await _platformTask(ref);
    if (task == null) return true;
    _userCanceled.add(ref.destination);
    return _cancelAndConfirm(ref, task);
  }

  /// Deletes partial-transfer files no live resume data refers to.
  ///
  /// A hard kill during a multi-gigabyte download leaves its partial behind
  /// forever: the plugin sweeps nothing, the Storage screen cannot see these
  /// files, and the disk-space preflight eventually refuses the very download
  /// that is leaking. Runs after start() has restored resume data, so a
  /// resumable partial is never mistaken for an orphan.
  Future<void> _sweepOrphanedPartials() async {
    if (temporaryDirectories.isEmpty) return;
    final live = <String>{};
    for (final data in await _guard(
      () => _storage.retrieveAllResumeData(),
      const <ResumeData>[],
    )) {
      live.add(data.tempFilepath);
    }
    for (final path in temporaryDirectories) {
      final directory = Directory(path);
      if (!await directory.exists()) continue;
      try {
        await for (final entry in directory.list(followLinks: false)) {
          if (entry is! File) continue;
          final name = entry.uri.pathSegments.last;
          if (!name.startsWith('com.bbflight.background_downloader')) continue;
          if (live.contains(entry.path)) continue;
          try {
            await entry.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }
  }
}
