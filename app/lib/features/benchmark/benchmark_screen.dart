import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_sheet.dart';
import '../../core/domain/app_state.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/labeled_row.dart';
import '../../core/widgets/section_header.dart';

class BenchmarkScreen extends ConsumerWidget {
  const BenchmarkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final benchmark = ref.watch(benchmarkControllerProvider);
    return CupertinoPageScaffold(
      navigationBar: GolemNavBar(
        title: 'Benchmark',
        previousPageTitle: 'Settings',
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const Key('benchmark-list'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            const _SimulatedNotice(),
            const SizedBox(height: 28),
            const SectionHeader('Protocol'),
            const SizedBox(height: 8),
            GolemCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Prompt',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  CupertinoButton(
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
                              _caseTitle(benchmark.caseId),
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
                  const Text(
                    'Run',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  CupertinoSlidingSegmentedControl<BenchmarkPhase>(
                    key: const Key('benchmark-phase-picker'),
                    groupValue: benchmark.phase,
                    children: const {
                      BenchmarkPhase.warmup: Padding(
                        padding: EdgeInsets.all(9),
                        child: Text('Warmup'),
                      ),
                      BenchmarkPhase.measured: Padding(
                        padding: EdgeInsets.all(9),
                        child: Text('Measured'),
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
                  const LabeledRow(label: 'Context', value: '4,096'),
                  const SizedBox(height: 10),
                  const LabeledRow(label: 'Maximum output', value: '1,024'),
                  const SizedBox(height: 10),
                  LabeledRow(
                    label: 'Seed',
                    value: _seed(benchmark.caseId).toString(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Uses the tracked production prompt fixture. Output and timing are deterministic simulations only.',
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
            const SectionHeader('Simulation status'),
            const SizedBox(height: 8),
            GolemCard(
              child: Column(
                children: [
                  const LabeledRow(label: 'Thermal', value: 'Not measured'),
                  const SizedBox(height: 10),
                  const LabeledRow(label: 'Low Power Mode', value: 'Not read'),
                  const SizedBox(height: 10),
                  const LabeledRow(label: 'Hardware validation', value: 'No'),
                  const SizedBox(height: 16),
                  CupertinoButton(
                    key: Key(
                      benchmark.isRunning
                          ? 'benchmark-stop-button'
                          : 'benchmark-run-button',
                    ),
                    minimumSize: const Size.fromHeight(50),
                    color: benchmark.isRunning ? null : GolemTheme.accent,
                    onPressed: benchmark.isRunning
                        ? () => ref
                              .read(benchmarkControllerProvider.notifier)
                              .stop()
                        : () => ref
                              .read(benchmarkControllerProvider.notifier)
                              .run(),
                    child: benchmark.isRunning
                        ? const Text('Stop Simulated Benchmark')
                        : const Text(
                            'Run Simulated Benchmark',
                            style: TextStyle(color: CupertinoColors.white),
                          ),
                  ),
                  if (benchmark.isRunning) ...[
                    const SizedBox(height: 14),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CupertinoActivityIndicator(),
                        SizedBox(width: 10),
                        Text('Generating deterministic result…'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (benchmark.result != null) ...[
              const SizedBox(height: 28),
              const SectionHeader('Simulated result'),
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
    title: 'Benchmark prompt',
    actions: [
      for (final id in const [
        'short-explanation',
        'medium-review',
        'long-synthesis',
      ])
        GolemSheetAction(
          label: '${id == selected ? '✓  ' : ''}${_caseTitle(id)}',
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
            child: const Text(
              'SIMULATED · NOT HARDWARE VALIDATED',
              style: TextStyle(
                color: GolemTheme.amber,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          LabeledRow(
            label: 'Generated',
            value: '${result.metrics.tokenCount} tokens',
          ),
          const SizedBox(height: 10),
          LabeledRow(
            label: 'Decode',
            value:
                '${result.metrics.decodeTokensPerSecond.toStringAsFixed(1)} tok/s',
          ),
          const SizedBox(height: 10),
          const LabeledRow(label: 'Peak memory', value: 'Not measured'),
          const SizedBox(height: 10),
          const LabeledRow(label: 'Stop', value: 'Simulated end of turn'),
          const SizedBox(height: 16),
          CupertinoButton(
            key: const Key('benchmark-export-button'),
            minimumSize: const Size.fromHeight(50),
            color: GolemTheme.accent,
            onPressed: () async {
              final path = await ref
                  .read(benchmarkControllerProvider.notifier)
                  .export();
              if (path == null || !context.mounted) return;
              final box = context.findRenderObject() as RenderBox?;
              await SharePlus.instance.share(
                ShareParams(
                  title: 'Golem simulated benchmark',
                  text: 'Simulated benchmark JSON — not hardware validated.',
                  files: [XFile(path)],
                  sharePositionOrigin: box == null
                      ? null
                      : box.localToGlobal(Offset.zero) & box.size,
                ),
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.share, color: CupertinoColors.white),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Export Simulated JSON',
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
    child: const Row(
      children: [
        Icon(
          CupertinoIcons.exclamationmark_triangle_fill,
          color: GolemTheme.amber,
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'This screen simulates the workflow. It does not measure this device.',
            style: TextStyle(fontWeight: FontWeight.w600, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

String _caseTitle(String id) => switch (id) {
  'short-explanation' => 'Short explanation',
  'medium-review' => 'Medium review',
  'long-synthesis' => 'Long synthesis',
  _ => id,
};

int _seed(String id) => switch (id) {
  'short-explanation' => 20260721,
  'medium-review' => 20260722,
  'long-synthesis' => 20260723,
  _ => 0,
};
