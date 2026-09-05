import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';

import 'artifact_adoption_policy.dart';
import 'artifact_stop_policy.dart';
import 'artifact_task_metadata.dart';

export 'artifact_adoption_policy.dart';
// Only the ref: the metadata helpers were private statics here before the
// split, and the whole premise of the file they moved to is that a task's
// identity is this adapter's business. Re-exporting them would let a
// repository hand-roll a metadata blob outside the adapter that owns the rule.
export 'artifact_task_metadata.dart' show ArtifactFileRef;

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

/// The task the platform holds for a transfer, resolved together with what is
/// known about it — so a decision and its execution cannot act on different
/// tasks.
final class _ResolvedTransfer {
  const _ResolvedTransfer(this.task, this.snapshot);
  final Task? task;
  final ArtifactTransferSnapshot snapshot;
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

/// Where the plugin lands a transfer, in its own terms. The plugin resolves
/// the base directory itself, so the repository's `documentsDirectory` must
/// name the same place — the phone flavors' documents directory, or, for the
/// lab, `Documents` under the bundle-scoped application support directory
/// (ADR 0021): on an unsandboxed Mac the documents directory is the user's
/// real `~/Documents`, shared by every flavor.
enum ArtifactDownloadRoot { documents, applicationSupport }

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
    this.root = ArtifactDownloadRoot.documents,
    this.subdirectory = '',
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

  /// Static, like the plugin handles above them, and deliberately not instance
  /// fields (#131). `launch_composition` builds a fresh downloader on every
  /// composition attempt and four integration suites build their own, so per
  /// instance this readiness would re-run `trackTasks` and
  /// `resumeFromBackground` against one shared platform queue, and the
  /// [_terminal] backlog below — which exists precisely because those calls
  /// fire before any `download()` is listening — would be dropped by whichever
  /// instance did not record it.
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

  /// The plugin base directory every task is placed under, and the path
  /// inside it that an [ArtifactFileRef.directory] is relative to ('' for
  /// the base itself). Together they must resolve to the repository's
  /// `documentsDirectory`, or downloads land where verification never looks.
  final ArtifactDownloadRoot root;
  final String subdirectory;

  @override
  Future<void> initialize() async {
    // A failure is never cached: storing the rejected future would make every
    // later inspect() throw, which reconciliation turns into an AsyncError and
    // a permanently blank Models screen.
    try {
      await (_ready ??= _initialize());
    } catch (_) {
      _ready = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    // Attached before start() and never cancelled: the plugin drops updates
    // outright when its stream has no listener, so this subscription is what
    // makes the database and the replay map trustworthy.
    _permanent ??= _updates.listen(_recordTerminal);
    // Bounded so a hung start throws instead of parking a forever-pending
    // future in _ready — a caller that stopped waiting must find a cleared
    // slot, or "the next call retries the start" would be a lie.
    await _downloader
        .start(
          doTrackTasks: true,
          markDownloadedComplete: true,
          // The app decides what restarts. rescheduleKilledTasks re-enqueues
          // killed tasks on its own, producing a writer the repository never
          // sequenced and no hash gate governs.
          doRescheduleKilledTasks: false,
          // Its defaults drop records older than ten days, which is exactly
          // the record a long-paused multi-gigabyte download is recovered
          // through.
          autoCleanDatabase: false,
        )
        .timeout(platformCallTimeout);
    await _pruneFinishedRecords();
    await _sweepOrphanedPartials();
  }

  /// Drops tracking records for transfers that have ended.
  ///
  /// Automatic cleanup is off (it would drop the record a long-paused download
  /// is recovered through), so without this one record accumulates per
  /// generation per file forever — and `start()` stats every one of them on the
  /// path that blocks the first frame, so launch would slow in proportion to
  /// the app's entire download history. Terminal records carry nothing the app
  /// reads: resume data lives in its own store, and whether the platform holds
  /// a transfer is answered by liveness alone.
  Future<void> _pruneFinishedRecords() async {
    for (final record in await _guard(
      () => _downloader.database.allRecords(group: _group),
      const <TaskRecord>[],
    )) {
      if (!record.status.isFinalState) continue;
      await _guard(
        () => _downloader.database.deleteRecordWithId(record.taskId),
        null,
      );
    }
  }

  static void _recordTerminal(TaskUpdate update) {
    if (update is! TaskStatusUpdate || !update.status.isFinalState) return;
    final destination = _destinationOf(update.task);
    if (destination != null) _terminal[destination] = update;
  }

  static String? _destinationOf(Task task) =>
      artifactDestinationIn(task.metaData);

  DownloadTask _taskFor(ArtifactFileRef ref) => DownloadTask(
    url: ref.sourceUrl,
    directory: subdirectory.isEmpty
        ? ref.directory
        : '$subdirectory/${ref.directory}',
    filename: ref.filename,
    baseDirectory: switch (root) {
      ArtifactDownloadRoot.documents => BaseDirectory.applicationDocuments,
      ArtifactDownloadRoot.applicationSupport =>
        BaseDirectory.applicationSupport,
    },
    group: _group,
    metaData: artifactTaskMetadata(ref),
    updates: Updates.statusAndProgress,
    allowPause: true,
    retries: 3,
  );

  bool _matches(Task task, ArtifactFileRef ref) =>
      artifactTaskMetadataMatches(task.metaData, ref);

  /// The task the platform is actually holding for [ref] — running, waiting to
  /// retry, or paused. **Never** a tracking record: the plugin keeps records
  /// for completed and cancelled tasks indefinitely, so treating one as a held
  /// task makes cancellation structurally unconfirmable.
  Future<Task?> _heldTask(ArtifactFileRef ref) async {
    for (final task in await _guard(
      () => _downloader.allTasks(group: _group),
      const <Task>[],
    )) {
      if (_matches(task, ref)) return task;
    }
    for (final task in await _guard(
      () => _storage.retrieveAllPausedTasks(),
      const <Task>[],
    )) {
      if (_matches(task, ref)) return task;
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

  /// True when the downloader is usable. Never throws: a platform that refuses
  /// to start degrades downloads, and must not take reconciliation — or the
  /// screen reading it — down with them.
  Future<bool> _started() async {
    try {
      await initialize();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ArtifactTransferSnapshot> inspect(ArtifactFileRef ref) async {
    if (!await _started()) return const ArtifactTransferSnapshot();
    return (await _resolve(ref)).snapshot;
  }

  /// Resolves the held task and what is known about it in one pass, so the
  /// decision and its execution act on the same task.
  ///
  /// Liveness is authoritative and the stores are consulted only for progress:
  /// a record can say `running` long after a force-stop, and `waitingToRetry`
  /// outlives the retry itself. Resume data is the one thing that legitimately
  /// survives with no task at all — that is a killed transfer, still resumable.
  Future<_ResolvedTransfer> _resolve(ArtifactFileRef ref) async {
    final held = await _heldTask(ref);
    if (held == null) {
      for (final record in await _guard(
        () => _downloader.database.allRecords(group: _group),
        const <TaskRecord>[],
      )) {
        if (!_matches(record.task, ref)) continue;
        final resume = await _guard(
          () => _storage.retrieveResumeData(record.task.taskId),
          null,
        );
        if (resume == null) continue;
        return _ResolvedTransfer(
          record.task,
          ArtifactTransferSnapshot(
            receivedBytes: resume.requiredStartByte,
            resumable: true,
          ),
        );
      }
      return const _ResolvedTransfer(null, ArtifactTransferSnapshot());
    }

    final resumeData = await _guard(
      () => _storage.retrieveResumeData(held.taskId),
      null,
    );
    final record = await _guard(
      () => _downloader.database.recordForId(held.taskId),
      null,
    );

    // The larger of the two stores wins, because they answer different
    // questions and either can be behind. Resume data records where a resumed
    // transfer would restart — frozen at the last pause — while the tracking
    // record follows a live one. Measured on an OnePlus 12R: preferring resume
    // data reported a 145 MB transfer as 50 MB after a process kill, and a
    // progress bar that jumps backwards reads as lost work.
    final resumePoint = resumeData?.requiredStartByte;
    final tracked = record != null && record.progress > 0
        ? (record.progress * ref.expectedBytes).round()
        : null;
    final received = switch ((resumePoint, tracked)) {
      (null, null) => null,
      (final a?, null) => a,
      (null, final b?) => b,
      (final a?, final b?) => a > b ? a : b,
    };

    final isPaused = (await _guard(
      () => _storage.retrieveAllPausedTasks(),
      const <Task>[],
    )).any((each) => each.taskId == held.taskId);

    final presence = isPaused
        ? ArtifactTransferPresence.paused
        : record?.status == TaskStatus.waitingToRetry
        ? ArtifactTransferPresence.waitingToRetry
        : ArtifactTransferPresence.running;

    return _ResolvedTransfer(
      held,
      ArtifactTransferSnapshot(
        presence: presence,
        receivedBytes: received,
        resumable: resumeData != null,
      ),
    );
  }

  Future<bool> _destinationComplete(ArtifactFileRef ref) async {
    final path = await _documentsPath(ref);
    if (path == null) return false;
    final file = File(path);
    return await file.exists() && await file.length() == ref.expectedBytes;
  }

  /// The plugin owns the mapping from the base directory to a real path, so
  /// the destination is resolved through its own join rather than re-derived
  /// here.
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
    TaskId? generation;
    try {
      if (!await _started()) {
        yield const ArtifactFileFailed('The downloader is unavailable.');
        return;
      }

      // One resolution, used for both the decision and its execution: two
      // lookups are not atomic, and adopting a task other than the one whose
      // liveness justified adopting would watch a dead generation while the
      // live one runs unobserved.
      final resolved = await _resolve(ref);
      final decision = decideArtifactTransfer(
        platform: resolved.snapshot,
        destinationComplete: await _destinationComplete(ref),
      );

      final existing = resolved.task;
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
      // Mirrored to the outer scope so the finally can drop this generation's
      // recorded intent whichever way the stream ends.
      final id = generation = TaskId(taskId);
      _attached.add(id);

      // A terminal status recorded before this stream attached — a background
      // completion, or one replayed by resumeFromBackground at startup. A
      // cancel commanded while nothing was listening is still the user's.
      final replayed = _terminal.remove(ref.destination);
      if (replayed != null && replayed.task.taskId == taskId) {
        final event =
            _stopEvent(
              verdictFor(status: replayed.status, commanded: _stops.of(id)),
            ) ??
            _terminalEvent(replayed);
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
          final snapshot = (await _resolve(ref)).snapshot;
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
          final snapshot = (await _resolve(ref)).snapshot;
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

        switch (update) {
          case TaskProgressUpdate(:final progress) when progress >= 0:
            yield ArtifactFileProgress((progress * ref.expectedBytes).round());
          case TaskProgressUpdate():
            break;
          case TaskStatusUpdate():
            // Read per update, not carried between them: an out-of-band pause
            // or cancel lands between iterations, and the platform event it
            // causes is the very next one — a stale flag would report the
            // user's own stop as uncommanded and strand the card.
            final verdict = verdictFor(
              status: update.status,
              commanded: _stops.of(id),
            );
            if (verdict == StopVerdict.uncommandedPause) {
              pauseFinalize = Timer(
                uncommandedPauseGrace,
                () => buffer.add(_finalizePause),
              );
              break;
            }
            final event = _stopEvent(verdict) ?? _terminalEvent(update);
            if (event != null) {
              yield event;
              return;
            }
        }
      }
    } finally {
      watchdog?.cancel();
      pauseFinalize?.cancel();
      if (generation != null) {
        _attached.remove(generation);
        _stops.forget(generation);
      }
      await subscription.cancel();
      await buffer.close();
    }
  }

  /// The event a stop verdict calls for, or null when the verdict is not one
  /// the stream ends on.
  ArtifactFileEvent? _stopEvent(StopVerdict verdict) => switch (verdict) {
    StopVerdict.userPaused => const ArtifactFilePaused(),
    StopVerdict.userCanceled => const ArtifactFileCanceled(),
    StopVerdict.uncommandedCancel => const ArtifactFileCanceled(
      userInitiated: false,
    ),
    StopVerdict.uncommandedPause || StopVerdict.notAStop => null,
  };

  /// Completion and failure only — they carry no intent, so [verdictFor] owns
  /// every status that does.
  ArtifactFileEvent? _terminalEvent(TaskStatusUpdate update) =>
      switch (update.status) {
        TaskStatus.complete => const ArtifactFileComplete(),
        TaskStatus.failed || TaskStatus.notFound => ArtifactFileFailed(
          update.exception?.description ?? 'The download failed.',
        ),
        TaskStatus.paused ||
        TaskStatus.canceled ||
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
      if (await _heldTask(ref) == null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return await _heldTask(ref) == null;
  }

  /// Stops commanded and not yet seen through, and the generations a
  /// `download()` stream is listening to.
  ///
  /// Static, like the plugin handles beside them: two instances in one process
  /// share the platform, so intent recorded through one has to be visible to a
  /// stream running on the other. `launch_composition` builds a fresh
  /// downloader per composition attempt and the integration suite builds
  /// several, and per-instance state would put the 15s grace straight back
  /// with nothing to catch it. Testability is not affected — [CommandedStops]
  /// is exercised on its own instances.
  static final CommandedStops _stops = CommandedStops();
  static final Set<TaskId> _attached = {};

  /// A command nobody is listening to has no consumer to read it, so it is
  /// dropped as soon as it resolves rather than waiting for a `finally` that
  /// will never run.
  void _releaseIfUnattached(TaskId id) {
    if (!_attached.contains(id)) _stops.forget(id);
  }

  // `static final`, never `const`: Dart canonicalizes const objects, so two
  // `const Object()` sentinels are the *same* instance and `identical` cannot
  // tell them apart.
  static final Object _finalizePause = Object();
  static final Object _probe = Object();

  @override
  Future<bool> pause(ArtifactFileRef ref) async {
    if (!await _started()) return false;
    final task = await _heldTask(ref);
    if (task is! DownloadTask) return false;
    final id = TaskId(task.taskId);
    _stops.commandPause(id);
    if (!await _guard(() => _downloader.pause(task), false)) {
      // Refused outright, so the pause will never happen: the record has to go
      // even with a stream attached, or the next uncommanded pause on this
      // generation is reported as the user's.
      _stops.forgetPause(id);
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
      if (paused.any((each) => each.taskId == task.taskId)) {
        _releaseIfUnattached(id);
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // Unconfirmed is not refused — the request was accepted and may still
    // land — so an attached stream keeps the intent and labels it correctly.
    _releaseIfUnattached(id);
    return false;
  }

  @override
  Future<bool> cancel(ArtifactFileRef ref) async {
    if (!await _started()) return false;
    final task = await _heldTask(ref);
    if (task == null) return true;
    final id = TaskId(task.taskId);
    _stops.commandCancel(id);
    final cleared = await _cancelAndConfirm(ref, task);
    // Not rolled back on a confirmation timeout: the cancel was issued and may
    // still land, and an attached stream must report it as the user's when it
    // does. Only a generation nobody is listening to is dropped here.
    _releaseIfUnattached(id);
    return cleared;
  }

  /// How long a staging file must have sat untouched before it counts as an
  /// orphan. The plugin writes resume data only when a transfer *pauses*, so a
  /// running transfer's staging file is referenced by nothing — age is the only
  /// signal that separates it from genuine debris. A live worker rewrites its
  /// file continuously, so it can never look this stale.
  static const _orphanAge = Duration(hours: 24);

  /// Deletes partial-transfer files nothing refers to and nothing has touched
  /// in [_orphanAge].
  ///
  /// A hard kill during a multi-gigabyte download otherwise leaves its partial
  /// behind forever: the plugin sweeps nothing, the Storage screen cannot see
  /// these files, and the disk-space preflight eventually refuses the very
  /// download that is leaking. Runs after start() has restored resume data.
  Future<void> _sweepOrphanedPartials() async {
    if (temporaryDirectories.isEmpty) return;
    final referenced = <String>{
      for (final data in await _guard(
        () => _storage.retrieveAllResumeData(),
        const <ResumeData>[],
      ))
        data.tempFilepath,
    };
    // Deleting a running transfer's staging file does not stop it: the worker
    // holds the descriptor and keeps writing to an unlinked inode, so progress
    // still climbs and only the final move fails — a multi-gigabyte download
    // lost with no symptom until the very end.
    final anyLive = (await _guard(
      () => _downloader.allTasks(group: _group),
      const <Task>[],
    )).isNotEmpty;
    if (anyLive) return;

    final cutoff = DateTime.now().subtract(_orphanAge);
    for (final path in temporaryDirectories) {
      final directory = Directory(path);
      if (!await directory.exists()) continue;
      try {
        await for (final entry in directory.list(followLinks: false)) {
          if (entry is! File) continue;
          if (!isPartialTransferFile(entry)) continue;
          if (referenced.contains(entry.path)) continue;
          try {
            if ((await entry.lastModified()).isAfter(cutoff)) continue;
            await entry.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }
  }
}

/// Prefix the download plugin gives every partial-transfer file it stages.
/// Shared so the sweep and the cache probe cannot disagree about which files
/// are live download progress — one deleting what the other preserves.
const partialTransferPrefix = 'com.bbflight.background_downloader';

bool isPartialTransferFile(FileSystemEntity entry) {
  final segments = entry.uri.pathSegments;
  return segments.isNotEmpty && segments.last.startsWith(partialTransferPrefix);
}
