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

/// One ordered piece of a message's content. A list of parts rather than a
/// string so an image can sit at a known position relative to the text;
/// text-only messages carry one [TextPart], which is how pre-#18 chats migrate.
sealed class MessagePart {
  const MessagePart();

  Map<String, Object?> toJson();

  static MessagePart fromJson(Map<String, Object?> json) =>
      switch (json['type']) {
        'text' => TextPart(_requireString(json['text'], 'text')),
        'image' => ImagePart.fromJson(json),
        final unsupported => throw FormatException(
          'Unsupported message part type: $unsupported',
        ),
      };
}

final class TextPart extends MessagePart {
  const TextPart(this.text);

  final String text;

  @override
  Map<String, Object?> toJson() => {'type': 'text', 'text': text};
}

/// [attachmentId] is an opaque store identifier, never a photo-library or
/// filesystem path: an export must not leak where the picture came from.
final class ImagePart extends MessagePart {
  const ImagePart({
    required this.attachmentId,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.byteCount,
  });

  final String attachmentId;
  final String mimeType;
  final int width;
  final int height;
  final int byteCount;

  @override
  Map<String, Object?> toJson() => {
    'type': 'image',
    'attachmentId': attachmentId,
    'mimeType': mimeType,
    'width': width,
    'height': height,
    'byteCount': byteCount,
  };

  factory ImagePart.fromJson(Map<String, Object?> json) => ImagePart(
    attachmentId: _requireString(json['attachmentId'], 'attachmentId'),
    mimeType: _requireString(json['mimeType'], 'mimeType'),
    width: _requireInt(json['width'], 'width'),
    height: _requireInt(json['height'], 'height'),
    byteCount: _requireInt(json['byteCount'], 'byteCount'),
  );
}

String _requireString(Object? raw, String field) {
  if (raw is String) return raw;
  throw FormatException('$field must be a string');
}

int _requireInt(Object? raw, String field) {
  if (raw is int) return raw;
  throw FormatException('$field must be an integer');
}

/// One turn as the inference boundary sees it. Deliberately not [ChatMessage]:
/// ids, timestamps, metrics and streaming state are presentation concerns an
/// engine has no business receiving, and a build's system turn has none.
final class PromptMessage {
  const PromptMessage({required this.role, required this.parts});

  /// `user`, `assistant`, or `system`.
  final String role;
  final List<MessagePart> parts;

  factory PromptMessage.text(String role, String text) =>
      PromptMessage(role: role, parts: [TextPart(text)]);

  String get text => parts.whereType<TextPart>().map((p) => p.text).join();

  Iterable<ImagePart> get images => parts.whereType<ImagePart>();

  bool get hasImages => parts.any((part) => part is ImagePart);
}

final class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.parts,
    required this.createdAt,
    this.reasoning,
    this.metrics,
    this.isStreaming = false,
  });

  factory ChatMessage.text({
    required String id,
    required MessageRole role,
    required String text,
    required DateTime createdAt,
    String? reasoning,
    InferenceMetrics? metrics,
    bool isStreaming = false,
  }) => ChatMessage(
    id: id,
    role: role,
    parts: [TextPart(text)],
    createdAt: createdAt,
    reasoning: reasoning,
    metrics: metrics,
    isStreaming: isStreaming,
  );

  final String id;
  final MessageRole role;
  final List<MessagePart> parts;
  final String? reasoning;
  final InferenceMetrics? metrics;
  final DateTime createdAt;
  final bool isStreaming;

  /// Every text part joined; only rendering and the prompt boundary see parts.
  String get text => parts.whereType<TextPart>().map((p) => p.text).join();

  Iterable<ImagePart> get images => parts.whereType<ImagePart>();

  bool get hasImages => parts.any((part) => part is ImagePart);

  ChatMessage copyWith({
    List<MessagePart>? parts,
    String? reasoning,
    InferenceMetrics? metrics,
    bool? isStreaming,
  }) => ChatMessage(
    id: id,
    role: role,
    parts: parts ?? this.parts,
    reasoning: reasoning ?? this.reasoning,
    metrics: metrics ?? this.metrics,
    createdAt: createdAt,
    isStreaming: isStreaming ?? this.isStreaming,
  );

  /// Replaces the text, keeping images ahead of it as a vision prompt expects.
  /// This is how a streaming assistant draft accumulates.
  ChatMessage withText(String text) =>
      copyWith(parts: [...parts.whereType<ImagePart>(), TextPart(text)]);

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role.name,
    'parts': parts.map((part) => part.toJson()).toList(),
    'reasoning': reasoning,
    'metrics': metrics?.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };

  /// Reads v2 `parts`, migrating a v1 `text` message so pre-#18 history loads.
  factory ChatMessage.fromJson(Map<String, Object?> json) {
    final rawParts = json['parts'];
    final parts = rawParts is List
        ? [
            for (final item in rawParts)
              MessagePart.fromJson(Map<String, Object?>.from(item as Map)),
          ]
        : [TextPart(_requireString(json['text'], 'text'))];
    return ChatMessage(
      id: _requireString(json['id'], 'id'),
      role: MessageRole.values.byName(_requireString(json['role'], 'role')),
      parts: parts,
      reasoning: json['reasoning'] as String?,
      metrics: json['metrics'] == null
          ? null
          : InferenceMetrics.fromJson(
              Map<String, Object?>.from(json['metrics']! as Map),
            ),
      createdAt: DateTime.parse(_requireString(json['createdAt'], 'createdAt')),
    );
  }
}

final class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
    this.reasoningEnabled = false,
    this.pinned = false,
    this.modelKey,
  });

  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime updatedAt;
  final bool reasoningEnabled;
  final bool pinned;

  /// Catalog key of the model chosen for this chat; null means the build's
  /// default. Acted on only where supported (the fake today, real with #20).
  final String? modelKey;

  ChatConversation copyWith({
    String? title,
    List<ChatMessage>? messages,
    DateTime? updatedAt,
    bool? reasoningEnabled,
    bool? pinned,
  }) => ChatConversation(
    id: id,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    updatedAt: updatedAt ?? this.updatedAt,
    reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
    pinned: pinned ?? this.pinned,
    modelKey: modelKey,
  );

  ChatConversation togglePinned() => copyWith(pinned: !pinned);

  /// Explicit because [copyWith] cannot null a field.
  ChatConversation withModel(String? key) => ChatConversation(
    id: id,
    title: title,
    messages: messages,
    updatedAt: updatedAt,
    reasoningEnabled: reasoningEnabled,
    pinned: pinned,
    modelKey: key,
  );

  ChatConversation? branchUpTo(
    String messageId, {
    required String id,
    required DateTime now,
  }) {
    final index = messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return null;
    return ChatConversation(
      id: id,
      title: title,
      messages: messages.take(index + 1).toList(growable: false),
      updatedAt: now,
      reasoningEnabled: reasoningEnabled,
      modelKey: modelKey,
    );
  }

  ChatConversation withoutMessage(String messageId) => copyWith(
    messages: messages
        .where((message) => message.id != messageId)
        .toList(growable: false),
  );

  /// Shareable transcript; reasoning stays private, like [promptContext].
  String transcriptMarkdown() {
    final buffer = StringBuffer('## $title\n');
    for (final message in messages.where((message) => !message.isStreaming)) {
      final speaker = message.role == MessageRole.user ? 'You' : 'Golem';
      buffer.write('\n**$speaker:** ${message.text}\n');
    }
    return buffer.toString();
  }

  /// Prompt context intentionally excludes private reasoning.
  List<PromptMessage> get promptContext => messages
      .where((message) => !message.isStreaming)
      .map(
        (message) =>
            PromptMessage(role: message.role.name, parts: message.parts),
      )
      .toList(growable: false);

  /// The store keeps exactly the union of these across all conversations.
  Iterable<String> get attachmentIds =>
      messages.expand((message) => message.images).map((i) => i.attachmentId);

  // pinned/modelKey stay additive under schemaVersion 1: absent keys
  // default below, so pre-#47 histories load unchanged.
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'messages': messages
        .where((message) => !message.isStreaming)
        .map((m) => m.toJson())
        .toList(),
    'updatedAt': updatedAt.toIso8601String(),
    'reasoningEnabled': reasoningEnabled,
    'pinned': pinned,
    'modelKey': modelKey,
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
        pinned: json['pinned'] as bool? ?? false,
        modelKey: json['modelKey'] as String?,
      );
}

final class ChatHistorySnapshot {
  const ChatHistorySnapshot({required this.conversations, this.activeId});
  final List<ChatConversation> conversations;
  final String? activeId;

  /// v2 replaced each message's flat `text` with ordered `parts` (#18); a v1
  /// file loads unchanged and is rewritten as v2 on the next save.
  static const schemaVersion = 2;

  Set<String> get referencedAttachmentIds => {
    for (final conversation in conversations) ...conversation.attachmentIds,
  };

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'activeConversationId': activeId,
    'conversations': conversations.map((item) => item.toJson()).toList(),
  };

  factory ChatHistorySnapshot.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != 1 && version != schemaVersion) {
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
    this.promptTokenCount,
    this.timeToFirstTokenSeconds,
    this.peakPhysicalFootprintBytes,
  });
  final double promptTokensPerSecond;
  final double decodeTokensPerSecond;
  final int tokenCount;
  final double elapsedSeconds;

  /// Measurement-grade fields a real engine reports and the fake leaves null;
  /// serialized sparsely so persisted history stays stable.
  final int? promptTokenCount;
  final double? timeToFirstTokenSeconds;
  final int? peakPhysicalFootprintBytes;

  Map<String, Object> toJson() => {
    'promptTokensPerSecond': promptTokensPerSecond,
    'decodeTokensPerSecond': decodeTokensPerSecond,
    'tokenCount': tokenCount,
    'elapsedSeconds': elapsedSeconds,
    'promptTokenCount': ?promptTokenCount,
    'timeToFirstTokenSeconds': ?timeToFirstTokenSeconds,
    'peakPhysicalFootprintBytes': ?peakPhysicalFootprintBytes,
  };

  factory InferenceMetrics.fromJson(
    Map<String, Object?> json,
  ) => InferenceMetrics(
    promptTokensPerSecond: (json['promptTokensPerSecond']! as num).toDouble(),
    decodeTokensPerSecond: (json['decodeTokensPerSecond']! as num).toDouble(),
    tokenCount: json['tokenCount']! as int,
    elapsedSeconds: (json['elapsedSeconds']! as num).toDouble(),
    promptTokenCount: json['promptTokenCount'] as int?,
    timeToFirstTokenSeconds: (json['timeToFirstTokenSeconds'] as num?)
        ?.toDouble(),
    peakPhysicalFootprintBytes: json['peakPhysicalFootprintBytes'] as int?,
  );
}

/// Why a generation ended, mirrored from the engine's stop policy.
enum InferenceStopReason {
  endOfSequence,
  stopSequence,
  stopToken,
  maxTokens,
  cancelled,
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
  const CompletedEvent({this.stopReason, this.rawTextHash, this.rawTextLength});

  /// Null when the source does not report one (the fake, cancellations).
  final InferenceStopReason? stopReason;

  /// FNV-1a 64 hash and length of the raw pre-parser text, present only under a
  /// fixed sampling seed (determinism probes, eval); never the transcript.
  final String? rawTextHash;
  final int? rawTextLength;
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

  /// [copyWith] then carries these stamps through every later transition.
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

  // Deliberately hardcoded even in real-engine builds: the only benchmark
  // implementation is the deterministic fake, so this labeling stays honest
  // until a real one exists (docs/decisions/0003-flavor-backend-defaults.md).
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
