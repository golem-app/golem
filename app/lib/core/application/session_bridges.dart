import '../domain/app_state.dart';
import '../domain/model_catalog.dart';
import '../domain/models.dart';

/// What the model commands ask of whoever owns the session: the model the
/// engine would load now, and whether a generation is in flight.
typedef SessionFacts = ({String? activeModelKey, bool generationActive});

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
  SessionFacts? Function()? _facts;

  void bindEnsureOwner(void Function() fn) => _ensureOwner = fn;

  void bindPersistCurrent(Future<void> Function() fn) => _persistCurrent = fn;

  /// The live session state, exactly what the owner's `state.value` reads;
  /// one getter so the facts can never be bound partially. In flight means
  /// preparing or streaming, not merely non-idle: [GenerationPhase.failed] is
  /// sticky until the user retries or discards, and treating it as active
  /// would block the very commands the failure copy tells them to use
  /// (#124). Matches the chat screen's own busy predicate.
  void bindSessionState(ChatState? Function() fn) => bindFacts(() {
    final state = fn();
    return state == null
        ? null
        : (
            activeModelKey: state.active?.modelKey,
            generationActive:
                state.generation == GenerationPhase.preparing ||
                state.generation == GenerationPhase.streaming,
          );
  });

  /// The same facts from an owner that is not chat — the bench (ADR 0021),
  /// which has no chat state to derive them from.
  void bindFacts(SessionFacts? Function() fn) => _facts = fn;

  /// Persists the live session under the current save-history policy.
  Future<void> persistCurrent() async {
    _ensureOwner?.call();
    await _persistCurrent?.call();
  }

  /// The owner's model choice, or null while it has no state.
  String? activeModelKey() {
    _ensureOwner?.call();
    return _facts?.call()?.activeModelKey;
  }

  /// Whether a generation is visibly in flight; false while the owner has no
  /// state.
  bool generationActive() {
    _ensureOwner?.call();
    return _facts?.call()?.generationActive ?? false;
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
