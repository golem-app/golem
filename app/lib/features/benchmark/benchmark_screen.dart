import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/chrome/golem_chrome.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_sheet.dart';
import '../../core/chrome/golem_tappable.dart';
import '../../core/domain/app_state.dart';
import '../../core/domain/models.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/labeled_row.dart';
import '../../core/widgets/section_header.dart';
import '../../l10n/l10n.dart';
import 'application/benchmark_providers.dart';

class BenchmarkScreen extends ConsumerWidget {
  const BenchmarkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final benchmark = ref.watch(benchmarkControllerProvider);
    return CupertinoPageScaffold(
      navigationBar: GolemNavBar(
        title: context.l10n.benchmark,
        previousPageTitle: context.l10n.settings,
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const Key('benchmark-list'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            const _SimulatedNotice(),
            const SizedBox(height: 28),
            SectionHeader(context.l10n.protocol),
            const SizedBox(height: 8),
            GolemCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.prompt,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  GolemTappable(
                    key: const Key('benchmark-case-picker'),
                    padding: EdgeInsets.zero,
                    onPressed: () => _pickCase(context, ref, benchmark.caseId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      height: 50,
                      decoration: BoxDecoration(
                        color: CupertinoDynamicColor.resolve(
                          GolemTheme.canvas,
                          context,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _caseTitle(context, benchmark.caseId),
                              style: TextStyle(
                                color: CupertinoDynamicColor.resolve(
                                  GolemTheme.ink,
                                  context,
                                ),
                              ),
                            ),
                          ),
                          const Icon(
                            CupertinoIcons.chevron_up_chevron_down,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.run,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  CupertinoSlidingSegmentedControl<BenchmarkPhase>(
                    key: const Key('benchmark-phase-picker'),
                    groupValue: benchmark.phase,
                    // Height from the platform floor, width from the padding
                    // that was always here: this control is built directly
                    // rather than through GolemSegmented — which lives in
                    // another feature — so it carries its own sizing.
                    children: {
                      for (final (phase, label) in <(BenchmarkPhase, String)>[
                        (BenchmarkPhase.warmup, context.l10n.warmup),
                        (BenchmarkPhase.measured, context.l10n.measured),
                      ])
                        phase: SizedBox(
                          height: GolemChrome.current.minimumTapTarget,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            child: Center(child: Text(label)),
                          ),
                        ),
                    },
                    onValueChanged: (value) {
                      if (!benchmark.isRunning && value != null) {
                        ref
                            .read(benchmarkControllerProvider.notifier)
                            .selectPhase(value);
                      }
                    },
                  ),
                  const SizedBox(height: 18),
                  LabeledRow(label: context.l10n.context, value: '4,096'),
                  const SizedBox(height: 10),
                  LabeledRow(label: context.l10n.maximumOutput, value: '1,024'),
                  const SizedBox(height: 10),
                  LabeledRow(
                    label: context.l10n.seed,
                    value: _seed(benchmark.caseId).toString(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.benchmarkProtocolDetail,
                    style: TextStyle(
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.mutedInk,
                        context,
                      ),
                      height: 1.4,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SectionHeader(context.l10n.simulationStatus),
            const SizedBox(height: 8),
            GolemCard(
              child: Column(
                children: [
                  LabeledRow(
                    label: context.l10n.thermal,
                    value: context.l10n.notMeasured,
                  ),
                  const SizedBox(height: 10),
                  LabeledRow(
                    label: context.l10n.lowPowerMode,
                    value: context.l10n.notRead,
                  ),
                  const SizedBox(height: 10),
                  LabeledRow(
                    label: context.l10n.hardwareValidation,
                    value: context.l10n.no,
                  ),
                  const SizedBox(height: 16),
                  GolemTappable(
                    key: Key(
                      benchmark.isRunning
                          ? 'benchmark-stop-button'
                          : 'benchmark-run-button',
                    ),
                    shape: GolemTapShape.wide,
                    minimumHeight: GolemSize.button,
                    color: benchmark.isRunning ? null : GolemTheme.accent,
                    onPressed: benchmark.isRunning
                        ? () => ref
                              .read(benchmarkControllerProvider.notifier)
                              .stop()
                        : () => ref
                              .read(benchmarkControllerProvider.notifier)
                              .run(),
                    child: benchmark.isRunning
                        ? Text(context.l10n.stopSimulatedBenchmark)
                        : Text(
                            context.l10n.runSimulatedBenchmark,
                            style: const TextStyle(
                              color: CupertinoColors.white,
                            ),
                          ),
                  ),
                  if (benchmark.isRunning) ...[
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CupertinoActivityIndicator(),
                        const SizedBox(width: 10),
                        Text(context.l10n.generatingDeterministicResult),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (benchmark.result != null) ...[
              const SizedBox(height: 28),
              SectionHeader(context.l10n.simulatedResult),
              const SizedBox(height: 8),
              _ResultCard(state: benchmark),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickCase(
    BuildContext context,
    WidgetRef ref,
    String selected,
  ) => showGolemActions(
    context: context,
    title: context.l10n.benchmarkPrompt,
    actions: [
      for (final id in const [
        'short-explanation',
        'medium-review',
        'long-synthesis',
      ])
        GolemSheetAction(
          label: '${id == selected ? '✓  ' : ''}${_caseTitle(context, id)}',
          onPressed: () {
            ref.read(benchmarkControllerProvider.notifier).selectCase(id);
            Navigator.pop(context);
          },
        ),
    ],
  );
}

class _ResultCard extends ConsumerWidget {
  const _ResultCard({required this.state});
  final BenchmarkState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = state.result!;
    return GolemCard(
      key: const Key('benchmark-result-card'),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: CupertinoDynamicColor.resolve(
                GolemTheme.reasoningSurface,
                context,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              context.l10n.simulatedNotValidated,
              style: const TextStyle(
                color: GolemTheme.amber,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          LabeledRow(
            label: context.l10n.generated,
            value: context.l10n.tokenCount(result.metrics.tokenCount),
          ),
          const SizedBox(height: 10),
          LabeledRow(
            label: context.l10n.decode,
            value: context.l10n.tokenRate(
              result.metrics.decodeTokensPerSecond.toStringAsFixed(1),
            ),
          ),
          const SizedBox(height: 10),
          LabeledRow(
            label: context.l10n.peakMemory,
            value: context.l10n.notMeasured,
          ),
          const SizedBox(height: 10),
          LabeledRow(
            label: context.l10n.stop,
            value: context.l10n.simulatedEndOfTurn,
          ),
          const SizedBox(height: 16),
          GolemTappable(
            key: const Key('benchmark-export-button'),
            shape: GolemTapShape.wide,
            minimumHeight: GolemSize.button,
            color: GolemTheme.accent,
            onPressed: () async {
              final path = await ref
                  .read(benchmarkControllerProvider.notifier)
                  .export();
              if (path == null || !context.mounted) return;
              final box = context.findRenderObject() as RenderBox?;
              await SharePlus.instance.share(
                ShareParams(
                  title: context.l10n.benchmarkExportTitle,
                  text: context.l10n.benchmarkExportText,
                  files: [XFile(path)],
                  sharePositionOrigin: box == null
                      ? null
                      : box.localToGlobal(Offset.zero) & box.size,
                ),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.share, color: CupertinoColors.white),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    context.l10n.exportSimulatedJson,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: CupertinoColors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Unconditionally "simulated", even in real-engine builds: the only
/// benchmark implementation is the deterministic fake, so sweeping this
/// copy onto the backend signal would make it dishonest
/// (docs/decisions/0003-flavor-backend-defaults.md).
class _SimulatedNotice extends StatelessWidget {
  const _SimulatedNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(
        GolemTheme.reasoningSurface,
        context,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: CupertinoDynamicColor.resolve(
          GolemTheme.reasoningBorder,
          context,
        ),
      ),
    ),
    child: Row(
      children: [
        const Icon(
          CupertinoIcons.exclamationmark_triangle_fill,
          color: GolemTheme.amber,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            context.l10n.benchmarkSimulationNotice,
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

String _caseTitle(BuildContext context, String id) => switch (id) {
  'short-explanation' => context.l10n.shortExplanation,
  'medium-review' => context.l10n.mediumReview,
  'long-synthesis' => context.l10n.longSynthesis,
  _ => id,
};

int _seed(String id) => switch (id) {
  'short-explanation' => 20260721,
  'medium-review' => 20260722,
  'long-synthesis' => 20260723,
  _ => 0,
};
