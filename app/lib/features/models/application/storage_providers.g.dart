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
///
/// It counts chats but does not watch chat: it lives one layer below chat in
/// the feature direction (#129), so `ChatController` invalidates it when the
/// conversation and message counts move. Every other input is a core seam or
/// this feature's own controller. Staleness is owned entirely by invalidation
/// — that signal and `ref.invalidate` after a cache clear — never by a
/// `KeepAliveLink` TTL (handbook v5.0 §4.4, a silent no-op on keepAlive
/// providers).
///
/// KeepAlive, deliberately (#69): the always-mounted drawer meter watches it
/// continuously anyway, and autoDispose is ruled out besides — on the pinned
/// flutter_riverpod (3.3.2) a widget-watched derivation over an async
/// controller trips Flutter's element-update invariant when a provider scope
/// is swapped mid-test, the class of bug fixed upstream in 3.4.0
/// ("markNeedsBuild ... inside Widget lifecycle"). The pin cannot move on this
/// SDK — flutter_test's test_api caps analyzer below the ^13 the newer
/// generator needs, and the family is exact-pinned end to end
/// (docs/notes/dependencies.md). Revisit on the SDK bump (#38).

@ProviderFor(storageBreakdown)
final storageBreakdownProvider = StorageBreakdownProvider._();

/// Storage accounting for the drawer meter and the Storage screen. Free and
/// total bytes are null whenever the platform cannot report them (or the seams
/// are unwired) — surfaces hide those figures instead of inventing them. The
/// provider owns seam tolerance; the service owns the computation and its
/// required-vs-optional failure policy.
///
/// It counts chats but does not watch chat: it lives one layer below chat in
/// the feature direction (#129), so `ChatController` invalidates it when the
/// conversation and message counts move. Every other input is a core seam or
/// this feature's own controller. Staleness is owned entirely by invalidation
/// — that signal and `ref.invalidate` after a cache clear — never by a
/// `KeepAliveLink` TTL (handbook v5.0 §4.4, a silent no-op on keepAlive
/// providers).
///
/// KeepAlive, deliberately (#69): the always-mounted drawer meter watches it
/// continuously anyway, and autoDispose is ruled out besides — on the pinned
/// flutter_riverpod (3.3.2) a widget-watched derivation over an async
/// controller trips Flutter's element-update invariant when a provider scope
/// is swapped mid-test, the class of bug fixed upstream in 3.4.0
/// ("markNeedsBuild ... inside Widget lifecycle"). The pin cannot move on this
/// SDK — flutter_test's test_api caps analyzer below the ^13 the newer
/// generator needs, and the family is exact-pinned end to end
/// (docs/notes/dependencies.md). Revisit on the SDK bump (#38).

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
  ///
  /// It counts chats but does not watch chat: it lives one layer below chat in
  /// the feature direction (#129), so `ChatController` invalidates it when the
  /// conversation and message counts move. Every other input is a core seam or
  /// this feature's own controller. Staleness is owned entirely by invalidation
  /// — that signal and `ref.invalidate` after a cache clear — never by a
  /// `KeepAliveLink` TTL (handbook v5.0 §4.4, a silent no-op on keepAlive
  /// providers).
  ///
  /// KeepAlive, deliberately (#69): the always-mounted drawer meter watches it
  /// continuously anyway, and autoDispose is ruled out besides — on the pinned
  /// flutter_riverpod (3.3.2) a widget-watched derivation over an async
  /// controller trips Flutter's element-update invariant when a provider scope
  /// is swapped mid-test, the class of bug fixed upstream in 3.4.0
  /// ("markNeedsBuild ... inside Widget lifecycle"). The pin cannot move on this
  /// SDK — flutter_test's test_api caps analyzer below the ^13 the newer
  /// generator needs, and the family is exact-pinned end to end
  /// (docs/notes/dependencies.md). Revisit on the SDK bump (#38).
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
