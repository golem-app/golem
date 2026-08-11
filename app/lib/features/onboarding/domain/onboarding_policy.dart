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
  if (models.artifacts.isNotEmpty ||
      models.runtime != RuntimePhase.unloaded ||
      models.failure != null) {
    return false;
  }
  return true;
}
