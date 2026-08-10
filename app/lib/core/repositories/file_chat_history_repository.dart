import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';
import 'contracts.dart';
import 'persistence_io.dart';

final class FileChatHistoryRepository implements ChatHistoryRepository {
  FileChatHistoryRepository(this.file);
  final File file;
  Future<void> _writes = Future.value();

  static const _what = 'chat history';

  @override
  Future<ChatHistorySnapshot> load() async {
    final raw = await readStore(file, what: _what);
    if (raw == null) return const ChatHistorySnapshot(conversations: []);
    try {
      return ChatHistorySnapshot.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      // Only pure decode/parse can throw here, so this is corruption by
      // definition: preserve the file for inspection, start empty.
      await quarantineStore(file, what: _what);
      return const ChatHistorySnapshot(conversations: []);
    }
  }

  @override
  Future<int> storedBytes() async {
    try {
      return await file.exists() ? await file.length() : 0;
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        PersistenceException(
          PersistenceFailureKind.read,
          'Could not read the stored $_what.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> save(ChatHistorySnapshot snapshot) {
    // Saves are fire-and-forget at call sites, so serialize them: concurrent
    // writes would otherwise race on the shared temporary file and could
    // rename stale content over a newer snapshot.
    final write = _writes.then(
      (_) => writeStore(file, snapshot.encode(), what: _what),
    );
    _writes = write.catchError((_) {});
    return write;
  }
}
