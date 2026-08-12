import 'package:flutter/cupertino.dart';

import '../../core/theme/golem_theme.dart';
import '../../l10n/l10n.dart';

/// The same plain-language limitation appears before setup and beside the
/// model controls, so it is visible at both first use and everyday use.
class AiDisclaimer extends StatelessWidget {
  const AiDisclaimer({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.aiDisclaimer,
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
            GolemTheme.reasoningSurface,
            context,
          ),
          borderRadius: BorderRadius.circular(GolemRadius.field),
          border: Border.all(
            color: CupertinoDynamicColor.resolve(
              GolemTheme.reasoningBorder,
              context,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              size: 18,
              color: GolemTheme.amber,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(context.l10n.aiDisclaimer, style: GolemText.footnote),
            ),
          ],
        ),
      ),
    ),
  );
}
