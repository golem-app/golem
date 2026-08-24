import 'dart:async';

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

  /// Every attempted save, including injected failures.
  int saveCalls = 0;

  /// While > 0, each [storedBytes] throws a typed read failure and
  /// decrements — the storage-breakdown fault hook.
  int failingStoredBytes = 0;

  /// How often the breakdown actually probed this store — the lifecycle
  /// suite's recompute observability.
  int storedBytesCalls = 0;

  /// While > 0, each load throws a typed read failure and decrements.
  int failingLoads = 0;

  /// While set, each load blocks on it. The store that has not answered yet is
  /// a real gate state, and counting pumped frames cannot observe it.
  Completer<void>? parkLoad;

  @override
  Future<ChatHistorySnapshot> load() async {
    final parked = parkLoad;
    if (parked != null) await parked.future;
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
    saveCalls++;
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
