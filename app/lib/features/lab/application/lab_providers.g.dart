// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lab_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The configurations the bench offers, from the pinned catalog.

@ProviderFor(labConfigurationList)
final labConfigurationListProvider = LabConfigurationListProvider._();

/// The configurations the bench offers, from the pinned catalog.

final class LabConfigurationListProvider
    extends
        $FunctionalProvider<
          List<LabConfiguration>,
          List<LabConfiguration>,
          List<LabConfiguration>
        >
    with $Provider<List<LabConfiguration>> {
  /// The configurations the bench offers, from the pinned catalog.
  LabConfigurationListProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'labConfigurationListProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$labConfigurationListHash();

  @$internal
  @override
  $ProviderElement<List<LabConfiguration>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<LabConfiguration> create(Ref ref) {
    return labConfigurationList(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<LabConfiguration> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<LabConfiguration>>(value),
    );
  }
}

String _$labConfigurationListHash() =>
    r'72db0d41932f44fe2cae0672973551c641ff78a1';

/// The families the sidebar and the Rig list, grouped once per catalog
/// rather than on every rebuild.

@ProviderFor(labModelFamilies)
final labModelFamiliesProvider = LabModelFamiliesProvider._();

/// The families the sidebar and the Rig list, grouped once per catalog
/// rather than on every rebuild.

final class LabModelFamiliesProvider
    extends
        $FunctionalProvider<
          List<LabModelFamily>,
          List<LabModelFamily>,
          List<LabModelFamily>
        >
    with $Provider<List<LabModelFamily>> {
  /// The families the sidebar and the Rig list, grouped once per catalog
  /// rather than on every rebuild.
  LabModelFamiliesProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'labModelFamiliesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$labModelFamiliesHash();

  @$internal
  @override
  $ProviderElement<List<LabModelFamily>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<LabModelFamily> create(Ref ref) {
    return labModelFamilies(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<LabModelFamily> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<LabModelFamily>>(value),
    );
  }
}

String _$labModelFamiliesHash() => r'c8f91518fdb49b63976ca3cffc98780f1b22b1c6';

@ProviderFor(labProbes)
final labProbesProvider = LabProbesProvider._();

final class LabProbesProvider
    extends $FunctionalProvider<LabProbes, LabProbes, LabProbes>
    with $Provider<LabProbes> {
  LabProbesProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'labProbesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$labProbesHash();

  @$internal
  @override
  $ProviderElement<LabProbes> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LabProbes create(Ref ref) {
    return labProbes(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LabProbes value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LabProbes>(value),
    );
  }
}

String _$labProbesHash() => r'43cf3589810d0ab2433a0bbd37db2d694d1cb43a';

/// What this machine is, read once per session. A reading that fails or
/// stalls stays unknown — the Rig says so — rather than delaying a run.

@ProviderFor(labDeviceProvenance)
final labDeviceProvenanceProvider = LabDeviceProvenanceProvider._();

/// What this machine is, read once per session. A reading that fails or
/// stalls stays unknown — the Rig says so — rather than delaying a run.

final class LabDeviceProvenanceProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeviceProvenance?>,
          DeviceProvenance?,
          FutureOr<DeviceProvenance?>
        >
    with
        $FutureModifier<DeviceProvenance?>,
        $FutureProvider<DeviceProvenance?> {
  /// What this machine is, read once per session. A reading that fails or
  /// stalls stays unknown — the Rig says so — rather than delaying a run.
  LabDeviceProvenanceProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'labDeviceProvenanceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$labDeviceProvenanceHash();

  @$internal
  @override
  $FutureProviderElement<DeviceProvenance?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DeviceProvenance?> create(Ref ref) {
    return labDeviceProvenance(ref);
  }
}

String _$labDeviceProvenanceHash() =>
    r'769042d9458f904d53e4b4f14b3836c1209629c9';
