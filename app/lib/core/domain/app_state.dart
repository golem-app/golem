import 'models.dart';

/// What kind of failure the chat banner is showing, deciding its actions:
/// Retry is offered only where retrying can succeed, and the one failure
/// it can never fix ([contextExhausted]) offers a new chat instead.
enum ChatFailureKind {
  generic,
  missingModel,
  contextExhausted,
  outOfMemory,
  insufficientMemory,
}

/// A typed chat failure: the classification that picks banner actions,
/// the user-presentable message, and — for [ChatFailureKind.missingModel]
/// — the catalog key whose download the banner can offer. Raw exception
/// text never lands here; controllers map everything to copy first.
final class ChatFailure {
  const ChatFailure({
    required this.kind,
    required this.message,
    this.artifactKey,
  });

  final ChatFailureKind kind;
  final String message;
  final String? artifactKey;
}

final class ChatState {
  const ChatState({
    this.conversations = const [],
    this.activeId,
    this.generation = GenerationPhase.idle,
    this.failure,
    this.hasUnsavedAssistant = false,
  });

  final List<ChatConversation> conversations;
  final String? activeId;
  final GenerationPhase generation;
  final ChatFailure? failure;

  final bool hasUnsavedAssistant;

  ChatConversation? get active => conversations
      .where((conversation) => conversation.id == activeId)
      .firstOrNull;

  ChatState copyWith({
    List<ChatConversation>? conversations,
    String? activeId,
    GenerationPhase? generation,
    ChatFailure? failure,
    bool clearFailure = false,
    bool? hasUnsavedAssistant,
  }) => ChatState(
    conversations: conversations ?? this.conversations,
    activeId: activeId ?? this.activeId,
    generation: generation ?? this.generation,
    failure: clearFailure ? null : failure ?? this.failure,
    hasUnsavedAssistant: hasUnsavedAssistant ?? this.hasUnsavedAssistant,
  );
}

enum StartupPhase { resolving, preloading, missingModel, failed, complete }

final class StartupState {
  const StartupState({this.phase = StartupPhase.resolving, this.progress = 0});
  final StartupPhase phase;
  final double progress;
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
