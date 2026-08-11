import 'package:inferno/inferno.dart';

import '../core/domain/device_eligibility.dart';

/// The launch-time capability read: what this device *is*, taken once before
/// anything is downloaded or loaded. Both readings degrade to unknown — a
/// platform or an engine that will not answer must never fail the launch, and
/// must never be mistaken for a refusal — and they run concurrently, because
/// this sits ahead of every other launch step inside the composition deadline.
///
/// The simulated backend reads nothing at all: it loads no weights, so it has
/// no floor, and a qa build must not depend on a platform channel or on native
/// assets its composition never links. [engineProbe] is the seam that keeps
/// this testable from outside the broker, where Inferno cannot be imported.
Future<DeviceCapabilities> probeDeviceCapabilities({
  required String backendName,
  required Future<int?> Function() physicalMemoryBytes,
  int memoryOverrideBytes = 0,
  bool forceEngineUnsupported = false,
  Future<bool?> Function(String backendName)? engineProbe,
}) async {
  if (backendName == 'fake') return const DeviceCapabilities();
  final readings = await Future.wait([
    memoryOverrideBytes > 0
        ? Future<Object?>.value(memoryOverrideBytes)
        : _guarded<Object?>(physicalMemoryBytes),
    forceEngineUnsupported
        ? Future<Object?>.value(false)
        : _guarded<Object?>(
            () => (engineProbe ?? _engineSupported)(backendName),
          ),
  ]);
  return DeviceCapabilities(
    physicalMemoryBytes: readings[0] as int?,
    engineSupported: readings[1] as bool?,
  );
}

/// Whether the engine this build composed can execute here at all. `auto` is
/// llama.cpp (ADR 0002), so it asks the same question, and it asks about that
/// engine alone — the probe otherwise loads every shipped engine's library on
/// the launch path to answer about one.
///
/// An engine missing from the payload is unknown, not unsupported: a carrier
/// this platform does not ship says nothing about the CPU, and answering
/// `false` there would refuse the device under the instruction-set copy.
Future<bool?> _engineSupported(String backendName) async {
  final engine = switch (backendName) {
    'mlx' => InfernoEngineKind.mlx,
    'llama' || 'auto' => InfernoEngineKind.llamaCpp,
    _ => null,
  };
  if (engine == null) return null;
  final probe = await Inferno.probeDevice(engine: engine);
  for (final reported in probe.engines) {
    if (reported.engine == engine) return reported.available;
  }
  return null;
}

/// One guard for every reading: a probe that throws, or answers nothing, leaves
/// the fact unknown, and the classifier treats unknown as permitting — this
/// degrades toward letting a device try, never toward refusing it. The timeout
/// bounds a probe that answers late; native work that blocks before yielding is
/// bounded by asking one engine rather than all of them.
Future<T?> _guarded<T>(Future<T?> Function() probe) async {
  try {
    return await probe().timeout(const Duration(seconds: 1));
  } catch (_) {
    return null;
  }
}
