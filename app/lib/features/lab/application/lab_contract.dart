import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../broker/effective_sampling.dart';
import '../../../broker/model_profile.dart';
import '../../../broker/runtime.dart' show BrokerSamplingParameters;
import '../../../core/providers/retry.dart';
import 'lab_bench_controller.dart';

part 'lab_contract.g.dart';

/// The contract the next run will carry: the broker's effective sampling for
/// the armed profile under the current settings, exactly as `send` computes
/// it. Null while nothing is armed. Recomputed only when its inputs move —
/// the bench state is reassigned every publish, and a run cannot change
/// either input while it flies.
@Riverpod(keepAlive: true, retry: noRetry)
BrokerSamplingParameters? labContract(Ref ref) {
  final (armed, settings) = ref.watch(
    labBenchControllerProvider.select((s) => (s.armed, s.settings)),
  );
  if (armed == null) return null;
  final profile = modelProfiles[armed.profileKey]!;
  final (sampling, _) = effectiveSampling(
    profile: profile,
    defaults: profile.sampling(reasoningEnabled: settings.reasoningEnabled),
    overrides: settings.toOverrides(),
    seed: settings.seed,
  );
  return sampling;
}
