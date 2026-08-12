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
import '../../../l10n/l10n.dart';
import '../../settings/application/preferences_providers.dart';
import '../application/chat_providers.dart';
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

  final bool idle;

  /// Token count of a failed generation's partial answer; non-null only on the
  /// message the failure banner refers to. Ephemeral — nothing persists it.
  final int? stoppedTokens;

  /// Readable measure on wide desktop windows; a phone's 88% stays under it.
  static const _maxBubbleWidth = GolemSize.bubbleMaxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.role == MessageRole.user;
    // A failed or cancelled generation can leave an assistant message with
    // nothing in it; rendering it would paint an empty bubble shell next to
    // the recovery banner. While streaming it stays as the typing indicator.
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
                // Streaming reasoning is always live; settled cards follow the
                // appearance preference. A card opened by streaming latches
                // open when the run settles (see _ReasoningCardState).
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
                context.l10n.stoppedAfterTokens(stoppedTokens!),
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
      label: _semanticLabel(context, message, isUser: isUser),
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
            label: context.l10n.copyMessage,
            onPressed: () => _copy(context),
          ),
          if (canRegenerate)
            action(
              key: Key('message-regenerate-${message.id}'),
              icon: CupertinoIcons.arrow_clockwise,
              label: context.l10n.regenerateResponse,
              onPressed: () =>
                  ref.read(chatControllerProvider.notifier).regenerate(),
            ),
          action(
            key: Key('message-share-${message.id}'),
            icon: CupertinoIcons.square_arrow_up,
            label: context.l10n.shareMessage,
            onPressed: () => _share(context),
          ),
          GolemMenu(
            anchorKey: Key('message-menu-${message.id}'),
            triggerSemanticLabel: context.l10n.messageActions,
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
      label: context.l10n.copy,
      icon: CupertinoIcons.doc_on_doc,
      onPressed: () => _copy(context),
    ),
    if (canRegenerate)
      GolemMenuItem(
        itemKey: const Key('menu-message-regenerate'),
        label: context.l10n.regenerate,
        icon: CupertinoIcons.arrow_clockwise,
        onPressed: () => ref.read(chatControllerProvider.notifier).regenerate(),
      ),
    GolemMenuItem(
      itemKey: const Key('menu-message-branch'),
      label: context.l10n.branchFromHere,
      icon: CupertinoIcons.arrow_branch,
      onPressed: () => _branch(context, ref),
    ),
    GolemMenuItem(
      itemKey: const Key('menu-message-share'),
      label: context.l10n.share,
      icon: CupertinoIcons.square_arrow_up,
      onPressed: () => _share(context),
    ),
    GolemMenuItem(
      itemKey: const Key('menu-message-delete'),
      label: context.l10n.deleteMessage,
      icon: CupertinoIcons.trash,
      isDestructive: true,
      onPressed: () =>
          ref.read(chatControllerProvider.notifier).deleteMessage(message.id),
    ),
  ];

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.text));
    showGolemToast(context, context.l10n.copiedToClipboard);
  }

  Future<void> _branch(BuildContext context, WidgetRef ref) async {
    await ref.read(chatControllerProvider.notifier).branchFrom(message.id);
    if (context.mounted) {
      showGolemToast(context, context.l10n.newBranchStarted);
    }
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
    // The controller silently rejects mutating actions while a generation is
    // in flight, so don't offer them — a Save that discards the user's edit is
    // worse than a missing menu entry. Handlers pop their own sheet route and
    // open follow-ups on the bubble context, which survives the pop.
    await showGolemActions(
      context: context,
      title: message.role == MessageRole.user
          ? context.l10n.yourMessage
          : context.l10n.golemResponse,
      actions: [
        GolemSheetAction(
          label: context.l10n.copy,
          onPressed: () {
            Navigator.pop(context);
            _copy(context);
          },
        ),
        if (message.role == MessageRole.user && idle)
          GolemSheetAction(
            label: context.l10n.editAndRetry,
            onPressed: () {
              Navigator.pop(context);
              _showEdit(context, ref);
            },
          ),
        if (message.role == MessageRole.assistant && canRegenerate)
          GolemSheetAction(
            label: context.l10n.regenerate,
            onPressed: () {
              Navigator.pop(context);
              ref.read(chatControllerProvider.notifier).regenerate();
            },
          ),
        if (idle)
          GolemSheetAction(
            label: context.l10n.branchFromHere,
            onPressed: () {
              Navigator.pop(context);
              _branch(context, ref);
            },
          ),
        if (message.role == MessageRole.assistant)
          GolemSheetAction(
            label: context.l10n.share,
            onPressed: () {
              Navigator.pop(context);
              _share(context);
            },
          ),
        if (idle)
          GolemSheetAction(
            label: context.l10n.deleteMessage,
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
      title: context.l10n.editMessage,
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
          label: context.l10n.cancel,
          onPressed: () => Navigator.pop(context),
        ),
        GolemAlertAction(
          key: const Key('edit-message-save'),
          label: context.l10n.saveAndRegenerate,
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

  /// Whether the owning message is still streaming at all. The header's LIVE
  /// state, [streaming], ends earlier — when answer text starts.
  final bool live;
  final bool initiallyExpanded;

  @override
  State<_ReasoningCard> createState() => _ReasoningCardState();
}

class _ReasoningCardState extends State<_ReasoningCard> {
  // Collapsing a card is ephemeral presentation state, never persisted. Until
  // the user touches it the card follows [_ReasoningCard.initiallyExpanded]
  // reactively: preferences resolve a frame after cold start, and an
  // initial-only read would freeze on that pre-resolution frame.
  bool? _userToggle;
  bool get _expanded => _userToggle ?? widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant _ReasoningCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A card the stream opened stays open when the run settles — the reader
    // may be mid-thought. Latching only on the live→settled edge keeps
    // preference toggles reactive for every other card.
    if (oldWidget.live && !widget.live && _userToggle == null) {
      _userToggle = true;
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    // Its own node, or the whole card — header, thoughts, and the answer
    // below it — collapses into the bubble's long-press node as one
    // unreadable run.
    container: true,
    child: Container(
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
          // The disclosure is the row, not the chevron: labelling the glyph
          // alone left the control itself nameless, and its state readable
          // only as whichever arrow happened to be drawn.
          Semantics(
            key: const Key('reasoning-card-header'),
            container: true,
            button: true,
            label: widget.streaming
                ? context.l10n.reasoningLive
                : context.l10n.reasoning,
            value: _expanded ? context.l10n.expanded : context.l10n.collapsed,
            onTap: () => setState(() => _userToggle = !_expanded),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // The wrapper above owns the tap action; left in, this detector
              // adds a second, nameless tappable node over the same row.
              excludeFromSemantics: true,
              onTap: () => setState(() => _userToggle = !_expanded),
              child: ExcludeSemantics(
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
                        widget.streaming
                            ? context.l10n.reasoningLiveBadge
                            : context.l10n.reasoning,
                        style: GolemText.footnoteStrong,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      size: 14,
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.mutedInk,
                        context,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Text(widget.text, style: GolemText.footnote),
          ],
        ],
      ),
    ),
  );
}

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
              context.l10n.generatingAtRate(
                metrics.decodeTokensPerSecond.toStringAsFixed(1),
              ),
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
      context.l10n.tokenRateSummary(
        metrics.decodeTokensPerSecond.toStringAsFixed(1),
        metrics.tokenCount,
      ),
      style: GolemText.metrics.copyWith(
        color: CupertinoDynamicColor.resolve(GolemTheme.accent, context),
      ),
    ),
  );
}

/// Who is speaking, and whether a picture is present — prefixed onto the
/// bubble's own rendered text rather than restating it. Repeating the message
/// here read every answer twice, once from this label and once from the
/// Text below it.
String _semanticLabel(
  BuildContext context,
  ChatMessage message, {
  required bool isUser,
}) {
  final speaker = isUser
      ? context.l10n.userSpeaker
      : context.l10n.assistantSpeaker;
  final images = message.images.length;
  final picture = context.l10n.imageCountSentence(images);
  return '$speaker:$picture';
}

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
                      ? context.l10n.imageUnavailable
                      : context.l10n.loadingImage,
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
