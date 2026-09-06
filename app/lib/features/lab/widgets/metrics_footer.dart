import 'package:flutter/cupertino.dart';

import '../../../l10n/bidi.dart';
import '../../../l10n/l10n.dart';
import '../domain/lab_run.dart';
import '../lab_copy.dart';
import '../lab_theme.dart';

/// The persistent metrics band: one figure per phase, a dash where none has
/// been measured, and a note saying which run they belong to.
class MetricsFooter extends StatelessWidget {
  const MetricsFooter({required this.run, super.key});

  final LabRun? run;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context);
    final localeTag = locale.toString();
    final run = this.run;
    final metrics = run?.metrics;
    final telemetry = run?.telemetry;
    const dash = '—';
    final entries = <(String, String?)>[
      (
        l10n.labFooterLoad,
        telemetry?.loadDuration == null
            ? null
            : LabFormat.seconds(
                telemetry!.loadDuration!.inMilliseconds / 1000,
                localeTag,
              ),
      ),
      (
        l10n.labFooterRead,
        metrics?.promptTokenCount == null
            ? null
            : l10n.labPhaseReadDone(
                LabFormat.count(metrics!.promptTokenCount!, localeTag),
                LabFormat.rate(metrics.promptTokensPerSecond, localeTag),
              ),
      ),
      (
        l10n.labFooterTtft,
        metrics?.timeToFirstTokenSeconds == null
            ? null
            : LabFormat.ttft(metrics!.timeToFirstTokenSeconds!, localeTag),
      ),
      (
        l10n.labFooterDecode,
        metrics == null
            ? null
            : l10n.tokenRate(
                LabFormat.rate(metrics.decodeTokensPerSecond, localeTag),
              ),
      ),
      (
        l10n.labFooterPeak,
        metrics?.peakPhysicalFootprintBytes == null
            ? null
            : LabFormat.bytes(metrics!.peakPhysicalFootprintBytes!),
      ),
    ];
    final note = switch (run?.phase) {
      null => l10n.labFooterNoRun,
      LabRunPhase.completed => l10n.labFooterRun(ltrIsolate(run!.id)),
      LabRunPhase.cancelled => l10n.labFooterCancelled(ltrIsolate(run!.id)),
      LabRunPhase.failed => l10n.labFooterFailed(ltrIsolate(run!.id)),
      _ => l10n.labFooterLive,
    };
    return Container(
      key: const Key('lab-footer'),
      constraints: const BoxConstraints(minHeight: LabSize.footer),
      padding: const EdgeInsets.symmetric(
        horizontal: LabSpace.gutter,
        vertical: LabSpace.s3,
      ),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(top: BorderSide(color: context.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: LabSpace.s7,
              runSpacing: LabSpace.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (label, value) in entries)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        localizedUppercase(label, locale),
                        style: localizedLabelStyle(
                          LabText.overline,
                          locale,
                        ).copyWith(color: context.mutedInk),
                      ),
                      const SizedBox(width: LabSpace.s2),
                      Flexible(
                        child: Text(
                          value ?? dash,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LabText.detailStrong.copyWith(
                            color: value == null
                                ? context.mutedInk
                                : context.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: LabSpace.s7),
          Flexible(
            child: Text(
              note,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LabText.detail.copyWith(color: context.mutedInk),
            ),
          ),
        ],
      ),
    );
  }
}
