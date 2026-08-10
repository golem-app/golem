import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/chrome/golem_alert.dart';
import '../../../core/chrome/golem_menu.dart';
import '../../../core/chrome/golem_sheet.dart';
import '../../../core/chrome/golem_toast.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';
import 'markdown/golem_markdown.dart';

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    required this.message,
    required this.canRegenerate,
    required this.idle,
    this.stoppedTokens,
    super.key,
  });
  final ChatMessage message;
  final bool canRegenerate;

  /// Whether generation is idle; actions render only on a settled chat.
  final bool idle;

  /// Token count of a failed generation's partial answer; non-null only
  /// on the message the failure banner refers to. Ephemeral by design —
  /// nothing persists a failure marker.
  final int? stoppedTokens;

  /// Readable measure for a bubble on wide desktop windows; phone layouts
  /// never reach it (88% of a phone viewport stays below the cap).
  static const _maxBubbleWidth = GolemSize.bubbleMaxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.role == MessageRole.user;
    // A failed or cancelled generation can leave an assistant message with
    // no text, reasoning, or metrics behind; rendering it would paint an
    // empty bubble shell next to the recovery banner. While streaming, the
    // bubble stays visible as the typing indicator.
    final hasContent =
        message.text.isNotEmpty ||
        message.hasImages ||
        (message.reasoning?.isNotEmpty ?? false) ||
        message.metrics != null;
    if (!isUser && !hasContent && !message.isStreaming) {
      return const SizedBox.shrink();
    }
    final bubble = GestureDetector(
      onLongPress: () => _showActions(context, ref),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: math.min(
            MediaQuery.sizeOf(context).width * GolemSize.bubbleMaxFraction,
            _maxBubbleWidth,
          ),
        ),
        padding: const EdgeInsets.all(18),
        // Every corner equally round — no tails, per the handoff.
        decoration: BoxDecoration(
          color: isUser
              ? GolemTheme.userBubble
              : CupertinoDynamicColor.resolve(
                  GolemTheme.assistantBubble,
                  context,
                ),
          borderRadius: BorderRadius.circular(
            isUser ? GolemRadius.bubble : GolemRadius.bubbleAssistant,
          ),
          border: isUser
              ? null
              : Border.all(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.divider,
                    context,
                  ),
                ),
          boxShadow: isUser ? null : GolemShadow.card(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && (message.reasoning?.isNotEmpty ?? false))
              _ReasoningCard(
                text: message.reasoning!,
                streaming: message.isStreaming && message.text.isEmpty,
                live: message.isStreaming,
                // Streaming reasoning is always shown live; settled cards
                // start collapsed unless the appearance preference says
                // otherwise. A card opened by streaming latches open when
                // the run settles (see _ReasoningCardState).
                initiallyExpanded:
                    message.isStreaming ||
                    (ref
                            .watch(preferencesControllerProvider)
                            .value
                            ?.expandReasoning ??
                        false),
              ),
            // Images sit above the text, the order a vision prompt uses.
            for (final image in message.images)
              Padding(
                padding: EdgeInsets.only(bottom: message.text.isEmpty ? 0 : 8),
                child: _AttachedImage(image: image),
              ),
            if (isUser && message.text.isNotEmpty)
              Text(
                message.text,
                style: GolemText.body.copyWith(color: GolemTheme.textOnDark),
              )
            else if (!isUser &&
                (message.text.isNotEmpty || message.isStreaming))
              DefaultTextStyle.merge(
                style: GolemText.body.copyWith(
                  color: CupertinoDynamicColor.resolve(GolemTheme.ink, context),
                ),
                child: GolemMarkdown(
                  text: message.text,
                  streaming: message.isStreaming,
                ),
              ),
            if (stoppedTokens != null) ...[
              const SizedBox(height: 8),
              Text(
                'Stopped after $stoppedTokens tokens',
                key: const Key('stopped-caption'),
                style: GolemText.caption.copyWith(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                ),
              ),
            ],
            if (!isUser && message.metrics != null) ...[
              // The generating pill is streaming status and always shows;
              // the settled chip is what the appearance toggle hides.
              if (message.isStreaming) ...[
                const SizedBox(height: 12),
                _GeneratingPill(metrics: message.metrics!),
              ] else if (ref
                      .watch(preferencesControllerProvider)
                      .value
                      ?.showMetrics ??
                  true) ...[
                const SizedBox(height: 12),
                _MetricsPill(metrics: message.metrics!),
              ],
            ],
          ],
        ),
      ),
    );
    return Semantics(
      key: Key('message-${message.id}'),
      label: _semanticLabel(message, isUser: isUser),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: bubble,
            ),
            if (!isUser && idle && hasContent) _actionRow(context, ref),
          ],
        ),
      ),
    );
  }

  /// The ghost action row under a settled assistant message: copy,
  /// regenerate (tail only), share, and the anchored overflow menu.
  Widget _actionRow(BuildContext context, WidgetRef ref) {
    final tint = CupertinoDynamicColor.resolve(GolemTheme.tertiaryInk, context);
    Widget action({
      required Key key,
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
    }) => CupertinoButton(
      key: key,
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: Icon(icon, size: 18, color: tint, semanticLabel: label),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          action(
            key: Key('message-copy-${message.id}'),
            icon: CupertinoIcons.doc_on_doc,
            label: 'Copy message',
            onPressed: () => _copy(context),
          ),
          if (canRegenerate)
            action(
              key: Key('message-regenerate-${message.id}'),
              icon: CupertinoIcons.arrow_clockwise,
              label: 'Regenerate response',
              onPressed: () =>
                  ref.read(chatControllerProvider.notifier).regenerate(),
            ),
          action(
            key: Key('message-share-${message.id}'),
            icon: CupertinoIcons.square_arrow_up,
            label: 'Share message',
            onPressed: () => _share(context),
          ),
          GolemMenu(
            anchorKey: Key('message-menu-${message.id}'),
            triggerSemanticLabel: 'Message actions',
            triggerColor: tint,
            items: _menuItems(context, ref),
          ),
        ],
      ),
    );
  }

  List<GolemMenuItem> _menuItems(BuildContext context, WidgetRef ref) => [
    GolemMenuItem(
      itemKey: const Key('menu-message-copy'),
      label: 'Copy',
      icon: CupertinoIcons.doc_on_doc,
      onPressed: () => _copy(context),
    ),
    if (canRegenerate)
      GolemMenuItem(
        itemKey: const Key('menu-message-regenerate'),
        label: 'Regenerate',
        icon: CupertinoIcons.arrow_clockwise,
        onPressed: () => ref.read(chatControllerProvider.notifier).regenerate(),
      ),
    GolemMenuItem(
      itemKey: const Key('menu-message-branch'),
      label: 'Branch from here',
      icon: CupertinoIcons.arrow_branch,
      onPressed: () => _branch(context, ref),
    ),
    GolemMenuItem(
      itemKey: const Key('menu-message-share'),
      label: 'Share',
      icon: CupertinoIcons.square_arrow_up,
      onPressed: () => _share(context),
    ),
    GolemMenuItem(
      itemKey: const Key('menu-message-delete'),
      label: 'Delete message',
      icon: CupertinoIcons.trash,
      isDestructive: true,
      onPressed: () =>
          ref.read(chatControllerProvider.notifier).deleteMessage(message.id),
    ),
  ];

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.text));
    showGolemToast(context, 'Copied to clipboard');
  }

  Future<void> _branch(BuildContext context, WidgetRef ref) async {
    await ref.read(chatControllerProvider.notifier).branchFrom(message.id);
    if (context.mounted) showGolemToast(context, 'New branch started');
  }

  Future<void> _share(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: message.text,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    // Mutating actions are silently rejected by the controller while a
    // generation is in flight, so don't offer them — a Save that discards
    // the user's edit is worse than a missing menu entry.
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
            Navigator.pop(context);
            _copy(context);
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
        if (idle)
          GolemSheetAction(
            label: 'Branch from here',
            onPressed: () {
              Navigator.pop(context);
              _branch(context, ref);
            },
          ),
        if (message.role == MessageRole.assistant)
          GolemSheetAction(
            label: 'Share',
            onPressed: () {
              Navigator.pop(context);
              _share(context);
            },
          ),
        if (idle)
          GolemSheetAction(
            label: 'Delete message',
            isDestructive: true,
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(chatControllerProvider.notifier)
                  .deleteMessage(message.id);
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

class _ReasoningCard extends StatefulWidget {
  const _ReasoningCard({
    required this.text,
    required this.streaming,
    required this.live,
    required this.initiallyExpanded,
  });
  final String text;
  final bool streaming;

  /// Whether the owning message is still streaming at all (the reasoning
  /// header's LIVE state, [streaming], ends earlier — when answer text
  /// starts).
  final bool live;
  final bool initiallyExpanded;

  @override
  State<_ReasoningCard> createState() => _ReasoningCardState();
}

class _ReasoningCardState extends State<_ReasoningCard> {
  // Widget-local disclosure: collapsing a reasoning card is ephemeral
  // presentation state, never persisted. Until the user touches the
  // card it follows [_ReasoningCard.initiallyExpanded] reactively —
  // preferences resolve a frame after cold start, and an initial-only
  // read would freeze on that pre-resolution frame.
  bool? _userToggle;
  bool get _expanded => _userToggle ?? widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant _ReasoningCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A card the stream opened stays open when the run settles — the
    // reader may be mid-thought. Latching only on the live→settled edge
    // keeps preference toggles reactive for every other card.
    if (oldWidget.live && !widget.live && _userToggle == null) {
      _userToggle = true;
    }
  }

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
      borderRadius: BorderRadius.circular(GolemRadius.notice),
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
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _userToggle = !_expanded),
          child: Row(
            children: [
              const Icon(
                CupertinoIcons.lightbulb_fill,
                color: GolemTheme.amber,
                size: 16,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.streaming ? 'Reasoning · LIVE' : 'Reasoning',
                  style: GolemText.footnoteStrong,
                ),
              ),
              Icon(
                _expanded
                    ? CupertinoIcons.chevron_up
                    : CupertinoIcons.chevron_down,
                size: 14,
                semanticLabel: _expanded
                    ? 'Collapse reasoning'
                    : 'Expand reasoning',
                color: CupertinoDynamicColor.resolve(
                  GolemTheme.mutedInk,
                  context,
                ),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          Text(widget.text, style: GolemText.footnote),
        ],
      ],
    ),
  );
}

/// The live "Generating · 26.8 tok/s" pill with its blinking dot.
class _GeneratingPill extends StatelessWidget {
  const _GeneratingPill({required this.metrics});
  final InferenceMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoDynamicColor.resolve(GolemTheme.accent, context);
    return Container(
      key: const Key('generating-pill'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(GolemTheme.accentSoft, context),
        borderRadius: BorderRadius.circular(GolemRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BlinkDot(color: accent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Generating · '
              '${metrics.decodeTokensPerSecond.toStringAsFixed(1)} tok/s',
              style: GolemText.metrics.copyWith(color: accent),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlinkDot extends StatefulWidget {
  const _BlinkDot({required this.color});
  final Color color;

  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _controller.drive(Tween(begin: 0.35, end: 1)),
    child: Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}

class _MetricsPill extends StatelessWidget {
  const _MetricsPill({required this.metrics});
  final InferenceMetrics metrics;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('metrics-pill'),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(GolemTheme.accentSoft, context),
      borderRadius: BorderRadius.circular(GolemRadius.pill),
    ),
    child: Text(
      '${metrics.decodeTokensPerSecond.toStringAsFixed(1)} tok/s  ·  ${metrics.tokenCount} tokens',
      style: GolemText.metrics.copyWith(
        color: CupertinoDynamicColor.resolve(GolemTheme.accent, context),
      ),
    ),
  );
}

/// The accessible name for a bubble. Images are announced by count so a
/// screen reader says a picture is present instead of skipping it.
String _semanticLabel(ChatMessage message, {required bool isUser}) {
  final speaker = isUser ? 'You' : 'Golem';
  final images = message.images.length;
  final picture = switch (images) {
    0 => '',
    1 => '1 image. ',
    _ => '$images images. ',
  };
  return '$speaker: $picture${message.text}';
}

/// One attached image inside a bubble, loaded from the app-owned store.
///
/// A message can outlive its bytes if the OS trims the container, so a missing
/// attachment renders a labelled placeholder rather than a broken box.
class _AttachedImage extends ConsumerStatefulWidget {
  const _AttachedImage({required this.image});

  final ImagePart image;

  @override
  ConsumerState<_AttachedImage> createState() => _AttachedImageState();
}

class _AttachedImageState extends ConsumerState<_AttachedImage> {
  late Future<Uint8List?> _bytes = _read();

  Future<Uint8List?> _read() async {
    final bytes = await ref
        .read(attachmentRepositoryProvider)
        .read(widget.image.attachmentId);
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  void didUpdateWidget(covariant _AttachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.attachmentId != widget.image.attachmentId) {
      _bytes = _read();
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final aspect = image.height == 0 ? 1.0 : image.width / image.height;
    return ClipRRect(
      borderRadius: BorderRadius.circular(GolemRadius.field),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: AspectRatio(
          aspectRatio: aspect <= 0 ? 1 : aspect,
          child: FutureBuilder<Uint8List?>(
            future: _bytes,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return Semantics(
                  label: snapshot.connectionState == ConnectionState.done
                      ? 'Image is no longer available'
                      : 'Loading image',
                  child: ColoredBox(
                    color: CupertinoDynamicColor.resolve(
                      GolemTheme.divider,
                      context,
                    ),
                    child: snapshot.connectionState == ConnectionState.done
                        ? Center(
                            child: Icon(
                              CupertinoIcons.photo,
                              color: CupertinoDynamicColor.resolve(
                                GolemTheme.mutedInk,
                                context,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                );
              }
              return Image.memory(
                bytes,
                key: Key('message-image-${image.attachmentId}'),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              );
            },
          ),
        ),
      ),
    );
  }
}
