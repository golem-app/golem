import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/chrome/golem_alert.dart';
import '../../../core/chrome/golem_sheet.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    required this.message,
    required this.canRegenerate,
    super.key,
  });
  final ChatMessage message;
  final bool canRegenerate;

  /// Readable measure for a bubble on wide desktop windows; phone layouts
  /// never reach it (82% of a phone viewport stays below the cap).
  static const _maxBubbleWidth = 640.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.role == MessageRole.user;
    // A failed or cancelled generation can leave an assistant message with
    // no text, reasoning, or metrics behind; rendering it would paint an
    // empty bubble shell next to the recovery banner. While streaming, the
    // bubble stays visible as the typing indicator.
    final hasContent =
        message.text.isNotEmpty ||
        (message.reasoning?.isNotEmpty ?? false) ||
        message.metrics != null;
    if (!isUser && !hasContent && !message.isStreaming) {
      return const SizedBox.shrink();
    }
    return Semantics(
      key: Key('message-${message.id}'),
      label: isUser ? 'You: ${message.text}' : 'Golem: ${message.text}',
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: () => _showActions(context, ref),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: math.min(
                MediaQuery.sizeOf(context).width * 0.82,
                _maxBubbleWidth,
              ),
            ),
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isUser
                  ? GolemTheme.userBubble
                  : CupertinoDynamicColor.resolve(
                      GolemTheme.assistantBubble,
                      context,
                    ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(24),
                topRight: const Radius.circular(24),
                bottomLeft: Radius.circular(isUser ? 24 : 6),
                bottomRight: Radius.circular(isUser ? 6 : 24),
              ),
              border: isUser
                  ? null
                  : Border.all(
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.divider,
                        context,
                      ),
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isUser && (message.reasoning?.isNotEmpty ?? false))
                  _ReasoningCard(
                    text: message.reasoning!,
                    streaming: message.isStreaming,
                  ),
                if (message.text.isNotEmpty)
                  SelectableText(
                    message.text,
                    style: TextStyle(
                      color: isUser
                          ? CupertinoColors.white
                          : CupertinoDynamicColor.resolve(
                              GolemTheme.ink,
                              context,
                            ),
                      height: 1.42,
                      fontSize: 16,
                    ),
                  ),
                if (message.isStreaming) ...[
                  const SizedBox(height: 10),
                  const CupertinoActivityIndicator(radius: 8),
                ],
                if (!isUser && message.metrics != null) ...[
                  const SizedBox(height: 12),
                  _MetricsPill(
                    metrics: message.metrics!,
                    live: message.isStreaming,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    // Editing is silently rejected by the controller while a generation is
    // in flight, so don't offer it — a Save that discards the user's edit is
    // worse than a missing menu entry.
    final idle =
        ref.read(chatControllerProvider).requireValue.generation ==
        GenerationPhase.idle;
    // Action handlers pop their own sheet route and then open follow-up
    // dialogs on the bubble context, which survives the pop.
    await showGolemActions(
      context: context,
      title: message.role == MessageRole.user
          ? 'Your message'
          : 'Golem response',
      actions: [
        GolemSheetAction(
          label: 'Copy',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: message.text));
            Navigator.pop(context);
          },
        ),
        if (message.role == MessageRole.user && idle)
          GolemSheetAction(
            label: 'Edit and retry',
            onPressed: () {
              Navigator.pop(context);
              _showEdit(context, ref);
            },
          ),
        if (message.role == MessageRole.assistant && canRegenerate)
          GolemSheetAction(
            label: 'Regenerate',
            onPressed: () {
              Navigator.pop(context);
              ref.read(chatControllerProvider.notifier).regenerate();
            },
          ),
      ],
    );
  }

  Future<void> _showEdit(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: message.text);
    await showGolemAlert(
      context: context,
      title: 'Edit message',
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(
          key: const Key('edit-message-field'),
          controller: controller,
          minLines: 2,
          maxLines: 5,
        ),
      ),
      actions: [
        GolemAlertAction(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        GolemAlertAction(
          key: const Key('edit-message-save'),
          label: 'Save and regenerate',
          onPressed: () {
            Navigator.pop(context);
            ref
                .read(chatControllerProvider.notifier)
                .editAndTruncate(message.id, controller.text);
          },
        ),
      ],
    );
    controller.dispose();
  }
}

class _ReasoningCard extends StatelessWidget {
  const _ReasoningCard({required this.text, required this.streaming});
  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('reasoning-card'),
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(
        GolemTheme.reasoningSurface,
        context,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: CupertinoDynamicColor.resolve(
          GolemTheme.reasoningBorder,
          context,
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              CupertinoIcons.lightbulb_fill,
              color: GolemTheme.amber,
              size: 16,
            ),
            const SizedBox(width: 7),
            Text(
              streaming ? 'Reasoning · LIVE' : 'Reasoning',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(text, style: const TextStyle(fontSize: 14, height: 1.38)),
      ],
    ),
  );
}

class _MetricsPill extends StatelessWidget {
  const _MetricsPill({required this.metrics, required this.live});
  final InferenceMetrics metrics;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('metrics-pill'),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(GolemTheme.accentSoft, context),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '${live ? 'LIVE · ' : ''}${metrics.decodeTokensPerSecond.toStringAsFixed(1)} tok/s  ·  ${metrics.tokenCount} tokens',
      style: TextStyle(
        color: CupertinoDynamicColor.resolve(GolemTheme.accent, context),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
