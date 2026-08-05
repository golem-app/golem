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
  const ArtifactFilePaused();
}

final class ArtifactFileCanceled extends ArtifactFileEvent {
  const ArtifactFileCanceled();
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
  final Map<String, DownloadTask> _pausedTasks = {};
  Task? _current;

  @override
  Stream<ArtifactFileEvent> download({
    required String url,
    required String directory,
    required String filename,
    required int expectedBytes,
  }) async* {
    final pathKey = '$directory/$filename';
    final downloader = FileDownloader();
    var task = _pausedTasks.remove(pathKey);
    if (task != null && await downloader.taskCanResume(task)) {
      _current = task;
      if (!await downloader.resume(task)) {
        task = null;
      }
    } else {
      task = null;
    }
    if (task == null) {
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
    await for (final update in downloader.updates.where(
      (update) => update.task.taskId == taskId,
    )) {
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
              _pausedTasks[pathKey] = task;
              yield const ArtifactFilePaused();
              return;
            case TaskStatus.canceled:
              yield const ArtifactFileCanceled();
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
  }

  @override
  Future<void> pause() async {
    final task = _current;
    if (task is DownloadTask) {
      await FileDownloader().pause(task);
    }
  }

  @override
  Future<void> cancel() async {
    final task = _current;
    if (task != null) {
      await FileDownloader().cancelTaskWithId(task.taskId);
    }
  }
}
