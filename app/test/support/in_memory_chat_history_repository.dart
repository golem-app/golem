import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';

final class InMemoryChatHistoryRepository implements ChatHistoryRepository {
  InMemoryChatHistoryRepository([
    this.snapshot = const ChatHistorySnapshot(conversations: []),
  ]);
  ChatHistorySnapshot snapshot;

  @override
  Future<ChatHistorySnapshot> load() async => snapshot;

  @override
  Future<int> storedBytes() async => snapshot.encode().length;

  @override
  Future<void> save(ChatHistorySnapshot value) async => snapshot = value;
}
