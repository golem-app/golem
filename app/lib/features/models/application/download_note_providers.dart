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
    // A multi-file artifact flips downloading→verifying→downloading at every
    // file boundary; that is still the same attempt, so a dismissal must
    // survive it. Every other prior phase means a fresh attempt.
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
