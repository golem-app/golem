import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../broker/effective_sampling.dart';
import '../../../broker/model_profile.dart';
import '../../../broker/model_runtime_config.dart';
import '../../../broker/runtime.dart' show engineBuildLabel;
import '../../../core/domain/app_state.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';
import '../../../core/repositories/contracts.dart';
import '../../../core/services/device_storage.dart';
import '../../models/application/model_providers.dart';
import '../domain/lab_configuration.dart';
import '../domain/lab_run.dart';
import '../domain/lab_run_reducer.dart';
import '../domain/lab_run_settings.dart';
import 'lab_providers.dart';

part 'lab_bench_controller.g.dart';

/// The bench's live state: what is armed, the run settings, everything
/// measured this session, and which run is in flight. Identity-equal like
/// ChatState, for the same reason — it is reassigned per coalesced tick.
final class LabBenchState {
  const LabBenchState({
    this.armed,
    this.settings = const LabRunSettings(),
    this.session = const LabSession(),
    this.activeRunId,
  });

  final LabConfiguration? armed;
  final LabRunSettings settings;
  final LabSession session;
  final String? activeRunId;

  LabRun? get activeRun => activeRunId == null
      ? null
      : session.active?.runs.where((run) => run.id == activeRunId).firstOrNull;

  /// A run in flight locks the Rig: changing what a run measures under
  /// mid-run would silently invalidate the comparison, so it is impossible
  /// rather than merely warned against (#58).
  bool get locked => !(activeRun?.isTerminal ?? true);

  LabBenchState copyWith({
    LabConfiguration? Function()? armed,
    LabRunSettings? settings,
    LabSession? session,
    String? Function()? activeRunId,
  }) => LabBenchState(
    armed: armed == null ? this.armed : armed(),
    settings: settings ?? this.settings,
    session: session ?? this.session,
    activeRunId: activeRunId == null ? this.activeRunId : activeRunId(),
  );
}

/// How often the bench publishes a run in flight. Events fold into a pending
/// run as they arrive; the state — and so the transcript and the chart —
/// rebuilds on this cadence, never per token (#58). Phase changes and the
/// terminal event publish at once.
const labPublishInterval = Duration(milliseconds: 60);

/// How often the process footprint is sampled while a run is in flight.
const labFootprintInterval = Duration(milliseconds: 500);

/// KeepAlive: a command controller whose run, epoch and timers must outlive
/// any one widget (handbook v5.0 §3.4).
@Riverpod(keepAlive: true, retry: noRetry)
class LabBenchController extends _$LabBenchController {
  int _epoch = 0;
  int _runSerial = 0;
  int _conversationSerial = 0;
  LabRun? _pending;
  Timer? _publish;
  Timer? _footprint;
  StreamSubscription<InferenceEvent>? _subscription;

  @override
  LabBenchState build() {
    // The lab has no chat: model commands asking whether a generation is in
    // flight read the bench instead (ADR 0021). Watched so a refreshed bridge
    // re-binds.
    ref
        .watch(chatSessionBridgeProvider)
        .bindSessionState(
          () => ChatState(
            generation: state.locked
                ? GenerationPhase.streaming
                : GenerationPhase.idle,
          ),
        );
    ref.onDispose(() {
      _publish?.cancel();
      _footprint?.cancel();
      unawaited(_subscription?.cancel());
    });
    return const LabBenchState();
  }

  /// Arms a configuration. A change under a conversation with runs starts a
  /// new conversation, so its runs never sit beside runs of another
  /// configuration. Refused while a run is in flight.
  bool arm(String catalogKey) {
    if (state.locked) return false;
    final configuration = ref
        .read(labConfigurationListProvider)
        .where((c) => c.key == catalogKey)
        .firstOrNull;
    if (configuration == null) return false;
    if (state.armed == configuration) return true;
    state = state.copyWith(
      armed: () => configuration,
      session: _sessionForChange(),
    );
    return true;
  }

  /// Applies settings that validate against the armed profile; returns the
  /// problems otherwise and applies nothing. A change under a conversation
  /// with runs starts a new one. Refused while a run is in flight.
  List<LabSettingsProblem> updateSettings(LabRunSettings settings) {
    if (state.locked) return const [LabSettingsProblem.contextBelowFloor];
    final armed = state.armed;
    if (armed != null) {
      final problems = settings.validate(
        defaults: _profileFor(
          armed,
        ).sampling(reasoningEnabled: settings.reasoningEnabled),
        contextCeiling: armed.entry.contextLength,
      );
      if (problems.isNotEmpty) return problems;
    }
    if (settings == state.settings) return const [];
    state = state.copyWith(settings: settings, session: _sessionForChange());
    return const [];
  }

  /// Starts a fresh conversation under the current configuration. Refused
  /// while a run is in flight; a no-op when the current one is empty.
  bool newConversation() {
    if (state.locked) return false;
    if (state.session.active?.runs.isEmpty ?? false) return true;
    state = state.copyWith(session: _startConversation(state.session));
    return true;
  }

  /// Sends [prompt] against the armed configuration as a new run. Returns
  /// false when nothing is armed, a run is in flight, the prompt is empty, or
  /// the settings do not validate — the surfaces gate every one of those
  /// before offering the action, so this is the second line.
  Future<bool> send(String prompt) async {
    final armed = state.armed;
    if (armed == null || state.locked || prompt.trim().isEmpty) return false;
    final profile = _profileFor(armed);
    final settings = state.settings;
    final defaults = profile.sampling(
      reasoningEnabled: settings.reasoningEnabled,
    );
    if (settings
        .validate(defaults: defaults, contextCeiling: armed.entry.contextLength)
        .isNotEmpty) {
      return false;
    }
    final (sampling, _) = effectiveSampling(
      profile: profile,
      defaults: defaults,
      overrides: settings.toOverrides(),
      seed: settings.seed,
    );
    // The artifact's verified state, from the model store once it has read;
    // a store that will not read leaves the provenance unverified rather than
    // blocking the run.
    ModelState? models;
    try {
      models = await ref.read(modelControllerProvider.future);
    } on Object {
      models = null;
    }
    if (!ref.mounted || state.locked) return false;
    final artifact = models?.statusOf(armed.key);
    final run = LabRun(
      id: 'run-${++_runSerial}',
      prompt: prompt.trim(),
      configuration: LabRunConfiguration(
        catalogKey: armed.key,
        displayName: armed.displayName,
        engine: armed.engine,
        profileKey: armed.profileKey,
        quantization: armed.entry.quantization,
        revision: armed.entry.revision,
        sampling: sampling,
        settings: settings,
        engineBuild: engineBuildLabel(brokerEngineFor(armed.engine)),
        artifact: LabArtifactProvenance(
          fileCount: armed.entry.files.length,
          totalBytes: armed.entry.totalBytes,
          verified: artifact?.phase == ArtifactPhase.installed,
        ),
        device: ref.read(labDeviceProvenanceProvider).value,
        startedAt: DateTime.now(),
      ),
    );
    final session = state.session.active == null
        ? _startConversation(state.session)
        : state.session;
    final conversation = session.active!;
    final context = [
      ...conversation.context,
      PromptMessage.text('user', run.prompt),
    ];
    _pending = run;
    state = state.copyWith(
      session: session.withActive(conversation.withRun(run)),
      activeRunId: () => run.id,
    );
    final epoch = ++_epoch;
    _startFootprintSampling(epoch);
    final repository = ref.read(inferenceRepositoryProvider);
    final completed = Completer<void>();
    _subscription = repository
        .generate(
          context: context,
          reasoningEnabled: settings.reasoningEnabled,
          overrides: settings.toOverrides(),
          modelKey: armed.key,
          observe: GenerationObservation.everything,
          seed: settings.seed,
        )
        .listen(
          (event) => _fold(epoch, event),
          onError: (Object error) {
            if (epoch != _epoch) return;
            _terminate(
              epoch,
              failRun(
                _pending!,
                error is InferenceException
                    ? error.kind
                    : InferenceFailureKind.engine,
              ),
            );
          },
          onDone: () {
            if (epoch != _epoch) return;
            final pending = _pending!;
            // A stream that ended without its completion event: the engine
            // was torn down under it, or Stop cut it before the first event.
            _terminate(
              epoch,
              pending.isTerminal
                  ? pending
                  : reduceLabRun(pending, const CompletedEvent()),
            );
            completed.complete();
          },
          cancelOnError: true,
        );
    return true;
  }

  /// Stop: the run reads as cancelling until the engine ends the stream,
  /// keeping whatever it produced. The cancel itself is fire-and-forget, like
  /// chat's — the stream's own end is what terminates the run.
  void stop() {
    final pending = _pending;
    if (pending == null || !state.locked) return;
    _pending = requestCancel(pending);
    _publishNow();
    unawaited(ref.read(inferenceRepositoryProvider).cancel());
  }

  /// Sends the last cancelled or failed prompt again under the current
  /// configuration, as a new run beside the old one.
  Future<bool> retry() async {
    final last = state.session.active?.last;
    if (last == null ||
        !last.isTerminal ||
        last.phase == LabRunPhase.completed) {
      return false;
    }
    return send(last.prompt);
  }

  void _fold(int epoch, InferenceEvent event) {
    if (epoch != _epoch) return;
    final before = _pending!;
    final after = reduceLabRun(before, event);
    _pending = after;
    if (after.isTerminal) {
      _terminate(epoch, after);
    } else if (after.phase != before.phase) {
      _publishNow();
    } else {
      _publish ??= Timer(labPublishInterval, _publishNow);
    }
  }

  void _terminate(int epoch, LabRun run) {
    if (epoch != _epoch) return;
    _pending = run;
    _footprint?.cancel();
    _footprint = null;
    _publishNow();
    _pending = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _publishNow() {
    _publish?.cancel();
    _publish = null;
    final pending = _pending;
    final conversation = state.session.active;
    if (pending == null || conversation == null || !ref.mounted) return;
    state = state.copyWith(
      session: state.session.withActive(conversation.withRun(pending)),
    );
  }

  void _startFootprintSampling(int epoch) {
    _footprint?.cancel();
    final probe = ref.read(labProbesProvider).footprint;
    // Once at the start, so a run shorter than the interval still carries a
    // reading, then on the cadence.
    unawaited(_sampleFootprint(epoch, probe));
    _footprint = Timer.periodic(
      labFootprintInterval,
      (_) => _sampleFootprint(epoch, probe),
    );
  }

  Future<void> _sampleFootprint(int epoch, ProcessFootprintProbe probe) async {
    if (epoch != _epoch) return;
    final int? bytes;
    try {
      bytes = await probe.physicalFootprintBytes();
    } on Object {
      return;
    }
    if (epoch != _epoch || !ref.mounted) return;
    final pending = _pending;
    if (pending == null || pending.isTerminal) return;
    _pending = pending.copyWith(
      telemetry: pending.telemetry.withFootprint(bytes),
    );
    _publish ??= Timer(labPublishInterval, _publishNow);
  }

  ModelProfile _profileFor(LabConfiguration configuration) =>
      modelProfiles[configuration.profileKey]!;

  LabSession _startConversation(LabSession session) =>
      session.startConversation('conversation-${++_conversationSerial}');

  /// A change of what a run measures under closes the current conversation
  /// when it holds runs, and leaves an empty one alone.
  LabSession _sessionForChange() {
    final session = state.session;
    return (session.active?.runs.isNotEmpty ?? false)
        ? _startConversation(session)
        : session;
  }
}
