import '../domain/app_preferences.dart';
import '../domain/generation_settings.dart';
import '../domain/model_catalog.dart';
import '../domain/models.dart';

abstract interface class ChatHistoryRepository {
  Future<ChatHistorySnapshot> load();
  Future<void> save(ChatHistorySnapshot snapshot);

  /// Bytes the stored history occupies on disk (0 when nothing is stored),
  /// for the Storage screen's breakdown.
  Future<int> storedBytes();
}

abstract interface class InferenceRepository {
  Future<void> prepare();
  Future<void> unload();
  Future<void> cancel();

  /// [overrides] are the user's sparse per-model settings; a real backend
  /// merges them onto its profile's recommended defaults, the fake ignores
  /// them (simulated output has no sampling to steer).
  ///
  /// [modelKey] is the conversation's chosen catalog model. The fake
  /// varies its simulated voice and metrics per key; real engines run
  /// their configured model regardless until per-chat switching (#20).
  ///
  /// [systemPrompt] is the user's custom system prompt (Advanced mode).
  /// Real backends render it as the leading system turn of the chat
  /// template; the fake acknowledges it in its canned reply so the
  /// round-trip is provable without a model.
  Stream<InferenceEvent> generate({
    required List<Map<String, String>> context,
    required bool reasoningEnabled,
    SamplingOverrides? overrides,
    String? modelKey,
    String? systemPrompt,
  });
}

/// Persisted per-model generation settings, stored with the same versioned
/// atomic-JSON discipline as chat history.
abstract interface class SettingsRepository {
  Future<GenerationSettings> load();
  Future<void> save(GenerationSettings settings);
}

/// Persisted app-wide preferences (appearance, transcript, privacy,
/// Advanced mode, response styles, custom repositories) — a separate store
/// from [SettingsRepository] so neither file's schema constrains the other.
abstract interface class PreferencesRepository {
  Future<AppPreferences> load();
  Future<void> save(AppPreferences preferences);
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

  /// Registers a hand-added catalog entry (Advanced mode's custom
  /// repository). The fake simulates its download like any pinned entry;
  /// the real implementation records nothing — arbitrary-repository
  /// downloads arrive with #20 and the UI keeps Add disabled there.
  Future<ModelState> addModel(ModelCatalogEntry entry);
}

abstract interface class BenchmarkRepository {
  Future<BenchmarkRecord> run(String caseId, BenchmarkPhase phase);
  Future<String> export(BenchmarkRecord result);
}
