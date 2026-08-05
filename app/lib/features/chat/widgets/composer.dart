import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';

class Composer extends ConsumerWidget {
  const Composer({
    required this.controller,
    required this.focus,
    required this.reasoningEnabled,
    required this.generation,
    super.key,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final bool reasoningEnabled;
  final GenerationPhase generation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final generating = generation != GenerationPhase.idle;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Glass(
        radius: 30,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: CupertinoButton(
                  key: const Key('reasoning-toggle'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 48),
                  onPressed: generating
                      ? null
                      : () => ref
                            .read(chatControllerProvider.notifier)
                            .toggleReasoning(),
                  child: Icon(
                    reasoningEnabled
                        ? CupertinoIcons.lightbulb_fill
                        : CupertinoIcons.lightbulb,
                    semanticLabel: reasoningEnabled
                        ? 'Reasoning on'
                        : 'Reasoning off',
                    color: reasoningEnabled
                        ? GolemTheme.amber
                        : CupertinoDynamicColor.resolve(
                            GolemTheme.mutedInk,
                            context,
                          ),
                    size: 20,
                  ),
                ),
              ),
              Expanded(
                child: CupertinoTextField.borderless(
                  key: const Key('chat-composer'),
                  controller: controller,
                  focusNode: focus,
                  enabled: !generating,
                  // A borderless field with no decoration paints Flutter's
                  // built-in disabled fill (near-black in dark mode) over
                  // the Glass pill while generating; an explicit empty
                  // decoration keeps the disabled state transparent. The
                  // stop button already communicates that input is closed.
                  decoration: const BoxDecoration(),
                  minLines: 1,
                  maxLines: 6,
                  placeholder: 'Message Golem…',
                  textInputAction: TextInputAction.newline,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              // Only the send button depends on the live text, so it listens
              // to the controller alone instead of rebuilding the whole
              // composer on every keystroke.
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final hasText = controller.text.trim().isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.all(6),
                    child: CupertinoButton(
                      key: Key(generating ? 'stop-button' : 'send-button'),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 48),
                      color: generating || hasText
                          ? CupertinoDynamicColor.resolve(
                              GolemTheme.accent,
                              context,
                            )
                          : CupertinoDynamicColor.resolve(
                              GolemTheme.divider,
                              context,
                            ),
                      borderRadius: BorderRadius.circular(24),
                      onPressed: generating
                          ? () =>
                                ref.read(chatControllerProvider.notifier).stop()
                          : !hasText
                          ? null
                          : () {
                              final text = controller.text;
                              controller.clear();
                              ref
                                  .read(chatControllerProvider.notifier)
                                  .send(text);
                            },
                      child: Icon(
                        generating
                            ? CupertinoIcons.stop_fill
                            : CupertinoIcons.arrow_up,
                        semanticLabel: generating ? 'Stop' : 'Send',
                        color: CupertinoColors.white,
                        size: 20,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
