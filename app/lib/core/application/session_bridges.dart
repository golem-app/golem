import '../domain/model_catalog.dart';

/// Cross-feature controller capabilities (#88). An owning controller binds its
/// own methods here during `build()`, and dependent controllers read this seam
/// instead of the owner's provider, so feature ownership points one way.
///
/// Unbound is not an error: it means the owner has not built yet, and every
/// capability mirrors what its pre-split call already did against a controller
/// with empty state — commands no-op, facts report an idle session.
final class ChatSessionBridge {
  Future<void> Function()? _persistCurrent;
  String? Function()? _activeModelKey;
  bool Function()? _generationActive;

  void bindPersistCurrent(Future<void> Function() fn) => _persistCurrent = fn;

  /// Persists the live session under the current save-history policy. No-op
  /// while chat has not built, matching a persist of an empty session.
  Future<void> persistCurrent() async => await _persistCurrent?.call();

  void bindSessionFacts({
    required String? Function() activeModelKey,
    required bool Function() generationActive,
  }) {
    _activeModelKey = activeModelKey;
    _generationActive = generationActive;
  }

  /// The active conversation's model choice, or null while chat has no state.
  String? activeModelKey() => _activeModelKey?.call();

  /// Whether a generation is visibly in flight; false while chat has no state.
  bool generationActive() => _generationActive?.call() ?? false;
}

/// The model feature's capabilities offered across feature boundaries (#88),
/// bound by ModelController during `build()`.
final class ModelSessionBridge {
  Future<void> Function()? _reflectEngineLoaded;
  Future<void> Function(ModelCatalogEntry)? _registerCustomModel;

  void bindReflectEngineLoaded(Future<void> Function() fn) =>
      _reflectEngineLoaded = fn;

  void bindRegisterCustomModel(Future<void> Function(ModelCatalogEntry) fn) =>
      _registerCustomModel = fn;

  /// Registers a committed custom model with the runtime catalog. No-op while
  /// the model controller has not built; the stored spec re-merges at the
  /// next launch either way.
  Future<void> registerCustomModel(ModelCatalogEntry entry) async =>
      await _registerCustomModel?.call(entry);

  /// Records that the engine holds weights after a lazy prepare. No-op while
  /// the model controller has not built, matching its own empty-state guard.
  Future<void> reflectEngineLoaded() async =>
      await _reflectEngineLoaded?.call();
}
