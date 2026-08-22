/// One artifact's transfer, projected once for every surface that shows it.
///
/// First run, Settings ▸ Models, the chat setup banner and the model picker
/// each derived the percentage, the pace figures and the phase's affordance
/// for themselves, and they had drifted: the picker counted verification
/// against the single transfer slot while nothing else did, and only first run
/// ever quoted a rate (#131).
///
/// Two things this file deliberately does not decide:
///
/// - **The button's words.** "Resume download" on a full-width Settings
///   primary and "Resume" on a compact picker button are one decision worded
///   for two places, so [TransferOffer] carries the [TransferAction] and each
///   surface words it.
/// - **Whether a blocked offer is dimmed or withheld.** The picker withholds
///   (ADR 0007: a full-width button that does nothing when tapped undoes the
///   honesty of the copy beside it); Settings dims it and prints the reason
///   underneath. [TransferOffer.block] says *why*, and the surface chooses.
library;

import '../../core/domain/byte_format.dart';
import '../../core/domain/device_eligibility.dart';
import '../../core/domain/download_pace.dart';
import '../../core/domain/model_catalog.dart';
import '../../core/domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/presentation_messages.dart';

/// What starting this transfer would do. The three are distinct because they
/// read differently to a user, not because they take different code paths.
enum TransferAction {
  /// A first, full-size fetch — the one every entrance gates behind explicit
  /// consent (#26).
  start,

  /// Continues one the user already approved and then paused.
  resume,

  /// Continues one that stopped on its own.
  retry,
}

/// Why an offer cannot be taken. Carried beside the copy rather than instead
/// of it: the enum is for tests and keys, the sentence is for the user.
enum TransferBlock {
  /// Another artifact holds the single transfer slot.
  busy,

  /// This device is admitted to no model at all (#27).
  deviceRefused,

  /// The build pins an operator-supplied file, so there is nothing to fetch.
  sideload,

  /// Admitted, but not to this artifact: the launch classification sized this
  /// build for a lighter one.
  needsMoreMemory,

  /// A hand-added repository whose file list was never resolved (#52).
  unresolvedRepository,

  /// Listed or installed, but this build's engine cannot load its format.
  otherEngine,
}

/// What a surface may offer for this artifact, or `null` when there is nothing
/// to offer because the weights are already here.
sealed class TransferAffordance {
  const TransferAffordance();
}

/// A transfer that could be started: a first download, a resume, or a retry.
final class TransferOffer extends TransferAffordance {
  const TransferOffer({required this.action, this.block, this.note});

  final TransferAction action;

  /// Why it cannot be taken, or null when it can.
  final TransferBlock? block;

  /// Why it is blocked, or what went wrong on the attempt before it. Null for
  /// an unblocked first download, which owes no explanation, and for every
  /// block but [TransferBlock.busy], whose sentence each surface words itself.
  final String? note;

  bool get enabled => block == null;
}

/// A transfer already under way, described for a progress bar.
final class TransferInFlight extends TransferAffordance {
  const TransferInFlight({required this.pausable});

  /// Verification cannot be interrupted; a download can.
  final bool pausable;
}

/// Everything the four transfer surfaces render, computed once.
final class ArtifactTransferPresentation {
  const ArtifactTransferPresentation({
    required this.phase,
    required this.fraction,
    required this.percent,
    required this.transferred,
    required this.total,
    required this.remaining,
    required this.chipIsLive,
    this.chip,
    this.chipSlot,
    this.remainder,
    this.affordance,
  });

  final ArtifactPhase phase;

  /// 0–1 against the catalog's total, so persistence never stores a stale
  /// percentage. Each in-flight phase has its own counter: transferred bytes
  /// until the bar reaches the total, hashed bytes while the files are
  /// checked — so a finished download never steps back, and a verification
  /// is no longer a full bar pretending (#143).
  final double fraction;
  final int percent;

  /// The three byte figures, through the one formatter (`1.58 GB`): the
  /// phase's own progress against the total, like [fraction].
  final String transferred, total, remaining;

  /// The state chip: a live rate while one is honest, else the phase — and
  /// nothing at all during a download whose pace window is still warming up,
  /// because a fabricated figure is worse than none.
  final String? chip;

  /// Whether [chip] reports a running transfer, which is the difference
  /// between an accent chip and a quiet one.
  final bool chipIsLive;

  /// A value at least as wide as anything [chip] will show, so the pill keeps
  /// one width while its figure ticks — "9.8 MB/s" becoming "10.2 MB/s" used
  /// to nudge the unit. Null for a chip that names a state.
  final String? chipSlot;

  /// The trailing figure under the bar: time left while downloading, amount
  /// left while paused, where it stopped when it failed.
  final String? remainder;

  final TransferAffordance? affordance;
}

/// Projects [status] against [entry] for every surface at once.
///
/// The gating flags are *asked*, never re-derived here: [deviceRefusal] is
/// `deviceRefusalProvider`'s answer, [admitted] the shared admission policy's,
/// [downloadable] the repository's, and [loadsHere] the backend's — a fake
/// backend loads every format, so its caller passes true rather than having
/// [simulated] stand in for it. [simulated] means only that the *download* is
/// simulated, which is a different flag on a different seam.
ArtifactTransferPresentation artifactTransfer({
  required ModelCatalogEntry entry,
  required ArtifactStatus status,
  required AppLocalizations localizations,
  DownloadPaceSnapshot? pace,
  bool simulated = false,
  DeviceIneligibilityReason? deviceRefusal,
  bool sideloaded = false,
  bool admitted = true,
  bool downloadable = true,
  bool loadsHere = true,
  String? transferringKey,
}) {
  final progressed = status.progressBytes;
  final fraction = entry.totalBytes <= 0
      ? 0.0
      : (progressed / entry.totalBytes).clamp(0.0, 1.0).toDouble();
  final percent = (fraction * 100).round();
  // The pace notifier publishes one artifact at a time; a snapshot naming
  // another, or measured in the other phase, belongs to a transfer this
  // surface is not showing.
  final snapshot = pace?.artifactKey == entry.key && pace?.phase == status.phase
      ? pace
      : null;
  // The qualifier every phase appends: a simulated download must never read
  // like a real one, and all four surfaces describe one repository.
  final suffix = simulated ? ' · ${localizations.simulated}' : '';

  return ArtifactTransferPresentation(
    phase: status.phase,
    fraction: fraction,
    percent: percent,
    transferred: gigabytes(progressed),
    total: gigabytes(entry.totalBytes),
    remaining: gigabytes(entry.totalBytes - progressed),
    chip: _chip(status.phase, snapshot, suffix, localizations),
    chipSlot: status.phase == ArtifactPhase.downloading && snapshot != null
        ? localizations.rateMbs('999.9')
        : null,
    chipIsLive:
        status.phase == ArtifactPhase.downloading ||
        status.phase == ArtifactPhase.verifying,
    remainder: _remainder(
      phase: status.phase,
      snapshot: snapshot,
      percent: percent,
      remaining: entry.totalBytes - progressed,
      localizations: localizations,
    ),
    affordance: _affordance(
      entry: entry,
      status: status,
      suffix: suffix,
      deviceRefusal: deviceRefusal,
      sideloaded: sideloaded,
      admitted: admitted,
      downloadable: downloadable,
      loadsHere: loadsHere,
      transferringKey: transferringKey,
      localizations: localizations,
    ),
  );
}

/// Only a transfer quotes its rate; a verification names its phase, because
/// a hash throughput in MB/s would read as a download that slowed down.
String? _chip(
  ArtifactPhase phase,
  DownloadPaceSnapshot? snapshot,
  String suffix,
  AppLocalizations localizations,
) => switch (phase) {
  ArtifactPhase.downloading when snapshot != null => localizations.rateMbs(
    snapshot.mbPerSecond.toStringAsFixed(1),
  ),
  ArtifactPhase.verifying => localizations.verifyingStatus(suffix),
  ArtifactPhase.paused => localizations.paused,
  ArtifactPhase.failed => localizations.stopped,
  _ => null,
};

String? _remainder({
  required ArtifactPhase phase,
  required DownloadPaceSnapshot? snapshot,
  required int percent,
  required int remaining,
  required AppLocalizations localizations,
}) => switch (phase) {
  ArtifactPhase.downloading || ArtifactPhase.verifying
      when snapshot?.eta != null =>
    localizations.etaAboutMinutesLeft(aboutMinutesLeft(snapshot!.eta!)),
  ArtifactPhase.paused => localizations.amountLeft(gigabytes(remaining)),
  ArtifactPhase.failed => localizations.stoppedAtPercent(percent),
  _ => null,
};

/// What the phase permits, and why it does not.
///
/// A transfer already under way is described whatever the row's verdict:
/// Settings has no tier gate, so it can start one this device is not admitted
/// to, and a surface that hid it would blame a download it refused to show
/// while offering no way to stop it.
TransferAffordance? _affordance({
  required ModelCatalogEntry entry,
  required ArtifactStatus status,
  required String suffix,
  required DeviceIneligibilityReason? deviceRefusal,
  required bool sideloaded,
  required bool admitted,
  required bool downloadable,
  required bool loadsHere,
  required String? transferringKey,
  required AppLocalizations localizations,
}) {
  switch (status.phase) {
    case ArtifactPhase.installed:
      return null;
    case ArtifactPhase.downloading:
      return const TransferInFlight(pausable: true);
    case ArtifactPhase.verifying:
      return const TransferInFlight(pausable: false);
    case ArtifactPhase.notDownloaded:
    case ArtifactPhase.paused:
    case ArtifactPhase.failed:
      break;
  }

  final blocked = _block(
    entry: entry,
    deviceRefusal: deviceRefusal,
    sideloaded: sideloaded,
    admitted: admitted,
    downloadable: downloadable,
    loadsHere: loadsHere,
    transferringKey: transferringKey,
    localizations: localizations,
  );

  return TransferOffer(
    action: switch (status.phase) {
      ArtifactPhase.paused => TransferAction.resume,
      ArtifactPhase.failed => TransferAction.retry,
      _ => TransferAction.start,
    },
    block: blocked.$1,
    // A busy slot explains itself; an unblocked resume or retry explains where
    // it stopped instead.
    note: blocked.$1 != null
        ? blocked.$2
        : switch (status.phase) {
            ArtifactPhase.paused => localizations.pausedDownloadAmount(
              gigabytes(status.downloadedBytes),
              gigabytes(entry.totalBytes),
              suffix,
            ),
            ArtifactPhase.failed => artifactFailureMessage(
              localizations,
              status,
            ),
            _ => null,
          },
  );
}

/// Ordered by what a user can do least about.
///
/// The device verdict outranks the sideload: under both, nothing will load for
/// either reason, and "this device cannot run models" is the one that nothing
/// on any of these screens can fix.
///
/// Only [TransferBlock.busy] carries a sentence. The others are worded by the
/// surface — the picker prints them as `ModelChoice.blockReason` and Settings
/// prints its own, in its own order, because an unresolved repository is the
/// more specific problem there and the device verdict is the one it cannot fix.
/// A second copy here would be copy nobody reads, drifting quietly.
(TransferBlock?, String?) _block({
  required ModelCatalogEntry entry,
  required DeviceIneligibilityReason? deviceRefusal,
  required bool sideloaded,
  required bool admitted,
  required bool downloadable,
  required bool loadsHere,
  required String? transferringKey,
  required AppLocalizations localizations,
}) {
  if (deviceRefusal != null) return (TransferBlock.deviceRefused, null);
  if (sideloaded) return (TransferBlock.sideload, null);
  if (!admitted) return (TransferBlock.needsMoreMemory, null);
  // Nothing can be fetched for a repository that never resolved, so no surface
  // may tell the user to download it.
  if (!downloadable) return (TransferBlock.unresolvedRepository, null);
  // Nor for an artifact this build's engine could never run, even when a
  // previous build installed it.
  if (!loadsHere) return (TransferBlock.otherEngine, null);
  if (transferringKey != null && transferringKey != entry.key) {
    return (TransferBlock.busy, localizations.anotherModelDownloading);
  }
  return (null, null);
}
