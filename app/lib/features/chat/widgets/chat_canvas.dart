import 'package:flutter/cupertino.dart';
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
    required this.showJump,
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
  final bool showJump;
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
                NotificationListener<UserScrollNotification>(
                  onNotification: (notification) {
                    onUserScroll(notification.direction);
                    return false;
                  },
                  // Content growth changes the metrics without a scroll — the
                  // only signal while detached from a streaming tail.
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
            message: deviceRefusalMessage(
              context.l10n,
              ref.watch(deviceEligibilityProvider).reason,
            ),
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
