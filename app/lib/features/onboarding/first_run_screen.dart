import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_identity.dart';
import '../../core/chrome/golem_badge.dart';
import '../../core/chrome/golem_button.dart';
import '../../core/chrome/golem_chrome.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/domain/model_catalog.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/progress_track.dart';
import '../../l10n/l10n.dart';
import '../../l10n/presentation_messages.dart';
import '../legal/ai_disclaimer.dart';
import 'application/onboarding_controller.dart';
import 'model_download_consent.dart';
import '../../core/domain/model_admission.dart';

class FirstRunScreen extends ConsumerWidget {
  const FirstRunScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(firstRunControllerProvider);
    final catalog = ref.watch(modelCatalogEntriesProvider);
    final backend = ref.watch(inferenceBackendProvider);
    final eligibility = ref.watch(deviceEligibilityProvider);
    final storedKey = ref
        .watch(preferencesControllerProvider)
        .value
        ?.onboardingModelKey;
    final selectedKey =
        storedKey ??
        recommendedAdmittedModelKey(
          catalog: catalog,
          backend: backend,
          eligibility: eligibility,
        );
    final selectedOption = modelAdmissionOptions(
      catalog: catalog,
      backend: backend,
      eligibility: eligibility,
    ).where((option) => option.entry.key == selectedKey).firstOrNull;
    final selected = selectedOption?.entry;
    return switch (state.step) {
      FirstRunStep.welcome => _WelcomeScreen(failure: state.failure),
      FirstRunStep.model => _ModelScreen(
        entry: selected,
        recommended: selectedOption?.recommended ?? false,
        failure: state.failure,
      ),
      FirstRunStep.catalog => _CatalogScreen(
        selectedKey: selectedKey,
        failure: state.failure,
      ),
      FirstRunStep.download => _DownloadScreen(
        entry: selected,
        failure: state.failure,
      ),
      FirstRunStep.unsupported => _UnsupportedScreen(failure: state.failure),
      FirstRunStep.complete => const CupertinoPageScaffold(
        child: SizedBox.shrink(),
      ),
    };
  }
}

class _WelcomeScreen extends ConsumerWidget {
  const _WelcomeScreen({this.failure});

  final FirstRunFailure? failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _FirstRunScaffold(
    key: const Key('first-run-welcome'),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        Center(
          child: Image.asset(
            AppIdentity.current.iconAsset,
            width: 74,
            height: 74,
          ),
        ),
        const SizedBox(height: GolemSpace.s6),
        Text(context.l10n.firstRunTagline, style: GolemText.display),
        const SizedBox(height: GolemSpace.s3),
        Text(
          context.l10n.firstRunIntroduction,
          style: GolemText.body.copyWith(
            color: CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context),
          ),
        ),
        const SizedBox(height: GolemSpace.s4),
        const AiDisclaimer(key: Key('first-run-ai-disclaimer')),
        const SizedBox(height: GolemSpace.s8),
        _Promise(
          icon: CupertinoIcons.lock,
          title: context.l10n.promisePrivateTitle,
          detail: context.l10n.promisePrivateDetail,
        ),
        _Promise(
          icon: CupertinoIcons.wifi,
          title: context.l10n.promiseOfflineTitle,
          detail: context.l10n.promiseOfflineDetail,
        ),
        _Promise(
          icon: CupertinoIcons.slider_horizontal_3,
          title: context.l10n.promiseControlTitle,
          detail: context.l10n.promiseControlDetail,
        ),
        const Spacer(),
        if (failure != null) _FailureText(failure!),
      ],
    ),
    action: GolemButton.filled(
      key: const Key('first-run-get-started'),
      label: context.l10n.getStarted,
      onPressed: () =>
          ref.read(firstRunControllerProvider.notifier).continueFromWelcome(),
    ),
  );
}

class _Promise extends StatelessWidget {
  const _Promise({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: GolemSpace.s4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: GolemTheme.accentIcon),
        const SizedBox(width: GolemSpace.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GolemText.footnoteStrong),
              Text(
                detail,
                style: GolemText.caption.copyWith(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ModelScreen extends ConsumerWidget {
  const _ModelScreen({
    required this.entry,
    required this.recommended,
    this.failure,
  });

  final ModelCatalogEntry? entry;
  final bool recommended;
  final FirstRunFailure? failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = entry;
    return _FirstRunScaffold(
      key: const Key('first-run-model'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: GolemSpace.s8),
          Text(context.l10n.oneModelHeadline, style: GolemText.display),
          const SizedBox(height: GolemSpace.s3),
          Text(
            selected == null
                ? context.l10n.noCompatibleModel
                : context.l10n.modelOfflineIntroduction(selected.displayName),
            style: GolemText.body.copyWith(
              color: CupertinoDynamicColor.resolve(
                GolemTheme.mutedInk,
                context,
              ),
            ),
          ),
          const SizedBox(height: GolemSpace.s10),
          if (selected != null)
            _FeaturedModelCard(entry: selected, recommended: recommended),
          if (failure != null) ...[
            const SizedBox(height: GolemSpace.s4),
            _FailureText(failure!),
          ],
        ],
      ),
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GolemButton.filled(
            key: const Key('first-run-download'),
            label: selected == null
                ? context.l10n.downloadUnavailable
                : context.l10n.downloadSize(
                    formatModelBytes(selected.totalBytes),
                  ),
            onPressed: selected == null
                ? null
                : () => _requestDownload(context, ref, selected),
          ),
          CupertinoButton(
            key: const Key('first-run-choose-model'),
            minimumSize: Size.fromHeight(GolemChrome.current.minimumTapTarget),
            onPressed: () =>
                ref.read(firstRunControllerProvider.notifier).showCatalog(),
            child: Text(context.l10n.chooseDifferentModel),
          ),
          const _PageDots(index: 1),
        ],
      ),
    );
  }
}

class _FeaturedModelCard extends StatelessWidget {
  const _FeaturedModelCard({required this.entry, required this.recommended});

  final ModelCatalogEntry entry;
  final bool recommended;

  @override
  Widget build(BuildContext context) => GolemCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(entry.displayName, style: GolemText.cardTitle),
            ),
            if (recommended) GolemBadge(label: context.l10n.recommended),
          ],
        ),
        const SizedBox(height: GolemSpace.s1),
        Text(
          '${entry.engine.name.toUpperCase()} · ${entry.quantization}',
          style: GolemText.caption.copyWith(
            color: CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context),
          ),
        ),
        const SizedBox(height: GolemSpace.s5),
        Row(
          children: [
            Expanded(
              child: _Fact(
                label: context.l10n.download,
                value: formatModelBytes(entry.totalBytes),
              ),
            ),
            const SizedBox(width: GolemSpace.s2),
            Expanded(
              child: _Fact(
                label: context.l10n.context,
                value: context.l10n.tokensThousands(
                  entry.contextLength ~/ 1024,
                ),
              ),
            ),
            const SizedBox(width: GolemSpace.s2),
            Expanded(
              child: _Fact(
                label: context.l10n.input,
                value: entry.supportsImages
                    ? context.l10n.textAndImages
                    : context.l10n.textOnly,
              ),
            ),
          ],
        ),
        const SizedBox(height: GolemSpace.s4),
        Text(
          context.l10n.featuredModelDetail,
          style: GolemText.footnote.copyWith(
            color: CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context),
          ),
        ),
      ],
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(GolemTheme.field, context),
      borderRadius: BorderRadius.circular(GolemRadius.field),
    ),
    child: Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: GolemText.captionStrong,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GolemText.caption.copyWith(
            color: CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context),
          ),
        ),
      ],
    ),
  );
}

class _CatalogScreen extends ConsumerWidget {
  const _CatalogScreen({required this.selectedKey, this.failure});

  final String? selectedKey;
  final FirstRunFailure? failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = modelAdmissionOptions(
      catalog: ref.watch(modelCatalogEntriesProvider),
      backend: ref.watch(inferenceBackendProvider),
      eligibility: ref.watch(deviceEligibilityProvider),
    );
    final selected = options
        .where((option) => option.entry.key == selectedKey)
        .firstOrNull;
    return CupertinoPageScaffold(
      key: const Key('first-run-catalog'),
      navigationBar: GolemNavBar(
        title: context.l10n.allModelsTitle,
        previousPageTitle: context.l10n.back,
        leading: GolemBackButton(
          key: const Key('first-run-catalog-back'),
          onPressed: () =>
              ref.read(firstRunControllerProvider.notifier).showModel(),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 18, 16, 20),
                children: [
                  Text(
                    ref.watch(inferenceBackendProvider).simulatedInference
                        ? context.l10n.catalogSimulationDetail
                        : context.l10n.catalogDeviceDetail,
                    style: GolemText.footnote.copyWith(
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.mutedInk,
                        context,
                      ),
                    ),
                  ),
                  const SizedBox(height: GolemSpace.s4),
                  for (final option in options) ...[
                    _CatalogModelRow(
                      option: option,
                      selected: option.entry.key == selectedKey,
                      onTap: option.enabled
                          ? () => ref
                                .read(firstRunControllerProvider.notifier)
                                .selectModel(option.entry.key)
                          : null,
                    ),
                    const SizedBox(height: GolemSpace.s3),
                  ],
                  if (failure != null) _FailureText(failure!),
                ],
              ),
            ),
            Container(
              padding: EdgeInsetsDirectional.fromSTEB(
                16,
                12,
                16,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              child: GolemButton.filled(
                key: const Key('first-run-catalog-download'),
                label: selected == null
                    ? context.l10n.chooseModel
                    : context.l10n.downloadSize(
                        formatModelBytes(selected.entry.totalBytes),
                      ),
                onPressed: selected == null
                    ? null
                    : () => _requestDownload(context, ref, selected.entry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogModelRow extends StatelessWidget {
  const _CatalogModelRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ModelAdmissionOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoDynamicColor.resolve(GolemTheme.accent, context);
    return CupertinoButton(
      key: Key('first-run-model-${option.entry.key}'),
      padding: EdgeInsets.zero,
      minimumSize: Size.fromHeight(GolemChrome.current.minimumTapTarget),
      onPressed: onTap,
      child: Opacity(
        opacity: option.enabled ? 1 : 0.48,
        child: GolemCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            option.entry.displayName,
                            style: GolemText.bodyStrong,
                          ),
                        ),
                        if (option.recommended) ...[
                          const SizedBox(width: 8),
                          GolemBadge(label: context.l10n.recommended),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${option.entry.engine.name.toUpperCase()} · '
                      '${option.entry.quantization} · '
                      '${formatModelBytes(option.entry.totalBytes)}',
                      style: GolemText.caption.copyWith(
                        color: CupertinoDynamicColor.resolve(
                          GolemTheme.mutedInk,
                          context,
                        ),
                      ),
                    ),
                    if (!option.enabled) ...[
                      const SizedBox(height: 3),
                      Text(
                        modelAdmissionReason(context.l10n, option),
                        style: GolemText.caption.copyWith(
                          color: CupertinoDynamicColor.resolve(
                            GolemTheme.mutedInk,
                            context,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                color: selected
                    ? accent
                    : CupertinoDynamicColor.resolve(
                        GolemTheme.borderStrong,
                        context,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadScreen extends ConsumerWidget {
  const _DownloadScreen({required this.entry, this.failure});

  final ModelCatalogEntry? entry;
  final FirstRunFailure? failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = entry;
    final model = ref.watch(modelControllerProvider).value;
    final status = selected == null
        ? const ArtifactStatus()
        : model?.statusOf(selected.key) ?? const ArtifactStatus();
    final progress = selected == null || selected.totalBytes == 0
        ? 0.0
        : (status.downloadedBytes / selected.totalBytes).clamp(0.0, 1.0);
    final simulated = model?.simulated ?? false;
    return _FirstRunScaffold(
      key: const Key('first-run-download-progress'),
      body: Column(
        children: [
          const Spacer(),
          Semantics(
            label: context.l10n.downloadProgress,
            value: context.l10n.percentValue((progress * 100).round()),
            child: Text('${(progress * 100).round()}%', style: GolemText.hero),
          ),
          const SizedBox(height: GolemSpace.s4),
          ProgressTrack(
            key: const Key('first-run-download-track'),
            value: progress,
            trackColor: GolemTheme.divider,
            fillColor: GolemTheme.accent,
            height: 8,
          ),
          const SizedBox(height: GolemSpace.s6),
          Text(
            _downloadHeading(context, selected, status),
            textAlign: TextAlign.center,
            style: GolemText.display,
          ),
          const SizedBox(height: GolemSpace.s3),
          Text(
            _downloadDetail(context, selected, status, simulated),
            textAlign: TextAlign.center,
            style: GolemText.body.copyWith(
              color: CupertinoDynamicColor.resolve(
                GolemTheme.mutedInk,
                context,
              ),
            ),
          ),
          if (failure != null) ...[
            const SizedBox(height: GolemSpace.s4),
            _FailureText(failure!),
          ],
          const Spacer(),
        ],
      ),
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GolemButton.filled(
            key: const Key('first-run-start-chatting'),
            label: context.l10n.startChatting,
            onPressed: () =>
                ref.read(firstRunControllerProvider.notifier).complete(),
          ),
          if (selected != null)
            switch (status.phase) {
              ArtifactPhase.downloading => CupertinoButton(
                key: const Key('first-run-pause-download'),
                minimumSize: Size.fromHeight(
                  GolemChrome.current.minimumTapTarget,
                ),
                onPressed: () => ref
                    .read(modelControllerProvider.notifier)
                    .pause(selected.key),
                child: Text(context.l10n.pauseDownload),
              ),
              ArtifactPhase.paused || ArtifactPhase.failed => CupertinoButton(
                key: const Key('first-run-resume-download'),
                minimumSize: Size.fromHeight(
                  GolemChrome.current.minimumTapTarget,
                ),
                onPressed: () => unawaited(
                  ref
                      .read(modelControllerProvider.notifier)
                      .download(selected.key),
                ),
                child: Text(
                  status.phase == ArtifactPhase.failed
                      ? context.l10n.retryDownload
                      : context.l10n.resumeDownload,
                ),
              ),
              _ => const SizedBox(height: 44),
            },
        ],
      ),
    );
  }

  String _downloadHeading(
    BuildContext context,
    ModelCatalogEntry? entry,
    ArtifactStatus status,
  ) => switch (status.phase) {
    ArtifactPhase.installed => context.l10n.modelReady(
      entry?.displayName ?? context.l10n.model,
    ),
    ArtifactPhase.verifying => context.l10n.modelVerifying(
      entry?.displayName ?? context.l10n.model,
    ),
    ArtifactPhase.paused => context.l10n.downloadPaused,
    ArtifactPhase.failed => context.l10n.downloadNeedsAttention,
    _ => context.l10n.modelDownloading(
      entry?.displayName ?? context.l10n.model,
    ),
  };

  String _downloadDetail(
    BuildContext context,
    ModelCatalogEntry? entry,
    ArtifactStatus status,
    bool simulated,
  ) {
    if (entry == null) return context.l10n.selectedCatalogUnavailable;
    if (status.phase == ArtifactPhase.failed) {
      return artifactFailureMessage(context.l10n, status);
    }
    if (status.phase == ArtifactPhase.installed) {
      return simulated
          ? context.l10n.downloadSimulationComplete
          : context.l10n.downloadComplete;
    }
    final amount = context.l10n.downloadAmount(
      formatModelBytes(status.downloadedBytes),
      formatModelBytes(entry.totalBytes),
    );
    return simulated
        ? context.l10n.downloadSimulationProgress(amount)
        : context.l10n.downloadRealProgress(amount);
  }
}

class _UnsupportedScreen extends ConsumerWidget {
  const _UnsupportedScreen({this.failure});

  final FirstRunFailure? failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _FirstRunScaffold(
    key: const Key('first-run-unsupported'),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        const Icon(
          CupertinoIcons.device_phone_portrait,
          size: 54,
          color: GolemTheme.accentIcon,
        ),
        const SizedBox(height: GolemSpace.s6),
        Text(context.l10n.chatsStayAvailable, style: GolemText.display),
        const SizedBox(height: GolemSpace.s3),
        Text(
          deviceRefusalMessage(
            context.l10n,
            ref.watch(deviceEligibilityProvider).reason,
          ),
          style: GolemText.body.copyWith(
            color: CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context),
          ),
        ),
        const SizedBox(height: GolemSpace.s4),
        Text(
          context.l10n.unsupportedFeaturesRemain,
          style: GolemText.footnote.copyWith(
            color: CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context),
          ),
        ),
        if (failure != null) ...[
          const SizedBox(height: GolemSpace.s4),
          _FailureText(failure!),
        ],
        const Spacer(),
      ],
    ),
    action: GolemButton.filled(
      key: const Key('first-run-continue-unsupported'),
      label: context.l10n.continueToGolem,
      onPressed: () => ref
          .read(firstRunControllerProvider.notifier)
          .complete(keepSelection: false),
    ),
  );
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < 2; i++)
        Container(
          width: i == index ? 6 : 4,
          height: i == index ? 6 : 4,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CupertinoDynamicColor.resolve(
              i == index ? GolemTheme.accent : GolemTheme.borderStrong,
              context,
            ),
          ),
        ),
    ],
  );
}

class _FailureText extends StatelessWidget {
  const _FailureText(this.failure);

  final FirstRunFailure failure;

  @override
  Widget build(BuildContext context) => Text(
    switch (failure) {
      FirstRunFailure.modelChoiceSave => context.l10n.modelChoiceSaveFailed,
      FirstRunFailure.setupSave => context.l10n.setupSaveFailed,
    },
    key: const Key('first-run-save-failure'),
    style: GolemText.footnote.copyWith(
      color: CupertinoDynamicColor.resolve(GolemTheme.destructiveText, context),
    ),
  );
}

class _FirstRunScaffold extends StatelessWidget {
  const _FirstRunScaffold({
    required this.body,
    required this.action,
    super.key,
  });

  final Widget body;
  final Widget action;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(22, 8, 22, 12),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - 108).clamp(
                        0,
                        double.infinity,
                      ),
                    ),
                    child: IntrinsicHeight(child: body),
                  ),
                ),
              ),
              const SizedBox(height: GolemSpace.s3),
              action,
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _requestDownload(
  BuildContext context,
  WidgetRef ref,
  ModelCatalogEntry entry,
) async {
  final controller = ref.read(firstRunControllerProvider.notifier);
  if (!await controller.selectModel(entry.key) || !context.mounted) return;
  final model = ref.read(modelControllerProvider).value;
  final approved = await confirmModelDownload(
    context: context,
    entry: entry,
    simulated:
        model?.simulated ??
        ref.read(inferenceBackendProvider).simulatedInference,
  );
  if (!context.mounted) return;
  if (!approved) {
    await controller.complete();
    return;
  }
  controller.showDownload();
  unawaited(ref.read(modelControllerProvider.notifier).download(entry.key));
}
