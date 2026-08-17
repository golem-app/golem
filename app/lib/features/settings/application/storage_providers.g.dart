// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'storage_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Storage accounting for the drawer meter and the Storage screen. Free and
/// total bytes are null whenever the platform cannot report them (or the seams
/// are unwired) — surfaces hide those figures instead of inventing them. The
/// provider owns seam tolerance; the service owns the computation and its
/// required-vs-optional failure policy.
/// KeepAlive, deliberately (#69): the always-mounted drawer meter watches it
/// continuously anyway, and the 3.3.2 scope-swap hazard (see
/// chatStorageSignature) rules autoDispose out. Staleness is owned by
/// invalidation — the storage signature upstream and `ref.invalidate` after
/// a cache clear — never by a `KeepAliveLink` TTL (handbook v5.0 §4.4, a
/// silent no-op on keepAlive providers).

@ProviderFor(storageBreakdown)
final storageBreakdownProvider = StorageBreakdownProvider._();

/// Storage accounting for the drawer meter and the Storage screen. Free and
/// total bytes are null whenever the platform cannot report them (or the seams
/// are unwired) — surfaces hide those figures instead of inventing them. The
/// provider owns seam tolerance; the service owns the computation and its
/// required-vs-optional failure policy.
/// KeepAlive, deliberately (#69): the always-mounted drawer meter watches it
/// continuously anyway, and the 3.3.2 scope-swap hazard (see
/// chatStorageSignature) rules autoDispose out. Staleness is owned by
/// invalidation — the storage signature upstream and `ref.invalidate` after
/// a cache clear — never by a `KeepAliveLink` TTL (handbook v5.0 §4.4, a
/// silent no-op on keepAlive providers).

final class StorageBreakdownProvider
    extends
        $FunctionalProvider<
          AsyncValue<StorageBreakdown>,
          StorageBreakdown,
          FutureOr<StorageBreakdown>
        >
    with $FutureModifier<StorageBreakdown>, $FutureProvider<StorageBreakdown> {
  /// Storage accounting for the drawer meter and the Storage screen. Free and
  /// total bytes are null whenever the platform cannot report them (or the seams
  /// are unwired) — surfaces hide those figures instead of inventing them. The
  /// provider owns seam tolerance; the service owns the computation and its
  /// required-vs-optional failure policy.
  /// KeepAlive, deliberately (#69): the always-mounted drawer meter watches it
  /// continuously anyway, and the 3.3.2 scope-swap hazard (see
  /// chatStorageSignature) rules autoDispose out. Staleness is owned by
  /// invalidation — the storage signature upstream and `ref.invalidate` after
  /// a cache clear — never by a `KeepAliveLink` TTL (handbook v5.0 §4.4, a
  /// silent no-op on keepAlive providers).
  StorageBreakdownProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'storageBreakdownProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$storageBreakdownHash();

  @$internal
  @override
  $FutureProviderElement<StorageBreakdown> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<StorageBreakdown> create(Ref ref) {
    return storageBreakdown(ref);
  }
}

String _$storageBreakdownHash() => r'4ba7c85265ff7001eabf61e7b6339e0080f2a0ba';
