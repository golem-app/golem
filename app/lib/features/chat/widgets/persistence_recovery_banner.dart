import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/chrome/golem_tappable.dart';
import '../../../core/domain/app_state.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../l10n/l10n.dart';
import '../application/chat_providers.dart';

/// Non-blocking recovery for a live chat session whose durable snapshot is
/// stale. This is separate from generation recovery because saving history
/// must never modify, retry, or discard an inference turn.
class PersistenceRecoveryBanner extends ConsumerWidget {
  const PersistenceRecoveryBanner({
    required this.phase,
    this.historyRecovered = false,
    super.key,
  });

  final ChatPersistencePhase phase;

  /// The read-side notice. A write failure outranks it while one stands —
  /// that one has an action — and it returns once the write recovers.
  final bool historyRecovered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final retrying = phase == ChatPersistencePhase.retrying;
    final recovered = historyRecovered && phase == ChatPersistencePhase.idle;
    List<Widget> messageChildren() => [
      const ExcludeSemantics(
        child: Icon(
          CupertinoIcons.exclamationmark_triangle_fill,
          color: GolemTheme.amber,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Semantics(
          liveRegion: true,
          child: Text(
            recovered
                ? context.l10n.chatHistoryPartlyUnreadable
                : context.l10n.chatHistoryNotSaving,
            style: GolemText.footnote,
          ),
        ),
      ),
    ];

    // The read-side notice has nothing to retry: the loss already happened,
    // so its only affordance is to be put away.
    Widget retryButton() => GolemTappable(
      key: Key(recovered ? 'dismiss-chat-recovery' : 'retry-chat-persistence'),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      onPressed: retrying
          ? null
          : () {
              final controller = ref.read(chatControllerProvider.notifier);
              if (recovered) {
                controller.acknowledgeRecovery();
              } else {
                unawaited(controller.retryPersistence());
              }
            },
      child: recovered
          ? Text(context.l10n.done)
          : retrying
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ExcludeSemantics(
                  child: CupertinoActivityIndicator(radius: 8),
                ),
                const SizedBox(width: 6),
                Text(context.l10n.saving),
              ],
            )
          : Text(context.l10n.tryAgain),
    );

    return Semantics(
      container: true,
      child: Container(
        key: const Key('chat-persistence-banner'),
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        padding: const EdgeInsets.all(12),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 340) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: messageChildren()),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: retryButton(),
                  ),
                ],
              );
            }
            return Row(children: [...messageChildren(), retryButton()]);
          },
        ),
      ),
    );
  }
}
