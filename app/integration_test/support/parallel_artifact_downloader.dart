import 'dart:async';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:golem_flutter/core/services/artifact_downloader.dart';

/// Spike-quality [ArtifactFileDownloader] over the plugin's
/// [ParallelDownloadTask]: one file split into [chunks] ranged connections —
/// wget's multi-session trick expressed through the same plugin the app
/// already ships (#36).
///
/// Bench-only, deliberately not production-grade:
///
/// - Tasks live in their own group, never `golem-models` (so production
///   reconciliation can never see or adopt a bench task) and never the
///   plugin's reserved `chunk` group.
/// - [inspect] answers from the live task map and the tracking record only.
///   Chunked-parent resume data stores per-chunk state, which the production
///   snapshot arithmetic does not describe — making that adoption-grade is a
///   named cost of any real implementation, not of this spike.
/// - Chunk-size arithmetic on Android: each chunk is its own transfer under
///   the ~9-minute service limit, so `bytes / chunks / rate` must stay well
///   under 540 s. At the 1.21 GB bench artifact and 4 chunks, a chunk is
///   ~300 MB — safe above ~0.6 MB/s per connection, and the current
///   single-connection floor observed on this network is above that.
///
/// The plugin doc claims a [ParallelDownloadTask] cannot be paused, but chunk
/// resume machinery exists in its source; [pause] is wired so the bench can
/// settle that empirically.
final class ParallelArtifactDownloader implements ArtifactFileDownloader {
  ParallelArtifactDownloader({this.chunks = 4});

  final int chunks;

  static const _group = 'golem-bench-parallel';

  /// Live parent tasks by destination, so pause/cancel/inspect act on the
  /// exact task download() enqueued — but only as a fast path. The platform
  /// is the authority: a fresh instance must still be able to cancel or see
  /// a task another instance enqueued, or teardown hygiene silently breaks.
  final Map<String, DownloadTask> _live = {};

  /// Destinations whose pause was commanded through [pause], so an
  /// uncommanded pause (network loss, Android's transfer-service timeout)
  /// reports `userInitiated: false` per the seam contract — the repository
  /// persists paused state only for uncommanded pauses.
  final Set<String> _userPaused = {};

  bool _matches(Task task, ArtifactFileRef ref) {
    try {
      final meta = jsonDecode(task.metaData) as Map<String, Object?>;
      return meta['path'] == ref.destination && meta['url'] == ref.sourceUrl;
    } catch (_) {
      return false;
    }
  }

  /// The task the platform holds for [ref], regardless of which instance
  /// enqueued it.
  Future<Task?> _heldTask(ArtifactFileRef ref) async {
    final local = _live[ref.destination];
    if (local != null) return local;
    for (final task in await FileDownloader().allTasks(group: _group)) {
      if (_matches(task, ref)) return task;
    }
    return null;
  }

  /// The production downloader owns the plugin singleton's construction:
  /// FileDownloader asserts if persistent storage arrives after the singleton
  /// exists, so establishing its chain first is the only safe order when both
  /// transports run in one bench process.
  @override
  Future<void> initialize() => BackgroundArtifactDownloader().initialize();

  /// Chunking is for LFS-backed weights only. Hugging Face serves small
  /// non-LFS repo files dynamically — no Content-Length, no Accept-Ranges —
  /// so a ParallelDownloadTask on them fails at enqueue ("cannot chunk
  /// download", proven on-device both ways). Any real implementation is
  /// therefore a hybrid: ranged chunks for large hashed files, a plain
  /// DownloadTask for the rest. 32 MB clears every repo metadata file by
  /// orders of magnitude.
  static const _chunkFloorBytes = 32 * 1000 * 1000;

  DownloadTask _taskFor(ArtifactFileRef ref) {
    if (ref.expectedBytes < _chunkFloorBytes) {
      return DownloadTask(
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
    }
    return ParallelDownloadTask(
      url: ref.sourceUrl,
      chunks: chunks,
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
  }

  @override
  Stream<ArtifactFileEvent> download(ArtifactFileRef ref) {
    final controller = StreamController<ArtifactFileEvent>();
    final task = _taskFor(ref);
    _live[ref.destination] = task;

    void finish(ArtifactFileEvent event) {
      if (controller.isClosed) return;
      controller
        ..add(event)
        ..close();
      _live.remove(ref.destination);
    }

    unawaited(
      initialize()
          .then(
            (_) => FileDownloader().download(
              task,
              onProgress: (progress) {
                // Negative values are the plugin's status sentinels, not
                // byte fractions.
                if (progress > 0 && !controller.isClosed) {
                  controller.add(
                    ArtifactFileProgress(
                      (progress * ref.expectedBytes).round(),
                    ),
                  );
                }
              },
              onStatus: (status) {
                if (status == TaskStatus.paused) {
                  finish(
                    ArtifactFilePaused(
                      userInitiated: _userPaused.remove(ref.destination),
                    ),
                  );
                }
              },
            ),
          )
          .then((update) {
            switch (update.status) {
              case TaskStatus.complete:
                finish(const ArtifactFileComplete());
              case TaskStatus.canceled:
                finish(const ArtifactFileCanceled());
              case TaskStatus.paused:
                finish(
                  ArtifactFilePaused(
                    userInitiated: _userPaused.remove(ref.destination),
                  ),
                );
              default:
                finish(
                  ArtifactFileFailed(
                    update.exception?.description ??
                        'parallel download ended: ${update.status.name}',
                  ),
                );
            }
          })
          .catchError((Object e) {
            finish(ArtifactFileFailed('$e'));
          }),
    );
    return controller.stream;
  }

  @override
  Future<bool> pause(ArtifactFileRef ref) async {
    await initialize();
    final task = await _heldTask(ref);
    if (task == null || task is! DownloadTask) return false;
    _userPaused.add(ref.destination);
    final paused = await FileDownloader().pause(task);
    if (!paused) _userPaused.remove(ref.destination);
    return paused;
  }

  @override
  Future<bool> cancel(ArtifactFileRef ref) async {
    await initialize();
    _live.remove(ref.destination);
    final task = await _heldTask(ref);
    if (task == null) return true;
    return FileDownloader().cancelTaskWithId(task.taskId);
  }

  @override
  Future<ArtifactTransferSnapshot> inspect(ArtifactFileRef ref) async {
    await initialize();
    final task = await _heldTask(ref);
    if (task == null) return const ArtifactTransferSnapshot();
    final record = await FileDownloader().database.recordForId(task.taskId);
    if (record == null || record.status.isFinalState) {
      return const ArtifactTransferSnapshot();
    }
    return ArtifactTransferSnapshot(
      presence: record.status == TaskStatus.paused
          ? ArtifactTransferPresence.paused
          : ArtifactTransferPresence.running,
      receivedBytes: record.progress > 0
          ? (record.progress * ref.expectedBytes).round()
          : null,
    );
  }
}
