import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/features/chat/application/chat_failure_classifier.dart';

/// The engine-to-banner translation, which decided what a failed turn offers
/// the user and was previously reachable only by driving a whole generation
/// through a container (#127). Exhaustive on purpose: a new
/// [InferenceFailureKind] with no chat peer is a banner with no action.
void main() {
  group('the kind table', () {
    test('every inference kind maps to a chat kind', () {
      // The table, written out rather than derived, so a silent re-point of
      // one arm fails here instead of changing a banner nobody re-reads.
      const expected = {
        InferenceFailureKind.contextExhausted: ChatFailureKind.contextExhausted,
        InferenceFailureKind.outOfMemory: ChatFailureKind.outOfMemory,
        InferenceFailureKind.insufficientMemory:
            ChatFailureKind.insufficientMemory,
        InferenceFailureKind.budgetExhaustedBeforeAnswer:
            ChatFailureKind.budgetExhaustedBeforeAnswer,
        InferenceFailureKind.modelUnavailable: ChatFailureKind.modelUnavailable,
        InferenceFailureKind.unsupportedModel: ChatFailureKind.unsupportedModel,
        InferenceFailureKind.attachmentUnavailable:
            ChatFailureKind.attachmentUnavailable,
        InferenceFailureKind.unsupportedImages:
            ChatFailureKind.unsupportedImages,
        InferenceFailureKind.invalidModelArtifact:
            ChatFailureKind.invalidModelArtifact,
        InferenceFailureKind.unsupportedDevice:
            ChatFailureKind.unsupportedDevice,
        InferenceFailureKind.engine: ChatFailureKind.generic,
      };

      expect(
        expected.keys.toSet(),
        InferenceFailureKind.values.toSet(),
        reason: 'a new inference kind needs a chat kind and a row here',
      );
      for (final entry in expected.entries) {
        expect(
          chatFailureKindFor(entry.key),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test('the two kinds chat raises itself have no inference source', () {
      // attachmentSave and missingModel are decided before any engine call, so
      // nothing in the table may produce them — a mapping that did would let an
      // engine fault offer a download that fixes nothing.
      final mapped = InferenceFailureKind.values
          .map(chatFailureKindFor)
          .toSet();
      expect(mapped, isNot(contains(ChatFailureKind.attachmentSave)));
      expect(mapped, isNot(contains(ChatFailureKind.missingModel)));
    });
  });

  group('the failure it builds', () {
    test('a typed exception keeps its recovery kind and context size', () {
      final failure = chatFailureFor(
        const InferenceException(
          InferenceFailureKind.contextExhausted,
          'diagnostic copy',
          contextTokens: 4096,
        ),
      );

      expect(failure.kind, ChatFailureKind.contextExhausted);
      expect(failure.contextTokens, 4096);
    });

    test('an unknown error stays generic and carries no arguments', () {
      // The point of the fallback: raw exception text never reaches the banner
      // (handbook v5.0 §8.1), so an unclassified fault must not smuggle
      // anything presentational through.
      final failure = chatFailureFor(StateError('engine went sideways'));

      expect(failure.kind, ChatFailureKind.generic);
      expect(failure.contextTokens, isNull);
      expect(failure.artifactKey, isNull);
    });
  });

  group('the recovery each kind offers', () {
    test('the one failure retrying cannot fix offers a new chat instead', () {
      expect(ChatFailureKind.contextExhausted.recovery, ChatRecovery.newChat);
    });

    test('an unsupported device is offered nothing', () {
      // Every other kind must offer something, or the banner is a dead end.
      expect(ChatFailureKind.unsupportedDevice.recovery, ChatRecovery.none);
      for (final kind in ChatFailureKind.values) {
        if (kind == ChatFailureKind.unsupportedDevice) continue;
        expect(kind.recovery, isNot(ChatRecovery.none), reason: '$kind');
      }
    });

    test('a failure about the model itself offers another model', () {
      for (final kind in [
        ChatFailureKind.modelUnavailable,
        ChatFailureKind.unsupportedModel,
        ChatFailureKind.invalidModelArtifact,
      ]) {
        expect(kind.recovery, ChatRecovery.chooseModel, reason: '$kind');
      }
    });

    test('a turn that cannot be replayed is removed, not retried', () {
      for (final kind in [
        ChatFailureKind.attachmentUnavailable,
        ChatFailureKind.unsupportedImages,
      ]) {
        expect(kind.recovery, ChatRecovery.removeTurn, reason: '$kind');
      }
    });

    test('memory pressure keeps Retry — it can genuinely succeed later', () {
      expect(ChatFailureKind.outOfMemory.recovery, ChatRecovery.retry);
      expect(ChatFailureKind.insufficientMemory.recovery, ChatRecovery.retry);
    });
  });
}
