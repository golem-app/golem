import '../../../core/domain/app_state.dart';
import '../../../core/repositories/contracts.dart';

/// Typed inference exceptions retain their recovery kind and safe arguments;
/// presentation owns localized copy. Unknown errors stay generic, and raw
/// exception text never reaches the banner (handbook v5.0 §8.1).
///
/// Extracted from ChatController (#127) because it is the decision and the
/// notifier around it is plumbing. It lives in the chat feature rather than
/// `core/domain/app_state.dart` as the ticket proposed: that file imports only
/// `models.dart`, while the kinds this reads come from
/// `core/repositories/contracts.dart`, which already imports four
/// `core/domain` files — the move would invert that edge.
ChatFailure chatFailureFor(Object error) => switch (error) {
  InferenceException(:final kind, :final contextTokens) => ChatFailure(
    kind: chatFailureKindFor(kind),
    contextTokens: contextTokens,
  ),
  _ => const ChatFailure(kind: ChatFailureKind.generic),
};

/// The two chat kinds with no inference peer — [ChatFailureKind.attachmentSave]
/// and [ChatFailureKind.missingModel] — are raised by the controller itself
/// before any engine call, so they are deliberately absent here.
ChatFailureKind chatFailureKindFor(InferenceFailureKind kind) => switch (kind) {
  InferenceFailureKind.contextExhausted => ChatFailureKind.contextExhausted,
  InferenceFailureKind.outOfMemory => ChatFailureKind.outOfMemory,
  InferenceFailureKind.insufficientMemory => ChatFailureKind.insufficientMemory,
  InferenceFailureKind.budgetExhaustedBeforeAnswer =>
    ChatFailureKind.budgetExhaustedBeforeAnswer,
  InferenceFailureKind.modelUnavailable => ChatFailureKind.modelUnavailable,
  InferenceFailureKind.unsupportedModel => ChatFailureKind.unsupportedModel,
  InferenceFailureKind.attachmentUnavailable =>
    ChatFailureKind.attachmentUnavailable,
  InferenceFailureKind.unsupportedImages => ChatFailureKind.unsupportedImages,
  InferenceFailureKind.invalidModelArtifact =>
    ChatFailureKind.invalidModelArtifact,
  InferenceFailureKind.unsupportedDevice => ChatFailureKind.unsupportedDevice,
  // The one arm that is not an identity: an unclassified engine fault says
  // nothing the banner can act on beyond offering another attempt.
  InferenceFailureKind.engine => ChatFailureKind.generic,
};
