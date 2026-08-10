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
  Future<ChatHistorySnapshot> load() => loadStore(
    file,
    what: _what,
    decode: (raw) => ChatHistorySnapshot.fromJson(
      Map<String, Object?>.from(jsonDecode(raw) as Map),
    ),
    orElse: () => const ChatHistorySnapshot(conversations: []),
  );

  @override
  Future<int> storedBytes() => storeBytes(file, what: _what);

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
