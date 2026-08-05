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

/// Per-artifact model management. Keys address entries of the injected
/// catalog; operational failures (network, disk, verification) surface as
/// [ArtifactPhase.failed] snapshots with a message — never as thrown errors.
abstract interface class ModelManagementRepository {
  Future<ModelState> load();

  /// Starts, resumes, or retries the download for [artifactKey], emitting
  /// persisted snapshots until it installs, fails, pauses, or is cancelled.
  Stream<ModelState> download(String artifactKey);

  /// Out-of-band stop that keeps partial data for a later [download].
  Future<ModelState> pause(String artifactKey);

  /// Out-of-band stop that discards partial data.
  Future<ModelState> cancel(String artifactKey);

  /// Removes an installed artifact from disk.
  Future<ModelState> delete(String artifactKey);

  Future<ModelState> loadRuntime();
  Future<ModelState> unloadRuntime();
}

abstract interface class BenchmarkRepository {
  Future<BenchmarkRecord> run(String caseId, BenchmarkPhase phase);
  Future<String> export(BenchmarkRecord result);
}
