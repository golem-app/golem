import '../../../core/domain/app_preferences.dart';
import '../../../core/domain/app_state.dart';
import '../../../core/domain/inference_backend.dart';
import '../../../core/domain/models.dart';

/// Whether the root should present first run, wait for persisted state, or
/// enter chat. Existing installs are detected from all three stores so adding
/// #26 cannot strand a user who already has chats or model work on disk.
bool shouldShowFirstRun({
  required AppPreferences preferences,
  required ChatState chats,
  required ModelState models,
  required InferenceBackendConfig backend,
}) {
  if (preferences.onboardingVersion >= currentOnboardingVersion) return false;
  if (backend.sideloaded) return false;
  if (chats.conversations.isNotEmpty) return false;
  return isPristineModelState(models);
}

/// Reconciliation materializes every catalog key, so map presence cannot be a
/// legacy-install signal. Only untouched, zero-byte entries are pristine.
bool isPristineModelState(ModelState models) =>
    models.runtime == RuntimePhase.unloaded &&
    models.failure == null &&
    models.artifacts.values.every(
      (status) =>
          status.phase == ArtifactPhase.notDownloaded &&
          status.downloadedBytes == 0 &&
          status.failure == null &&
          status.failureReason == null,
    );
