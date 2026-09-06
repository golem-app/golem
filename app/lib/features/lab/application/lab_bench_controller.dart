import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../broker/effective_sampling.dart';
import '../../../broker/model_profile.dart';
import '../../../broker/model_runtime_config.dart';
import '../../../broker/runtime.dart' show engineBuildLabel;
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
  });

  final LabConfiguration? armed;
  final LabRunSettings settings;
  final LabSession session;

  /// The run in flight, or the last one: `send` appends a run last and every
  /// publish re-appends it, so the active conversation's tail is the run.
  LabRun? get activeRun => session.active?.last;

  /// A run in flight locks the Rig: changing what a run measures under
  /// mid-run would silently invalidate the comparison, so it is impossible
  /// rather than merely warned against (#58).
  bool get locked => !(activeRun?.isTerminal ?? true);

  LabBenchState copyWith({
    LabConfiguration? armed,
    LabRunSettings? settings,
    LabSession? session,
  }) => LabBenchState(
    armed: armed ?? this.armed,
    settings: settings ?? this.settings,
    session: session ?? this.session,
  );
}

/// How often the bench publishes a run in flight. Events fold into a pending
/// run as they arrive; the state — and so the transcript and the chart —
/// rebuilds on this cadence, never per token (#58). Phase changes and the
/// terminal event publish at once.
const labPublishInterval = Duration(milliseconds: 60);

/// How often the process footprint is sampled while a run is in flight.
const labFootprintInterval = Duration(milliseconds: 500);

/// How long Stop waits for the engine to end the stream before the bench
/// ends the run itself. The stream's own end is the honest terminator; an
/// engine that never sends it must not hold the whole bench locked.
const labStopDeadline = Duration(seconds: 10);

/// KeepAlive: a command controller whose run, epoch and timers must outlive
/// any one widget (handbook v5.0 §3.4).
@Riverpod(keepAlive: true, retry: noRetry)
class LabBenchController extends _$LabBenchController {
  /// Advances on every run start *and* end, so a late event, a late footprint
  /// sample or a stale watchdog for a finished run is dropped by the guard
  /// rather than by the order stream teardown happens to take.
  int _epoch = 0;
  int _runSerial = 0;
  int _conversationSerial = 0;
  LabRun? _pending;
  Timer? _publish;
  Timer? _footprint;
  Timer? _stopWatchdog;
  StreamSubscription<InferenceEvent>? _subscription;

  /// The repository the run in flight streams from, held so disposal can
  /// cancel the engine without touching `ref` inside a lifecycle.
  InferenceRepository? _inFlight;

  @override
  LabBenchState build() {
    // The lab has no chat: model commands asking whether a generation is in
    // flight read the bench instead (ADR 0021). Read, not watched — the
    // bridge is bound once per container, and a rebuild here would reset
    // the session under a run whose subscription lives in this instance.
    final bridge = ref.read(chatSessionBridgeProvider);
    bridge.bindFacts(
      () => (activeModelKey: state.armed?.key, generationActive: state.locked),
    );
    ref.onDispose(() {
      _epoch++;
      _publish?.cancel();
      _footprint?.cancel();
      _stopWatchdog?.cancel();
      unawaited(_subscription?.cancel());
      // Native decode outlives the subscription otherwise (#127).
      unawaited(_inFlight?.cancel());
      bridge.bindFacts(() => null);
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
    // Settings are the bench's, not the model's: ones the new profile cannot
    // take (a context above its ceiling) reset to its defaults rather than
    // leaving Run silently refused.
    final settings = state.settings;
    final defaults = _profileFor(
      configuration,
    ).sampling(reasoningEnabled: settings.reasoningEnabled);
    final valid = settings
        .validate(
          defaults: defaults,
          contextCeiling: configuration.entry.contextLength,
        )
        .isEmpty;
    state = state.copyWith(
      armed: configuration,
      settings: valid
          ? settings
          : LabRunSettings(
              reasoningEnabled: settings.reasoningEnabled,
              seed: settings.seed,
            ),
      session: _sessionForChange(),
    );
    return true;
  }

  /// Applies settings that validate against the armed profile; returns the
  /// problems otherwise and applies nothing. A change under a conversation
  /// with runs starts a new one. Refused while a run is in flight.
  List<LabSettingsProblem> updateSettings(LabRunSettings settings) {
    if (state.locked) return const [LabSettingsProblem.benchLocked];
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
  /// before offering the action, so this is the second line. Synchronous up
  /// to the subscription: the bench is locked before anything can change
  /// what the run measures under.
  bool send(String prompt) {
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
    // What the engine receives: an empty seed inherits the launch seed at
    // the broker, so the snapshot resolves it the same way.
    final seed = settings.seed ?? launchSamplingSeed;
    final (sampling, _) = effectiveSampling(
      profile: profile,
      defaults: defaults,
      overrides: settings.toOverrides(),
      seed: seed,
    );
    // The artifact's verified state, from the model store as it stands; a
    // store that has not read yet leaves the provenance unverified rather
    // than holding the bench open, unlocked, until it has.
    final artifact = ref
        .read(modelControllerProvider)
        .value
        ?.statusOf(armed.key);
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
    );
    final epoch = ++_epoch;
    _startFootprintSampling(epoch);
    final repository = ref.read(inferenceRepositoryProvider);
    _inFlight = repository;
    unawaited(_subscription?.cancel());
    _subscription = repository
        .generate(
          context: context,
          reasoningEnabled: settings.reasoningEnabled,
          overrides: settings.toOverrides(),
          modelKey: armed.key,
          observe: GenerationObservation.everything,
          seed: seed,
        )
        .listen(
          (event) => _fold(epoch, event),
          onError: (Object error) {
            final pending = _pending;
            if (epoch != _epoch || pending == null) return;
            _terminate(
              epoch,
              failRun(
                pending,
                error is InferenceException
                    ? error.kind
                    : InferenceFailureKind.engine,
                contextTokens: error is InferenceException
                    ? error.contextTokens
                    : null,
              ),
            );
          },
          onDone: () {
            final pending = _pending;
            if (epoch != _epoch || pending == null) return;
            // A stream that ended without its completion event: the engine
            // was torn down under it. That run did not finish — it reads as
            // cancelled, keeps its partial output, feeds nothing to the next
            // turn and can be retried — never as a completed measurement.
            _terminate(
              epoch,
              pending.isTerminal
                  ? pending
                  : reduceLabRun(
                      requestCancel(pending),
                      const CompletedEvent(
                        stopReason: InferenceStopReason.cancelled,
                      ),
                    ),
            );
          },
          cancelOnError: true,
        );
    return true;
  }

  /// Stop: the run reads as cancelling until the engine ends the stream,
  /// keeping whatever it produced. The cancel itself is fire-and-forget, like
  /// chat's — the stream's own end is what terminates the run. Once per run:
  /// a held Escape repeats, and each repeat would re-arm the deadline.
  void stop() {
    final pending = _pending;
    if (pending == null || !state.locked || pending.cancelRequested) return;
    _pending = requestCancel(pending);
    _publishNow();
    unawaited(ref.read(inferenceRepositoryProvider).cancel());
    // The engine's end of stream is what terminates the run; an engine that
    // never sends it must not hold the bench locked for the process's life.
    final epoch = _epoch;
    _stopWatchdog?.cancel();
    _stopWatchdog = Timer(labStopDeadline, () {
      final stuck = _pending;
      if (epoch != _epoch || stuck == null || stuck.isTerminal) return;
      _terminate(
        epoch,
        reduceLabRun(
          stuck,
          const CompletedEvent(stopReason: InferenceStopReason.cancelled),
        ),
      );
    });
  }

  /// Sends the last cancelled or failed prompt again under the current
  /// configuration, as a new run beside the old one.
  bool retry() {
    final last = state.session.active?.last;
    if (last == null ||
        !last.isTerminal ||
        last.phase == LabRunPhase.completed) {
      return false;
    }
    return send(last.prompt);
  }

  void _fold(int epoch, InferenceEvent event) {
    final before = _pending;
    if (epoch != _epoch || before == null) return;
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
    // Whatever the stream still delivers belongs to a run that has ended.
    _epoch++;
    _pending = run;
    _footprint?.cancel();
    _footprint = null;
    _stopWatchdog?.cancel();
    _stopWatchdog = null;
    _publishNow();
    _pending = null;
    _inFlight = null;
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
