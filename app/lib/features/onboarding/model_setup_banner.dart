import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chrome/golem_button.dart';
import '../../core/domain/app_preferences.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/progress_track.dart';
import 'model_download_consent.dart';

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
            _headline(entry.displayName, status),
            style: GolemText.footnoteStrong,
          ),
          const SizedBox(height: 3),
          Text(
            _detail(status, model.simulated),
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
            // the only thing carrying how far along it is.
            Semantics(
              container: true,
              label: 'Download',
              value: '${(progress * 100).round()} percent',
              child: ProgressTrack(
                value: progress,
                trackColor: GolemTheme.divider,
                fillColor: GolemTheme.accent,
              ),
            ),
          ],
          const SizedBox(height: 10),
          switch (status.phase) {
            ArtifactPhase.notDownloaded => GolemButton.filled(
              key: const Key('model-setup-download'),
              label: 'Download · ${formatModelBytes(entry.totalBytes)}',
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
              label: 'Pause',
              onPressed: () =>
                  ref.read(modelControllerProvider.notifier).pause(key),
            ),
            ArtifactPhase.paused || ArtifactPhase.failed => GolemButton.filled(
              key: const Key('model-setup-resume'),
              label: status.phase == ArtifactPhase.failed ? 'Retry' : 'Resume',
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

  String _headline(String name, ArtifactStatus status) =>
      switch (status.phase) {
        ArtifactPhase.notDownloaded => 'Finish setting up $name',
        ArtifactPhase.downloading => 'Downloading $name',
        ArtifactPhase.paused => '$name download paused',
        ArtifactPhase.verifying => 'Verifying $name',
        ArtifactPhase.failed => '$name needs attention',
        ArtifactPhase.installed => '$name is ready',
      };

  String _detail(
    ArtifactStatus status,
    bool simulated,
  ) => switch (status.phase) {
    ArtifactPhase.notDownloaded =>
      'Download the selected model before sending. You can still draft messages and use the rest of Golem.',
    ArtifactPhase.downloading =>
      simulated
          ? 'Deterministic QA simulation; no network or weights.'
          : 'The model must finish and verify before messages can be sent.',
    ArtifactPhase.paused =>
      'Resume when you are ready. Existing progress is kept.',
    ArtifactPhase.verifying =>
      'Checking the downloaded files before they can run.',
    ArtifactPhase.failed =>
      status.failure ?? 'The download failed. Your chats are unaffected.',
    ArtifactPhase.installed => 'Ready.',
  };
}
