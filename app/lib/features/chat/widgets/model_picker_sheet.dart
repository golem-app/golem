import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/chrome/golem_sheet.dart';
import '../../../core/domain/model_catalog.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';
import '../model_label.dart';

/// The per-chat "Model for this chat" sheet. Selection persists on the
/// conversation; the fake simulates the switch fully, while a real
/// engine keeps running its configured model until #20 — the footnote
/// says so instead of letting the sheet imply a hot swap.
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
    final catalog = ref.watch(modelCatalogEntriesProvider);
    final backend = ref.watch(inferenceBackendProvider);
    final models = ref.watch(modelControllerProvider).value;
    final modelKey = ref.watch(
      chatControllerProvider.select(
        (state) => state.value?.conversations
            .where((item) => item.id == conversationId)
            .firstOrNull
            ?.modelKey,
      ),
    );
    final selected = effectiveModelKey(
      backend: backend,
      catalog: catalog,
      modelKey: modelKey,
      residentModelKey: ref.watch(residentModelKeyProvider),
    );
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
              'Model for this chat',
              textAlign: TextAlign.center,
              style: GolemText.cardTitle,
            ),
            const SizedBox(height: GolemSpace.s4),
            for (final entry in catalog) ...[
              _ModelRow(
                entry: entry,
                selected: entry.key == selected,
                status: _statusLine(entry, models),
                // A real engine cannot switch models per chat until #20:
                // only the running artifact's row stays tappable, and the
                // footnote below explains why. The fake honors the choice
                // in generation, so every row is live there.
                onTap: backend.simulatedInference || entry.key == selected
                    ? () async {
                        final controller = ref.read(
                          chatControllerProvider.notifier,
                        );
                        await controller.setConversationModel(
                          conversationId,
                          entry.key,
                        );
                        if (context.mounted) Navigator.pop(context);
                      }
                    : null,
              ),
              const SizedBox(height: GolemSpace.s2),
            ],
            if (!backend.simulatedInference)
              Padding(
                padding: const EdgeInsets.only(top: GolemSpace.s1),
                child: Text(
                  'Golem is running '
                  '${chatModelLabel(backend: backend, catalog: catalog, modelKey: null, residentModelKey: ref.watch(residentModelKeyProvider))}. '
                  'Per-chat model switching arrives in a future update.',
                  style: GolemText.caption.copyWith(
                    color: CupertinoDynamicColor.resolve(
                      GolemTheme.mutedInk,
                      context,
                    ),
                  ),
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
                'Manage models',
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

  String _statusLine(ModelCatalogEntry entry, ModelState? models) {
    final engine = entry.engine.name.toUpperCase();
    final base = '$engine · ${entry.quantization}';
    final status = models?.statusOf(entry.key);
    if (status == null) return base;
    return switch (status.phase) {
      ArtifactPhase.installed => '$base · Installed',
      ArtifactPhase.downloading =>
        '$base · Downloading · '
            '${(status.downloadedBytes / entry.totalBytes * 100).clamp(0, 100).round()}%',
      ArtifactPhase.paused => '$base · Paused',
      ArtifactPhase.verifying => '$base · Verifying',
      ArtifactPhase.failed => '$base · Failed',
      ArtifactPhase.notDownloaded => '$base · Not downloaded',
    };
  }
}

final class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.entry,
    required this.selected,
    required this.status,
    required this.onTap,
  });
  final ModelCatalogEntry entry;
  final bool selected;
  final String status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoDynamicColor.resolve(GolemTheme.accent, context);
    return CupertinoButton(
      key: Key('model-picker-${entry.key}'),
      padding: EdgeInsets.zero,
      minimumSize: const Size.fromHeight(GolemSize.hitTarget),
      onPressed: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: GolemSpace.s3,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GolemRadius.field),
            border: Border.all(
              width: selected ? 1.5 : 1,
              color: selected
                  ? accent
                  : CupertinoDynamicColor.resolve(GolemTheme.divider, context),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      style: GolemText.bodyStrong.copyWith(
                        color: CupertinoDynamicColor.resolve(
                          GolemTheme.ink,
                          context,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
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
              if (selected)
                Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  size: 22,
                  color: accent,
                  semanticLabel: 'Selected model',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
