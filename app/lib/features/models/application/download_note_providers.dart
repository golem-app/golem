import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/models.dart';
import '../../../core/providers/retry.dart';
import 'model_providers.dart';

part 'download_note_providers.g.dart';

/// Which artifacts' foreground-speed notes the user has waved away, scoped to
/// the download attempt: an artifact re-entering `downloading` — a fresh
/// download, a resume, a retry — clears its dismissal, so the note returns
/// exactly when the trade-off becomes live again. In-memory on purpose; the
/// note is situational advice, not a preference.
///
/// KeepAlive: dismissal must survive navigation between the surfaces that
/// share it (first-run, Settings, the chat setup banner).
@Riverpod(keepAlive: true, retry: noRetry)
class DownloadNoteDismissal extends _$DownloadNoteDismissal {
  @override
  Set<String> build() {
    // listen, not watch: watching would rebuild this notifier per model tick
    // and reset the dismissal set it exists to hold.
    ref.listen(
      modelControllerProvider,
      (previous, next) => _onModel(previous?.value, next.value),
    );
    return const {};
  }

  void dismiss(String artifactKey) => state = {...state, artifactKey};

  void _onModel(ModelState? previous, ModelState? next) {
    if (next == null) return;
    // A verification that finds a sideloaded forgery re-fetches it; that
    // verifying→downloading edge is still the same attempt, so a dismissal
    // must survive it. Every other prior phase means a fresh attempt.
    const sameAttempt = {ArtifactPhase.downloading, ArtifactPhase.verifying};
    final entering = <String>{
      for (final entry in next.artifacts.entries)
        if (entry.value.phase == ArtifactPhase.downloading &&
            !sameAttempt.contains(previous?.statusOf(entry.key).phase))
          entry.key,
    };
    if (entering.isEmpty) return;
    final kept = state.difference(entering);
    if (kept.length != state.length) state = kept;
  }
}

/// The byte count each downloading artifact had when its current attempt
/// began, frozen so the note's "about X instead of about Y" comparison keeps
/// one pair of figures for the whole attempt instead of counting down under
/// the reader. Re-recorded at the same boundary that resurrects a dismissed
/// note; seeded from the current state so a surface opened mid-transfer
/// still gets a stable figure.
@Riverpod(keepAlive: true, retry: noRetry)
class DownloadNoteFigures extends _$DownloadNoteFigures {
  @override
  Map<String, int> build() {
    // listen, not watch: watching would rebuild this notifier per model tick
    // and re-freeze the figures it exists to hold still.
    ref.listen(
      modelControllerProvider,
      (previous, next) => _onModel(previous?.value, next.value),
    );
    final model = ref.read(modelControllerProvider).value;
    return {
      if (model != null)
        for (final entry in model.artifacts.entries)
          if (entry.value.phase == ArtifactPhase.downloading)
            entry.key: entry.value.downloadedBytes,
    };
  }

  void _onModel(ModelState? previous, ModelState? next) {
    if (next == null) return;
    const sameAttempt = {ArtifactPhase.downloading, ArtifactPhase.verifying};
    final updates = <String, int>{
      for (final entry in next.artifacts.entries)
        if (entry.value.phase == ArtifactPhase.downloading &&
            (!sameAttempt.contains(previous?.statusOf(entry.key).phase) ||
                !state.containsKey(entry.key)))
          entry.key: entry.value.downloadedBytes,
    };
    if (updates.isEmpty) return;
    state = {...state, ...updates};
  }
}

/// The one statement of the note's visibility rule: an artifact is actively
/// downloading and its note has not been dismissed this attempt. Applies in
/// simulated mode too — QA drives the fake backend, and the surfaces already
/// carry their own simulation labeling.
@Riverpod(retry: noRetry)
bool downloadNoteVisible(Ref ref, String artifactKey) {
  final phase = ref.watch(
    modelControllerProvider.select(
      (value) => value.value?.statusOf(artifactKey).phase,
    ),
  );
  if (phase != ArtifactPhase.downloading) return false;
  return !ref.watch(downloadNoteDismissalProvider).contains(artifactKey);
}
