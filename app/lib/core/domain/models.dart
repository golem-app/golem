/// Stays in core (#69): chat, settings, and storage all consume these
/// entities, and the repository contracts name them.
library;

import 'dart:collection';
import 'dart:convert';

import 'equality.dart';

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
  if (normalized.isEmpty) return '';
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
    required this._parts,
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
  final List<MessagePart> _parts;
  final String? reasoning;
  final InferenceMetrics? metrics;
  final DateTime createdAt;
  final bool isStreaming;

  /// Unmodifiable — streaming accumulates through [withText]/[copyWith].
  List<MessagePart> get parts => UnmodifiableListView(_parts);

  /// Every text part joined; only rendering and the prompt boundary see parts.
  String get text => _parts.whereType<TextPart>().map((p) => p.text).join();

  Iterable<ImagePart> get images => _parts.whereType<ImagePart>();

  bool get hasImages => _parts.any((part) => part is ImagePart);

  ChatMessage copyWith({
    List<MessagePart>? parts,
    String? reasoning,
    InferenceMetrics? metrics,
    bool? isStreaming,
  }) => ChatMessage(
    id: id,
    role: role,
    parts: parts ?? _parts,
    reasoning: reasoning ?? this.reasoning,
    metrics: metrics ?? this.metrics,
    createdAt: createdAt,
    isStreaming: isStreaming ?? this.isStreaming,
  );

  /// Replaces the text, keeping images ahead of it as a vision prompt expects.
  /// This is how a streaming assistant draft accumulates.
  ChatMessage withText(String text) =>
      copyWith(parts: [..._parts.whereType<ImagePart>(), TextPart(text)]);

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role.name,
    'parts': _parts.map((part) => part.toJson()).toList(),
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
    required this._messages,
    required this.updatedAt,
    this.reasoningEnabled = false,
    this.pinned = false,
    this.modelKey,
  });

  final String id;
  final String title;
  final List<ChatMessage> _messages;
  final DateTime updatedAt;
  final bool reasoningEnabled;
  final bool pinned;

  /// Unmodifiable — turns are appended through the controller's copy helpers.
  List<ChatMessage> get messages => UnmodifiableListView(_messages);

  /// Catalog key of the model chosen for this chat; null means the build's
  /// default. Only ever set to a model the build could load, which is what lets
  /// labels name it before the engine has swapped to it.
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
    messages: messages ?? _messages,
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
    messages: _messages,
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
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return null;
    return ChatConversation(
      id: id,
      title: title,
      messages: _messages.take(index + 1).toList(growable: false),
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
  String transcriptMarkdown({
    required String untitledTitle,
    required String userSpeaker,
    required String assistantSpeaker,
  }) {
    final buffer = StringBuffer(
      '## ${title.isEmpty ? untitledTitle : title}\n',
    );
    for (final message in _messages.where((message) => !message.isStreaming)) {
      final speaker = message.role == MessageRole.user
          ? userSpeaker
          : assistantSpeaker;
      buffer.write('\n**$speaker:** ${message.text}\n');
    }
    return buffer.toString();
  }

  /// Prompt context intentionally excludes private reasoning.
  List<PromptMessage> get promptContext => _messages
      .where((message) => !message.isStreaming)
      .map(
        (message) =>
            PromptMessage(role: message.role.name, parts: message.parts),
      )
      .toList(growable: false);

  /// The store keeps exactly the union of these across all conversations.
  Iterable<String> get attachmentIds =>
      _messages.expand((message) => message.images).map((i) => i.attachmentId);

  // pinned/modelKey stay additive under schemaVersion 1: absent keys
  // default below, so pre-#47 histories load unchanged.
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'messages': _messages
        .where((message) => !message.isStreaming)
        .map((m) => m.toJson())
        .toList(),
    'updatedAt': updatedAt.toIso8601String(),
    'reasoningEnabled': reasoningEnabled,
    'pinned': pinned,
    'modelKey': modelKey,
  };

  factory ChatConversation.fromJson(
    Map<String, Object?> json, {
    bool migrateGeneratedPlaceholder = false,
  }) {
    final messages = (json['messages']! as List)
        .map(
          (item) =>
              ChatMessage.fromJson(Map<String, Object?>.from(item as Map)),
        )
        .toList(growable: false);
    final storedTitle = json['title']! as String;
    final generatedPlaceholder =
        migrateGeneratedPlaceholder &&
        (storedTitle == 'New chat' && messages.isEmpty ||
            storedTitle == 'Image' &&
                messages.firstOrNull?.role == MessageRole.user &&
                messages.firstOrNull?.text.isEmpty == true &&
                messages.firstOrNull?.hasImages == true);
    return ChatConversation(
      id: json['id']! as String,
      title: generatedPlaceholder ? '' : normalizeTitle(storedTitle),
      messages: messages,
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      reasoningEnabled: json['reasoningEnabled'] as bool? ?? false,
      pinned: json['pinned'] as bool? ?? false,
      modelKey: json['modelKey'] as String?,
    );
  }
}

final class ChatHistorySnapshot {
  const ChatHistorySnapshot({required this._conversations, this.activeId});
  final List<ChatConversation> _conversations;
  final String? activeId;

  /// Unmodifiable — snapshots are rebuilt, never edited in place.
  List<ChatConversation> get conversations =>
      UnmodifiableListView(_conversations);

  /// v2 replaced message text with ordered parts (#18); v3 made generated
  /// untitled placeholders semantic (#71).
  static const schemaVersion = 3;

  Set<String> get referencedAttachmentIds => {
    for (final conversation in _conversations) ...conversation.attachmentIds,
  };

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'activeConversationId': activeId,
    'conversations': _conversations.map((item) => item.toJson()).toList(),
  };

  factory ChatHistorySnapshot.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != 1 && version != 2 && version != schemaVersion) {
      throw const FormatException('Unsupported chat history schema');
    }
    final conversations = (json['conversations']! as List)
        .map(
          (item) => ChatConversation.fromJson(
            Map<String, Object?>.from(item as Map),
            migrateGeneratedPlaceholder: version != schemaVersion,
          ),
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

  @override
  bool operator ==(Object other) =>
      other is InferenceMetrics &&
      other.promptTokensPerSecond == promptTokensPerSecond &&
      other.decodeTokensPerSecond == decodeTokensPerSecond &&
      other.tokenCount == tokenCount &&
      other.elapsedSeconds == elapsedSeconds &&
      other.promptTokenCount == promptTokenCount &&
      other.timeToFirstTokenSeconds == timeToFirstTokenSeconds &&
      other.peakPhysicalFootprintBytes == peakPhysicalFootprintBytes;

  @override
  int get hashCode => Object.hash(
    promptTokensPerSecond,
    decodeTokensPerSecond,
    tokenCount,
    elapsedSeconds,
    promptTokenCount,
    timeToFirstTokenSeconds,
    peakPhysicalFootprintBytes,
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

/// Why the engine is not holding weights. Persisted, so it names the cause
/// rather than quoting an exception: `'$error'` can carry an absolute path off
/// the device into the user's store, and hand-written copy there is copy no
/// locale can translate (#130).
enum RuntimeFailureKind {
  /// This device is outside every supported tier (#27).
  deviceRefused,

  /// No installed artifact the composed engine could load.
  notInstalled,

  /// `prepare()` threw.
  engineLoad,

  /// `unload()` threw.
  engineUnload,
}

/// A stable model-transfer failure classification. The diagnostic [failure]
/// string on [ArtifactStatus] remains available for logs, while presentation
/// localizes this value and its safe parameters without parsing prose.
enum ArtifactFailureKind {
  insufficientStorage,
  hashVerification,
  unexpectedSize,
  transfer,
}

final class ArtifactFailure {
  const ArtifactFailure(
    this.kind, {
    this.requiredBytes,
    this.availableBytes,
    this.fileName,
  });

  final ArtifactFailureKind kind;
  final int? requiredBytes;
  final int? availableBytes;
  final String? fileName;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'requiredBytes': ?requiredBytes,
    'availableBytes': ?availableBytes,
    'fileName': ?fileName,
  };

  factory ArtifactFailure.fromJson(Map<String, Object?> json) =>
      ArtifactFailure(
        ArtifactFailureKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => ArtifactFailureKind.transfer,
        ),
        requiredBytes: json['requiredBytes'] as int?,
        availableBytes: json['availableBytes'] as int?,
        fileName: json['fileName'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is ArtifactFailure &&
      other.kind == kind &&
      other.requiredBytes == requiredBytes &&
      other.availableBytes == availableBytes &&
      other.fileName == fileName;

  @override
  int get hashCode =>
      Object.hash(kind, requiredBytes, availableBytes, fileName);
}

final class ArtifactStatus {
  const ArtifactStatus({
    this.phase = ArtifactPhase.notDownloaded,
    this.downloadedBytes = 0,
    this.verifiedBytes = 0,
    this.failure,
    this.failureReason,
  });

  final ArtifactPhase phase;

  /// Bytes on disk at their pinned size plus the in-flight transfer; the UI
  /// derives fractions from the catalog's total, so persistence never stores
  /// a stale percentage.
  final int downloadedBytes;

  /// Bytes the current [ArtifactPhase.verifying] pass has hashed — the
  /// receipted files plus every file read so far, whether it passed — the
  /// determinate reading of a phase that used to be a spinner (#143). Never
  /// decreases within a pass. In-memory like [failure]: a verify phase never
  /// survives a relaunch (reconciliation re-derives it from the receipt), so
  /// the store would only ever hold a stale count.
  final int verifiedBytes;

  /// The counter this phase is measured by: hashed bytes while verifying,
  /// transferred bytes otherwise. The one rule every bar, percentage and
  /// pace window reads, so none of them can disagree on which it is.
  int get progressBytes =>
      phase == ArtifactPhase.verifying ? verifiedBytes : downloadedBytes;

  /// Internal diagnostic — never rendered, and never written to disk. It
  /// quotes whatever failed, which for a transfer means a platform message or
  /// an exception that can name a path on this device; [failureReason] is what
  /// survives a relaunch and what presentation words (#130).
  final String? failure;

  /// Localizable failure classification and safe presentation parameters.
  final ArtifactFailure? failureReason;

  ArtifactStatus copyWith({
    ArtifactPhase? phase,
    int? downloadedBytes,
    int? verifiedBytes,
    String? failure,
    ArtifactFailure? failureReason,
    bool clearFailure = false,
  }) => ArtifactStatus(
    phase: phase ?? this.phase,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    verifiedBytes: verifiedBytes ?? this.verifiedBytes,
    failure: clearFailure ? null : failure ?? this.failure,
    failureReason: clearFailure ? null : failureReason ?? this.failureReason,
  );

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'downloadedBytes': downloadedBytes,
    'failureReason': failureReason?.toJson(),
  };

  factory ArtifactStatus.fromJson(Map<String, Object?> json) => ArtifactStatus(
    phase: ArtifactPhase.values.byName(
      json['phase'] as String? ?? 'notDownloaded',
    ),
    downloadedBytes: json['downloadedBytes'] as int? ?? 0,
    failureReason: json['failureReason'] is Map
        ? ArtifactFailure.fromJson(
            Map<String, Object?>.from(json['failureReason']! as Map),
          )
        : null,
  );

  @override
  bool operator ==(Object other) =>
      other is ArtifactStatus &&
      other.phase == phase &&
      other.downloadedBytes == downloadedBytes &&
      other.verifiedBytes == verifiedBytes &&
      other.failure == failure &&
      other.failureReason == failureReason;

  @override
  int get hashCode => Object.hash(
    phase,
    downloadedBytes,
    verifiedBytes,
    failure,
    failureReason,
  );
}

final class ModelState {
  const ModelState({
    this._artifacts = const {},
    this.runtime = RuntimePhase.unloaded,
    this.failure,
    this.activeArtifactKey,
    this.simulated = false,
  });

  final Map<String, ArtifactStatus> _artifacts;
  final RuntimePhase runtime;

  /// Why [runtime] is not `loaded`, or null while nothing has failed.
  final RuntimeFailureKind? failure;

  /// Unmodifiable — transitions go through [withArtifact]/[copyWith].
  Map<String, ArtifactStatus> get artifacts => UnmodifiableMapView(_artifacts);

  /// Stamped by the repository from its configuration; never persisted.
  final String? activeArtifactKey;

  /// True when the backing repository simulates downloads; drives every
  /// "simulated" label in the UI so honesty follows the wiring.
  final bool simulated;

  ArtifactStatus statusOf(String key) =>
      _artifacts[key] ?? const ArtifactStatus();

  ModelState copyWith({
    Map<String, ArtifactStatus>? artifacts,
    RuntimePhase? runtime,
    RuntimeFailureKind? failure,
    bool clearFailure = false,
  }) => ModelState(
    artifacts: artifacts ?? _artifacts,
    runtime: runtime ?? this.runtime,
    failure: clearFailure ? null : failure ?? this.failure,
    activeArtifactKey: activeArtifactKey,
    simulated: simulated,
  );

  ModelState withArtifact(String key, ArtifactStatus status) =>
      copyWith(artifacts: {..._artifacts, key: status});

  /// [copyWith] then carries these stamps through every later transition.
  ModelState stamp({String? activeArtifactKey, required bool simulated}) =>
      ModelState(
        artifacts: _artifacts,
        runtime: runtime,
        failure: failure,
        activeArtifactKey: activeArtifactKey,
        simulated: simulated,
      );

  /// Schema 3 replaced a free-text `failure` with a [RuntimeFailureKind] name;
  /// schema 2 is still read, and its sentence is dropped rather than kept as a
  /// kind nobody can derive from prose (#130). The file name stays v2 — it
  /// marks a change of *location*, which this is not.
  ///
  /// The move is one-way: a build that predates schema 3 rejects this file and
  /// falls back to defaults, so a rollback re-offers every install as a
  /// download. Accepted rather than dodged by leaving the number at 2 — the
  /// field changed type, and a version that does not say so is the lie the
  /// version exists to prevent.
  static const schemaVersion = 3;

  // activeArtifactKey and simulated are stamped from repository wiring on
  // every load, so persisting them would only let stale configuration lie.
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'runtime': runtime.name,
    'failure': failure?.name,
    'artifacts': _artifacts.map(
      (key, status) => MapEntry(key, status.toJson()),
    ),
  };

  @override
  bool operator ==(Object other) =>
      other is ModelState &&
      other.runtime == runtime &&
      other.failure == failure &&
      other.activeArtifactKey == activeArtifactKey &&
      other.simulated == simulated &&
      mapEquals(other._artifacts, _artifacts);

  @override
  int get hashCode => Object.hash(
    runtime,
    failure,
    activeArtifactKey,
    simulated,
    mapHash(_artifacts),
  );

  factory ModelState.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != 2 && version != schemaVersion) {
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
      // Tolerant on purpose: a schema-2 store holds an English sentence here,
      // and an unrecognized name from any build is a value this one cannot act
      // on. Both read as "nothing classified".
      failure: RuntimeFailureKind.values
          .where((kind) => kind.name == json['failure'])
          .firstOrNull,
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
