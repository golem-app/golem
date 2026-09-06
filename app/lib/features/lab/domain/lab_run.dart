import '../../../broker/runtime.dart' show BrokerSamplingParameters;
import '../../../core/domain/model_catalog.dart';
import '../../../core/domain/models.dart';
import '../../../core/repositories/contracts.dart';
import '../../../core/services/device_storage.dart';
import 'lab_run_settings.dart';

/// Where a bench run is. Each run passes through exactly one terminal phase;
/// the reducer refuses to move a terminal run and the controller drops late
/// events by epoch, so a run is terminated once.
enum LabRunPhase {
  loading,
  promptProcessing,
  generating,
  cancelling,
  completed,
  cancelled,
  failed;

  bool get isTerminal =>
      this == completed || this == cancelled || this == failed;
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

  bool get reasoningEnabled => settings.reasoningEnabled;
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
/// the state per token, while [observationCount] keeps the true total.
final class LabTelemetry {
  const LabTelemetry({
    this.loadFraction,
    this.loadDuration,
    this.promptCompleted,
    this.promptTotal,
    this.observationKind,
    this.observationCount = 0,
    this.instantsMs = const [],
    this.firstInstantMs,
    this.footprintBytes,
    this.peakFootprintBytes,
  });

  static const instantCapacity = 512;

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
  final double? firstInstantMs;

  /// The process footprint as last sampled, and its peak during the run —
  /// this process, not the model: null where the platform does not report.
  final int? footprintBytes;
  final int? peakFootprintBytes;

  LabTelemetry copyWith({
    double? loadFraction,
    Duration? loadDuration,
    int? promptCompleted,
    int? promptTotal,
    ObservationKind? observationKind,
    int? observationCount,
    List<double>? instantsMs,
    double? firstInstantMs,
    int? footprintBytes,
    int? peakFootprintBytes,
  }) => LabTelemetry(
    loadFraction: loadFraction ?? this.loadFraction,
    loadDuration: loadDuration ?? this.loadDuration,
    promptCompleted: promptCompleted ?? this.promptCompleted,
    promptTotal: promptTotal ?? this.promptTotal,
    observationKind: observationKind ?? this.observationKind,
    observationCount: observationCount ?? this.observationCount,
    instantsMs: instantsMs ?? this.instantsMs,
    firstInstantMs: firstInstantMs ?? this.firstInstantMs,
    footprintBytes: footprintBytes ?? this.footprintBytes,
    peakFootprintBytes: peakFootprintBytes ?? this.peakFootprintBytes,
  );

  /// Appends a batch, keeping the newest [instantCapacity] instants.
  LabTelemetry withInstants(ObservationKind kind, List<double> batch) {
    if (batch.isEmpty) return this;
    final merged = [...instantsMs, ...batch];
    return copyWith(
      observationKind: kind,
      observationCount: observationCount + batch.length,
      instantsMs: merged.length > instantCapacity
          ? merged.sublist(merged.length - instantCapacity)
          : merged,
      firstInstantMs: firstInstantMs ?? batch.first,
    );
  }

  LabTelemetry withFootprint(int? bytes) => bytes == null
      ? this
      : copyWith(
          footprintBytes: bytes,
          peakFootprintBytes:
              peakFootprintBytes == null || bytes > peakFootprintBytes!
              ? bytes
              : peakFootprintBytes,
        );
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
    this.cancelRequested = false,
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

  /// Stop was pressed: whatever ends the stream is a cancellation.
  final bool cancelRequested;
  final DateTime? endedAt;

  bool get isTerminal => phase.isTerminal;
  bool get hasOutput => reasoning.isNotEmpty || answer.isNotEmpty;

  /// Tokens produced, from the metrics once they exist, else the engine's
  /// live count — which on an engine that stamps chunks is a chunk count.
  int? get outputTokens => metrics?.tokenCount;

  LabRun copyWith({
    LabRunPhase? phase,
    String? reasoning,
    String? answer,
    LabTelemetry? telemetry,
    InferenceMetrics? metrics,
    InferenceStopReason? stopReason,
    InferenceFailureKind? failure,
    bool? cancelRequested,
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
    cancelRequested: cancelRequested ?? this.cancelRequested,
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

  LabConversation withRun(LabRun run) => LabConversation(
    id: id,
    runs: [
      for (final existing in runs)
        if (existing.id != run.id) existing,
      run,
    ],
  );

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

  int get runCount => conversations.fold(0, (sum, c) => sum + c.runs.length);

  LabSession withActive(LabConversation conversation) => LabSession(
    conversations: [
      for (final existing in conversations)
        if (existing.id != conversation.id) existing,
      conversation,
    ],
  );

  LabSession startConversation(String id) => LabSession(
    conversations: [
      ...conversations,
      LabConversation(id: id, runs: const []),
    ],
  );
}
