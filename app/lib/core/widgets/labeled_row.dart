import 'package:flutter/cupertino.dart';

import '../theme/golem_theme.dart';

/// Label on the left, muted value on the right; the value wraps instead of
/// overflowing when it is long.
class LabeledRow extends StatelessWidget {
  const LabeledRow({required this.label, required this.value, super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(label)),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: TextStyle(
            color: CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context),
          ),
        ),
      ),
    ],
  );
}
