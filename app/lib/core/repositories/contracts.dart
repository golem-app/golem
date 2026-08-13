import 'package:flutter/foundation.dart' show ValueListenable;

import '../domain/app_preferences.dart';
import '../domain/generation_settings.dart';
import '../domain/model_catalog.dart';
import '../domain/models.dart';

abstract interface class ChatHistoryRepository {
  Future<ChatHistorySnapshot> load();

  /// Completes only after [snapshot] has been committed. Operational write
  /// failures surface as [PersistenceException] with
  /// [PersistenceFailureKind.write]; the session owner decides whether its
  /// live state rolls back or remains authoritative.
  Future<void> save(ChatHistorySnapshot snapshot);

  /// Bytes on disk (0 when nothing is stored), for the Storage breakdown.
  Future<int> storedBytes();
}

/// Which side of a store operation failed, deciding the recovery affordance:
/// a [read] failure invalidates what a screen shows, while a [write] failure
/// means the durable snapshot did not advance. The owning controller decides
/// whether presentation rolls back or keeps recoverable live state.
enum PersistenceFailureKind { read, write }

/// An unexpected I/O failure at a persistence boundary — permissions, a full
/// disk, a vanished directory. Deliberately distinct from corrupt-data
/// recovery, which quarantines the file and falls back to defaults without
/// throwing. [message] is user-presentable copy, like [InferenceException];
/// [cause] keeps the `dart:io` error for logs only.
class PersistenceException implements Exception {
  const PersistenceException(this.kind, this.message, {this.cause});

  final PersistenceFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Semantic classification, stable across fake and real backends so the
/// recovery banner picks actions without parsing copy (§19.1). Recovery
/// categories, not engine codes: [contextExhausted] is the one Retry can't fix.
enum InferenceFailureKind {
  /// Unclassified engine or runtime failure; Retry is a reasonable action.
  engine,

  /// A persisted conversation names a model this build no longer carries.
  modelUnavailable,

  /// The model's profile or artifact shape is not supported by this build.
  unsupportedModel,

  /// An attachment referenced by persisted history no longer exists.
  attachmentUnavailable,

  /// The selected model or composed backend cannot consume attached images.
  unsupportedImages,

  /// Installed weights are missing, damaged, or incompatible with the engine.
  invalidModelArtifact,

  /// The native engine reports that this processor is unsupported.
  unsupportedDevice,

  /// The conversation no longer fits the window; an identical retry must fail.
  contextExhausted,

  /// Out of memory mid-operation; retrying after freeing memory can succeed.
  outOfMemory,

  /// The load preflight found too little free memory to even try.
  insufficientMemory,

  /// The whole token budget went to reasoning and no answer surfaced.
  budgetExhaustedBeforeAnswer,
}

/// The runtime's live residency, distinct from durable artifact installation.
/// A sideload is loaded with no catalog key; a null key therefore cannot stand
/// in for the much more important question of whether weights are resident.
final class InferenceResidency {
  const InferenceResidency({required this.loaded, this.catalogKey})
    : assert(loaded || catalogKey == null);

  const InferenceResidency.unloaded() : loaded = false, catalogKey = null;

  final bool loaded;
  final String? catalogKey;

  @override
  bool operator ==(Object other) =>
      other is InferenceResidency &&
      other.loaded == loaded &&
      other.catalogKey == catalogKey;

  @override
  int get hashCode => Object.hash(loaded, catalogKey);
}

/// [message] is diagnostic source-language copy for logs and tests. App
/// presentation switches exhaustively on [kind] and never displays it.
class InferenceException implements Exception {
  const InferenceException(
    this.kind,
    this.message, {
    this.cause,
    this.contextTokens,
  });

  final InferenceFailureKind kind;
  final String message;
  final int? contextTokens;

  /// The underlying vendor error, for logs and failure metrics only.
  final Object? cause;

  @override
  String toString() => message;
}

abstract interface class InferenceRepository {
  /// Ensures a model is resident: [modelKey]'s configuration, else the
  /// process's initial one. Single-flight — callers join the load in flight.
  Future<void> prepare({String? modelKey});
  Future<void> unload();
  Future<void> cancel();

  /// The live engine state. This repository is the only component that loads
  /// or unloads weights (#42), so honesty labels follow this rather than the
  /// boot-resolved configuration or durable download phase.
  ValueListenable<InferenceResidency> get residency;

  /// [overrides] are the user's sparse per-model settings for the profile of
  /// [modelKey]'s model, merged onto that profile's recommended defaults by a
  /// real backend and ignored by the fake. [modelKey] is activated when it is
  /// not already resident. [systemPrompt] renders as the leading system turn;
  /// the fake acknowledges it so the round-trip is provable model-free.
  Stream<InferenceEvent> generate({
    required List<PromptMessage> context,
    required bool reasoningEnabled,
    SamplingOverrides? overrides,
    String? modelKey,
    String? systemPrompt,
  });
}

/// Persisted per-model generation settings, versioned atomic JSON.
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

/// Bytes are copied in on attach so a conversation never depends on a
/// photo-library entry that can be deleted or revoked. Chat history is the only
/// owner of references: [retainOnly] is how deletion cascades.
abstract interface class AttachmentRepository {
  Future<StoredAttachment> store(List<int> bytes, {required String mimeType});

  /// The stored bytes, or null when the attachment is missing — a message can
  /// outlive its file if the container was trimmed by the OS.
  Future<List<int>?> read(String attachmentId);

  Future<void> retainOnly(Set<String> attachmentIds);

  Future<int> storedBytes();
}

/// Persisted app-wide preferences — a separate store from [SettingsRepository]
/// so neither file's schema constrains the other.
abstract interface class PreferencesRepository {
  Future<AppPreferences> load();
  Future<void> save(AppPreferences preferences);
}

/// Keys address entries of the injected catalog; operational failures (network,
/// disk, verification) surface as failed-phase snapshots, never thrown errors.
/// [load] is the one exception: a store the process cannot read at all throws
/// [PersistenceException] instead of presenting invented state, while a
/// corrupt store still quarantines and falls back to defaults.
abstract interface class ModelManagementRepository {
  Future<ModelState> load();

  /// Emits persisted snapshots until it installs, fails, pauses, or cancels.
  Stream<ModelState> download(String artifactKey);

  /// Out-of-band stop that keeps partial data for a later [download].
  Future<ModelState> pause(String artifactKey);

  /// Out-of-band stop that discards partial data.
  Future<ModelState> cancel(String artifactKey);

  Future<ModelState> delete(String artifactKey);

  /// Bookkeeping only: loading and unloading weights is the inference
  /// repository's job alone (#42). A null [failure] clears any recorded one.
  Future<ModelState> recordRuntime(RuntimePhase phase, {String? failure});

  /// Registers a hand-added catalog entry (Advanced mode), which then
  /// downloads, verifies, lists and deletes exactly like a pinned one (#52).
  /// Re-adding a key refreshes the entry without disturbing its download state;
  /// receipts are scoped by revision, so a changed commit re-earns its proof.
  Future<ModelState> addModel(ModelCatalogEntry entry);
}

abstract interface class BenchmarkRepository {
  Future<BenchmarkRecord> run(String caseId, BenchmarkPhase phase);
  Future<String> export(BenchmarkRecord result);
}
