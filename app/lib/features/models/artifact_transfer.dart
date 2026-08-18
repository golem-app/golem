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
import '../../core/domain/download_pace.dart';
import '../../core/domain/model_admission.dart';
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
  /// an unblocked first download, which owes no explanation, and for the two
  /// blocks whose sentence belongs to the caller.
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
    this.remainder,
    this.affordance,
  });

  final ArtifactPhase phase;

  /// 0–1 against the catalog's total, so persistence never stores a stale
  /// percentage (`ArtifactStatus.downloadedBytes`).
  final double fraction;
  final int percent;

  /// The three byte figures, through the one formatter (`1.58 GB`).
  final String transferred, total, remaining;

  /// The state chip: a live rate while one is honest, else the phase — and
  /// nothing at all during a download whose pace window is still warming up,
  /// because a fabricated figure is worse than none.
  final String? chip;

  /// Whether [chip] reports a running transfer, which is the difference
  /// between an accent chip and a quiet one.
  final bool chipIsLive;

  /// The trailing figure under the bar: time left while downloading, amount
  /// left while paused, where it stopped when it failed.
  final String? remainder;

  final TransferAffordance? affordance;
}

/// Projects [status] against [entry] for every surface at once.
///
/// The gating flags are *asked*, never re-derived here: [deviceRefusal] is
/// `deviceRefusalProvider`'s answer, [admitted] the shared admission policy's,
/// [downloadable] the repository's. A surface that has already filtered its
/// list by engine passes `loadsHere: true` rather than being second-guessed.
///
/// [localizations] is nullable to match `model_choice.dart`, whose pure tests
/// run without a widget tree. The English fallbacks are the ones that already
/// lived at the call sites; growing that set is #130's to undo, not this
/// file's to add to.
ArtifactTransferPresentation artifactTransfer({
  required ModelCatalogEntry entry,
  required ArtifactStatus status,
  required AppLocalizations? localizations,
  DownloadPaceSnapshot? pace,
  bool simulated = false,
  String? deviceRefusal,
  bool sideloaded = false,
  bool admitted = true,
  bool downloadable = true,
  bool loadsHere = true,
  String? transferringKey,
}) {
  final fraction = entry.totalBytes <= 0
      ? 0.0
      : (status.downloadedBytes / entry.totalBytes).clamp(0.0, 1.0).toDouble();
  final percent = (fraction * 100).round();
  // The pace notifier publishes one artifact at a time; a snapshot naming
  // another belongs to a transfer this surface is not showing.
  final snapshot = pace?.artifactKey == entry.key ? pace : null;
  // The qualifier every phase appends: a simulated download must never read
  // like a real one, and all four surfaces describe one repository.
  final suffix = simulated
      ? ' · ${localizations?.simulated ?? 'simulated'}'
      : '';

  return ArtifactTransferPresentation(
    phase: status.phase,
    fraction: fraction,
    percent: percent,
    transferred: gigabytes(status.downloadedBytes),
    total: gigabytes(entry.totalBytes),
    remaining: gigabytes(entry.totalBytes - status.downloadedBytes),
    chip: _chip(status.phase, snapshot, localizations),
    chipIsLive: status.phase == ArtifactPhase.downloading,
    remainder: _remainder(
      phase: status.phase,
      snapshot: snapshot,
      percent: percent,
      remaining: entry.totalBytes - status.downloadedBytes,
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
      simulated: simulated,
      transferringKey: transferringKey,
      localizations: localizations,
    ),
  );
}

String? _chip(
  ArtifactPhase phase,
  DownloadPaceSnapshot? snapshot,
  AppLocalizations? localizations,
) => switch (phase) {
  ArtifactPhase.downloading when snapshot != null =>
    localizations?.rateMbs(snapshot.mbPerSecond.toStringAsFixed(1)) ??
        '${snapshot.mbPerSecond.toStringAsFixed(1)} MB/s',
  ArtifactPhase.paused => localizations?.paused ?? 'Paused',
  ArtifactPhase.failed => localizations?.stopped ?? 'Stopped',
  _ => null,
};

String? _remainder({
  required ArtifactPhase phase,
  required DownloadPaceSnapshot? snapshot,
  required int percent,
  required int remaining,
  required AppLocalizations? localizations,
}) => switch (phase) {
  ArtifactPhase.downloading when snapshot?.eta != null =>
    localizations?.etaAboutMinutesLeft(aboutMinutesLeft(snapshot!.eta!)) ??
        'About ${aboutMinutesLeft(snapshot!.eta!)} minutes left',
  ArtifactPhase.paused =>
    localizations?.amountLeft(gigabytes(remaining)) ??
        '${gigabytes(remaining)} left',
  ArtifactPhase.failed =>
    localizations?.stoppedAtPercent(percent) ?? 'Stopped at $percent%',
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
  required String? deviceRefusal,
  required bool sideloaded,
  required bool admitted,
  required bool downloadable,
  required bool loadsHere,
  required bool simulated,
  required String? transferringKey,
  required AppLocalizations? localizations,
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
    simulated: simulated,
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
    // A block explains itself; an unblocked resume or retry explains where it
    // stopped instead.
    note: blocked.$1 != null
        ? blocked.$2
        : switch (status.phase) {
            ArtifactPhase.paused =>
              localizations?.pausedDownloadAmount(
                    gigabytes(status.downloadedBytes),
                    gigabytes(entry.totalBytes),
                    suffix,
                  ) ??
                  'Paused at ${gigabytes(status.downloadedBytes)} '
                      'of ${gigabytes(entry.totalBytes)}$suffix.',
            ArtifactPhase.failed =>
              localizations == null
                  ? status.failure ?? 'Download failed.'
                  : artifactFailureMessage(localizations, status),
            _ => null,
          },
  );
}

/// Ordered by what a user can do least about.
///
/// The device verdict outranks the sideload: under both, nothing will load for
/// either reason, and "this device cannot run models" is the one nothing on
/// any of these screens can fix. Two blocks carry no sentence — the admission
/// policy words its own (`ModelAdmissionOption.disabledReason`) and the engine
/// mismatch has to name the build's engine, which is the caller's to know.
(TransferBlock?, String?) _block({
  required ModelCatalogEntry entry,
  required String? deviceRefusal,
  required bool sideloaded,
  required bool admitted,
  required bool downloadable,
  required bool loadsHere,
  required bool simulated,
  required String? transferringKey,
  required AppLocalizations? localizations,
}) {
  if (deviceRefusal != null) {
    return (
      TransferBlock.deviceRefused,
      localizations?.notAvailableOnDevice ?? 'Not available on this device.',
    );
  }
  if (sideloaded) {
    return (
      TransferBlock.sideload,
      localizations?.pinnedByBuild ?? 'Pinned by this build.',
    );
  }
  if (!admitted) return (TransferBlock.needsMoreMemory, null);
  // Nothing can be fetched for a repository that never resolved, so no surface
  // may tell the user to download it.
  if (!downloadable) {
    return (
      TransferBlock.unresolvedRepository,
      localizations?.unresolvedRepositoryReason ?? unresolvedRepositoryReason,
    );
  }
  // Nor for an artifact this build could never run, even when a previous build
  // installed it.
  if (!loadsHere && !simulated) return (TransferBlock.otherEngine, null);
  if (transferringKey != null && transferringKey != entry.key) {
    return (
      TransferBlock.busy,
      localizations?.anotherModelDownloading ?? 'Another model is downloading.',
    );
  }
  return (null, null);
}
