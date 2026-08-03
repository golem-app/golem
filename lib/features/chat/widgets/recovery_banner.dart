import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';

class RecoveryBanner extends ConsumerWidget {
  const RecoveryBanner({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    key: const Key('recovery-banner'),
    margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(GolemTheme.errorSurface, context),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        const Icon(
          CupertinoIcons.exclamationmark_triangle_fill,
          color: GolemTheme.destructive,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
        CupertinoButton(
          key: const Key('retry-generation'),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onPressed: () =>
              ref.read(chatControllerProvider.notifier).retryFailure(),
          child: const Text('Retry'),
        ),
        CupertinoButton(
          key: const Key('discard-generation'),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onPressed: () =>
              ref.read(chatControllerProvider.notifier).discardFailure(),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
}
