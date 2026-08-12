import 'package:flutter/cupertino.dart';

import '../../l10n/l10n.dart';
import '../theme/golem_theme.dart';

/// The small uppercase accent chip — `DEFAULT`, `ACTIVE`, `RECOMMENDED`.
/// Shared because first run and the chat model picker both label a row this
/// way, and two copies drifted by a padding point the moment there were two.
class GolemBadge extends StatelessWidget {
  const GolemBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(GolemTheme.accentSoft, context),
      borderRadius: BorderRadius.circular(GolemRadius.badge),
    ),
    child: Text(
      label,
      style:
          localizedLabelStyle(
            GolemText.badge,
            Localizations.localeOf(context),
          ).copyWith(
            color: CupertinoDynamicColor.resolve(GolemTheme.accent, context),
          ),
    ),
  );
}
