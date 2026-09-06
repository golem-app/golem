// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

String _$chatControllerHash() => r'2b195fe28fbac1eb3d6d9dd03ca8bd55610aa71a';

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
