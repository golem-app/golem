import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';
import '../model_label.dart';

class EmptyChat extends ConsumerWidget {
  const EmptyChat({required this.onStarter, super.key});

  /// Receives a starter prompt to prefill the composer with.
  final ValueChanged<String> onStarter;

  static const _starters = [
    (
      key: Key('starter-chip-draft-reply'),
      icon: CupertinoIcons.pencil,
      label: 'Draft a reply',
      prompt: 'Draft a reply to this message: ',
    ),
    (
      key: Key('starter-chip-explain'),
      icon: CupertinoIcons.lightbulb,
      label: 'Explain something',
      prompt: 'Explain, simply: ',
    ),
    (
      key: Key('starter-chip-rewrite'),
      icon: CupertinoIcons.doc_on_doc,
      label: 'Rewrite my text',
      prompt: 'Rewrite this so it reads clearly: ',
    ),
    (
      key: Key('starter-chip-summarise'),
      icon: CupertinoIcons.search,
      label: 'Summarise a note',
      prompt: 'Summarise this note: ',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Copy stays honest in both directions: only the fake backend may call
    // itself simulated.
    final backend = ref.watch(inferenceBackendProvider);
    // A device outside every supported tier says so here rather than letting a
    // user write a prompt that could only fail (#27). The simulated backend
    // loads nothing, so it is never refused.
    final eligibility = ref.watch(deviceEligibilityProvider);
    final refusal = backend.simulatedInference || eligibility.runsModels
        ? null
        : eligibility.message;
    final label = chatModelLabel(
      backend: backend,
      catalog: ref.watch(effectiveModelCatalogProvider),
      modelKey: ref.watch(
        chatControllerProvider.select((state) => state.value?.active?.modelKey),
      ),
      residentModelKey: ref.watch(residentModelKeyProvider),
      loadableKeys: ref.watch(loadableModelKeysProvider),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Semantics(
          key: const Key('empty-chat'),
          label: refusal == null
              ? 'Start a private conversation'
              : 'Golem cannot run models on this device',
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
                const Text('What are we building?', style: GolemText.display)
              else
                const Text(
                  'Golem can’t run models here',
                  textAlign: TextAlign.center,
                  style: GolemText.display,
                ),
              const SizedBox(height: 10),
              Text(
                key: refusal == null
                    ? null
                    : const Key('device-unsupported-notice'),
                refusal ??
                    (backend.simulatedInference
                        ? 'This preview simulates $label on this phone. '
                              'Nothing you type here goes anywhere.'
                        : '$label is loaded and running on this phone. '
                              'Nothing you type here goes anywhere.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.4,
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Starter chips would only prefill a prompt this device cannot
              // answer, so a refused device gets none.
              if (refusal == null)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    for (final starter in _starters)
                      CupertinoButton(
                        key: starter.key,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
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
                              Text(
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
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
