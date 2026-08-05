import 'dart:convert';

enum MessageRole { user, assistant }

enum ArtifactPhase {
  notDownloaded,
  downloading,
  paused,
  verifying,
  installed,
  failed,
}

enum RuntimePhase { unloaded, loading, loaded, failed }

enum GenerationPhase { idle, preparing, streaming, failed }

enum BenchmarkPhase { warmup, measured }

String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

int _nextId = 0;

String normalizeTitle(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return 'New chat';
  return normalized.length <= 48
      ? normalized
      : '${normalized.substring(0, 47)}…';
}

final class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.reasoning,
    this.metrics,
    this.isStreaming = false,
  });

  final String id;
  final MessageRole role;
  final String text;
  final String? reasoning;
  final InferenceMetrics? metrics;
  final DateTime createdAt;
  final bool isStreaming;

  ChatMessage copyWith({
    String? text,
    String? reasoning,
    InferenceMetrics? metrics,
    bool? isStreaming,
  }) => ChatMessage(
    id: id,
    role: role,
    text: text ?? this.text,
    reasoning: reasoning ?? this.reasoning,
    metrics: metrics ?? this.metrics,
    createdAt: createdAt,
    isStreaming: isStreaming ?? this.isStreaming,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'reasoning': reasoning,
    'metrics': metrics?.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
    id: json['id']! as String,
    role: MessageRole.values.byName(json['role']! as String),
    text: json['text']! as String,
    reasoning: json['reasoning'] as String?,
    metrics: json['metrics'] == null
        ? null
        : InferenceMetrics.fromJson(
            Map<String, Object?>.from(json['metrics']! as Map),
          ),
    createdAt: DateTime.parse(json['createdAt']! as String),
  );
}

final class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
    this.reasoningEnabled = false,
  });

  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime updatedAt;
  final bool reasoningEnabled;

  ChatConversation copyWith({
    String? title,
    List<ChatMessage>? messages,
    DateTime? updatedAt,
    bool? reasoningEnabled,
  }) => ChatConversation(
    id: id,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    updatedAt: updatedAt ?? this.updatedAt,
    reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
  );

  /// Prompt context intentionally excludes private reasoning.
  List<Map<String, String>> get promptContext => messages
      .where((message) => !message.isStreaming)
      .map((message) => {'role': message.role.name, 'content': message.text})
      .toList(growable: false);

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'messages': messages
        .where((message) => !message.isStreaming)
        .map((m) => m.toJson())
        .toList(),
    'updatedAt': updatedAt.toIso8601String(),
    'reasoningEnabled': reasoningEnabled,
  };

  factory ChatConversation.fromJson(Map<String, Object?> json) =>
      ChatConversation(
        id: json['id']! as String,
        title: normalizeTitle(json['title']! as String),
        messages: (json['messages']! as List)
            .map(
              (item) =>
                  ChatMessage.fromJson(Map<String, Object?>.from(item as Map)),
            )
            .toList(growable: false),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
        reasoningEnabled: json['reasoningEnabled'] as bool? ?? false,
      );
}

final class ChatHistorySnapshot {
  const ChatHistorySnapshot({required this.conversations, this.activeId});
  final List<ChatConversation> conversations;
  final String? activeId;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'activeConversationId': activeId,
    'conversations': conversations.map((item) => item.toJson()).toList(),
  };

  factory ChatHistorySnapshot.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported chat history schema');
    }
    final conversations = (json['conversations']! as List)
        .map(
          (item) =>
              ChatConversation.fromJson(Map<String, Object?>.from(item as Map)),
        )
        .toList();
    final requested = json['activeConversationId'] as String?;
    final active = conversations.any((item) => item.id == requested)
        ? requested
        : conversations.firstOrNull?.id;
    return ChatHistorySnapshot(conversations: conversations, activeId: active);
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

final class InferenceMetrics {
  const InferenceMetrics({
    required this.promptTokensPerSecond,
    required this.decodeTokensPerSecond,
    required this.tokenCount,
    required this.elapsedSeconds,
  });
  final double promptTokensPerSecond;
  final double decodeTokensPerSecond;
  final int tokenCount;
  final double elapsedSeconds;

  Map<String, Object> toJson() => {
    'promptTokensPerSecond': promptTokensPerSecond,
    'decodeTokensPerSecond': decodeTokensPerSecond,
    'tokenCount': tokenCount,
    'elapsedSeconds': elapsedSeconds,
  };

  factory InferenceMetrics.fromJson(
    Map<String, Object?> json,
  ) => InferenceMetrics(
    promptTokensPerSecond: (json['promptTokensPerSecond']! as num).toDouble(),
    decodeTokensPerSecond: (json['decodeTokensPerSecond']! as num).toDouble(),
    tokenCount: json['tokenCount']! as int,
    elapsedSeconds: (json['elapsedSeconds']! as num).toDouble(),
  );
}

sealed class InferenceEvent {
  const InferenceEvent();
}

final class ReasoningDelta extends InferenceEvent {
  const ReasoningDelta(this.text);
  final String text;
}

final class AnswerDelta extends InferenceEvent {
  const AnswerDelta(this.text);
  final String text;
}

final class AnswerResetEvent extends InferenceEvent {
  const AnswerResetEvent();
}

final class MetricsEvent extends InferenceEvent {
  const MetricsEvent(this.metrics);
  final InferenceMetrics metrics;
}

final class CompletedEvent extends InferenceEvent {
  const CompletedEvent();
}

final class ArtifactStatus {
  const ArtifactStatus({
    this.phase = ArtifactPhase.notDownloaded,
    this.downloadedBytes = 0,
    this.failure,
  });

  final ArtifactPhase phase;

  /// Verified-plus-in-flight bytes on disk; the UI derives fractions from the
  /// catalog's total, so persistence never stores a stale percentage.
  final int downloadedBytes;

  /// Non-null only when [phase] is [ArtifactPhase.failed].
  final String? failure;

  ArtifactStatus copyWith({
    ArtifactPhase? phase,
    int? downloadedBytes,
    String? failure,
    bool clearFailure = false,
  }) => ArtifactStatus(
    phase: phase ?? this.phase,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    failure: clearFailure ? null : failure ?? this.failure,
  );

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'downloadedBytes': downloadedBytes,
    'failure': failure,
  };

  factory ArtifactStatus.fromJson(Map<String, Object?> json) => ArtifactStatus(
    phase: ArtifactPhase.values.byName(
      json['phase'] as String? ?? 'notDownloaded',
    ),
    downloadedBytes: json['downloadedBytes'] as int? ?? 0,
    failure: json['failure'] as String?,
  );
}

final class ModelState {
  const ModelState({
    this.artifacts = const {},
    this.runtime = RuntimePhase.unloaded,
    this.failure,
    this.activeArtifactKey,
    this.simulated = false,
  });

  final Map<String, ArtifactStatus> artifacts;
  final RuntimePhase runtime;
  final String? failure;

  /// Stamped by the repository from its configuration; never persisted.
  final String? activeArtifactKey;

  /// True when the backing repository simulates downloads; drives every
  /// "simulated" label in the UI so honesty follows the wiring.
  final bool simulated;

  ArtifactStatus statusOf(String key) =>
      artifacts[key] ?? const ArtifactStatus();

  bool get activeModelInstalled =>
      activeArtifactKey != null &&
      statusOf(activeArtifactKey!).phase == ArtifactPhase.installed;

  ModelState copyWith({
    Map<String, ArtifactStatus>? artifacts,
    RuntimePhase? runtime,
    String? failure,
    bool clearFailure = false,
  }) => ModelState(
    artifacts: artifacts ?? this.artifacts,
    runtime: runtime ?? this.runtime,
    failure: clearFailure ? null : failure ?? this.failure,
    activeArtifactKey: activeArtifactKey,
    simulated: simulated,
  );

  ModelState withArtifact(String key, ArtifactStatus status) =>
      copyWith(artifacts: {...artifacts, key: status});

  /// Applies repository wiring to a freshly deserialized state; [copyWith]
  /// then carries the stamps through every subsequent transition.
  ModelState stamp({String? activeArtifactKey, required bool simulated}) =>
      ModelState(
        artifacts: artifacts,
        runtime: runtime,
        failure: failure,
        activeArtifactKey: activeArtifactKey,
        simulated: simulated,
      );

  // activeArtifactKey and simulated are stamped from repository wiring on
  // every load, so persisting them would only let stale configuration lie.
  Map<String, Object?> toJson() => {
    'schemaVersion': 2,
    'runtime': runtime.name,
    'failure': failure,
    'artifacts': artifacts.map((key, status) => MapEntry(key, status.toJson())),
  };

  factory ModelState.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 2) {
      throw const FormatException('Unsupported model state schema');
    }
    final artifacts = (json['artifacts'] as Map? ?? const {}).map(
      (key, value) => MapEntry(
        key as String,
        ArtifactStatus.fromJson(Map<String, Object?>.from(value as Map)),
      ),
    );
    return ModelState(
      artifacts: artifacts,
      runtime: RuntimePhase.values.byName(
        json['runtime'] as String? ?? 'unloaded',
      ),
      failure: json['failure'] as String?,
    );
  }
}

final class BenchmarkRecord {
  const BenchmarkRecord({
    required this.caseId,
    required this.phase,
    required this.timestamp,
    required this.metrics,
    required this.output,
  });
  final String caseId;
  final BenchmarkPhase phase;
  final DateTime timestamp;
  final InferenceMetrics metrics;
  final String output;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'simulated': true,
    'validation': 'UI simulation only — not hardware validated',
    'caseId': caseId,
    'phase': phase.name,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'device': 'Simulated Flutter backend',
    'metrics': metrics.toJson(),
    'output': output,
  };
}
