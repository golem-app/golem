import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/models.dart';
import '../../../core/providers/retry.dart';
import 'model_providers.dart';

part 'download_note_providers.g.dart';

/// The one statement of the note's visibility rule: the artifact is in
/// flight — downloading, or hashing what it downloaded, which a suspended
/// app also stops. Holding through the verify edge keeps the first-run card
/// from re-centring when the note would otherwise leave. Applies in
/// simulated mode too — QA drives the fake backend, and the surfaces already
/// carry their own simulation labeling.
@Riverpod(retry: noRetry)
bool downloadNoteVisible(Ref ref, String artifactKey) {
  final phase = ref.watch(
    modelControllerProvider.select(
      (value) => value.value?.statusOf(artifactKey).phase,
    ),
  );
  return phase == ArtifactPhase.downloading || phase == ArtifactPhase.verifying;
}
