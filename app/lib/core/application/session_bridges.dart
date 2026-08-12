import '../domain/app_state.dart';
import '../domain/model_catalog.dart';
import '../domain/models.dart';

/// Cross-feature controller capabilities (#88). An owning controller binds its
/// own methods here during `build()`, and dependent controllers read this seam
/// instead of the owner's provider, so feature ownership points one way.
///
/// Before the split, dependents reached the owner with `ref.read`, which
/// lazily constructs an unbuilt provider. The launch composition restores
/// that: it binds [bindEnsureOwner] with a read of the owner's provider, so a
/// dispatch that arrives first forces the owner to build — and the owner
/// binds itself here before its first await. A hand-rolled container without
/// that hook must build the owner (or bind here) before dispatching; until
/// then commands no-op and facts mirror a controller that has not finished
/// hydrating — no active model key, no generation in flight.
final class ChatSessionBridge {
  void Function()? _ensureOwner;
  Future<void> Function()? _persistCurrent;
  ChatState? Function()? _sessionState;

  void bindEnsureOwner(void Function() fn) => _ensureOwner = fn;

  void bindPersistCurrent(Future<void> Function() fn) => _persistCurrent = fn;

  /// The live session state, exactly what the owner's `state.value` reads;
  /// one getter so the facts below can never be bound partially.
  void bindSessionState(ChatState? Function() fn) => _sessionState = fn;

  /// Persists the live session under the current save-history policy.
  Future<void> persistCurrent() async {
    _ensureOwner?.call();
    await _persistCurrent?.call();
  }

  /// The active conversation's model choice, or null while chat has no state.
  String? activeModelKey() {
    _ensureOwner?.call();
    return _sessionState?.call()?.active?.modelKey;
  }

  /// Whether a generation is visibly in flight; false while chat has no state.
  bool generationActive() {
    _ensureOwner?.call();
    final state = _sessionState?.call();
    return state != null && state.generation != GenerationPhase.idle;
  }
}

/// The model feature's capabilities offered across feature boundaries (#88),
/// bound by ModelController during `build()`. The same ensure-owner contract
/// as [ChatSessionBridge] applies.
final class ModelSessionBridge {
  void Function()? _ensureOwner;
  Future<void> Function()? _reflectEngineLoaded;
  Future<void> Function(ModelCatalogEntry)? _registerCustomModel;

  void bindEnsureOwner(void Function() fn) => _ensureOwner = fn;

  void bindReflectEngineLoaded(Future<void> Function() fn) =>
      _reflectEngineLoaded = fn;

  void bindRegisterCustomModel(Future<void> Function(ModelCatalogEntry) fn) =>
      _registerCustomModel = fn;

  /// Registers a committed custom model with the runtime catalog. A failed
  /// registration surfaces on the model card; the stored spec re-merges at
  /// the next launch either way.
  Future<void> registerCustomModel(ModelCatalogEntry entry) async {
    _ensureOwner?.call();
    await _registerCustomModel?.call(entry);
  }

  /// Records that the engine holds weights after a lazy prepare.
  Future<void> reflectEngineLoaded() async {
    _ensureOwner?.call();
    await _reflectEngineLoaded?.call();
  }
}
