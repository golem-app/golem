import 'package:flutter/cupertino.dart';

import '../../../core/domain/models.dart';
import '../../../core/repositories/contracts.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../core/widgets/progress_track.dart';
import '../../../l10n/bidi.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/presentation_messages.dart';
import '../../chat/widgets/markdown/golem_markdown.dart';
import '../../chat/widgets/reasoning_card.dart';
import '../domain/lab_run.dart';
import '../domain/latency_series.dart';
import '../lab_copy.dart';
import '../lab_theme.dart';
import 'lab_controls.dart';
import 'latency_sparkline.dart';

/// One turn on the bench: the prompt, then the run — its phases as they
/// happened, the reasoning and answer, and the numbers, each phase kept
/// separate and never averaged into one (#58).
class RunCard extends StatelessWidget {
  const RunCard({
    required this.run,
    required this.now,
    this.onRetry,
    super.key,
  });

  final LabRun run;

  /// The clock the elapsed figures read against; passed in so a golden is
  /// still.
  final DateTime now;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: Key('lab-run-${run.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: LabSize.transcriptMaxWidth * 0.76,
            ),
            child: Semantics(
              label: l10n.userSpeaker,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: LabSpace.s6,
                  vertical: LabSpace.s3,
                ),
                decoration: BoxDecoration(
                  color: GolemTheme.userBubble,
                  borderRadius: BorderRadius.circular(LabRadius.card),
                ),
                child: Text(
                  run.prompt,
                  textDirection: contentTextDirection(
                    run.prompt,
                    fallback: Directionality.of(context),
                  ),
                  style: LabText.body.copyWith(color: GolemTheme.textOnDark),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: LabSpace.s6),
        Semantics(
          container: true,
          label: l10n.assistantSpeaker,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              LabSpace.s7,
              LabSpace.s5,
              LabSpace.s7,
              LabSpace.s6,
            ),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(LabRadius.card),
              border: Border.all(color: context.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PhaseRow(run: run, now: now),
                if (run.phase == LabRunPhase.loading) ...[
                  const SizedBox(height: LabSpace.s5),
                  _LoadProgress(run: run, now: now),
                ],
                if (run.reasoning.isNotEmpty) ...[
                  const SizedBox(height: LabSpace.s5),
                  ReasoningCard(
                    text: run.reasoning,
                    streaming: !run.isTerminal && run.answer.isEmpty,
                    live: !run.isTerminal,
                    initiallyExpanded: run.isTerminal,
                  ),
                ],
                if (run.answer.isNotEmpty) ...[
                  const SizedBox(height: LabSpace.s5),
                  DefaultTextStyle.merge(
                    style: LabText.body.copyWith(color: context.ink),
                    child: GolemMarkdown(text: run.answer),
                  ),
                ],
                if (run.phase == LabRunPhase.completed) ...[
                  const SizedBox(height: LabSpace.s5),
                  _ResultRow(run: run),
                ],
                if (run.phase == LabRunPhase.cancelled) ...[
                  const SizedBox(height: LabSpace.s5),
                  _CancelledRow(run: run, onRetry: onRetry),
                ],
                if (run.phase == LabRunPhase.failed) ...[
                  const SizedBox(height: LabSpace.s5),
                  _FailedRow(run: run, onRetry: onRetry),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The three phases as chips, each with the counts its engine actually
/// reported: a submitted-token count for a prompt in flight and a measured
/// rate only once the metrics say so; token or chunk counts by their name.
class _PhaseRow extends StatelessWidget {
  const _PhaseRow({required this.run, required this.now});

  final LabRun run;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final telemetry = run.telemetry;
    final metrics = run.metrics;
    final live = !run.isTerminal;
    final chips = <Widget>[];

    if (telemetry.loadDuration != null) {
      chips.add(
        _phaseChip(
          context,
          key: 'lab-phase-load',
          text: l10n.labPhaseLoad(
            LabFormat.seconds(
              telemetry.loadDuration!.inMilliseconds / 1000,
              locale,
            ),
          ),
        ),
      );
    } else if (run.phase == LabRunPhase.loading) {
      final fraction = telemetry.loadFraction;
      chips.add(
        _phaseChip(
          context,
          key: 'lab-phase-load',
          active: true,
          text: fraction == null
              ? l10n.labPhaseLoading
              : l10n.labPhaseLoadingPercent((fraction * 100).round()),
        ),
      );
    }

    // Read (prompt processing).
    if (metrics?.promptTokenCount case final total?) {
      chips.add(
        _phaseChip(
          context,
          key: 'lab-phase-read',
          text: metrics!.promptTokensPerSecond > 0
              ? l10n.labPhaseReadDone(
                  LabFormat.count(total, locale),
                  LabFormat.rate(metrics.promptTokensPerSecond, locale),
                )
              : l10n.labPhaseReadCount(LabFormat.count(total, locale)),
        ),
      );
    } else if (run.phase.reaches(LabRunPhase.promptProcessing) &&
        !run.isTerminal) {
      final completed = telemetry.promptCompleted;
      final total = telemetry.promptTotal;
      chips.add(
        _phaseChip(
          context,
          key: 'lab-phase-read',
          active: run.phase == LabRunPhase.promptProcessing,
          text: completed == null || total == null
              ? l10n.labPhaseReading
              : l10n.labPhaseReadSubmitted(
                  LabFormat.count(completed, locale),
                  LabFormat.count(total, locale),
                ),
        ),
      );
    }

    if (metrics != null) {
      chips.add(
        _phaseChip(
          context,
          key: 'lab-phase-generate',
          text: l10n.labPhaseGenerated(
            LabFormat.count(metrics.tokenCount, locale),
            LabFormat.rate(metrics.decodeTokensPerSecond, locale),
          ),
        ),
      );
    } else if (run.phase.reaches(LabRunPhase.generating) && live) {
      final count = telemetry.observationCount;
      // Tokens only — a chunk gap counts nothing — over the trailing window
      // of the instants' own clock, which starts at the engine's acceptance
      // rather than at the run (the load sits between), so the figure sinks
      // when arrivals stop.
      final accepted = run.acceptedAt;
      final liveRate =
          telemetry.observationKind == ObservationKind.token && accepted != null
          ? liveDecodeRate(
              telemetry.instantsMs,
              now.difference(accepted).inMilliseconds.toDouble(),
            )
          : null;
      final text = switch (telemetry.observationKind) {
        ObservationKind.chunk => l10n.labPhaseGeneratingChunks(
          LabFormat.count(count, locale),
        ),
        _ when liveRate != null => l10n.labPhaseGeneratingRate(
          LabFormat.count(count, locale),
          LabFormat.rate(liveRate, locale),
        ),
        _ => l10n.labPhaseGenerating(LabFormat.count(count, locale)),
      };
      chips.add(
        _phaseChip(
          context,
          key: 'lab-phase-generate',
          active: true,
          text: text,
        ),
      );
    }

    if (telemetry.firstInstantMs case final first? when metrics == null) {
      chips.add(
        Text(
          l10n.labTtft(LabFormat.ttft(first / 1000, locale)),
          style: LabText.detail.copyWith(color: context.mutedInk),
        ),
      );
    }

    final series = telemetry.series;
    return Wrap(
      spacing: LabSpace.s3,
      runSpacing: LabSpace.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${run.configuration.displayName} · '
          '${engineLabel(run.configuration.engine)}',
          style: LabText.label.copyWith(color: context.ink),
        ),
        ...chips,
        if (series.gapsMs.isNotEmpty) _LatencyRow(run: run, series: series),
      ],
    );
  }

  Widget _phaseChip(
    BuildContext context, {
    required String key,
    required String text,
    bool active = false,
  }) => LabChip(
    key: Key(key),
    text: text,
    dotColor: active ? context.accent : context.mutedInk,
    fill: active ? context.accentSoft : null,
    textColor: active ? context.accentIcon : context.mutedInk,
  );
}

class _LatencyRow extends StatelessWidget {
  const _LatencyRow({required this.run, required this.series});

  final LabRun run;
  final LatencySeries series;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context);
    final tag = locale.toString();
    final isChunk = run.telemetry.observationKind == ObservationKind.chunk;
    final label = isChunk ? l10n.labInterChunk : l10n.labInterToken;
    return Wrap(
      spacing: LabSpace.s3,
      runSpacing: LabSpace.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          localizedUppercase(label, locale),
          style: localizedLabelStyle(
            LabText.overline,
            locale,
          ).copyWith(color: context.mutedInk),
        ),
        LatencySparkline(
          series: series,
          semanticLabel: l10n.labLatencyChart(
            label,
            LabFormat.milliseconds(series.medianMs ?? 0, tag),
            series.stallCount,
          ),
        ),
        Text(
          l10n.labMedian(LabFormat.milliseconds(series.medianMs ?? 0, tag)),
          style: LabText.detail.copyWith(color: context.mutedInk),
        ),
        if (series.stallCount > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: labResolve(GolemTheme.cautionIcon, context),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: LabSpace.s1),
              Text(
                l10n.labStalls(series.stallCount),
                style: LabText.detailStrong.copyWith(color: context.ink),
              ),
            ],
          ),
      ],
    );
  }
}

/// Loading: a determinate bar only from the engine's own fraction, an
/// indeterminate one otherwise, and the elapsed clock either way.
class _LoadProgress extends StatelessWidget {
  const _LoadProgress({required this.run, required this.now});

  final LabRun run;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final fraction = run.telemetry.loadFraction;
    final elapsed = now.difference(run.configuration.startedAt);
    final footprint = run.telemetry.footprintBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.labLoadingModel(ltrIsolate(run.configuration.displayName)),
                style: LabText.bodyStrong.copyWith(color: context.ink),
              ),
            ),
            Text(
              l10n.labElapsed(LabFormat.elapsed(elapsed, l10n, locale)),
              style: LabText.detailStrong.copyWith(color: context.mutedInk),
            ),
          ],
        ),
        const SizedBox(height: LabSpace.s4),
        if (fraction != null)
          Semantics(
            label: l10n.labLoadingModel(
              ltrIsolate(run.configuration.displayName),
            ),
            value: l10n.percentValue((fraction * 100).round()),
            child: ProgressTrack(
              value: fraction,
              height: 4,
              trackColor: context.field,
              fillColor: context.accent,
            ),
          )
        else
          Row(
            children: [
              if (reducedMotionOf(context))
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: context.accent,
                    shape: BoxShape.circle,
                  ),
                )
              else
                const CupertinoActivityIndicator(radius: 7),
              const SizedBox(width: LabSpace.s3),
              Expanded(
                child: Text(
                  l10n.labLoadIndeterminate,
                  style: LabText.detail.copyWith(color: context.mutedInk),
                ),
              ),
            ],
          ),
        const SizedBox(height: LabSpace.s3),
        Wrap(
          spacing: LabSpace.s8,
          runSpacing: LabSpace.s1,
          children: [
            Text(
              l10n.labArtifactMeta(
                ltrIsolate(
                  LabFormat.bytes(run.configuration.artifact.totalBytes),
                ),
                run.configuration.artifact.fileCount,
              ),
              style: LabText.detail.copyWith(color: context.mutedInk),
            ),
            if (footprint != null)
              Text(
                l10n.labResident(ltrIsolate(LabFormat.bytes(footprint))),
                style: LabText.detail.copyWith(color: context.mutedInk),
              ),
          ],
        ),
        const SizedBox(height: LabSpace.s4),
        Text(
          l10n.labLoadNote,
          style: LabText.detail.copyWith(color: context.mutedInk),
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.run});

  final LabRun run;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final metrics = run.metrics;
    final parts = <String>[];
    if (run.telemetry.loadDuration case final load?) {
      parts.add(
        l10n.labLoadSeconds(
          LabFormat.seconds(load.inMilliseconds / 1000, locale),
        ),
      );
    }
    if (metrics?.timeToFirstTokenSeconds case final ttft?) {
      parts.add(l10n.labTtft(LabFormat.ttft(ttft, locale)));
    }
    if (metrics?.peakPhysicalFootprintBytes case final peak?) {
      parts.add(l10n.labPeak(ltrIsolate(LabFormat.bytes(peak))));
    }
    return Wrap(
      spacing: LabSpace.s3,
      runSpacing: LabSpace.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (metrics != null)
          LabChip(
            key: const Key('lab-result-chip'),
            text: l10n.tokenRateSummary(
              LabFormat.rate(metrics.decodeTokensPerSecond, locale),
              metrics.tokenCount,
            ),
            fill: context.accentSoft,
            textColor: context.accentIcon,
          ),
        if (parts.isNotEmpty)
          Text(
            parts.join(' · '),
            style: LabText.detail.copyWith(color: context.mutedInk),
          ),
      ],
    );
  }
}

class _CancelledRow extends StatelessWidget {
  const _CancelledRow({required this.run, required this.onRetry});

  final LabRun run;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Tokens when the engine counted tokens; an engine that stamps chunks
    // has a chunk count until its metrics land, and says so.
    final tokens = run.outputTokens;
    return Wrap(
      spacing: LabSpace.s3,
      runSpacing: LabSpace.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        LabChip(
          key: const Key('lab-cancelled-chip'),
          icon: CupertinoIcons.xmark_circle,
          text: tokens != null
              ? l10n.stoppedAfterTokens(tokens)
              : l10n.labPhaseGeneratingChunks(
                  LabFormat.count(
                    run.telemetry.observationCount,
                    Localizations.localeOf(context).toString(),
                  ),
                ),
        ),
        Text(
          l10n.labCancelledNote,
          style: LabText.detail.copyWith(color: context.mutedInk),
        ),
        if (onRetry != null)
          LabButton(
            key: const Key('lab-retry'),
            label: l10n.retry,
            onPressed: onRetry,
            height: LabSize.chip,
          ),
      ],
    );
  }
}

class _FailedRow extends StatelessWidget {
  const _FailedRow({required this.run, required this.onRetry});

  final LabRun run;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      key: const Key('lab-failed-notice'),
      padding: const EdgeInsets.all(LabSpace.s5),
      decoration: BoxDecoration(
        color: labResolve(GolemTheme.errorSurface, context),
        borderRadius: BorderRadius.circular(LabRadius.field),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(
            child: Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              color: GolemTheme.destructive,
              size: 15,
            ),
          ),
          const SizedBox(width: LabSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    inferenceFailureMessage(
                      l10n,
                      run.failure ?? InferenceFailureKind.engine,
                      contextTokens: run.failureContextTokens,
                    ),
                    style: LabText.bodyStrong.copyWith(color: context.ink),
                  ),
                ),
                if (run.hasOutput) ...[
                  const SizedBox(height: LabSpace.s1),
                  Text(
                    l10n.labFailedPartial,
                    style: LabText.detail.copyWith(color: context.mutedInk),
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: LabSpace.s3),
                  LabButton(
                    key: const Key('lab-retry'),
                    label: l10n.retry,
                    onPressed: onRetry,
                    height: LabSize.chip,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
