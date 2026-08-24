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

@ProviderFor(storageBreakdown)
final storageBreakdownProvider = StorageBreakdownProvider._();

/// Storage accounting for the drawer meter and the Storage screen. Free and
/// total bytes are null whenever the platform cannot report them (or the seams
/// are unwired) — surfaces hide those figures instead of inventing them. The
/// provider owns seam tolerance; the service owns the computation and its
/// required-vs-optional failure policy.

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

String _$storageBreakdownHash() => r'37052d38d1c2bbc44c1959881ac1756e421aa29d';
