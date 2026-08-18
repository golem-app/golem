import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/chrome/golem_chrome.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/presentation_messages.dart';
import '../../models/application/model_providers.dart';
import '../../models/model_label.dart';
import '../application/active_model_providers.dart';

class EmptyChat extends ConsumerWidget {
  const EmptyChat({required this.onStarter, super.key});

  /// Receives a starter prompt to prefill the composer with.
  final ValueChanged<String> onStarter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Copy stays honest in both directions: only the fake backend may call
    // itself simulated.
    final backend = ref.watch(inferenceBackendProvider);
    // A device outside every supported tier says so here rather than letting a
    // user write a prompt that could only fail (#27). The simulated backend
    // loads nothing, so it is never refused.
    final refusal = ref.watch(deviceRefusalProvider);
    final refusalMessage = refusal == null
        ? null
        : deviceRefusalMessage(
            context.l10n,
            ref.watch(deviceEligibilityProvider).reason,
          );
    // Only the supported copy names a model, so only it pays for the label —
    // and only it subscribes this widget to residency and the catalog.
    final label = refusal != null
        ? null
        : modelDisplayLabel(
            backend: backend,
            catalog: ref.watch(effectiveModelCatalogProvider),
            activeKey: ref.watch(activeModelKeyProvider),
          );
    final residency = ref.watch(inferenceResidencyProvider);
    final l10n = context.l10n;
    final starters = [
      (
        key: const Key('starter-chip-draft-reply'),
        icon: CupertinoIcons.pencil,
        label: l10n.starterDraftReply,
        prompt: l10n.starterDraftReplyPrompt,
      ),
      (
        key: const Key('starter-chip-explain'),
        icon: CupertinoIcons.lightbulb,
        label: l10n.starterExplain,
        prompt: l10n.starterExplainPrompt,
      ),
      (
        key: const Key('starter-chip-rewrite'),
        icon: CupertinoIcons.doc_on_doc,
        label: l10n.starterRewrite,
        prompt: l10n.starterRewritePrompt,
      ),
      (
        key: const Key('starter-chip-summarise'),
        icon: CupertinoIcons.search,
        label: l10n.starterSummarise,
        prompt: l10n.starterSummarisePrompt,
      ),
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Semantics(
          key: const Key('empty-chat'),
          label: refusal == null
              ? l10n.startPrivateConversation
              : l10n.modelsUnavailableGeneric,
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: GolemTheme.accent,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(7),
                child: Image.asset('assets/images/golem_mascot.png'),
              ),
              const SizedBox(height: 22),
              if (refusal == null)
                Text(l10n.whatAreWeBuilding, style: GolemText.display)
              else
                Text(
                  l10n.cannotRunModelsHere,
                  textAlign: TextAlign.center,
                  style: GolemText.display,
                ),
              const SizedBox(height: 10),
              Text(
                key: refusal == null
                    ? null
                    : const Key('device-unsupported-notice'),
                refusalMessage ??
                    (backend.simulatedInference
                        ? l10n.simulatedModelPrivacy(label!)
                        : backend.sideloaded
                        ? l10n.validatedModelPrivacy(label!)
                        : residency.loaded
                        ? l10n.localModelPrivacy(label!)
                        : l10n.downloadedModelPrivacy(label!)),
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.4,
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                ),
              ),
              // Starter chips would only prefill a prompt this device cannot
              // answer, so a refused device gets neither them nor their space.
              if (refusal == null) ...[
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    for (final starter in starters)
                      CupertinoButton(
                        key: starter.key,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.square(
                          GolemChrome.current.minimumTapTarget,
                        ),
                        onPressed: () => onStarter(starter.prompt),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: CupertinoDynamicColor.resolve(
                              GolemTheme.surface,
                              context,
                            ),
                            borderRadius: BorderRadius.circular(
                              GolemRadius.pill,
                            ),
                            border: Border.all(
                              color: CupertinoDynamicColor.resolve(
                                GolemTheme.divider,
                                context,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                starter.icon,
                                size: 15,
                                color: CupertinoDynamicColor.resolve(
                                  GolemTheme.accentIcon,
                                  context,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // At an accessibility text size a chip's label
                              // outgrows the row it sits in; wrapping inside
                              // the pill beats spilling out of it.
                              Flexible(
                                child: Text(
                                  starter.label,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.3,
                                    color: CupertinoDynamicColor.resolve(
                                      GolemTheme.ink,
                                      context,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
