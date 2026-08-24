import 'package:flutter/cupertino.dart';

import '../theme/golem_theme.dart';
import '../../l10n/l10n.dart';

/// Screen section heading with an optional muted subtitle, announced as a
/// header to assistive technology.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.subtitle, super.key});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizedUppercase(title, locale),
            style: localizedLabelStyle(GolemText.overline, locale).copyWith(
              color: CupertinoDynamicColor.resolve(
                GolemTheme.mutedInk,
                context,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: GolemText.footnote.copyWith(
                color: CupertinoDynamicColor.resolve(
                  GolemTheme.mutedInk,
                  context,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
