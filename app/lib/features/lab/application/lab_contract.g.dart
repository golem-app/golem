// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lab_contract.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The contract the next run will carry: the broker's effective sampling for
/// the armed profile under the current settings, exactly as `send` computes
/// it. Null while nothing is armed. Recomputed only when its inputs move —
/// the bench state is reassigned every publish, and a run cannot change
/// either input while it flies.

@ProviderFor(labContract)
final labContractProvider = LabContractProvider._();

/// The contract the next run will carry: the broker's effective sampling for
/// the armed profile under the current settings, exactly as `send` computes
/// it. Null while nothing is armed. Recomputed only when its inputs move —
/// the bench state is reassigned every publish, and a run cannot change
/// either input while it flies.

final class LabContractProvider
    extends
        $FunctionalProvider<
          BrokerSamplingParameters?,
          BrokerSamplingParameters?,
          BrokerSamplingParameters?
        >
    with $Provider<BrokerSamplingParameters?> {
  /// The contract the next run will carry: the broker's effective sampling for
  /// the armed profile under the current settings, exactly as `send` computes
  /// it. Null while nothing is armed. Recomputed only when its inputs move —
  /// the bench state is reassigned every publish, and a run cannot change
  /// either input while it flies.
  LabContractProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'labContractProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$labContractHash();

  @$internal
  @override
  $ProviderElement<BrokerSamplingParameters?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrokerSamplingParameters? create(Ref ref) {
    return labContract(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrokerSamplingParameters? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrokerSamplingParameters?>(value),
    );
  }
}

String _$labContractHash() => r'ced13c36dbc852357eda75aaeb9bf163594227a4';
