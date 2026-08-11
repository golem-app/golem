import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/chrome/golem_chrome.dart';
import '../../../core/domain/app_state.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';

/// Non-blocking recovery for a live chat session whose durable snapshot is
/// stale. This is separate from generation recovery because saving history
/// must never modify, retry, or discard an inference turn.
class PersistenceRecoveryBanner extends ConsumerWidget {
  const PersistenceRecoveryBanner({required this.phase, super.key});

  final ChatPersistencePhase phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final retrying = phase == ChatPersistencePhase.retrying;
    final target = GolemChrome.current.minimumTapTarget;
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
          child: const Text(
            'Chat history isn’t saving. Your latest changes could be '
            'lost when you close the app.',
            style: GolemText.footnote,
          ),
        ),
      ),
    ];

    Widget retryButton() => CupertinoButton(
      key: const Key('retry-chat-persistence'),
      minimumSize: Size(target, target),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      onPressed: retrying
          ? null
          : () => ref.read(chatControllerProvider.notifier).retryPersistence(),
      child: retrying
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(child: CupertinoActivityIndicator(radius: 8)),
                SizedBox(width: 6),
                Text('Saving…'),
              ],
            )
          : const Text('Try again'),
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
