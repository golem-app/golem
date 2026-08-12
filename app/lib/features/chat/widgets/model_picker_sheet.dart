import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/chrome/golem_badge.dart';
import '../../../core/chrome/golem_button.dart';
import '../../../core/chrome/golem_sheet.dart';
import '../../../core/domain/model_activation.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../core/widgets/progress_track.dart';
import '../../../l10n/l10n.dart';
import '../../onboarding/model_download_consent.dart';
import '../model_choice.dart';

/// The per-chat model sheet. What each row says, why it is offered or refused,
/// and which one is recommended all come from [buildModelPickerView]; this file
/// paints that and forwards taps (#79).
Future<void> showModelPickerSheet(
  BuildContext context, {
  required String conversationId,
}) => showGolemSheet<void>(
  context: context,
  sheetKey: const Key('model-picker-sheet'),
  builder: (context) => _ModelPickerContent(conversationId: conversationId),
);

final class _ModelPickerContent extends ConsumerWidget {
  const _ModelPickerContent({required this.conversationId});
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(effectiveModelCatalogProvider);
    final backend = ref.watch(inferenceBackendProvider);
    final models = ref.watch(modelControllerProvider).value;
    final loadable = ref.watch(loadableModelKeysProvider);
    final chats = ref.watch(chatControllerProvider).value;
    final modelKey = chats?.conversations
        .where((item) => item.id == conversationId)
        .firstOrNull
        ?.modelKey;
    final preferences = ref.watch(preferencesControllerProvider).value;
    // One reading, used by the row label, the download guard and the consent
    // dialog alike. Defaulting these separately produced a real transfer
    // behind a dialog promising a simulation, in the window before model
    // state resolves.
    final simulatedTransfers = models?.simulated ?? backend.simulatedInference;
    final view = buildModelPickerView(
      catalog: catalog,
      pinnedCatalog: ref.watch(modelCatalogEntriesProvider),
      downloadableKeys: ref.watch(downloadableModelKeysProvider),
      backend: backend,
      models: models,
      loadableKeys: loadable,
      conversations: chats?.conversations ?? const <ChatConversation>[],
      eligibility: ref.watch(deviceEligibilityProvider),
      deviceRefusal: ref.watch(deviceRefusalProvider),
      advanced: preferences?.advancedMode ?? false,
      simulatedTransfers: simulatedTransfers,
      localizations: context.l10n,
      selectedKey: effectiveModelKey(
        backend: backend,
        catalog: catalog,
        modelKey: modelKey,
        residentModelKey: ref.watch(residentModelKeyProvider),
        loadableKeys: loadable,
      ),
    );

    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          GolemSpace.gutter,
          GolemSpace.s4,
          GolemSpace.gutter,
          GolemSpace.s3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.modelForChat,
              textAlign: TextAlign.center,
              style: GolemText.cardTitle,
            ),
            const SizedBox(height: GolemSpace.s4),
            // Rows carry four lines and a button now, so the list scrolls
            // inside the sheet rather than growing it past the screen.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final choice in view.choices) ...[
                      _ModelRow(
                        choice: choice,
                        onSelect: choice.selectable
                            ? () => _select(context, ref, choice.entry.key)
                            : null,
                        onTransfer: _transferAction(
                          context,
                          ref,
                          choice,
                          simulatedTransfers,
                        ),
                      ),
                      const SizedBox(height: GolemSpace.s2),
                    ],
                  ],
                ),
              ),
            ),
            for (final note in [view.hiddenNote, view.footnote])
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: GolemSpace.s1),
                  child: Text(
                    note,
                    style: GolemText.caption.copyWith(color: muted),
                  ),
                ),
            CupertinoButton(
              key: const Key('model-picker-manage'),
              padding: EdgeInsets.zero,
              minimumSize: const Size.fromHeight(GolemSize.hitTarget),
              alignment: Alignment.centerLeft,
              onPressed: () {
                Navigator.pop(context);
                context.push('/settings');
              },
              child: Text(
                context.l10n.manageModels,
                style: GolemText.footnoteStrong.copyWith(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.accent,
                    context,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _select(BuildContext context, WidgetRef ref, String key) async {
    await ref
        .read(chatControllerProvider.notifier)
        .setConversationModel(conversationId, key);
    if (context.mounted) Navigator.pop(context);
  }

  /// The transfer the row's button performs, or null when it has none to offer.
  /// Downloads run through the same controller Settings drives, so a transfer
  /// started here reconciles, verifies and resumes exactly as one started there
  /// (#79 adds a second entrance, not a second implementation). The sheet stays
  /// open: progress is the point of starting it from here.
  ///
  /// A first transfer asks for consent, exactly as Settings, first run, the
  /// setup banner and the recovery banner do (#26). This sheet is the most
  /// casual entrance of the five and offers no Cancel, so it is the last place
  /// that should start gigabytes on a stray tap.
  VoidCallback? _transferAction(
    BuildContext context,
    WidgetRef ref,
    ModelChoice choice,
    bool simulated,
  ) {
    final controller = ref.read(modelControllerProvider.notifier);
    Future<void> start() async {
      if (choice.needsConsent) {
        final approved = await confirmModelDownload(
          context: context,
          entry: choice.entry,
          simulated: simulated,
        );
        if (!approved) return;
      }
      await controller.download(choice.entry.key);
    }

    return switch (choice.transfer) {
      null => null,
      ModelTransferOffer(:final enabled) when !enabled => null,
      ModelTransferOffer() => start,
      ModelTransferProgress(:final pausable) when pausable =>
        () => controller.pause(choice.entry.key),
      ModelTransferProgress() => null,
    };
  }
}

final class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.choice,
    required this.onSelect,
    required this.onTransfer,
  });

  final ModelChoice choice;
  final VoidCallback? onSelect;
  final VoidCallback? onTransfer;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoDynamicColor.resolve(GolemTheme.accent, context);
    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    // Dimmed only when the row has nothing at all to offer — a refusal, another
    // engine's artifact, a pinned sideload. A row that cannot be picked *yet*
    // can still be downloaded, and greying out the button that fixes it would
    // hide the way forward.
    final inert = onSelect == null && choice.transfer == null;
    // The card is not itself a button. A row can carry a download button now,
    // and nesting one inside another leaves the middle of the row ambiguous —
    // a tap aimed at the model would start a transfer instead. The keyed button
    // is the selection target and nothing else is.
    return Opacity(
      opacity: inert ? 0.45 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: GolemSpace.s1,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GolemRadius.field),
          border: Border.all(
            width: choice.selected ? 1.5 : 1,
            color: choice.selected
                ? accent
                : CupertinoDynamicColor.resolve(GolemTheme.divider, context),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CupertinoButton(
              key: Key('model-picker-${choice.entry.key}'),
              padding: const EdgeInsets.symmetric(vertical: GolemSpace.s2),
              minimumSize: const Size.fromHeight(GolemSize.hitTarget),
              onPressed: onSelect,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Above the name rather than beside it: a badge
                            // sharing the line squeezes a long model name into
                            // three wrapped ones.
                            if (choice.recommendation != null) ...[
                              GolemBadge(label: context.l10n.recommended),
                              const SizedBox(height: 5),
                            ],
                            Text(
                              choice.title,
                              style: GolemText.bodyStrong.copyWith(
                                color: CupertinoDynamicColor.resolve(
                                  GolemTheme.ink,
                                  context,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              choice.detail,
                              style: GolemText.caption.copyWith(color: muted),
                            ),
                          ],
                        ),
                      ),
                      if (choice.selected)
                        Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          size: 22,
                          color: accent,
                          semanticLabel: context.l10n.selectedModel,
                        ),
                    ],
                  ),
                  // What the model is for, then what stands in the way of
                  // picking it. Both, when both apply.
                  for (final line in [choice.summary, choice.blockReason])
                    if (line != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        line,
                        style: GolemText.caption.copyWith(color: muted),
                      ),
                    ],
                  if (choice.recommendation != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      choice.recommendation!,
                      style: GolemText.caption.copyWith(color: accent),
                    ),
                  ],
                  if (choice.artifactLine != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      choice.artifactLine!,
                      key: Key('model-picker-artifact-${choice.entry.key}'),
                      style: GolemText.caption.copyWith(color: muted),
                    ),
                  ],
                ],
              ),
            ),
            ..._transfer(context, muted, accent),
          ],
        ),
      ),
    );
  }

  List<Widget> _transfer(BuildContext context, Color muted, Color accent) =>
      switch (choice.transfer) {
        null => const [],
        final ModelTransferProgress progress => [
          const SizedBox(height: GolemSpace.s3),
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.label,
                  style: GolemText.caption.copyWith(color: muted),
                ),
              ),
              if (progress.pausable)
                Text(
                  '${(progress.fraction * 100).round()}%',
                  style: GolemText.caption.copyWith(color: muted),
                ),
            ],
          ),
          const SizedBox(height: 7),
          ProgressTrack(
            value: progress.fraction,
            trackColor: GolemTheme.divider,
            fillColor: GolemTheme.accent,
          ),
          if (progress.pausable) ...[
            const SizedBox(height: GolemSpace.s2),
            CupertinoButton(
              key: Key('model-picker-pause-${choice.entry.key}'),
              padding: EdgeInsets.zero,
              minimumSize: const Size.fromHeight(GolemSize.hitTarget),
              onPressed: onTransfer,
              child: Text(
                context.l10n.pause,
                style: GolemText.footnoteStrong.copyWith(color: accent),
              ),
            ),
          ],
          const SizedBox(height: GolemSpace.s3),
        ],
        final ModelTransferOffer offer => [
          if (offer.note != null) ...[
            const SizedBox(height: 3),
            Text(offer.note!, style: GolemText.caption.copyWith(color: muted)),
          ],
          // Withheld rather than disabled while another artifact holds the one
          // transfer slot: GolemButton looks identical either way, so a dead
          // one beside a live one is a trap. The note above says why it is
          // gone, and it returns when the slot frees.
          if (offer.enabled) ...[
            const SizedBox(height: GolemSpace.s2),
            GolemButton.tinted(
              key: Key('model-picker-download-${choice.entry.key}'),
              label: offer.label,
              onPressed: onTransfer,
            ),
          ],
          const SizedBox(height: GolemSpace.s3),
        ],
      };
}
