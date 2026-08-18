import '../../../core/domain/app_preferences.dart';
import '../../../core/domain/inference_backend.dart';
import '../../../core/domain/models.dart';

/// Whether the root should present first run, wait for persisted state, or
/// enter chat. Existing installs are detected from all three stores so adding
/// #26 cannot strand a user who already has chats or model work on disk.
///
/// Chat arrives as [hasConversations] rather than the state itself: that one
/// bit is all this decides on, and the caller watches a chat controller that
/// reassigns its state on every streaming token.
bool shouldShowFirstRun({
  required AppPreferences preferences,
  required bool hasConversations,
  required ModelState models,
  required InferenceBackendConfig backend,
}) {
  if (preferences.onboardingVersion >= currentOnboardingVersion) return false;
  if (backend.sideloaded) return false;
  if (hasConversations) return false;
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

/// Which state the first-run screen opens in when the gate hands over. Named
/// rather than passed as a step: the gate decides *why* setup is required, and
/// the screen owns the step machine from there.
enum FirstRunEntry {
  /// A pristine install — the screen starts at its own welcome.
  fresh,

  /// Setup was interrupted with bytes already on disk.
  resumeDownload,

  /// An upgrade with no usable model, and nothing part-downloaded to resume.
  chooseModel,
}

/// What the app root may render. The whole admission decision as one value, so
/// it is a thing a test reads rather than a widget shape it has to infer.
sealed class StartupGate {
  const StartupGate();
}

/// A persisted store is still loading.
final class GateWaiting extends StartupGate {
  const GateWaiting();
}

/// A persisted store could not be read; the user is offered a retry.
final class GateUnavailable extends StartupGate {
  const GateUnavailable();
}

/// This device is outside every supported tier (#27).
final class GateUnsupported extends StartupGate {
  const GateUnsupported();
}

/// The shell may render.
final class GateAdmitted extends StartupGate {
  const GateAdmitted();
}

/// Setup is required before the shell may render.
final class GateFirstRun extends StartupGate {
  const GateFirstRun(this.entry);

  final FirstRunEntry entry;

  // Value equality so an unchanged decision does not notify: the model store
  // republishes on every download progress tick, and the gate is watched by
  // the widget wrapping every route.
  @override
  bool operator ==(Object other) =>
      other is GateFirstRun && other.entry == entry;

  @override
  int get hashCode => entry.hashCode;
}

/// The admission decision, once the three stores have been read and the device
/// has not been refused. [migrateLegacy] is returned beside the gate rather
/// than carried on it: the gate is a rendering instruction, while this is a
/// one-shot instruction to stamp the onboarding version of an install that
/// predates it — a write, and one a test should be able to assert without
/// inspecting what was rendered.
///
/// [pristineAtLaunch] is latched by the caller at the first successful read of
/// all three stores. Recomputing it per rebuild would let a model deleted
/// mid-session read as a fresh install.
({StartupGate gate, bool migrateLegacy}) resolveStartupGate({
  required bool pristineAtLaunch,
  required bool onboardingComplete,
  required bool hasUsableModel,
  required ArtifactStatus selectedStatus,
}) {
  if (hasUsableModel && (onboardingComplete || !pristineAtLaunch)) {
    return (gate: const GateAdmitted(), migrateLegacy: !onboardingComplete);
  }
  if (pristineAtLaunch) {
    return (
      gate: const GateFirstRun(FirstRunEntry.fresh),
      migrateLegacy: false,
    );
  }
  // An upgrade can carry an interrupted artifact; its bytes decide whether
  // setup resumes the transfer or sends the user back to model choice.
  final interrupted =
      selectedStatus.phase != ArtifactPhase.notDownloaded ||
      selectedStatus.downloadedBytes > 0;
  return (
    gate: GateFirstRun(
      interrupted ? FirstRunEntry.resumeDownload : FirstRunEntry.chooseModel,
    ),
    migrateLegacy: false,
  );
}
