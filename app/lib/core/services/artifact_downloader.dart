import 'dart:async';

import 'package:background_downloader/background_downloader.dart';

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
  const ArtifactFilePaused({this.userInitiated = true});

  /// False when the OS or plugin paused the task uncommanded (network loss,
  /// Android's transfer-service timeout) — the repository must then persist
  /// the paused state itself, since no out-of-band pause() call did.
  final bool userInitiated;
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
/// seam only moves bytes so tests can script it.
abstract interface class ArtifactFileDownloader {
  /// Streams progress until the file completes, pauses, cancels, or fails.
  /// [directory] is relative to the app documents directory.
  Stream<ArtifactFileEvent> download({
    required String url,
    required String directory,
    required String filename,
    required int expectedBytes,
  });

  /// Pauses the in-flight download, keeping partial data for a later
  /// [download] of the same file to resume from.
  Future<void> pause();

  /// Cancels the in-flight download and discards its partial data.
  Future<void> cancel();
}

/// background_downloader implementation: URLSession on iOS/macOS and
/// DownloadWorker on Android, so multi-gigabyte downloads survive screen
/// lock and backgrounding. allowPause is mandatory — Android hard-stops
/// plain downloads after ~9 minutes, and with allowPause the plugin
/// auto-pauses and resumes to complete the file.
final class BackgroundArtifactDownloader implements ArtifactFileDownloader {
  BackgroundArtifactDownloader({
    this.uncommandedPauseGrace = const Duration(seconds: 15),
  });

  // FileDownloader().updates is single-subscription; every per-file await-for
  // must tap one shared broadcast of it, created once per process.
  static final Stream<TaskUpdate> _updates = FileDownloader().updates
      .asBroadcastStream();

  /// How long an uncommanded pause may sit before it is surfaced as a real
  /// pause. Android's ~9-minute transfer-service timeout pauses the task and
  /// the plugin resumes it moments later; finalizing on the first pause
  /// event would flip the card to "Paused" every cycle on slow connections.
  final Duration uncommandedPauseGrace;

  final Map<String, DownloadTask> _pausedTasks = {};
  Task? _current;
  bool _userPause = false;
  bool _userCancel = false;

  static const _finalizePause = Object();

  @override
  Stream<ArtifactFileEvent> download({
    required String url,
    required String directory,
    required String filename,
    required int expectedBytes,
  }) async* {
    final pathKey = '$directory/$filename';
    final downloader = FileDownloader();
    _userPause = false;
    _userCancel = false;
    // Buffer updates from before enqueue completes: a small file can reach
    // its terminal status before a listener attached afterwards would see it.
    final buffer = StreamController<Object>();
    final subscription = _updates.listen(buffer.add);
    Timer? pauseFinalize;
    try {
      final stashed = _pausedTasks.remove(pathKey);
      var task = stashed;
      if (task != null && await downloader.taskCanResume(task)) {
        _current = task;
        if (!await downloader.resume(task)) {
          task = null;
        }
      } else {
        task = null;
      }
      if (task == null) {
        // A stale stashed task that cannot resume may still be live inside
        // the plugin (e.g. it auto-resumed after an uncommanded pause);
        // cancel it so a fresh enqueue never races it on the same file.
        if (stashed != null) {
          await downloader.cancelTaskWithId(stashed.taskId);
        }
        task = DownloadTask(
          url: url,
          directory: directory,
          filename: filename,
          baseDirectory: BaseDirectory.applicationDocuments,
          updates: Updates.statusAndProgress,
          allowPause: true,
          retries: 3,
        );
        _current = task;
        if (!await downloader.enqueue(task)) {
          yield const ArtifactFileFailed('Could not start the download.');
          return;
        }
      }
      final taskId = task.taskId;
      await for (final update in buffer.stream) {
        if (identical(update, _finalizePause)) {
          _pausedTasks[pathKey] = task;
          yield const ArtifactFilePaused(userInitiated: false);
          return;
        }
        if (update is! TaskUpdate || update.task.taskId != taskId) continue;
        // Any real update for this task supersedes a pending uncommanded
        // pause — the plugin resumed it on its own.
        pauseFinalize?.cancel();
        pauseFinalize = null;
        switch (update) {
          case TaskProgressUpdate(:final progress) when progress >= 0:
            yield ArtifactFileProgress((progress * expectedBytes).round());
          case TaskProgressUpdate():
            break;
          case TaskStatusUpdate(:final status, :final exception):
            switch (status) {
              case TaskStatus.complete:
                yield const ArtifactFileComplete();
                return;
              case TaskStatus.paused:
                if (_userPause) {
                  _pausedTasks[pathKey] = task;
                  yield const ArtifactFilePaused();
                  return;
                }
                pauseFinalize = Timer(
                  uncommandedPauseGrace,
                  () => buffer.add(_finalizePause),
                );
              case TaskStatus.canceled:
                yield ArtifactFileCanceled(userInitiated: _userCancel);
                return;
              case TaskStatus.failed || TaskStatus.notFound:
                yield ArtifactFileFailed(
                  exception?.description ?? 'The download failed.',
                );
                return;
              case TaskStatus.enqueued ||
                  TaskStatus.running ||
                  TaskStatus.waitingToRetry:
                break;
            }
        }
      }
    } finally {
      pauseFinalize?.cancel();
      await subscription.cancel();
      await buffer.close();
    }
  }

  @override
  Future<void> pause() async {
    final task = _current;
    if (task is DownloadTask) {
      _userPause = true;
      await FileDownloader().pause(task);
    }
  }

  @override
  Future<void> cancel() async {
    final task = _current;
    if (task != null) {
      _userCancel = true;
      await FileDownloader().cancelTaskWithId(task.taskId);
    }
  }
}
