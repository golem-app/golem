/// Stays in core (#69): ChatState/StartupState/BenchmarkState are named by
/// the controllers in core/providers and consumed across features.
library;

import 'dart:collection';

import 'models.dart';

/// What kind of failure the chat banner is showing, deciding its actions:
/// Retry is offered only where retrying can succeed, and the one failure
/// it can never fix ([contextExhausted]) offers a new chat instead.
enum ChatFailureKind {
  generic,
  attachmentSave,
  attachmentUnavailable,
  modelUnavailable,
  unsupportedModel,
  unsupportedImages,
  invalidModelArtifact,
  budgetExhaustedBeforeAnswer,
  missingModel,
  contextExhausted,
  outOfMemory,
  insufficientMemory,

  /// This device is outside every supported tier (#27). Unlike the others this
  /// one has no recovery at all: no retry, no download, no new chat.
  unsupportedDevice,
}

/// The one way out a failed turn offers. Declared beside the kinds rather than
/// derived at the banner, so the promise [ChatFailureKind]'s own doc makes is a
/// value a test can read instead of a widget shape it has to infer.
enum ChatRecovery {
  /// Nothing done here changes what this hardware can run.
  none,

  /// The conversation can never fit the window again; a fresh one can.
  newChat,

  /// The model is what failed, so the way out is naming another.
  chooseModel,

  /// The turn cannot be replayed — its attachment is gone or unsupported.
  removeTurn,

  /// An identical retry can succeed.
  retry,
}

extension ChatFailureRecovery on ChatFailureKind {
  /// Exhaustive on purpose: a new kind must state its recovery here rather
  /// than inherit Retry from a default arm the way the banner used to give it.
  ChatRecovery get recovery => switch (this) {
    ChatFailureKind.unsupportedDevice => ChatRecovery.none,
    ChatFailureKind.contextExhausted => ChatRecovery.newChat,
    ChatFailureKind.modelUnavailable ||
    ChatFailureKind.unsupportedModel ||
    ChatFailureKind.invalidModelArtifact => ChatRecovery.chooseModel,
    ChatFailureKind.attachmentUnavailable ||
    ChatFailureKind.unsupportedImages => ChatRecovery.removeTurn,
    ChatFailureKind.generic ||
    ChatFailureKind.attachmentSave ||
    ChatFailureKind.budgetExhaustedBeforeAnswer ||
    ChatFailureKind.missingModel ||
    ChatFailureKind.outOfMemory ||
    ChatFailureKind.insufficientMemory => ChatRecovery.retry,
  };
}

/// A typed chat failure: the classification that picks banner actions and —
/// for [ChatFailureKind.missingModel] — the catalog key whose download the
/// banner can offer. Presentation maps this semantic value to localized copy.
final class ChatFailure {
  const ChatFailure({required this.kind, this.artifactKey, this.contextTokens});

  final ChatFailureKind kind;
  final String? artifactKey;
  final int? contextTokens;

  // Value equality so the recovery banner can select on the failure itself.
  @override
  bool operator ==(Object other) =>
      other is ChatFailure &&
      other.kind == kind &&
      other.artifactKey == artifactKey &&
      other.contextTokens == contextTokens;

  @override
  int get hashCode => Object.hash(kind, artifactKey, contextTokens);
}

/// Whether the live chat session has a known durability problem. This state is
/// deliberately orthogonal to [ChatFailure]: retrying a history write must not
/// modify an inference turn, and inference recovery must not hide an unsaved
/// session.
enum ChatPersistencePhase { idle, failed, retrying }

// Deliberately identity-equal: the controller reassigns this state on every
// streaming token, so a deep compare in updateShouldNotify would cost
// O(messages × text) per token and suppress nothing — consecutive token
// states genuinely differ. Widgets filter with selects on value-typed fields.
final class ChatState {
  const ChatState({
    this._conversations = const [],
    this.activeId,
    this.generation = GenerationPhase.idle,
    this.failure,
    this.persistencePhase = ChatPersistencePhase.idle,
    this.hasUnsavedAssistant = false,
  });

  final List<ChatConversation> _conversations;
  final String? activeId;
  final GenerationPhase generation;
  final ChatFailure? failure;
  final ChatPersistencePhase persistencePhase;

  final bool hasUnsavedAssistant;

  /// Unmodifiable — mutation goes through the controller's copy helpers.
  List<ChatConversation> get conversations =>
      UnmodifiableListView(_conversations);

  ChatConversation? get active => _conversations
      .where((conversation) => conversation.id == activeId)
      .firstOrNull;

  ChatState copyWith({
    List<ChatConversation>? conversations,
    String? activeId,
    GenerationPhase? generation,
    ChatFailure? failure,
    bool clearFailure = false,
    ChatPersistencePhase? persistencePhase,
    bool? hasUnsavedAssistant,
  }) => ChatState(
    conversations: conversations ?? _conversations,
    activeId: activeId ?? this.activeId,
    generation: generation ?? this.generation,
    failure: clearFailure ? null : failure ?? this.failure,
    persistencePhase: persistencePhase ?? this.persistencePhase,
    hasUnsavedAssistant: hasUnsavedAssistant ?? this.hasUnsavedAssistant,
  );
}

enum StartupPhase { resolving, preloading, missingModel, failed, complete }

final class StartupState {
  const StartupState({this.phase = StartupPhase.resolving, this.progress = 0});
  final StartupPhase phase;
  final double progress;
}

/// Why a launch composition failed, classified for copy and recovery. Only
/// [invalidConfiguration] is terminal: a bad dart-define cannot be retried
/// into working, everything else is environmental and worth another attempt.
enum LaunchFailureKind {
  invalidConfiguration,
  storageUnavailable,
  timedOut,
  unknown,
}

/// A launch failure is semantic; presentation maps it to localized copy while
/// the throwing cause stays in diagnostics.
final class LaunchFailure {
  const LaunchFailure(this.kind);
  final LaunchFailureKind kind;

  bool get retryable => kind != LaunchFailureKind.invalidConfiguration;
}

final class BenchmarkState {
  const BenchmarkState({
    this.caseId = 'short-explanation',
    this.phase = BenchmarkPhase.warmup,
    this.isRunning = false,
    this.result,
  });
  final String caseId;
  final BenchmarkPhase phase;
  final bool isRunning;
  final BenchmarkRecord? result;

  BenchmarkState copyWith({
    String? caseId,
    BenchmarkPhase? phase,
    bool? isRunning,
    BenchmarkRecord? result,
    bool clearResult = false,
  }) => BenchmarkState(
    caseId: caseId ?? this.caseId,
    phase: phase ?? this.phase,
    isRunning: isRunning ?? this.isRunning,
    result: clearResult ? null : result ?? this.result,
  );
}
