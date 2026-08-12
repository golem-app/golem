import 'package:flutter/cupertino.dart';

import '../chrome/golem_button.dart';
import '../theme/golem_theme.dart';

/// The one read-failure surface: fixed copy (raw exception text never
/// reaches a screen, §8.1) and a retry that re-runs the failed read.
class RetryPane extends StatelessWidget {
  const RetryPane({
    required this.message,
    required this.actionLabel,
    required this.onRetry,
    super.key,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.exclamationmark_triangle, color: muted),
            const SizedBox(height: 12),
            Text(
              message,
              style: GolemText.body.copyWith(color: muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GolemButton.filled(
              label: actionLabel,
              onPressed: onRetry,
              expand: false,
            ),
          ],
        ),
      ),
    );
  }
}
