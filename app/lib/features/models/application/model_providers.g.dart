// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Pinned entries plus the user's custom repositories, derived — never stored —
/// so the pinned manifest stays the single source of model knowledge.
/// KeepAlive, deliberately (#69): watched by always-mounted chat surfaces
/// (composer, drawer, recovery banner), so disposal would never fire in
/// practice — and the 3.3.2 scope-swap hazard (see storageBreakdown, which
/// records why the pin cannot move) rules autoDispose out.

@ProviderFor(effectiveModelCatalog)
final effectiveModelCatalogProvider = EffectiveModelCatalogProvider._();

/// Pinned entries plus the user's custom repositories, derived — never stored —
/// so the pinned manifest stays the single source of model knowledge.
/// KeepAlive, deliberately (#69): watched by always-mounted chat surfaces
/// (composer, drawer, recovery banner), so disposal would never fire in
/// practice — and the 3.3.2 scope-swap hazard (see storageBreakdown, which
/// records why the pin cannot move) rules autoDispose out.

final class EffectiveModelCatalogProvider
    extends
        $FunctionalProvider<
          List<ModelCatalogEntry>,
          List<ModelCatalogEntry>,
          List<ModelCatalogEntry>
        >
    with $Provider<List<ModelCatalogEntry>> {
  /// Pinned entries plus the user's custom repositories, derived — never stored —
  /// so the pinned manifest stays the single source of model knowledge.
  /// KeepAlive, deliberately (#69): watched by always-mounted chat surfaces
  /// (composer, drawer, recovery banner), so disposal would never fire in
  /// practice — and the 3.3.2 scope-swap hazard (see storageBreakdown, which
  /// records why the pin cannot move) rules autoDispose out.
  EffectiveModelCatalogProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'effectiveModelCatalogProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$effectiveModelCatalogHash();

  @$internal
  @override
  $ProviderElement<List<ModelCatalogEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<ModelCatalogEntry> create(Ref ref) {
    return effectiveModelCatalog(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ModelCatalogEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ModelCatalogEntry>>(value),
    );
  }
}

String _$effectiveModelCatalogHash() =>
    r'aa68c62ef5cceb4bef133c12bd8a560a65a1477d';

/// The models a per-chat selection may name: installed, and of the engine this
/// build composed. Derived here so chat, Settings, and Storage cannot disagree
/// about which model is live (#20).
/// KeepAlive, deliberately (#69): same grounds as effectiveModelCatalog —
/// continuously watched, and the 3.3.2 scope-swap hazard.

@ProviderFor(loadableModelKeys)
final loadableModelKeysProvider = LoadableModelKeysProvider._();

/// The models a per-chat selection may name: installed, and of the engine this
/// build composed. Derived here so chat, Settings, and Storage cannot disagree
/// about which model is live (#20).
/// KeepAlive, deliberately (#69): same grounds as effectiveModelCatalog —
/// continuously watched, and the 3.3.2 scope-swap hazard.

final class LoadableModelKeysProvider
    extends $FunctionalProvider<Set<String>, Set<String>, Set<String>>
    with $Provider<Set<String>> {
  /// The models a per-chat selection may name: installed, and of the engine this
  /// build composed. Derived here so chat, Settings, and Storage cannot disagree
  /// about which model is live (#20).
  /// KeepAlive, deliberately (#69): same grounds as effectiveModelCatalog —
  /// continuously watched, and the 3.3.2 scope-swap hazard.
  LoadableModelKeysProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'loadableModelKeysProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$loadableModelKeysHash();

  @$internal
  @override
  $ProviderElement<Set<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Set<String> create(Ref ref) {
    return loadableModelKeys(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$loadableModelKeysHash() => r'12e16f3f980da93856da1aa47fec36b9d9201e01';

/// One effective compatible artifact for startup, chat and runtime controls.
/// A stale persisted iOS GGUF choice cannot pull those surfaces away from the
/// MLX artifact the composed engine can actually load.

@ProviderFor(startupModelKey)
final startupModelKeyProvider = StartupModelKeyProvider._();

/// One effective compatible artifact for startup, chat and runtime controls.
/// A stale persisted iOS GGUF choice cannot pull those surfaces away from the
/// MLX artifact the composed engine can actually load.

final class StartupModelKeyProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// One effective compatible artifact for startup, chat and runtime controls.
  /// A stale persisted iOS GGUF choice cannot pull those surfaces away from the
  /// MLX artifact the composed engine can actually load.
  StartupModelKeyProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'startupModelKeyProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$startupModelKeyHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return startupModelKey(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$startupModelKeyHash() => r'2934f5ffc9b100d9467d21df8caccf9e472d76fd';

/// The keys a download may be *started* for: the pinned catalog, plus custom
/// repositories that resolved against Hugging Face and so have a real file
/// list. An unresolved entry synthesizes its files, so a request for it could
/// not succeed — Settings and the chat picker both withhold the affordance
/// rather than failing on the tap, and derive that from here so the rule has
/// one statement (#79).
/// KeepAlive, deliberately (#69): same grounds as loadableModelKeys.

@ProviderFor(downloadableModelKeys)
final downloadableModelKeysProvider = DownloadableModelKeysProvider._();

/// The keys a download may be *started* for: the pinned catalog, plus custom
/// repositories that resolved against Hugging Face and so have a real file
/// list. An unresolved entry synthesizes its files, so a request for it could
/// not succeed — Settings and the chat picker both withhold the affordance
/// rather than failing on the tap, and derive that from here so the rule has
/// one statement (#79).
/// KeepAlive, deliberately (#69): same grounds as loadableModelKeys.

final class DownloadableModelKeysProvider
    extends $FunctionalProvider<Set<String>, Set<String>, Set<String>>
    with $Provider<Set<String>> {
  /// The keys a download may be *started* for: the pinned catalog, plus custom
  /// repositories that resolved against Hugging Face and so have a real file
  /// list. An unresolved entry synthesizes its files, so a request for it could
  /// not succeed — Settings and the chat picker both withhold the affordance
  /// rather than failing on the tap, and derive that from here so the rule has
  /// one statement (#79).
  /// KeepAlive, deliberately (#69): same grounds as loadableModelKeys.
  DownloadableModelKeysProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'downloadableModelKeysProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$downloadableModelKeysHash();

  @$internal
  @override
  $ProviderElement<Set<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Set<String> create(Ref ref) {
    return downloadableModelKeys(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$downloadableModelKeysHash() =>
    r'f9cd2176ddd9c2ba36232444c34b2f369499f5d2';

/// KeepAlive: a command controller whose downloads, busy guard, and epochs
/// must survive leaving the Models screen (handbook v5.0 §3.4 — an
/// autoDispose command provider dies mid-flight).

@ProviderFor(ModelController)
final modelControllerProvider = ModelControllerProvider._();

/// KeepAlive: a command controller whose downloads, busy guard, and epochs
/// must survive leaving the Models screen (handbook v5.0 §3.4 — an
/// autoDispose command provider dies mid-flight).
final class ModelControllerProvider
    extends $AsyncNotifierProvider<ModelController, ModelState> {
  /// KeepAlive: a command controller whose downloads, busy guard, and epochs
  /// must survive leaving the Models screen (handbook v5.0 §3.4 — an
  /// autoDispose command provider dies mid-flight).
  ModelControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'modelControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modelControllerHash();

  @$internal
  @override
  ModelController create() => ModelController();
}

String _$modelControllerHash() => r'494ae5bae02b12c5fd1b52e3b9bc12df005530ab';

/// KeepAlive: a command controller whose downloads, busy guard, and epochs
/// must survive leaving the Models screen (handbook v5.0 §3.4 — an
/// autoDispose command provider dies mid-flight).

abstract class _$ModelController extends $AsyncNotifier<ModelState> {
  FutureOr<ModelState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ModelState>, ModelState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ModelState>, ModelState>,
              AsyncValue<ModelState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
