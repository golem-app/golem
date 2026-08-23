import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/chrome/golem_tappable.dart';
import '../../../core/domain/app_state.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/presentation_messages.dart';
import '../../models/widgets/model_setup_banner.dart';
import 'attach_sheet.dart';
import 'composer.dart';
import 'empty_chat.dart';
import 'message_bubble.dart';
import 'persistence_recovery_banner.dart';
import 'recovery_banner.dart';

class ChatCanvas extends ConsumerWidget {
  const ChatCanvas({
    required this.chat,
    required this.composer,
    required this.focus,
    required this.scroll,
    required this.scrollToLatest,
    required this.onUserScroll,
    required this.onScrollMetrics,
    required this.onScrollSettled,
    required this.showJump,
    required this.tailSpacer,
    this.anchorKey,
    this.anchorId,
    this.picker = const AttachmentPicker(),
    super.key,
  });
  final ChatState chat;
  final TextEditingController composer;
  final FocusNode focus;
  final ScrollController scroll;
  final VoidCallback scrollToLatest;
  final ValueChanged<ScrollDirection> onUserScroll;
  final VoidCallback onScrollMetrics;
  final VoidCallback onScrollSettled;
  final bool showJump;

  /// Height of the trailing spacer. Sized so the anchored question sits at
  /// the top of the viewport; zero once its turn is taller than one screen,
  /// and zero in every transcript nobody has sent into. Listened to rather
  /// than passed by value so a delta resizes the list and nothing else.
  final ValueListenable<double> tailSpacer;

  /// Identifies the anchored message and carries the key the screen measures
  /// it through. Null until the reader sends something.
  final GlobalKey? anchorKey;
  final String? anchorId;
  final AttachmentPicker picker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = chat.active;
    final hasMessages = active != null && active.messages.isNotEmpty;
    final refusal = ref.watch(deviceRefusalProvider);
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              if (!hasMessages)
                EmptyChat(
                  onStarter: (prompt) {
                    composer.text = prompt;
                    composer.selection = TextSelection.collapsed(
                      offset: prompt.length,
                    );
                    focus.requestFocus();
                  },
                )
              else
                // Depth 0 only, on all three: a code card and the reasoning
                // peek are scrollables of their own inside these bubbles, and
                // their notifications bubble up here. Left ungated, dragging
                // a wide code line sideways decides the transcript's
                // follow state.
                NotificationListener<UserScrollNotification>(
                  onNotification: (notification) {
                    if (notification.depth == 0) {
                      onUserScroll(notification.direction);
                    }
                    return false;
                  },
                  // Content growth changes the metrics without a scroll — the
                  // only signal while detached from a streaming tail.
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (notification) {
                      if (notification.depth == 0) onScrollMetrics();
                      return false;
                    },
                    child: NotificationListener<ScrollEndNotification>(
                      onNotification: (notification) {
                        if (notification.depth == 0) onScrollSettled();
                        return false;
                      },
                      child: ValueListenableBuilder<double>(
                        valueListenable: tailSpacer,
                        builder: (context, spacer, _) => ListView.builder(
                          key: const Key('message-list'),
                          controller: scroll,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          // One trailing item, the anchor spacer: it holds the
                          // question the reader just asked at the top of the
                          // viewport while its answer streams in underneath.
                          // Present only when it has a height to contribute — a
                          // zero-height trailing child still costs the delegate
                          // an averaged estimate, and a transcript nobody has
                          // sent into scrolled by that estimate on load.
                          itemCount:
                              active.messages.length + (spacer > 0 ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == active.messages.length) {
                              return SizedBox(height: spacer);
                            }
                            final message = active.messages[index];
                            final isLast = index == active.messages.length - 1;
                            return MessageBubble(
                              key: message.id == anchorId ? anchorKey : null,
                              message: message,
                              canRegenerate:
                                  isLast &&
                                  chat.generation == GenerationPhase.idle,
                              idle: chat.generation == GenerationPhase.idle,
                              stoppedTokens:
                                  isLast &&
                                      chat.generation ==
                                          GenerationPhase.failed &&
                                      message.role == MessageRole.assistant
                                  ? message.metrics?.tokenCount
                                  : null,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              // A stale flag from a previous conversation must not leave a
              // dead control with no tail to jump to.
              if (showJump && hasMessages)
                PositionedDirectional(
                  bottom: 10,
                  end: 18,
                  child: Semantics(
                    button: true,
                    label: context.l10n.jumpToLatest,
                    child: GolemTappable(
                      key: const Key('jump-to-latest'),
                      padding: EdgeInsets.zero,
                      onPressed: scrollToLatest,
                      child: const Glass(
                        radius: 22,
                        floating: true,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(CupertinoIcons.arrow_down, size: 20),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (chat.persistencePhase != ChatPersistencePhase.idle)
          PersistenceRecoveryBanner(phase: chat.persistencePhase),
        if (chat.failure != null)
          RecoveryBanner(failure: chat.failure!)
        // The empty state carries this copy until the first message; once a
        // refused turn is on screen it would otherwise vanish behind a
        // dismissed banner, leaving an unanswered message and no explanation
        // (#27). Exactly one of the three is ever on screen.
        else if (hasMessages && refusal != null)
          _DeviceRefusalNotice(
            message: deviceRefusalMessage(context.l10n, refusal),
          ),
        if (chat.failure == null && refusal == null) const ModelSetupBanner(),
        Composer(
          picker: picker,
          controller: composer,
          focus: focus,
          reasoningEnabled: active?.reasoningEnabled ?? false,
          generation: chat.generation,
          activeId: active?.id,
        ),
      ],
    );
  }
}

/// The standing explanation on a device that can never run a model: the same
/// sentence the empty state shows, in the one place a populated transcript
/// leaves for it. Deliberately not an error surface — nothing failed here, the
/// hardware simply is what it is.
class _DeviceRefusalNotice extends StatelessWidget {
  const _DeviceRefusalNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('device-unsupported-notice'),
    margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(GolemTheme.surface, context),
      borderRadius: BorderRadius.circular(GolemRadius.notice),
      border: Border.all(
        color: CupertinoDynamicColor.resolve(GolemTheme.divider, context),
      ),
    ),
    child: Text(
      message,
      style: GolemText.footnote.copyWith(
        color: CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context),
      ),
    ),
  );
}
