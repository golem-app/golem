import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../broker/effective_sampling.dart';
import '../../../broker/model_profile.dart';
import '../../../broker/runtime.dart' show BrokerSamplingParameters;
import '../../../core/providers/retry.dart';
import 'lab_bench_controller.dart';

part 'lab_contract.g.dart';

/// The contract the next run will carry: the broker's effective sampling for
/// the armed profile under the current settings, exactly as `send` computes
/// it. Null while nothing is armed.
final class LabContract {
  const LabContract({required this.sampling, required this.pinned});

  final BrokerSamplingParameters sampling;

  /// Whether the profile pins the sampling fields in this mode, in which
  /// case the settings sheet shows them as the profile's, not the user's.
  final bool pinned;
}

@Riverpod(keepAlive: true, retry: noRetry)
LabContract? labContract(Ref ref) {
  final bench = ref.watch(labBenchControllerProvider);
  final armed = bench.armed;
  if (armed == null) return null;
  final profile = modelProfiles[armed.profileKey]!;
  final defaults = profile.sampling(
    reasoningEnabled: bench.settings.reasoningEnabled,
  );
  final (sampling, _) = effectiveSampling(
    profile: profile,
    defaults: defaults,
    overrides: bench.settings.toOverrides(),
    seed: bench.settings.seed,
  );
  return LabContract(sampling: sampling, pinned: defaults.pinned);
}
