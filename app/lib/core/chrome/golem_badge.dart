import 'package:flutter/cupertino.dart';

import '../../l10n/l10n.dart';
import '../theme/golem_theme.dart';

/// The small uppercase chip — `DEFAULT`, `ACTIVE`, `RECOMMENDED`, `LOADED`.
///
/// Shared because first run, the chat model picker and the Settings model card
/// all label a row this way, and the copies drifted by a padding point the
/// moment there were two — which is what the Settings one had already done by
/// the time it was folded back in (#131).
class GolemBadge extends StatelessWidget {
  /// The accent badge: what this row *is*.
  const GolemBadge({required this.label, super.key}) : _emphasized = true;

  /// The quiet badge, for a second fact on a row that already carries one.
  const GolemBadge.quiet({required this.label, super.key})
    : _emphasized = false;

  final String label;
  final bool _emphasized;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(
        _emphasized ? GolemTheme.accentSoft : GolemTheme.fillQuiet,
        context,
      ),
      borderRadius: BorderRadius.circular(GolemRadius.badge),
    ),
    child: Text(
      label,
      style:
          localizedLabelStyle(
            GolemText.badge,
            Localizations.localeOf(context),
          ).copyWith(
            color: _emphasized
                ? CupertinoDynamicColor.resolve(GolemTheme.accent, context)
                : null,
          ),
    ),
  );
}
