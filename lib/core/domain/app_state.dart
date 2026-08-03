import 'models.dart';

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
  final String? failure;
  final bool hasUnsavedAssistant;

  ChatConversation? get active => conversations
      .where((conversation) => conversation.id == activeId)
      .firstOrNull;

  ChatState copyWith({
    List<ChatConversation>? conversations,
    String? activeId,
    GenerationPhase? generation,
    String? failure,
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
  }) => BenchmarkState(
    caseId: caseId ?? this.caseId,
    phase: phase ?? this.phase,
    isRunning: isRunning ?? this.isRunning,
    result: result ?? this.result,
  );
}
