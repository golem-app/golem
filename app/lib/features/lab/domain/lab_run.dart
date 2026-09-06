import '../../../broker/runtime.dart' show BrokerSamplingParameters;
import '../../../core/domain/model_catalog.dart';
import '../../../core/domain/models.dart';
import '../../../core/repositories/contracts.dart';
import '../../../core/services/device_storage.dart';
import 'lab_run_settings.dart';
import 'latency_series.dart';

/// Where a bench run is. Each run passes through exactly one terminal phase;
/// the reducer refuses to move a terminal run and the controller drops late
/// events by epoch, so a run is terminated once. Stop is not a phase: a run
/// being cancelled keeps the phase it reached (see [LabRun.cancelling]), so
/// the card shows only what the engine actually did.
enum LabRunPhase {
  loading,
  promptProcessing,
  generating,
  completed,
  cancelled,
  failed;

  bool get isTerminal =>
      this == completed || this == cancelled || this == failed;

  /// Where the phase sits on a run's way forward. Explicit, so the reducer's
  /// "never backwards" and the card's "reached prefill yet" read the same
  /// order whatever the declaration order becomes.
  int get rank => switch (this) {
    loading => 0,
    promptProcessing => 1,
    generating => 2,
    completed || cancelled || failed => 3,
  };

  /// Whether a run in this phase has reached [other] on that way.
  bool reaches(LabRunPhase other) => rank >= other.rank;
}

/// Everything a run was measured under, frozen when it started (#58): a
/// cancelled or failed run keeps its own snapshot, and a later settings change
/// cannot relabel it.
final class LabRunConfiguration {
  const LabRunConfiguration({
    required this.catalogKey,
    required this.displayName,
    required this.engine,
    required this.profileKey,
    required this.quantization,
    required this.revision,
    required this.sampling,
    required this.settings,
    required this.engineBuild,
    required this.artifact,
    required this.device,
    required this.startedAt,
  });

  final String catalogKey;
  final String displayName;
  final ModelEngine engine;
  final String profileKey;
  final String quantization;
  final String revision;

  /// What the engine received — the broker's own effective merge, not a
  /// second reading of the rules.
  final BrokerSamplingParameters sampling;

  /// What the user asked for, sparse; [sampling] is what that became.
  final LabRunSettings settings;

  /// The native build behind the engine, from the package's pins.
  final String engineBuild;
  final LabArtifactProvenance artifact;
  final DeviceProvenance? device;
  final DateTime startedAt;
}

/// The artifact as it stood when the run started: how many files and bytes
/// the catalog pins, and whether the install was verified.
final class LabArtifactProvenance {
  const LabArtifactProvenance({
    required this.fileCount,
    required this.totalBytes,
    required this.verified,
  });

  final int fileCount;
  final int totalBytes;
  final bool verified;
}

/// The live observations of one run, bounded (#58): the instants ring holds
/// the newest [instantCapacity] arrivals so a long generation cannot grow
/// the state per token, while [observationCount] keeps the true total. The
/// latency figures therefore describe the last [instantCapacity] arrivals of
/// a run longer than that, which the README states beside them.
final class LabTelemetry {
  const LabTelemetry({
    this.loadFraction,
    this.loadDuration,
    this.promptCompleted,
    this.promptTotal,
    this.observationKind,
    this.observationCount = 0,
    this.instantsMs = const [],
    this.series = LatencySeries.empty,
    this.firstInstantMs,
    this.footprintBytes,
  });

  /// Larger than any token budget the bench offers by default, so the ring
  /// only ever truncates a deliberately long run; 32 KB of doubles at most.
  static const instantCapacity = 4096;

  /// The engine's own fraction, or null for an engine that reports none —
  /// which the UI shows as an indeterminate load, never a guess.
  final double? loadFraction;
  final Duration? loadDuration;

  /// Prompt tokens submitted so far, and the prompt's total; null on an
  /// engine that reports neither.
  final int? promptCompleted;
  final int? promptTotal;

  /// Whether the instants are tokens or chunks; null before the first one.
  final ObservationKind? observationKind;
  final int observationCount;
  final List<double> instantsMs;

  /// The gaps over [instantsMs], computed once per batch rather than by
  /// every card on every publish.
  final LatencySeries series;
  final double? firstInstantMs;

  /// The process footprint as last sampled — this process, not the model:
  /// null where the platform does not report.
  final int? footprintBytes;

  LabTelemetry copyWith({
    double? loadFraction,
    Duration? loadDuration,
    int? promptCompleted,
    int? promptTotal,
    ObservationKind? observationKind,
    int? observationCount,
    List<double>? instantsMs,
    LatencySeries? series,
    double? firstInstantMs,
    int? footprintBytes,
  }) => LabTelemetry(
    loadFraction: loadFraction ?? this.loadFraction,
    loadDuration: loadDuration ?? this.loadDuration,
    promptCompleted: promptCompleted ?? this.promptCompleted,
    promptTotal: promptTotal ?? this.promptTotal,
    observationKind: observationKind ?? this.observationKind,
    observationCount: observationCount ?? this.observationCount,
    instantsMs: instantsMs ?? this.instantsMs,
    series: series ?? this.series,
    firstInstantMs: firstInstantMs ?? this.firstInstantMs,
    footprintBytes: footprintBytes ?? this.footprintBytes,
  );

  /// Appends a batch, keeping the newest [instantCapacity] instants in one
  /// allocation — from the batch alone when the batch is larger than that.
  LabTelemetry withInstants(ObservationKind kind, List<double> batch) {
    if (batch.isEmpty) return this;
    final total = instantsMs.length + batch.length;
    final drop = total > instantCapacity ? total - instantCapacity : 0;
    final fromBatch = drop > instantsMs.length ? drop - instantsMs.length : 0;
    final instants = [
      for (var i = drop; i < instantsMs.length; i++) instantsMs[i],
      for (var i = fromBatch; i < batch.length; i++) batch[i],
    ];
    return copyWith(
      observationKind: kind,
      observationCount: observationCount + batch.length,
      instantsMs: instants,
      series: LatencySeries.from(instants),
      firstInstantMs: firstInstantMs ?? batch.first,
    );
  }

  LabTelemetry withFootprint(int? bytes) =>
      bytes == null ? this : copyWith(footprintBytes: bytes);
}

/// One prompt against one configuration: the bench's unit of data (#40).
/// Immutable; the reducer returns a new run per event.
final class LabRun {
  const LabRun({
    required this.id,
    required this.prompt,
    required this.configuration,
    this.phase = LabRunPhase.loading,
    this.reasoning = '',
    this.answer = '',
    this.telemetry = const LabTelemetry(),
    this.metrics,
    this.stopReason,
    this.failure,
    this.failureContextTokens,
    this.cancelRequested = false,
    this.acceptedAt,
    this.endedAt,
  });

  final String id;
  final String prompt;
  final LabRunConfiguration configuration;
  final LabRunPhase phase;
  final String reasoning;
  final String answer;
  final LabTelemetry telemetry;

  /// The engine's final numbers, under the contract they name (#57).
  final InferenceMetrics? metrics;
  final InferenceStopReason? stopReason;
  final InferenceFailureKind? failure;

  /// The context length an out-of-memory failure named, when it did.
  final int? failureContextTokens;

  /// Stop was pressed: whatever ends the stream is a cancellation.
  final bool cancelRequested;

  /// When the engine accepted the request — the zero of the instants' clock,
  /// which starts after the load; null until prompt processing began.
  final DateTime? acceptedAt;
  final DateTime? endedAt;

  bool get isTerminal => phase.isTerminal;

  /// Stop was pressed and the engine has not ended the stream yet.
  bool get cancelling => cancelRequested && !isTerminal;
  bool get hasOutput => reasoning.isNotEmpty || answer.isNotEmpty;

  /// Tokens produced: the metrics' count once they exist, else the engine's
  /// live count when the engine stamps tokens. Null while an engine that
  /// stamps chunks has not yet reported — a chunk count is never a token
  /// count (see [LabTelemetry.observationCount] for what is known).
  int? get outputTokens =>
      metrics?.tokenCount ??
      (telemetry.observationKind == ObservationKind.token
          ? telemetry.observationCount
          : null);

  LabRun copyWith({
    LabRunPhase? phase,
    String? reasoning,
    String? answer,
    LabTelemetry? telemetry,
    InferenceMetrics? metrics,
    InferenceStopReason? stopReason,
    InferenceFailureKind? failure,
    int? failureContextTokens,
    bool? cancelRequested,
    DateTime? acceptedAt,
    DateTime? endedAt,
  }) => LabRun(
    id: id,
    prompt: prompt,
    configuration: configuration,
    phase: phase ?? this.phase,
    reasoning: reasoning ?? this.reasoning,
    answer: answer ?? this.answer,
    telemetry: telemetry ?? this.telemetry,
    metrics: metrics ?? this.metrics,
    stopReason: stopReason ?? this.stopReason,
    failure: failure ?? this.failure,
    failureContextTokens: failureContextTokens ?? this.failureContextTokens,
    cancelRequested: cancelRequested ?? this.cancelRequested,
    acceptedAt: acceptedAt ?? this.acceptedAt,
    endedAt: endedAt ?? this.endedAt,
  );
}

/// The turns run under one configuration snapshot. A model or settings change
/// starts a new one (#58), so comparisons never silently mix configurations.
final class LabConversation {
  const LabConversation({required this.id, required this.runs});

  final String id;
  final List<LabRun> runs;

  LabRun? get last => runs.lastOrNull;

  LabConversation withRun(LabRun run) =>
      LabConversation(id: id, runs: _replacing(runs, run, (r) => r.id));

  /// The prompt context the next turn carries: every completed turn's prompt
  /// and answer — never its reasoning (the broker's rule for chat too), and
  /// never a cancelled or failed turn's partial output, which stays on screen
  /// as what happened rather than becoming what the model is told.
  List<PromptMessage> get context => [
    for (final run in runs)
      if (run.phase == LabRunPhase.completed && run.answer.isNotEmpty) ...[
        PromptMessage.text('user', run.prompt),
        PromptMessage.text('assistant', run.answer),
      ],
  ];
}

/// Everything measured this session, in memory only (#58): saved history,
/// grading and comparison belong to #59.
final class LabSession {
  const LabSession({this.conversations = const []});

  final List<LabConversation> conversations;

  LabConversation? get active => conversations.lastOrNull;

  /// The newest run anywhere in the session: what the persistent metrics
  /// band shows across a conversation change.
  LabRun? get lastRun =>
      conversations.reversed.map((c) => c.last).nonNulls.firstOrNull;

  int get runCount => conversations.fold(0, (sum, c) => sum + c.runs.length);

  LabSession withActive(LabConversation conversation) => LabSession(
    conversations: _replacing(conversations, conversation, (c) => c.id),
  );

  LabSession startConversation(String id) => LabSession(
    conversations: [
      ...conversations,
      LabConversation(id: id, runs: const []),
    ],
  );
}

/// [items] with the element sharing [value]'s id replaced by [value] at the
/// end — the pending run and the active conversation are always last.
List<T> _replacing<T>(List<T> items, T value, String Function(T) id) => [
  for (final existing in items)
    if (id(existing) != id(value)) existing,
  value,
];
