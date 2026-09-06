// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lab_bench_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// KeepAlive: a command controller whose run, epoch and timers must outlive
/// any one widget (handbook v5.0 §3.4).

@ProviderFor(LabBenchController)
final labBenchControllerProvider = LabBenchControllerProvider._();

/// KeepAlive: a command controller whose run, epoch and timers must outlive
/// any one widget (handbook v5.0 §3.4).
final class LabBenchControllerProvider
    extends $NotifierProvider<LabBenchController, LabBenchState> {
  /// KeepAlive: a command controller whose run, epoch and timers must outlive
  /// any one widget (handbook v5.0 §3.4).
  LabBenchControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'labBenchControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$labBenchControllerHash();

  @$internal
  @override
  LabBenchController create() => LabBenchController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LabBenchState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LabBenchState>(value),
    );
  }
}

String _$labBenchControllerHash() =>
    r'b13a7af4d364ad558402c7aa2f0ad52eab10b1c1';

/// KeepAlive: a command controller whose run, epoch and timers must outlive
/// any one widget (handbook v5.0 §3.4).

abstract class _$LabBenchController extends $Notifier<LabBenchState> {
  LabBenchState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LabBenchState, LabBenchState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LabBenchState, LabBenchState>,
              LabBenchState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
