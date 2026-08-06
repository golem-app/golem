import 'package:flutter/cupertino.dart';

import '../theme/golem_theme.dart';
import 'golem_chrome.dart';

/// The adaptive navigation bar: a configured [CupertinoNavigationBar], so
/// the scaffold obstruction contract and the dynamic bar background keep
/// working unchanged. Cupertino centers the title and implies the `‹`
/// back affordance; Android left-aligns the title (with an optional
/// subtitle line) behind an always-visible back arrow.
class GolemNavBar extends CupertinoNavigationBar {
  GolemNavBar({
    required String title,
    String? subtitle,
    Widget? leading,
    String? previousPageTitle,
    super.trailing,
    super.backgroundColor,
    super.key,
  }) : super(
         automaticallyImplyLeading:
             GolemChrome.current == GolemChrome.cupertino,
         previousPageTitle: GolemChrome.current == GolemChrome.cupertino
             ? previousPageTitle
             : null,
         leading:
             leading ??
             (GolemChrome.current == GolemChrome.android
                 ? const GolemBackButton()
                 : null),
         middle: _middle(title, subtitle),
       );

  static Widget _middle(String title, String? subtitle) {
    final Widget text = subtitle == null
        ? Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: GolemChrome.current == GolemChrome.android
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Builder(
                // Resolved against the bar's context: the raw dynamic color
                // would collapse to its light variant on the dark bar.
                builder: (context) => Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GolemText.caption.copyWith(
                    color: CupertinoDynamicColor.resolve(
                      GolemTheme.mutedInk,
                      context,
                    ),
                  ),
                ),
              ),
            ],
          );
    if (GolemChrome.current == GolemChrome.android) {
      return Align(alignment: Alignment.centerLeft, child: text);
    }
    return text;
  }
}

/// Android chrome's always-visible back affordance. Renders nothing when
/// the route has nowhere to pop to.
class GolemBackButton extends StatelessWidget {
  const GolemBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null || !route.canPop) return const SizedBox.shrink();
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: () => Navigator.of(context).maybePop(),
      child: const Icon(
        CupertinoIcons.arrow_left,
        semanticLabel: 'Back',
        size: 24,
      ),
    );
  }
}
