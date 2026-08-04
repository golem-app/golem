import '../domain/models.dart';

abstract interface class ChatHistoryRepository {
  Future<ChatHistorySnapshot> load();
  Future<void> save(ChatHistorySnapshot snapshot);
}

abstract interface class InferenceRepository {
  Future<void> prepare();
  Future<void> unload();
  Future<void> cancel();
  Stream<InferenceEvent> generate({
    required List<Map<String, String>> context,
    required bool reasoningEnabled,
  });
}

abstract interface class ModelManagementRepository {
  Future<ModelState> load();
  Future<ModelState> selectBackend(BackendId backend);
  Stream<ModelState> downloadMlx();
  Future<ModelState> pauseMlx();
  Stream<ModelState> importTurboFieldfare();
  Future<ModelState> loadRuntime();
  Future<ModelState> unloadRuntime();
}

abstract interface class BenchmarkRepository {
  Future<BenchmarkRecord> run(String caseId, BenchmarkPhase phase);
  Future<String> export(BenchmarkRecord result);
}
