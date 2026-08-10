import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chrome/golem_alert.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_toast.dart';
import '../../core/domain/model_catalog.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/section_header.dart';
import 'widgets/settings_rows.dart';

class StorageScreen extends ConsumerWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown = ref.watch(storageBreakdownProvider).value;
    final model = ref.watch(modelControllerProvider).value;
    final catalog = ref.watch(effectiveModelCatalogProvider);
    return CupertinoPageScaffold(
      navigationBar: GolemNavBar(
        title: 'Storage',
        previousPageTitle: 'Settings',
      ),
      child: SafeArea(
        bottom: false,
        child: breakdown == null || model == null
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                key: const Key('storage-list'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  _UsageCard(breakdown: breakdown),
                  const SizedBox(height: 24),
                  const SectionHeader('Downloaded models'),
                  const SizedBox(height: 8),
                  _DownloadedModels(model: model, catalog: catalog),
                  const SizedBox(height: 24),
                  SettingsCard(
                    children: [
                      SettingsNavRow(
                        key: const Key('clear-cache'),
                        label: 'Clear inference cache',
                        value: _megabytes(breakdown.cacheBytes),
                        onTap: breakdown.cacheBytes == 0
                            ? null
                            : () => _clearCache(context, ref),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const SettingsFootnote(
                    'Deleting a model frees the space immediately. Your '
                    'chats are kept.',
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    await ref.read(cacheProbeProvider).clear();
    ref.invalidate(storageBreakdownProvider);
    if (context.mounted) showGolemToast(context, 'Cache cleared');
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
                    child: Text(_gigabytes(used), style: GolemText.display),
                  ),
                  if (free != null)
                    Text(
                      '${_gigabytes(free)} free',
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
                    label: 'Models ${_gigabytes(breakdown.modelsBytes)}',
                  ),
                  _Legend(
                    color: chatsColor,
                    label: 'Chats ${_megabytes(breakdown.chatsBytes)}',
                  ),
                  // An always-present "Images 0 MB" would be clutter on the
                  // many installs that never attach one; the bar's arithmetic
                  // counts them either way.
                  if (breakdown.attachmentsBytes > 0)
                    _Legend(
                      color: attachmentsColor,
                      label: 'Images ${_megabytes(breakdown.attachmentsBytes)}',
                    ),
                  _Legend(
                    color: cacheColor,
                    label: 'Cache ${_megabytes(breakdown.cacheBytes)}',
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
    // Anything holding bytes shows up — installed or partial — so what the
    // meter counts and what can be freed always agree.
    final rows = catalog
        .where((entry) => model.statusOf(entry.key).downloadedBytes > 0)
        .toList();
    if (rows.isEmpty) {
      return const SettingsFootnote(
        'No downloaded models yet.',
        key: Key('storage-models-empty'),
      );
    }
    return SettingsCard(
      children: [
        for (final entry in rows)
          Padding(
            // Natural height, floored by the trash button's 44pt target: the
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
                          if (entry.key == model.activeArtifactKey) 'active',
                          if (model.statusOf(entry.key).phase !=
                              ArtifactPhase.installed)
                            'partial',
                        ].join(' · '),
                        style: GolemText.caption.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                Text(
                  _gigabytes(model.statusOf(entry.key).downloadedBytes),
                  style: GolemText.body.copyWith(color: muted),
                ),
                const SizedBox(width: 4),
                CupertinoButton(
                  key: Key('storage-delete-${entry.key}'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: () => _confirmDelete(context, ref, entry),
                  child: const Icon(
                    CupertinoIcons.trash,
                    size: 20,
                    color: GolemTheme.destructive,
                  ),
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
    title: 'Delete ${entry.displayName}?',
    message:
        'Removes ${_gigabytes(model.statusOf(entry.key).downloadedBytes)} '
        'from this device. The model can be downloaded again later.',
    actions: [
      GolemAlertAction(label: 'Keep', onPressed: () => Navigator.pop(context)),
      GolemAlertAction(
        key: const Key('confirm-model-delete'),
        label: 'Delete',
        isDestructive: true,
        onPressed: () {
          Navigator.pop(context);
          ref.read(modelControllerProvider.notifier).delete(entry.key);
        },
      ),
    ],
  );
}

String _gigabytes(int bytes) => '${(bytes / 1e9).toStringAsFixed(2)} GB';

String _megabytes(int bytes) =>
    bytes >= 1e9 ? _gigabytes(bytes) : '${(bytes / 1e6).round()} MB';
