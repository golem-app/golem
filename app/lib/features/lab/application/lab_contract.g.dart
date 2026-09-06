// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lab_contract.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(labContract)
final labContractProvider = LabContractProvider._();

final class LabContractProvider
    extends $FunctionalProvider<LabContract?, LabContract?, LabContract?>
    with $Provider<LabContract?> {
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
  $ProviderElement<LabContract?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LabContract? create(Ref ref) {
    return labContract(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LabContract? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LabContract?>(value),
    );
  }
}

String _$labContractHash() => r'718e0bee85717e9814d98145b6f849edb1dbc7c8';
