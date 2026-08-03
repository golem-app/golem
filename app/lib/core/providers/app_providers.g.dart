// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(chatHistoryRepository)
const chatHistoryRepositoryProvider = ChatHistoryRepositoryProvider._();

final class ChatHistoryRepositoryProvider
    extends
        $FunctionalProvider<
          ChatHistoryRepository,
          ChatHistoryRepository,
          ChatHistoryRepository
        >
    with $Provider<ChatHistoryRepository> {
  const ChatHistoryRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatHistoryRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatHistoryRepositoryHash();

  @$internal
  @override
  $ProviderElement<ChatHistoryRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ChatHistoryRepository create(Ref ref) {
    return chatHistoryRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatHistoryRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatHistoryRepository>(value),
    );
  }
}

String _$chatHistoryRepositoryHash() =>
    r'272ebcd1745a580ce2a622e5b227e91c4435f30e';

@ProviderFor(inferenceRepository)
const inferenceRepositoryProvider = InferenceRepositoryProvider._();

final class InferenceRepositoryProvider
    extends
        $FunctionalProvider<
          InferenceRepository,
          InferenceRepository,
          InferenceRepository
        >
    with $Provider<InferenceRepository> {
  const InferenceRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inferenceRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inferenceRepositoryHash();

  @$internal
  @override
  $ProviderElement<InferenceRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  InferenceRepository create(Ref ref) {
    return inferenceRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(InferenceRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<InferenceRepository>(value),
    );
  }
}

String _$inferenceRepositoryHash() =>
    r'82143828d32f1c068c8a1562f08085502e619275';

@ProviderFor(modelManagementRepository)
const modelManagementRepositoryProvider = ModelManagementRepositoryProvider._();

final class ModelManagementRepositoryProvider
    extends
        $FunctionalProvider<
          ModelManagementRepository,
          ModelManagementRepository,
          ModelManagementRepository
        >
    with $Provider<ModelManagementRepository> {
  const ModelManagementRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modelManagementRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modelManagementRepositoryHash();

  @$internal
  @override
  $ProviderElement<ModelManagementRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ModelManagementRepository create(Ref ref) {
    return modelManagementRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ModelManagementRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ModelManagementRepository>(value),
    );
  }
}

String _$modelManagementRepositoryHash() =>
    r'883bf3845440e47f63576a82f18f225f31be3622';

@ProviderFor(benchmarkRepository)
const benchmarkRepositoryProvider = BenchmarkRepositoryProvider._();

final class BenchmarkRepositoryProvider
    extends
        $FunctionalProvider<
          BenchmarkRepository,
          BenchmarkRepository,
          BenchmarkRepository
        >
    with $Provider<BenchmarkRepository> {
  const BenchmarkRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'benchmarkRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$benchmarkRepositoryHash();

  @$internal
  @override
  $ProviderElement<BenchmarkRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BenchmarkRepository create(Ref ref) {
    return benchmarkRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BenchmarkRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BenchmarkRepository>(value),
    );
  }
}

String _$benchmarkRepositoryHash() =>
    r'c71d916e23996f845670a9ad8da54540b73dcdb7';

@ProviderFor(ChatController)
const chatControllerProvider = ChatControllerProvider._();

final class ChatControllerProvider
    extends $AsyncNotifierProvider<ChatController, ChatState> {
  const ChatControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
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

String _$chatControllerHash() => r'13c3bcbbdef3fb96725e62268bb536a8e02d4527';

abstract class _$ChatController extends $AsyncNotifier<ChatState> {
  FutureOr<ChatState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<ChatState>, ChatState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ChatState>, ChatState>,
              AsyncValue<ChatState>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(ModelController)
const modelControllerProvider = ModelControllerProvider._();

final class ModelControllerProvider
    extends $AsyncNotifierProvider<ModelController, ModelState> {
  const ModelControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
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

String _$modelControllerHash() => r'890a5b7e817de00a4e332a31eb1cd1a7b7d7bcad';

abstract class _$ModelController extends $AsyncNotifier<ModelState> {
  FutureOr<ModelState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<ModelState>, ModelState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ModelState>, ModelState>,
              AsyncValue<ModelState>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(StartupController)
const startupControllerProvider = StartupControllerProvider._();

final class StartupControllerProvider
    extends $AsyncNotifierProvider<StartupController, StartupState> {
  const StartupControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'startupControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$startupControllerHash();

  @$internal
  @override
  StartupController create() => StartupController();
}

String _$startupControllerHash() => r'937f4451c25348e2e4bdc562a9e8125d13f78af1';

abstract class _$StartupController extends $AsyncNotifier<StartupState> {
  FutureOr<StartupState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<StartupState>, StartupState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<StartupState>, StartupState>,
              AsyncValue<StartupState>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(BenchmarkController)
const benchmarkControllerProvider = BenchmarkControllerProvider._();

final class BenchmarkControllerProvider
    extends $NotifierProvider<BenchmarkController, BenchmarkState> {
  const BenchmarkControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'benchmarkControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$benchmarkControllerHash();

  @$internal
  @override
  BenchmarkController create() => BenchmarkController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BenchmarkState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BenchmarkState>(value),
    );
  }
}

String _$benchmarkControllerHash() =>
    r'd5ac45951cd24b9be36e3f97bf4f3f09c4ebdbd8';

abstract class _$BenchmarkController extends $Notifier<BenchmarkState> {
  BenchmarkState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<BenchmarkState, BenchmarkState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BenchmarkState, BenchmarkState>,
              BenchmarkState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
