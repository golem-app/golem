import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/chrome/golem_button.dart';
import '../../../core/domain/app_preferences.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../core/widgets/labeled_progress.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/presentation_messages.dart';
import '../../preferences/application/preferences_providers.dart';
import '../application/model_providers.dart';
import '../model_download_consent.dart';
import 'download_note_banner.dart';

/// The recoverable path promised when first-run consent is declined. It reads
/// the same model controller as Settings, so pause, verification, failure, and
/// completion can never drift into a second onboarding-only state machine.
class ModelSetupBanner extends ConsumerWidget {
  const ModelSetupBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesControllerProvider).value;
    final key = preferences?.onboardingModelKey;
    if (preferences == null ||
        preferences.onboardingVersion < currentOnboardingVersion ||
        key == null ||
        ref.watch(deviceRefusalProvider) != null) {
      return const SizedBox.shrink();
    }
    final entry = ref
        .watch(modelCatalogEntriesProvider)
        .where((item) => item.key == key)
        .firstOrNull;
    final model = ref.watch(modelControllerProvider).value;
    if (entry == null || model == null) return const SizedBox.shrink();
    final status = model.statusOf(key);
    if (status.phase == ArtifactPhase.installed) {
      return const SizedBox.shrink();
    }
    final progress = entry.totalBytes == 0
        ? 0.0
        : (status.downloadedBytes / entry.totalBytes).clamp(0.0, 1.0);
    return Container(
      key: const Key('model-setup-banner'),
      margin: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(GolemTheme.surface, context),
        borderRadius: BorderRadius.circular(GolemRadius.notice),
        border: Border.all(
          color: CupertinoDynamicColor.resolve(GolemTheme.divider, context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _headline(context, entry.displayName, status),
            style: GolemText.footnoteStrong,
          ),
          const SizedBox(height: 3),
          Text(
            _detail(context, status, model.simulated),
            style: GolemText.caption.copyWith(
              color: CupertinoDynamicColor.resolve(
                GolemTheme.mutedInk,
                context,
              ),
            ),
          ),
          if (status.phase == ArtifactPhase.downloading ||
              status.phase == ArtifactPhase.paused) ...[
            const SizedBox(height: 10),
            // The headline and detail above say what is happening; the bar is
            // the only thing carrying how far along it is, so it paints no
            // caption of its own.
            LabeledProgress(
              semanticsLabel: context.l10n.download,
              fraction: progress,
              percent: (progress * 100).round(),
              showPercent: false,
            ),
          ],
          DownloadNoteBanner(
            key: const Key('chat-download-note'),
            entry: entry,
            compact: true,
            margin: const EdgeInsetsDirectional.only(top: 10),
          ),
          const SizedBox(height: 10),
          switch (status.phase) {
            ArtifactPhase.notDownloaded => GolemButton.filled(
              key: const Key('model-setup-download'),
              label: context.l10n.downloadSize(
                formatModelBytes(entry.totalBytes),
              ),
              onPressed: () async {
                final approved = await confirmModelDownload(
                  context: context,
                  entry: entry,
                  simulated: model.simulated,
                );
                if (approved && context.mounted) {
                  unawaited(
                    ref.read(modelControllerProvider.notifier).download(key),
                  );
                }
              },
            ),
            ArtifactPhase.downloading => GolemButton.tinted(
              key: const Key('model-setup-pause'),
              label: context.l10n.pause,
              onPressed: () =>
                  ref.read(modelControllerProvider.notifier).pause(key),
            ),
            ArtifactPhase.paused || ArtifactPhase.failed => GolemButton.filled(
              key: const Key('model-setup-resume'),
              label: status.phase == ArtifactPhase.failed
                  ? context.l10n.retry
                  : context.l10n.resume,
              onPressed: () => unawaited(
                ref.read(modelControllerProvider.notifier).download(key),
              ),
            ),
            ArtifactPhase.verifying => const Center(
              child: CupertinoActivityIndicator(),
            ),
            ArtifactPhase.installed => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }

  String _headline(BuildContext context, String name, ArtifactStatus status) =>
      switch (status.phase) {
        ArtifactPhase.notDownloaded => context.l10n.finishModelSetup(name),
        ArtifactPhase.downloading => context.l10n.modelDownloading(name),
        ArtifactPhase.paused => context.l10n.modelDownloadPaused(name),
        ArtifactPhase.verifying => context.l10n.modelVerifying(name),
        ArtifactPhase.failed => context.l10n.modelNeedsAttention(name),
        ArtifactPhase.installed => context.l10n.modelReady(name),
      };

  String _detail(BuildContext context, ArtifactStatus status, bool simulated) =>
      switch (status.phase) {
        ArtifactPhase.notDownloaded => context.l10n.setupDownloadPrompt,
        ArtifactPhase.downloading =>
          simulated
              ? context.l10n.qaDownloadShort
              : context.l10n.downloadBeforeSending,
        ArtifactPhase.paused => context.l10n.resumeProgressKept,
        ArtifactPhase.verifying => context.l10n.checkingDownloadedFiles,
        ArtifactPhase.failed => artifactFailureMessage(context.l10n, status),
        ArtifactPhase.installed => context.l10n.ready,
      };
}
