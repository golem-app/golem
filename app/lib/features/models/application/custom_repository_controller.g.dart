// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_repository_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The Advanced-mode add-a-repository flow (#129). It was a `sealed` state
/// machine owned by `_ModelsScreenState`, driven through `setState` callbacks
/// threaded down into the card.
///
/// KeepAlive: `ListView(children:)` disposes off-screen elements, so an
/// autoDispose provider would drop a resolution the moment the card scrolled
/// out — which is exactly why the state used to live on the screen. Holding
/// the typed text here as well is what the move buys: the draft and the fields
/// now leave and re-enter the screen together, where before the resolution card
/// could come back over two empty fields.

@ProviderFor(CustomRepositoryController)
final customRepositoryControllerProvider =
    CustomRepositoryControllerProvider._();

/// The Advanced-mode add-a-repository flow (#129). It was a `sealed` state
/// machine owned by `_ModelsScreenState`, driven through `setState` callbacks
/// threaded down into the card.
///
/// KeepAlive: `ListView(children:)` disposes off-screen elements, so an
/// autoDispose provider would drop a resolution the moment the card scrolled
/// out — which is exactly why the state used to live on the screen. Holding
/// the typed text here as well is what the move buys: the draft and the fields
/// now leave and re-enter the screen together, where before the resolution card
/// could come back over two empty fields.
final class CustomRepositoryControllerProvider
    extends
        $NotifierProvider<CustomRepositoryController, CustomRepositoryDraft> {
  /// The Advanced-mode add-a-repository flow (#129). It was a `sealed` state
  /// machine owned by `_ModelsScreenState`, driven through `setState` callbacks
  /// threaded down into the card.
  ///
  /// KeepAlive: `ListView(children:)` disposes off-screen elements, so an
  /// autoDispose provider would drop a resolution the moment the card scrolled
  /// out — which is exactly why the state used to live on the screen. Holding
  /// the typed text here as well is what the move buys: the draft and the fields
  /// now leave and re-enter the screen together, where before the resolution card
  /// could come back over two empty fields.
  CustomRepositoryControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'customRepositoryControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$customRepositoryControllerHash();

  @$internal
  @override
  CustomRepositoryController create() => CustomRepositoryController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CustomRepositoryDraft value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CustomRepositoryDraft>(value),
    );
  }
}

String _$customRepositoryControllerHash() =>
    r'1573daef40a4b9534f67c3316e5d442d89dd82d5';

/// The Advanced-mode add-a-repository flow (#129). It was a `sealed` state
/// machine owned by `_ModelsScreenState`, driven through `setState` callbacks
/// threaded down into the card.
///
/// KeepAlive: `ListView(children:)` disposes off-screen elements, so an
/// autoDispose provider would drop a resolution the moment the card scrolled
/// out — which is exactly why the state used to live on the screen. Holding
/// the typed text here as well is what the move buys: the draft and the fields
/// now leave and re-enter the screen together, where before the resolution card
/// could come back over two empty fields.

abstract class _$CustomRepositoryController
    extends $Notifier<CustomRepositoryDraft> {
  CustomRepositoryDraft build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CustomRepositoryDraft, CustomRepositoryDraft>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CustomRepositoryDraft, CustomRepositoryDraft>,
              CustomRepositoryDraft,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
