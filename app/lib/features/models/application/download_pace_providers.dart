import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/download_pace.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/retry.dart';
import 'model_providers.dart';

part 'download_pace_providers.g.dart';

/// The wall clock the pace notifier samples with, injectable so tests can
/// script byte/time pairs instead of racing real timers.
@Riverpod(keepAlive: true, retry: noRetry)
DateTime Function() paceClock(Ref ref) => DateTime.now;

/// Live rate/ETA for the single in-flight artifact, derived by sampling
/// [ModelController]'s byte counts against the injected clock — transferred
/// bytes while downloading, hashed bytes while verifying, each phase its own
/// window. `null` until the trailing window can quote an honest figure, and
/// again the moment the artifact leaves both phases — surfaces render nothing
/// rather than a stale or fabricated number.
///
/// KeepAlive: the estimator's sample window lives in notifier fields, and the
/// model stream must stay observed across screens the way the controller
/// itself does. Timer-free by design — state only moves when the controller
/// publishes a tick, which keeps goldens and `pumpAndSettle` deterministic.
@Riverpod(keepAlive: true, retry: noRetry)
class DownloadPace extends _$DownloadPace {
  final _estimator = DownloadPaceEstimator();
  String? _artifactKey;
  ArtifactPhase? _phase;
  DateTime? _origin;

  @override
  DownloadPaceSnapshot? build() {
    // listen, not watch: watching would recreate this notifier on every model
    // tick and silently discard the estimator's window.
    ref.listen(modelControllerProvider, (_, next) => _onModel(next.value));
    return null;
  }

  void _onModel(ModelState? model) {
    final inFlight = model?.artifacts.entries
        .where(
          (entry) =>
              entry.value.phase == ArtifactPhase.downloading ||
              entry.value.phase == ArtifactPhase.verifying,
        )
        .firstOrNull;
    if (inFlight == null) {
      _artifactKey = null;
      _phase = null;
      _origin = null;
      _estimator.reset();
      state = null;
      return;
    }
    final status = inFlight.value;
    final now = ref.read(paceClockProvider)();
    // A new artifact or a new phase is a new window: a hash runs at a
    // different rate than the network, and averaging across the edge would
    // quote one as the other.
    if (inFlight.key != _artifactKey || status.phase != _phase) {
      _artifactKey = inFlight.key;
      _phase = status.phase;
      _origin = now;
      _estimator.reset();
    }
    final progressed = status.progressBytes;
    _estimator.add(now.difference(_origin!), progressed);
    final rate = _estimator.mbPerSecond;
    if (rate == null) {
      state = null;
      return;
    }
    final entry = ref
        .read(effectiveModelCatalogProvider)
        .where((entry) => entry.key == inFlight.key)
        .firstOrNull;
    final remaining = entry == null ? null : entry.totalBytes - progressed;
    state = DownloadPaceSnapshot(
      artifactKey: inFlight.key,
      mbPerSecond: rate,
      eta: remaining == null ? null : _estimator.eta(remaining),
      phase: status.phase,
    );
  }
}
