// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'benchmark_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// KeepAlive — a decision, not the old blanket default: a running benchmark
/// keeps running and its result survives leaving the screen.

@ProviderFor(BenchmarkController)
final benchmarkControllerProvider = BenchmarkControllerProvider._();

/// KeepAlive — a decision, not the old blanket default: a running benchmark
/// keeps running and its result survives leaving the screen.
final class BenchmarkControllerProvider
    extends $NotifierProvider<BenchmarkController, BenchmarkState> {
  /// KeepAlive — a decision, not the old blanket default: a running benchmark
  /// keeps running and its result survives leaving the screen.
  BenchmarkControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
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
    r'712ff941abd9db2d7880ee86b9217438d356f168';

/// KeepAlive — a decision, not the old blanket default: a running benchmark
/// keeps running and its result survives leaving the screen.

abstract class _$BenchmarkController extends $Notifier<BenchmarkState> {
  BenchmarkState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BenchmarkState, BenchmarkState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BenchmarkState, BenchmarkState>,
              BenchmarkState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
