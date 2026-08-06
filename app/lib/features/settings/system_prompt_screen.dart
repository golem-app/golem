import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chrome/golem_button.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import 'widgets/settings_rows.dart';

/// The Advanced-mode system prompt editor. The draft is widget-local;
/// leaving the screen commits it (empty means the model default).
class SystemPromptScreen extends ConsumerStatefulWidget {
  const SystemPromptScreen({super.key});

  @override
  ConsumerState<SystemPromptScreen> createState() => _SystemPromptScreenState();
}

class _SystemPromptScreenState extends ConsumerState<SystemPromptScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(preferencesControllerProvider).value?.systemPrompt ?? '',
    );
    // Commit on every edit (the controller trims and stores null for
    // blank), so system back, pop, and app kill all keep the draft — no
    // save button to forget.
    _controller.addListener(() {
      ref
          .read(preferencesControllerProvider.notifier)
          .setSystemPrompt(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: GolemNavBar(
        title: 'System prompt',
        previousPageTitle: 'Settings',
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 18),
              child: Text(
                'Standing instructions for every new response, sent ahead '
                'of the conversation. Leave it empty to keep the model\'s '
                'default behavior.',
                style: GolemText.body.copyWith(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                ),
              ),
            ),
            CupertinoTextField(
              key: const Key('system-prompt-field'),
              controller: _controller,
              maxLines: 8,
              minLines: 5,
              placeholder: 'e.g. Answer briefly, in plain language.',
              padding: const EdgeInsets.all(14),
              style: GolemText.body,
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                  GolemTheme.surface,
                  context,
                ),
                border: Border.all(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.borderStrong,
                    context,
                  ),
                ),
                borderRadius: BorderRadius.circular(GolemRadius.field),
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) => GolemButton.tinted(
                key: const Key('system-prompt-reset'),
                label: 'Reset to default',
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () => _controller.clear(),
              ),
            ),
            const SizedBox(height: 18),
            const SettingsFootnote(
              'The prompt applies to both models and stays on this device.',
            ),
          ],
        ),
      ),
    );
  }
}
