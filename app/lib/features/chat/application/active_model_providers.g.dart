// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_model_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The catalog key the open conversation effectively runs — stated once (#129).
/// The composer, the model picker, the Models screen, Storage and both label
/// helpers each derived it separately, and the copies had already drifted in
/// both directions at once: Send dark for a model the header named, and lit
/// for an artifact of the other engine (#118).
///
/// Null exactly where the resolution yields none — an operator sideload, which
/// no catalog entry describes, or a real build with nothing loadable yet.
///
/// [ChatController] deliberately does not read this. It is the *source* of the
/// conversation's key, so reading it here would make the provider depend on
/// itself; `resolveGenerationTarget` calls the same pure helper with the state
/// that command has just published.
///
/// KeepAlive, deliberately (#69): the composer, drawer and nav bar watch it
/// continuously, and it inherits the 3.3.2 scope-swap hazard recorded on
/// storageBreakdown.

@ProviderFor(activeModelKey)
final activeModelKeyProvider = ActiveModelKeyProvider._();

/// The catalog key the open conversation effectively runs — stated once (#129).
/// The composer, the model picker, the Models screen, Storage and both label
/// helpers each derived it separately, and the copies had already drifted in
/// both directions at once: Send dark for a model the header named, and lit
/// for an artifact of the other engine (#118).
///
/// Null exactly where the resolution yields none — an operator sideload, which
/// no catalog entry describes, or a real build with nothing loadable yet.
///
/// [ChatController] deliberately does not read this. It is the *source* of the
/// conversation's key, so reading it here would make the provider depend on
/// itself; `resolveGenerationTarget` calls the same pure helper with the state
/// that command has just published.
///
/// KeepAlive, deliberately (#69): the composer, drawer and nav bar watch it
/// continuously, and it inherits the 3.3.2 scope-swap hazard recorded on
/// storageBreakdown.

final class ActiveModelKeyProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// The catalog key the open conversation effectively runs — stated once (#129).
  /// The composer, the model picker, the Models screen, Storage and both label
  /// helpers each derived it separately, and the copies had already drifted in
  /// both directions at once: Send dark for a model the header named, and lit
  /// for an artifact of the other engine (#118).
  ///
  /// Null exactly where the resolution yields none — an operator sideload, which
  /// no catalog entry describes, or a real build with nothing loadable yet.
  ///
  /// [ChatController] deliberately does not read this. It is the *source* of the
  /// conversation's key, so reading it here would make the provider depend on
  /// itself; `resolveGenerationTarget` calls the same pure helper with the state
  /// that command has just published.
  ///
  /// KeepAlive, deliberately (#69): the composer, drawer and nav bar watch it
  /// continuously, and it inherits the 3.3.2 scope-swap hazard recorded on
  /// storageBreakdown.
  ActiveModelKeyProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'activeModelKeyProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeModelKeyHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return activeModelKey(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$activeModelKeyHash() => r'a8f167b428cb0079377b0a818e6623926577d38c';
