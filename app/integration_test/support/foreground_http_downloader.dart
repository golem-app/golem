import 'dart:async';
import 'dart:io';

import 'package:golem_flutter/core/services/artifact_downloader.dart';

/// Spike-quality [ArtifactFileDownloader] over plain `dart:io` sockets in
/// this process — the in-process transport candidate, and the curl-equivalent
/// baseline on the iPhone, where no shell exists (#36).
///
/// [connections] == 1 streams one GET (resuming with a `Range` header from an
/// existing partial); higher counts split the file into ranged slices written
/// through per-connection file handles, wget's multi-session trick without
/// the plugin.
///
/// Bench-only, deliberately not production-grade:
///
/// - Runs on the main isolate. Chunk callbacks are small copies and the HUD
///   only needs to stay legible; byte counting is unaffected either way.
/// - Bytes stage in `<destination>.golem-http-part`, renamed on completion,
///   so a half-written file can never look like an installed one.
/// - Ranged mode reports `resumable: false` — per-slice resume bookkeeping is
///   real-implementation work, not spike work.
/// - Nothing survives the process: a backgrounded iOS app loses these
///   sockets, which is precisely the trade the bench exists to price.
final class ForegroundHttpDownloader implements ArtifactFileDownloader {
  ForegroundHttpDownloader({
    required this.documentsDirectory,
    this.connections = 1,
  });

  /// The seam's paths are relative to the app documents directory; the plugin
  /// resolves them natively, this transport needs the root handed in.
  final String documentsDirectory;
  final int connections;

  final Map<String, _Transfer> _live = {};

  @override
  Future<void> initialize() async {}

  String _destinationPath(ArtifactFileRef ref) =>
      '$documentsDirectory/${ref.destination}';
  String _partPath(ArtifactFileRef ref) =>
      '${_destinationPath(ref)}.golem-http-part';

  @override
  Stream<ArtifactFileEvent> download(ArtifactFileRef ref) {
    final transfer = _Transfer();
    _live[ref.destination] = transfer;
    final controller = StreamController<ArtifactFileEvent>();

    Future<void> run() async {
      final part = File(_partPath(ref));
      await part.parent.create(recursive: true);
      try {
        if (connections == 1) {
          await _single(ref, part, transfer, controller);
        } else {
          await _ranged(ref, part, transfer, controller);
        }
        if (transfer.aborted) return;
        final length = await part.length();
        if (length != ref.expectedBytes) {
          controller.add(
            ArtifactFileFailed(
              'expected ${ref.expectedBytes} bytes, got $length',
            ),
          );
          return;
        }
        await part.rename(_destinationPath(ref));
        controller.add(const ArtifactFileComplete());
      } catch (e) {
        if (!transfer.aborted) {
          controller.add(ArtifactFileFailed('$e'));
        }
      }
    }

    unawaited(
      run().whenComplete(() {
        _live.remove(ref.destination);
        controller.close();
      }),
    );
    return controller.stream;
  }

  Future<void> _single(
    ArtifactFileRef ref,
    File part,
    _Transfer transfer,
    StreamController<ArtifactFileEvent> controller,
  ) async {
    final resumeFrom = await part.exists() ? await part.length() : 0;
    var received = resumeFrom;
    final request = await transfer.client.getUrl(Uri.parse(ref.sourceUrl));
    if (resumeFrom > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeFrom-');
    }
    final response = await request.close();
    if (response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: request.uri);
    }
    final resumed =
        resumeFrom > 0 && response.statusCode == HttpStatus.partialContent;
    final sink = part.openWrite(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    if (!resumed) received = 0;
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        transfer.throttled(
          () => controller.add(ArtifactFileProgress(received)),
        );
      }
    } finally {
      await sink.close();
    }
  }

  Future<void> _ranged(
    ArtifactFileRef ref,
    File part,
    _Transfer transfer,
    StreamController<ArtifactFileEvent> controller,
  ) async {
    // Preallocate so per-connection handles can seek anywhere.
    final prealloc = await part.open(mode: FileMode.write);
    await prealloc.truncate(ref.expectedBytes);
    await prealloc.close();

    var received = 0;
    final slice = ref.expectedBytes ~/ connections;
    await Future.wait([
      for (var i = 0; i < connections; i++)
        () async {
          final start = i * slice;
          final end = i == connections - 1
              ? ref.expectedBytes - 1
              : (i + 1) * slice - 1;
          final request = await transfer.client.getUrl(
            Uri.parse(ref.sourceUrl),
          );
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
          final response = await request.close();
          if (response.statusCode != HttpStatus.partialContent) {
            throw HttpException(
              'range request answered HTTP ${response.statusCode}',
              uri: request.uri,
            );
          }
          // Append mode: opens read-write without truncating what the other
          // slices already wrote.
          final handle = await part.open(mode: FileMode.append);
          await handle.setPosition(start);
          try {
            await for (final chunk in response) {
              await handle.writeFrom(chunk);
              received += chunk.length;
              transfer.throttled(
                () => controller.add(ArtifactFileProgress(received)),
              );
            }
          } finally {
            await handle.close();
          }
        }(),
    ]);
  }

  @override
  Future<bool> pause(ArtifactFileRef ref) async {
    final transfer = _live[ref.destination];
    if (transfer == null) return false;
    transfer.abort();
    return connections == 1;
  }

  @override
  Future<bool> cancel(ArtifactFileRef ref) async {
    _live[ref.destination]?.abort();
    final part = File(_partPath(ref));
    if (await part.exists()) await part.delete();
    return true;
  }

  @override
  Future<ArtifactTransferSnapshot> inspect(ArtifactFileRef ref) async {
    final part = File(_partPath(ref));
    if (_live.containsKey(ref.destination)) {
      return ArtifactTransferSnapshot(
        presence: ArtifactTransferPresence.running,
        receivedBytes: await part.exists() ? await part.length() : null,
      );
    }
    if (await part.exists() && connections == 1) {
      return ArtifactTransferSnapshot(
        presence: ArtifactTransferPresence.paused,
        receivedBytes: await part.length(),
        resumable: true,
      );
    }
    return const ArtifactTransferSnapshot();
  }
}

final class _Transfer {
  final HttpClient client = HttpClient();
  bool aborted = false;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  void abort() {
    aborted = true;
    client.close(force: true);
  }

  /// At most ~10 progress events a second; 50 MB/s arrives as thousands of
  /// chunks and each event crosses into the HUD's notifier.
  void throttled(void Function() emit) {
    final now = DateTime.now();
    if (now.difference(_lastEmit).inMilliseconds >= 100) {
      _lastEmit = now;
      emit();
    }
  }
}
