import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/device_eligibility.dart';

const _gib = 1024 * 1024 * 1024;

DeviceEligibility _classify({
  int? memory,
  bool? engineSupported,
  bool apple = false,
}) => classifyDevice(
  capabilities: DeviceCapabilities(
    physicalMemoryBytes: memory,
    engineSupported: engineSupported,
  ),
  memoryFloorBytes: deviceMemoryFloorBytes(reportsInstalledMemory: apple),
);

void main() {
  test('the floor is one nominal rule spelled per platform', () {
    expect(
      deviceMemoryFloorBytes(reportsInstalledMemory: true),
      appleMemoryFloorBytes,
    );
    expect(
      deviceMemoryFloorBytes(reportsInstalledMemory: false),
      androidMemoryFloorBytes,
    );
    expect(appleMemoryFloorBytes, 4 * _gib);
    expect(androidMemoryFloorBytes, 3 * _gib);
    expect(deviceMemoryThresholdBytes, 7 * _gib);
  });

  group('memory tiers', () {
    test('at or above the threshold takes the preferred model', () {
      for (final apple in [true, false]) {
        expect(
          _classify(memory: deviceMemoryThresholdBytes, apple: apple).tier,
          DeviceTier.preferred,
          reason: 'apple=$apple',
        );
        expect(
          _classify(memory: 12 * _gib, apple: apple).tier,
          DeviceTier.preferred,
        );
      }
    });

    test('between the floor and the threshold takes the lighter model', () {
      // A nominal 8 GB Android phone reads ~7.5 GB, which is why the threshold
      // is 7 GiB; 6 GiB is a genuine 6 GB device and belongs on the light tier.
      expect(_classify(memory: 6 * _gib).tier, DeviceTier.light);
      expect(_classify(memory: 4 * _gib, apple: true).tier, DeviceTier.light);
    });

    test('an iPhone 12 is the lowest supported Apple device', () {
      // ProcessInfo.physicalMemory reports installed DRAM, so these are the
      // exact readings: iPhone 12 has 4 GB, iPhone XR and SE 3 have 3 GB.
      expect(_classify(memory: 4 * _gib, apple: true).tier, DeviceTier.light);
      final xr = _classify(memory: 3 * _gib, apple: true);
      expect(xr.tier, DeviceTier.unsupported);
      expect(xr.reason, DeviceIneligibilityReason.belowMemoryFloor);
      expect(xr.runsModels, isFalse);
      expect(xr.message, isNotNull);
    });

    test(
      'a nominal 4 GB Android phone clears the floor its reading undercuts',
      () {
        // totalMem is net of reservations: 4 GB phones report 3.4-3.7 GiB, 3 GB
        // phones about 2.7 GiB. The 3 GiB floor separates them.
        expect(_classify(memory: 3435973836).tier, DeviceTier.light); // 3.2 GiB
        expect(_classify(memory: 3972844748).tier, DeviceTier.light); // 3.7 GiB
        expect(_classify(memory: 2899102924).tier, DeviceTier.unsupported);
      },
    );

    test('unknown memory takes the lighter model and never refuses', () {
      final unknown = _classify();
      expect(unknown.tier, DeviceTier.light);
      expect(unknown.reason, isNull);
      expect(unknown.runsModels, isTrue);
    });
  });

  group('instruction set', () {
    test('an engine that cannot execute here refuses at any memory size', () {
      final refused = _classify(memory: 12 * _gib, engineSupported: false);
      expect(refused.tier, DeviceTier.unsupported);
      expect(refused.reason, DeviceIneligibilityReason.missingInstructionSet);
      expect(refused.message, contains('instruction set'));
    });

    test('it decides before memory, including when memory is unknown', () {
      expect(
        _classify(engineSupported: false).reason,
        DeviceIneligibilityReason.missingInstructionSet,
      );
      // Both refusals apply; the one naming the real blocker must win, since
      // freeing memory would not make this device run a model.
      expect(
        _classify(memory: _gib, engineSupported: false).reason,
        DeviceIneligibilityReason.missingInstructionSet,
      );
    });

    test('an unreachable probe classifies on memory alone', () {
      expect(_classify(memory: 8 * _gib).tier, DeviceTier.preferred);
      expect(
        _classify(memory: 8 * _gib, engineSupported: null).tier,
        DeviceTier.preferred,
      );
      expect(
        _classify(memory: 8 * _gib, engineSupported: true).tier,
        DeviceTier.preferred,
      );
    });
  });

  test('an unclassified process permits everything', () {
    const value = DeviceEligibility.unclassified();
    expect(value.runsModels, isTrue);
    expect(value.reason, isNull);
    expect(value.message, isNull);
  });

  test('eligibility is value-equal so widgets can select on it', () {
    expect(_classify(memory: 8 * _gib), _classify(memory: 8 * _gib));
    expect(
      _classify(memory: 8 * _gib).hashCode,
      _classify(memory: 8 * _gib).hashCode,
    );
    expect(_classify(memory: 8 * _gib) == _classify(memory: 4 * _gib), isFalse);
    expect(
      const DeviceCapabilities(physicalMemoryBytes: 1, engineSupported: true),
      const DeviceCapabilities(physicalMemoryBytes: 1, engineSupported: true),
    );
  });
}
