import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';

final class InMemoryChatHistoryRepository implements ChatHistoryRepository {
  InMemoryChatHistoryRepository([
    this.snapshot = const ChatHistorySnapshot(conversations: []),
  ]);
  ChatHistorySnapshot snapshot;

  /// While > 0, each save throws a typed write failure and decrements —
  /// the fault-injection hook for rollback tests.
  int failingSaves = 0;

  @override
  Future<ChatHistorySnapshot> load() async => snapshot;

  @override
  Future<int> storedBytes() async => snapshot.encode().length;

  @override
  Future<void> save(ChatHistorySnapshot value) async {
    if (failingSaves > 0) {
      failingSaves--;
      throw const PersistenceException(
        PersistenceFailureKind.write,
        'Could not save the chat history.',
      );
    }
    snapshot = value;
  }
}
