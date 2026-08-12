// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A cheap signature that changes only when conversations or messages are added
/// or removed. ChatController reassigns state on every streaming delta, so
/// anything as heavy as disk probing must key on this rather than the raw chat
/// state, or it re-runs per token for the always-mounted drawer meter.
/// KeepAlive, deliberately (#69): would classify as an autoDispose derived
/// value, but on the pinned flutter_riverpod (3.3.2) a widget-watched
/// derivation over an async controller still trips Flutter's element-update
/// invariant when a provider scope is swapped mid-test — the class of bug
/// fixed upstream in 3.4.0 ("markNeedsBuild ... inside Widget lifecycle").
/// Revisit when the pin crosses 3.4.0.

@ProviderFor(chatStorageSignature)
final chatStorageSignatureProvider = ChatStorageSignatureProvider._();

/// A cheap signature that changes only when conversations or messages are added
/// or removed. ChatController reassigns state on every streaming delta, so
/// anything as heavy as disk probing must key on this rather than the raw chat
/// state, or it re-runs per token for the always-mounted drawer meter.
/// KeepAlive, deliberately (#69): would classify as an autoDispose derived
/// value, but on the pinned flutter_riverpod (3.3.2) a widget-watched
/// derivation over an async controller still trips Flutter's element-update
/// invariant when a provider scope is swapped mid-test — the class of bug
/// fixed upstream in 3.4.0 ("markNeedsBuild ... inside Widget lifecycle").
/// Revisit when the pin crosses 3.4.0.

final class ChatStorageSignatureProvider
    extends $FunctionalProvider<(int, int), (int, int), (int, int)>
    with $Provider<(int, int)> {
  /// A cheap signature that changes only when conversations or messages are added
  /// or removed. ChatController reassigns state on every streaming delta, so
  /// anything as heavy as disk probing must key on this rather than the raw chat
  /// state, or it re-runs per token for the always-mounted drawer meter.
  /// KeepAlive, deliberately (#69): would classify as an autoDispose derived
  /// value, but on the pinned flutter_riverpod (3.3.2) a widget-watched
  /// derivation over an async controller still trips Flutter's element-update
  /// invariant when a provider scope is swapped mid-test — the class of bug
  /// fixed upstream in 3.4.0 ("markNeedsBuild ... inside Widget lifecycle").
  /// Revisit when the pin crosses 3.4.0.
  ChatStorageSignatureProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'chatStorageSignatureProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatStorageSignatureHash();

  @$internal
  @override
  $ProviderElement<(int, int)> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  (int, int) create(Ref ref) {
    return chatStorageSignature(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue((int, int) value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<(int, int)>(value),
    );
  }
}

String _$chatStorageSignatureHash() =>
    r'ebfde4072049845a37f487bcef5a939d1755019a';

/// KeepAlive: the chat session aggregate — in-flight generation and unsaved
/// turns must survive every route transition.

@ProviderFor(ChatController)
final chatControllerProvider = ChatControllerProvider._();

/// KeepAlive: the chat session aggregate — in-flight generation and unsaved
/// turns must survive every route transition.
final class ChatControllerProvider
    extends $AsyncNotifierProvider<ChatController, ChatState> {
  /// KeepAlive: the chat session aggregate — in-flight generation and unsaved
  /// turns must survive every route transition.
  ChatControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'chatControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatControllerHash();

  @$internal
  @override
  ChatController create() => ChatController();
}

String _$chatControllerHash() => r'ca52e525d490a4fae28524159ea37f8fefc919e6';

/// KeepAlive: the chat session aggregate — in-flight generation and unsaved
/// turns must survive every route transition.

abstract class _$ChatController extends $AsyncNotifier<ChatState> {
  FutureOr<ChatState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ChatState>, ChatState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ChatState>, ChatState>,
              AsyncValue<ChatState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
