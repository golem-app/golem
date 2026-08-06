import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/app_state.dart';
import '../../../core/domain/models.dart';
import '../../../core/theme/golem_theme.dart';
import 'composer.dart';
import 'empty_chat.dart';
import 'message_bubble.dart';
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
    required this.showJump,
    super.key,
  });
  final ChatState chat;
  final TextEditingController composer;
  final FocusNode focus;
  final ScrollController scroll;
  final VoidCallback scrollToLatest;
  final ValueChanged<ScrollDirection> onUserScroll;
  final VoidCallback onScrollMetrics;
  final bool showJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = chat.active;
    final hasMessages = active != null && active.messages.isNotEmpty;
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
                NotificationListener<UserScrollNotification>(
                  onNotification: (notification) {
                    onUserScroll(notification.direction);
                    return false;
                  },
                  // Content growth changes the metrics without a scroll,
                  // which is the only signal while the user is detached
                  // from a streaming tail.
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (notification) {
                      onScrollMetrics();
                      return false;
                    },
                    child: ListView.builder(
                      key: const Key('message-list'),
                      controller: scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      itemCount: active.messages.length,
                      itemBuilder: (context, index) {
                        final message = active.messages[index];
                        final isLast = index == active.messages.length - 1;
                        return MessageBubble(
                          message: message,
                          canRegenerate:
                              isLast && chat.generation == GenerationPhase.idle,
                          idle: chat.generation == GenerationPhase.idle,
                          stoppedTokens:
                              isLast &&
                                  chat.generation == GenerationPhase.failed &&
                                  message.role == MessageRole.assistant
                              ? message.metrics?.tokenCount
                              : null,
                        );
                      },
                    ),
                  ),
                ),
              // Without messages there is no tail to jump to; a stale flag
              // from a previous conversation must not leave a dead control.
              if (showJump && hasMessages)
                Positioned(
                  bottom: 10,
                  right: 18,
                  child: Semantics(
                    button: true,
                    label: 'Jump to latest message',
                    child: CupertinoButton(
                      key: const Key('jump-to-latest'),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 44),
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
        if (chat.failure != null)
          RecoveryBanner(
            message: chat.failure!,
            missingModelArtifactKey: chat.missingModelArtifactKey,
          ),
        Composer(
          controller: composer,
          focus: focus,
          reasoningEnabled: active?.reasoningEnabled ?? false,
          generation: chat.generation,
          activeId: active?.id,
          modelKey: active?.modelKey,
        ),
      ],
    );
  }
}
