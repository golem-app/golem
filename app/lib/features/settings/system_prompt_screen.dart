import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chrome/golem_button.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import 'save_feedback.dart';
import 'widgets/settings_rows.dart';

/// The Advanced-mode system prompt editor. The draft is widget-local and
/// commits debounced on text changes (a TextEditingController also
/// notifies on caret moves, and each commit republishes the root-watched
/// preferences and fsyncs a file) with a flush on pop — no save button
/// to forget.
class SystemPromptScreen extends ConsumerStatefulWidget {
  const SystemPromptScreen({super.key});

  @override
  ConsumerState<SystemPromptScreen> createState() => _SystemPromptScreenState();
}

class _SystemPromptScreenState extends ConsumerState<SystemPromptScreen> {
  late final TextEditingController _controller;
  late String _lastCommitted;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _lastCommitted =
        ref.read(preferencesControllerProvider).value?.systemPrompt ?? '';
    _controller = TextEditingController(text: _lastCommitted);
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    // Selection and caret changes notify too; only text changes commit.
    if (_controller.text == _lastCommitted) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _commit);
  }

  void _commit() {
    _debounce?.cancel();
    _debounce = null;
    if (_controller.text == _lastCommitted) return;
    _lastCommitted = _controller.text;
    // The controller trims and stores null for blank. On a failed write the
    // stored value rolled back; the toast is best-effort — a pop-flush
    // failure has no surface left to show it on.
    announceFailedSave(
      context,
      ref
          .read(preferencesControllerProvider.notifier)
          .setSystemPrompt(_controller.text),
    );
  }

  @override
  void dispose() {
    // Cancel only — ref is unusable in dispose. The pop flush below is
    // the commit of record; the debounce covers app suspension.
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) => _commit(),
      child: CupertinoPageScaffold(
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
                      : () {
                          _controller.clear();
                          _commit();
                        },
                ),
              ),
              const SizedBox(height: 18),
              const SettingsFootnote(
                'The prompt applies to both models and stays on this device.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
