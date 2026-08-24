import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/services/artifact_adoption_policy.dart';

ArtifactTransferDecision decide({
  ArtifactTransferPresence presence = ArtifactTransferPresence.absent,
  int? receivedBytes,
  bool resumable = false,
  bool destinationComplete = false,
}) => decideArtifactTransfer(
  platform: ArtifactTransferSnapshot(
    presence: presence,
    receivedBytes: receivedBytes,
    resumable: resumable,
  ),
  destinationComplete: destinationComplete,
);

void main() {
  group('a whole destination ends the transfer', () {
    test('nothing is downloaded when the file is already complete', () {
      expect(
        decide(destinationComplete: true).action,
        ArtifactTransferAction.alreadyComplete,
      );
    });

    // Residue from an earlier generation: adopting it would wait for bytes
    // nothing needs, and leaving it running would overwrite a verified file.
    test('a live task over a complete destination is still residue', () {
      for (final presence in ArtifactTransferPresence.values) {
        expect(
          decide(
            presence: presence,
            resumable: true,
            receivedBytes: 10,
            destinationComplete: true,
          ).action,
          ArtifactTransferAction.alreadyComplete,
          reason: 'presence ${presence.name}',
        );
      }
    });
  });

  group('a live transfer is adopted, never duplicated', () {
    test('a running task is adopted', () {
      expect(
        decide(presence: ArtifactTransferPresence.running).action,
        ArtifactTransferAction.adopt,
      );
    });

    test('a task waiting to retry is adopted, not restarted', () {
      expect(
        decide(presence: ArtifactTransferPresence.waitingToRetry).action,
        ArtifactTransferAction.adopt,
      );
    });

    test('adoption reports the bytes already moved', () {
      expect(
        decide(
          presence: ArtifactTransferPresence.running,
          receivedBytes: 4096,
        ).bytesOnPlatform,
        4096,
      );
    });

    test('an adopted transfer of unknown progress reports zero', () {
      expect(
        decide(presence: ArtifactTransferPresence.running).bytesOnPlatform,
        0,
      );
    });
  });

  group('resumability decides, not presence', () {
    test('a paused transfer with resume data resumes', () {
      final decision = decide(
        presence: ArtifactTransferPresence.paused,
        resumable: true,
        receivedBytes: 1024,
      );
      expect(decision.action, ArtifactTransferAction.resume);
      expect(decision.bytesOnPlatform, 1024);
    });

    test('a paused transfer without resume data is replaced', () {
      expect(
        decide(presence: ArtifactTransferPresence.paused).action,
        ArtifactTransferAction.replace,
      );
    });

    // The process was killed mid-transfer: the native queue forgot the task,
    // but the resume data outlived it. Restarting here would silently throw
    // away a multi-gigabyte partial.
    test('resume data outliving the native queue still resumes', () {
      final decision = decide(
        presence: ArtifactTransferPresence.absent,
        resumable: true,
        receivedBytes: 2 * 1000 * 1000 * 1000,
      );
      expect(decision.action, ArtifactTransferAction.resume);
      expect(decision.bytesOnPlatform, 2 * 1000 * 1000 * 1000);
    });

    // A transfer the platform is not holding is absent however its tracking
    // record reads — records for finished and cancelled tasks are kept
    // indefinitely, so a record can never be allowed to mean "still there".
    test('a stale record does not keep a dead transfer alive', () {
      expect(
        decide(presence: ArtifactTransferPresence.absent).action,
        ArtifactTransferAction.start,
      );
    });
  });

  group('nothing anywhere', () {
    test('an unknown transfer starts fresh', () {
      expect(decide().action, ArtifactTransferAction.start);
    });

    test('a fresh start claims no prior bytes', () {
      expect(decide().bytesOnPlatform, 0);
    });
  });

  test('every presence and resumability pair decides something', () {
    for (final presence in ArtifactTransferPresence.values) {
      for (final resumable in [true, false]) {
        for (final complete in [true, false]) {
          expect(
            decide(
              presence: presence,
              resumable: resumable,
              destinationComplete: complete,
            ).action,
            isA<ArtifactTransferAction>(),
            reason: '${presence.name}/$resumable/$complete',
          );
        }
      }
    }
  });

  // Only adopt reuses a live task; every other action either starts nothing or
  // cancels first, which is what keeps a second writer off the same file.
  test('exactly one action reuses a live transfer', () {
    final live = [
      ArtifactTransferPresence.running,
      ArtifactTransferPresence.waitingToRetry,
    ];
    for (final presence in live) {
      expect(
        decide(presence: presence).action,
        ArtifactTransferAction.adopt,
        reason: presence.name,
      );
    }
    for (final presence in ArtifactTransferPresence.values) {
      if (live.contains(presence)) continue;
      expect(
        decide(presence: presence).action,
        isNot(ArtifactTransferAction.adopt),
        reason: presence.name,
      );
    }
  });
}
