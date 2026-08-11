import 'dart:async';

import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';

final class ScriptedChatSave {
  ScriptedChatSave(this.snapshot);

  final ChatHistorySnapshot snapshot;
  final Completer<void> _completion = Completer<void>();

  void succeed() => _completion.complete();

  void fail() => _completion.completeError(
    const PersistenceException(
      PersistenceFailureKind.write,
      'Could not save the chat history.',
    ),
  );
}

/// A history seam whose writes complete only when the test says so. It makes
/// overlapping completion order observable without weakening the serialized
/// behavior of the shipped file repository.
final class ScriptedChatHistoryRepository implements ChatHistoryRepository {
  ScriptedChatHistoryRepository([
    this.snapshot = const ChatHistorySnapshot(conversations: []),
  ]);

  ChatHistorySnapshot snapshot;
  final List<ScriptedChatSave> saves = [];

  @override
  Future<ChatHistorySnapshot> load() async => snapshot;

  @override
  Future<void> save(ChatHistorySnapshot value) async {
    final request = ScriptedChatSave(value);
    saves.add(request);
    await request._completion.future;
    snapshot = value;
  }

  @override
  Future<int> storedBytes() async => snapshot.encode().length;
}
