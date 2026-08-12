/// Cross-feature controller capabilities (#88). An owning controller binds its
/// own methods here during `build()`, and dependent controllers read this seam
/// instead of the owner's provider, so feature ownership points one way.
///
/// Unbound is not an error: it means the owner has not built yet, and every
/// capability mirrors what its pre-split call already did against a controller
/// with empty state — commands no-op, facts report an idle session.
final class ChatSessionBridge {
  String? Function()? _activeModelKey;
  bool Function()? _generationActive;

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
