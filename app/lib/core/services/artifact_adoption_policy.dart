/// The decision half of download reconciliation, kept pure so it is provable.
///
/// `FileDownloader` is a process singleton reached over a method channel, so
/// the adapter around it cannot be unit-tested. Everything that decides what to
/// do about a transfer therefore lives here, over plain values: the adapter
/// gathers a snapshot, calls [decideArtifactTransfer], and executes the answer.
library;

/// What the platform still knows about one file's transfer.
///
/// [running] and [waitingToRetry] mean bytes are moving or about to; [paused]
/// means the transfer stopped but may hold resumable partial data; [finished]
/// is the plugin's own claim that the task ended, which is a hint and never a
/// verdict — only the destination file and its hash decide that.
enum ArtifactTransferPresence {
  absent,
  running,
  waitingToRetry,
  paused,
  finished,
}

/// A union of what the plugin's four stores say about one transfer: the live
/// native queue, the tracking database, the paused-task store, and stored
/// resume data. Reading any one of them alone gives a wrong answer — after a
/// force-stop the database still says `running` while the only resumable state
/// is the resume data.
final class ArtifactTransferSnapshot {
  const ArtifactTransferSnapshot({
    this.presence = ArtifactTransferPresence.absent,
    this.receivedBytes,
    this.resumable = false,
  });

  final ArtifactTransferPresence presence;

  /// Bytes the platform reports for this transfer, or null when it cannot say.
  /// These live in the plugin's temp file, never at the destination — both
  /// platforms move the file into place only at completion.
  final int? receivedBytes;

  /// Stored resume data exists, so a resume continues from [receivedBytes]
  /// rather than restarting. Independent of [presence]: a task the native queue
  /// has forgotten can still be resumable.
  final bool resumable;
}

enum ArtifactTransferAction {
  /// Stream an existing native task's updates without enqueueing anything.
  /// The one action that cannot produce a second writer.
  adopt,

  /// Continue a paused transfer from its stored partial data.
  resume,

  /// Cancel what the platform holds, then enqueue fresh. The partial is lost.
  replace,

  /// The destination already holds the whole file; no transfer is needed.
  /// The repository still hashes it — this skips the network, not the proof.
  alreadyComplete,

  /// Nothing exists anywhere; enqueue fresh.
  start,
}

final class ArtifactTransferDecision {
  const ArtifactTransferDecision(this.action, {this.bytesOnPlatform = 0});

  final ArtifactTransferAction action;

  /// Progress to report immediately so an adopted or resumed transfer does not
  /// appear to restart from zero.
  final int bytesOnPlatform;

  @override
  String toString() =>
      'ArtifactTransferDecision(${action.name}, $bytesOnPlatform)';
}

/// Decides what to do about one file, given what the platform knows and
/// whether the destination is already whole.
///
/// [destinationComplete] must mean "present at exactly the expected length" —
/// the plugin's `markDownloadedComplete` records a task complete when the
/// destination merely exists, at any size, so the length check is what keeps a
/// truncated file from being mistaken for a finished one.
ArtifactTransferDecision decideArtifactTransfer({
  required ArtifactTransferSnapshot platform,
  required bool destinationComplete,
}) {
  // Checked before presence: a task still running against a destination that is
  // already whole is residue from a previous generation, and adopting it would
  // wait for bytes nothing needs. The caller cancels it.
  if (destinationComplete) {
    return const ArtifactTransferDecision(
      ArtifactTransferAction.alreadyComplete,
    );
  }

  final bytes = platform.receivedBytes ?? 0;
  return switch (platform.presence) {
    ArtifactTransferPresence.running ||
    ArtifactTransferPresence.waitingToRetry => ArtifactTransferDecision(
      ArtifactTransferAction.adopt,
      bytesOnPlatform: bytes,
    ),

    // Resumability decides, not presence. The plugin's database is routinely
    // stale about paused work, and resume data outlives the native queue.
    ArtifactTransferPresence.paused when platform.resumable =>
      ArtifactTransferDecision(
        ArtifactTransferAction.resume,
        bytesOnPlatform: bytes,
      ),
    ArtifactTransferPresence.paused => const ArtifactTransferDecision(
      ArtifactTransferAction.replace,
    ),

    // The task ended but the destination is not whole: whatever the plugin
    // thinks it finished, it is not the file we need.
    ArtifactTransferPresence.finished when platform.resumable =>
      ArtifactTransferDecision(
        ArtifactTransferAction.resume,
        bytesOnPlatform: bytes,
      ),
    ArtifactTransferPresence.finished => const ArtifactTransferDecision(
      ArtifactTransferAction.replace,
    ),

    // Nothing in the native queue, but resume data survived — the app was
    // killed mid-transfer. Resuming is what saves a multi-gigabyte partial.
    ArtifactTransferPresence.absent when platform.resumable =>
      ArtifactTransferDecision(
        ArtifactTransferAction.resume,
        bytesOnPlatform: bytes,
      ),
    ArtifactTransferPresence.absent => const ArtifactTransferDecision(
      ArtifactTransferAction.start,
    ),
  };
}
