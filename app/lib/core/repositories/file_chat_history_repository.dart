import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';
import 'contracts.dart';

final class FileChatHistoryRepository implements ChatHistoryRepository {
  FileChatHistoryRepository(this.file);
  final File file;
  Future<void> _writes = Future.value();

  @override
  Future<ChatHistorySnapshot> load() async {
    if (!await file.exists()) {
      return const ChatHistorySnapshot(conversations: []);
    }
    try {
      final value = jsonDecode(await file.readAsString());
      return ChatHistorySnapshot.fromJson(
        Map<String, Object?>.from(value as Map),
      );
    } catch (_) {
      // An unreadable or unknown-schema history file must not brick startup:
      // preserve it for inspection and start with an empty history.
      await file.rename('${file.path}.corrupt');
      return const ChatHistorySnapshot(conversations: []);
    }
  }

  @override
  Future<int> storedBytes() async => await file.exists() ? file.length() : 0;

  @override
  Future<void> save(ChatHistorySnapshot snapshot) {
    // Saves are fire-and-forget at call sites, so serialize them: concurrent
    // writes would otherwise race on the shared temporary file and could
    // rename stale content over a newer snapshot.
    final write = _writes.then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(snapshot.encode(), flush: true);
      await temporary.rename(file.path);
    });
    _writes = write.catchError((_) {});
    return write;
  }
}
