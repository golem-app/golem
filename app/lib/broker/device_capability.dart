import 'package:inferno/inferno.dart';

import '../core/domain/device_eligibility.dart';

/// The launch-time capability read: what this device *is*, taken once before
/// anything is downloaded or loaded. Both readings are guarded and degrade to
/// unknown — a platform or an engine that will not answer must never fail the
/// launch, and must never be mistaken for a refusal.
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
  return DeviceCapabilities(
    physicalMemoryBytes: memoryOverrideBytes > 0
        ? memoryOverrideBytes
        : await _guarded(physicalMemoryBytes),
    engineSupported: forceEngineUnsupported
        ? false
        : await _guarded(() => (engineProbe ?? _engineSupported)(backendName)),
  );
}

/// Whether the engine this build composed can execute here at all. `auto` is
/// llama.cpp (ADR 0002), so it asks the same question. The probe reads a native
/// free function — no engine is created and no weights are touched.
Future<bool?> _engineSupported(String backendName) async {
  final engine = switch (backendName) {
    'mlx' => InfernoEngineKind.mlx,
    'llama' || 'auto' => InfernoEngineKind.llamaCpp,
    _ => null,
  };
  if (engine == null) return null;
  return (await Inferno.probeDevice()).supports(engine);
}

/// One guard for every reading: a probe that throws, hangs, or answers nothing
/// leaves the fact unknown. The classifier treats unknown as permitting, so
/// this degrades toward letting a device try, never toward refusing it.
Future<T?> _guarded<T>(Future<T?> Function() probe) async {
  try {
    return await probe().timeout(const Duration(seconds: 1));
  } catch (_) {
    return null;
  }
}
