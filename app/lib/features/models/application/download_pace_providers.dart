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

/// One artifact's live transfer pace, published only while a rate is honest.
final class DownloadPaceSnapshot {
  const DownloadPaceSnapshot({
    required this.artifactKey,
    required this.mbPerSecond,
    this.eta,
  });

  final String artifactKey;

  /// Decimal MB/s over the estimator's trailing window.
  final double mbPerSecond;

  /// Time left at the current rate, when the catalog knows the total size.
  final Duration? eta;

  @override
  bool operator ==(Object other) =>
      other is DownloadPaceSnapshot &&
      other.artifactKey == artifactKey &&
      other.mbPerSecond == mbPerSecond &&
      other.eta == eta;

  @override
  int get hashCode => Object.hash(artifactKey, mbPerSecond, eta);
}

/// Live rate/ETA for the single in-flight download, derived by sampling
/// [ModelController]'s byte counts against the injected clock. `null` until
/// the trailing window can quote an honest figure, and again the moment the
/// transfer leaves the `downloading` phase — surfaces render nothing rather
/// than a stale or fabricated number.
///
/// KeepAlive: the estimator's sample window lives in notifier fields, and the
/// model stream must stay observed across screens the way the controller
/// itself does. Timer-free by design — state only moves when the controller
/// publishes a tick, which keeps goldens and `pumpAndSettle` deterministic.
@Riverpod(keepAlive: true, retry: noRetry)
class DownloadPace extends _$DownloadPace {
  final _estimator = DownloadPaceEstimator();
  String? _artifactKey;
  DateTime? _origin;

  @override
  DownloadPaceSnapshot? build() {
    // listen, not watch: watching would recreate this notifier on every model
    // tick and silently discard the estimator's window.
    ref.listen(modelControllerProvider, (_, next) => _onModel(next.value));
    return null;
  }

  void _onModel(ModelState? model) {
    final downloading = model?.artifacts.entries
        .where((entry) => entry.value.phase == ArtifactPhase.downloading)
        .firstOrNull;
    if (downloading == null) {
      _artifactKey = null;
      _origin = null;
      _estimator.reset();
      state = null;
      return;
    }
    final now = ref.read(paceClockProvider)();
    if (downloading.key != _artifactKey) {
      _artifactKey = downloading.key;
      _origin = now;
      _estimator.reset();
    }
    _estimator.add(now.difference(_origin!), downloading.value.downloadedBytes);
    final rate = _estimator.mbPerSecond;
    if (rate == null) {
      state = null;
      return;
    }
    final entry = ref
        .read(effectiveModelCatalogProvider)
        .where((entry) => entry.key == downloading.key)
        .firstOrNull;
    final remaining = entry == null
        ? null
        : entry.totalBytes - downloading.value.downloadedBytes;
    state = DownloadPaceSnapshot(
      artifactKey: downloading.key,
      mbPerSecond: rate,
      eta: remaining == null ? null : _estimator.eta(remaining),
    );
  }
}
