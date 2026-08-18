import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chrome/golem_alert.dart';
import '../../core/chrome/golem_icon_button.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_toast.dart';
import '../../core/domain/byte_format.dart';
import '../../core/domain/model_catalog.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/retry_pane.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/settings_rows.dart';
import '../../l10n/l10n.dart';
import '../chat/application/active_model_providers.dart';
import '../models/application/model_providers.dart';
import '../models/application/storage_providers.dart';

class StorageScreen extends ConsumerWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdownValue = ref.watch(storageBreakdownProvider);
    final modelValue = ref.watch(modelControllerProvider);
    final catalog = ref.watch(effectiveModelCatalogProvider);
    // This screen is *about* the stored data, so a failed read gets a
    // full error pane with a retry — never the eternal spinner that used
    // to render for loading and failure alike.
    final failed = breakdownValue.hasError || modelValue.hasError;
    final breakdown = breakdownValue.value;
    final model = modelValue.value;
    return CupertinoPageScaffold(
      navigationBar: GolemNavBar(
        title: context.l10n.settingsStorage,
        previousPageTitle: context.l10n.settingsTitle,
      ),
      child: SafeArea(
        bottom: false,
        child: failed
            ? RetryPane(
                key: const Key('storage-error'),
                message: context.l10n.storageReadFailed,
                actionLabel: context.l10n.tryAgain,
                onRetry: () {
                  // Only the provider that actually failed: invalidating a
                  // healthy ModelController would kill an in-flight download
                  // (the epoch/mounted guards abandon its stream).
                  if (breakdownValue.hasError) {
                    ref.invalidate(storageBreakdownProvider);
                  }
                  if (modelValue.hasError) {
                    ref.invalidate(modelControllerProvider);
                  }
                },
              )
            : breakdown == null || model == null
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                key: const Key('storage-list'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  _UsageCard(breakdown: breakdown),
                  const SizedBox(height: 24),
                  SectionHeader(context.l10n.downloadedModels),
                  const SizedBox(height: 8),
                  _DownloadedModels(model: model, catalog: catalog),
                  const SizedBox(height: 24),
                  SettingsCard(
                    children: [
                      SettingsNavRow(
                        key: const Key('clear-cache'),
                        label: context.l10n.clearInferenceCache,
                        value: _megabytes(context, breakdown.cacheBytes),
                        onTap: breakdown.cacheBytes == 0
                            ? null
                            : () => _clearCache(context, ref),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SettingsFootnote(context.l10n.modelDeletionFootnote),
                ],
              ),
      ),
    );
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    await ref.read(cacheProbeProvider).clear();
    ref.invalidate(storageBreakdownProvider);
    if (context.mounted) showGolemToast(context, context.l10n.cacheCleared);
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.breakdown});
  final StorageBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    final accent = CupertinoDynamicColor.resolve(GolemTheme.accent, context);
    final chatsColor = CupertinoDynamicColor.resolve(
      GolemTheme.accentIcon,
      context,
    );
    const cacheColor = GolemTheme.amber;
    final used = breakdown.usedBytes;
    final free = breakdown.freeBytes;
    // The bar shows the buckets against each other; disk-wide proportions
    // belong to the free label.
    final attachmentsColor = CupertinoDynamicColor.resolve(
      GolemTheme.reasoningBorder,
      context,
    );
    final segments = [
      (breakdown.modelsBytes, accent),
      (breakdown.chatsBytes, chatsColor),
      (breakdown.attachmentsBytes, attachmentsColor),
      (breakdown.cacheBytes, cacheColor),
    ].where((segment) => segment.$1 > 0).toList();
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(gigabytes(used), style: GolemText.display),
                  ),
                  if (free != null)
                    Text(
                      context.l10n.storageFree(gigabytes(free)),
                      style: GolemText.footnote.copyWith(color: muted),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (used > 0)
                ClipRRect(
                  key: const Key('storage-bar'),
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 6,
                    child: Row(
                      // Stretch, or the childless ColoredBoxes collapse
                      // to zero height and the bar vanishes.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, segment) in segments.indexed) ...[
                          if (index > 0) const SizedBox(width: 2),
                          Expanded(
                            flex: ((segment.$1 / used) * 1000).round(),
                            child: ColoredBox(color: segment.$2),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _Legend(
                    color: accent,
                    label: context.l10n.storageModelsAmount(
                      gigabytes(breakdown.modelsBytes),
                    ),
                  ),
                  _Legend(
                    color: chatsColor,
                    label: context.l10n.storageChatsAmount(
                      _megabytes(context, breakdown.chatsBytes),
                    ),
                  ),
                  // An always-present "Images 0 MB" would be clutter on the
                  // many installs that never attach one; the bar's arithmetic
                  // counts them either way.
                  if (breakdown.attachmentsBytes > 0)
                    _Legend(
                      color: attachmentsColor,
                      label: context.l10n.storageImagesAmount(
                        _megabytes(context, breakdown.attachmentsBytes),
                      ),
                    ),
                  _Legend(
                    color: cacheColor,
                    label: context.l10n.storageCacheAmount(
                      _megabytes(context, breakdown.cacheBytes),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(width: 6),
      // Flexible so an enlarged-text chip wraps instead of overflowing its run.
      Flexible(
        child: Text(
          label,
          style: GolemText.footnote.copyWith(
            color: CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context),
          ),
        ),
      ),
    ],
  );
}

class _DownloadedModels extends ConsumerWidget {
  const _DownloadedModels({required this.model, required this.catalog});
  final ModelState model;
  final List<ModelCatalogEntry> catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    // The same resolution chat and Settings use, so one model is called active
    // in exactly one place at a time (#20).
    final activeKey = ref.watch(activeModelKeyProvider);
    // Anything holding bytes shows up — installed or partial — so what the
    // meter counts and what can be freed always agree.
    final rows = catalog
        .where((entry) => model.statusOf(entry.key).downloadedBytes > 0)
        .toList();
    if (rows.isEmpty) {
      return SettingsFootnote(
        context.l10n.noDownloadedModels,
        key: const Key('storage-models-empty'),
      );
    }
    return SettingsCard(
      children: [
        for (final entry in rows)
          Padding(
            // Natural height, floored by the trash button's target: the
            // test font renders far taller than SF Pro, so a fixed row height
            // would overflow invisibly.
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              key: Key('storage-model-${entry.key}'),
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.displayName, style: GolemText.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        [
                          entry.engine == ModelEngine.mlx ? 'MLX' : 'GGUF',
                          entry.quantization,
                          if (entry.key == activeKey) context.l10n.active,
                          if (model.statusOf(entry.key).phase !=
                              ArtifactPhase.installed)
                            context.l10n.partial,
                        ].join(' · '),
                        style: GolemText.caption.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                Text(
                  gigabytes(model.statusOf(entry.key).downloadedBytes),
                  style: GolemText.body.copyWith(color: muted),
                ),
                const SizedBox(width: 4),
                GolemIconButton(
                  key: Key('storage-delete-${entry.key}'),
                  icon: CupertinoIcons.trash,
                  size: 20,
                  color: GolemTheme.destructive,
                  onPressed: () => _confirmDelete(context, ref, entry),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ModelCatalogEntry entry,
  ) => showGolemAlert(
    context: context,
    dialogKey: const Key('model-delete-dialog'),
    // Display names no longer carry a quantization, so two artifacts of one
    // family share one (#79). A destructive dialog must still say which.
    title: context.l10n.deleteModelArtifactTitle(
      entry.displayName,
      engineFormat(entry.engine),
    ),
    message: context.l10n.deleteModelStorageMessage(
      gigabytes(model.statusOf(entry.key).downloadedBytes),
    ),
    actions: [
      GolemAlertAction(
        label: context.l10n.keep,
        onPressed: () => Navigator.pop(context),
      ),
      GolemAlertAction(
        key: const Key('confirm-model-delete'),
        label: context.l10n.delete,
        isDestructive: true,
        onPressed: () {
          Navigator.pop(context);
          ref.read(modelControllerProvider.notifier).delete(entry.key);
        },
      ),
    ],
  );
}

String _megabytes(BuildContext context, int bytes) => bytes >= 1e9
    ? gigabytes(bytes)
    : context.l10n.megabytes((bytes / 1e6).round());
