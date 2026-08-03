import 'dart:convert';

enum MessageRole { user, assistant }

enum BackendId { mlx, turboFieldfare }

enum DownloadPhase { notDownloaded, downloading, paused, verifying, installed }

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

final class MetricsEvent extends InferenceEvent {
  const MetricsEvent(this.metrics);
  final InferenceMetrics metrics;
}

final class CompletedEvent extends InferenceEvent {
  const CompletedEvent();
}

final class ModelState {
  const ModelState({
    this.backend = BackendId.turboFieldfare,
    this.mlxPhase = DownloadPhase.notDownloaded,
    this.mlxProgress = 0,
    this.turboInstalled = true,
    this.importProgress = 0,
    this.runtime = RuntimePhase.loaded,
    this.failure,
  });

  final BackendId backend;
  final DownloadPhase mlxPhase;
  final double mlxProgress;
  final bool turboInstalled;
  final double importProgress;
  final RuntimePhase runtime;
  final String? failure;

  bool get activeModelInstalled => backend == BackendId.mlx
      ? mlxPhase == DownloadPhase.installed
      : turboInstalled;

  ModelState copyWith({
    BackendId? backend,
    DownloadPhase? mlxPhase,
    double? mlxProgress,
    bool? turboInstalled,
    double? importProgress,
    RuntimePhase? runtime,
    String? failure,
    bool clearFailure = false,
  }) => ModelState(
    backend: backend ?? this.backend,
    mlxPhase: mlxPhase ?? this.mlxPhase,
    mlxProgress: mlxProgress ?? this.mlxProgress,
    turboInstalled: turboInstalled ?? this.turboInstalled,
    importProgress: importProgress ?? this.importProgress,
    runtime: runtime ?? this.runtime,
    failure: clearFailure ? null : failure ?? this.failure,
  );

  // importProgress is deliberately not serialized: an import cannot survive
  // a relaunch, so persisted in-flight progress would only render a stuck bar.
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'backend': backend.name,
    'mlxPhase': mlxPhase.name,
    'mlxProgress': mlxProgress,
    'turboInstalled': turboInstalled,
    'runtime': runtime.name,
    'failure': failure,
  };

  factory ModelState.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported model state schema');
    }
    return ModelState(
      backend: BackendId.values.byName(
        json['backend'] as String? ?? 'turboFieldfare',
      ),
      mlxPhase: DownloadPhase.values.byName(
        json['mlxPhase'] as String? ?? 'notDownloaded',
      ),
      mlxProgress: (json['mlxProgress'] as num? ?? 0).toDouble(),
      turboInstalled: json['turboInstalled'] as bool? ?? true,
      runtime: RuntimePhase.values.byName(
        json['runtime'] as String? ?? 'loaded',
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
