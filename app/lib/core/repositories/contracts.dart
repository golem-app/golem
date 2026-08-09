import 'package:flutter/foundation.dart' show ValueListenable;

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

/// Semantic classification of an inference failure, stable across fake and
/// real backends so the recovery banner can pick actions without parsing
/// copy (§19.1). The kinds are recovery categories, not engine codes:
/// [contextExhausted] is the one failure Retry can never fix.
enum InferenceFailureKind {
  /// Engine or runtime failure with no better classification; Retry is a
  /// reasonable action.
  engine,

  /// The conversation no longer fits the model's context window; retrying
  /// the identical request is guaranteed to fail again.
  contextExhausted,

  /// The engine ran out of memory mid-operation; retrying after freeing
  /// memory can succeed.
  outOfMemory,

  /// The load preflight found too little free memory to even try.
  insufficientMemory,

  /// The whole token budget went to reasoning and no answer surfaced.
  budgetExhaustedBeforeAnswer,
}

/// A typed inference failure whose [message] is user-presentable copy;
/// `toString` is the message so no surface ever shows a package exception
/// verbatim. Thrown by fake and real repositories alike (§19.2).
class InferenceException implements Exception {
  const InferenceException(this.kind, this.message, {this.cause});

  final InferenceFailureKind kind;
  final String message;

  /// The underlying vendor error, for logs and failure metrics only.
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class InferenceRepository {
  /// Ensures a model is resident: the configuration for [modelKey] when
  /// given, otherwise this process's initial configuration. Loading is
  /// single-flight — concurrent callers join the activation in flight
  /// rather than tripping the engine's single-operation lifecycle.
  Future<void> prepare({String? modelKey});
  Future<void> unload();
  Future<void> cancel();

  /// The catalog key of the model currently resident in the engine, or
  /// null when nothing is loaded. This repository is the only component
  /// that loads or unloads weights (#42), so honesty labels follow this
  /// signal rather than the boot-resolved configuration.
  ValueListenable<String?> get residentModelKey;

  /// [overrides] are the user's sparse per-model settings; a real backend
  /// merges them onto its profile's recommended defaults, the fake ignores
  /// them (simulated output has no sampling to steer).
  ///
  /// [modelKey] is the conversation's chosen catalog model. The fake
  /// varies its simulated voice and metrics per key; real engines
  /// activate the requested configuration when it is not already resident,
  /// then generate. Chat-side switching UX and its guards remain with #20.
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

/// A stored attachment's identity. [id] is opaque and app-owned: the source
/// path a picture came from never leaves the intake layer.
final class StoredAttachment {
  const StoredAttachment({
    required this.id,
    required this.mimeType,
    required this.byteCount,
  });

  final String id;
  final String mimeType;
  final int byteCount;
}

/// The app-owned store for images the user attached to a chat.
///
/// Bytes are copied in on attach so the conversation never depends on a
/// photo-library entry that can be deleted or revoked. The chat history is the
/// only owner of references: [retainOnly] is how deletion cascades, so bytes
/// go away exactly when no conversation mentions them any more.
abstract interface class AttachmentRepository {
  /// Copies [bytes] into the store and returns its identity.
  Future<StoredAttachment> store(List<int> bytes, {required String mimeType});

  /// The stored bytes, or null when the attachment is missing — a message can
  /// outlive its file if the container was trimmed by the OS.
  Future<List<int>?> read(String attachmentId);

  /// Drops every attachment whose id is absent from [attachmentIds].
  Future<void> retainOnly(Set<String> attachmentIds);

  /// Bytes the store occupies, for the Storage screen's breakdown.
  Future<int> storedBytes();
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

  /// Persists the runtime phase the residency owner reports — bookkeeping
  /// only. Loading and unloading weights is the inference repository's job
  /// alone (#42); this repository never touches the engine. A null
  /// [failure] clears any recorded one.
  Future<ModelState> recordRuntime(RuntimePhase phase, {String? failure});

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
