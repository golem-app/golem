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

  /// While > 0, each [storedBytes] throws a typed read failure and
  /// decrements — the storage-breakdown fault hook.
  int failingStoredBytes = 0;

  /// How often the breakdown actually probed this store — the lifecycle
  /// suite's recompute observability.
  int storedBytesCalls = 0;

  /// While > 0, each load throws a typed read failure and decrements.
  int failingLoads = 0;

  @override
  Future<ChatHistorySnapshot> load() async {
    if (failingLoads > 0) {
      failingLoads--;
      throw const PersistenceException(
        PersistenceFailureKind.read,
        'Could not read the stored chat history.',
      );
    }
    return snapshot;
  }

  @override
  Future<int> storedBytes() async {
    storedBytesCalls++;
    if (failingStoredBytes > 0) {
      failingStoredBytes--;
      throw const PersistenceException(
        PersistenceFailureKind.read,
        'Could not read the stored chat history.',
      );
    }
    return snapshot.encode().length;
  }

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
