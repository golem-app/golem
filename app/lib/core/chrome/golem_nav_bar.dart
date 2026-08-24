import 'package:flutter/cupertino.dart';

import '../../l10n/bidi.dart';
import '../../l10n/l10n.dart';
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
        ? _ContentDirectedText(title)
        : Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: GolemChrome.current == GolemChrome.android
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              _ContentDirectedText(
                title,
                // Two-line bars have a fixed 44pt content slot. A compact
                // leading keeps Arabic's taller system glyphs inside it.
                style: GolemText.title.copyWith(height: 1.15),
              ),
              Builder(
                // Resolved against the bar's context: the raw dynamic color
                // would collapse to its light variant on the dark bar.
                builder: (context) => _ContentDirectedText(
                  subtitle,
                  style: GolemText.caption.copyWith(
                    height: 1.15,
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
      return Align(alignment: AlignmentDirectional.centerStart, child: text);
    }
    return text;
  }
}

/// Resolves only the title glyph run by its content. The navigation bar and
/// its directional leading/trailing controls keep the app locale direction.
class _ContentDirectedText extends StatelessWidget {
  const _ContentDirectedText(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textDirection: contentTextDirection(
      text,
      fallback: Directionality.of(context),
    ),
    style: style,
  );
}

/// Android chrome's always-visible back affordance. Renders nothing when
/// the route has nowhere to pop to.
class GolemBackButton extends StatelessWidget {
  const GolemBackButton({this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (onPressed == null && (route == null || !route.canPop)) {
      return const SizedBox.shrink();
    }
    final target = GolemChrome.current.minimumTapTarget;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size(target, target),
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      child: Icon(
        CupertinoIcons.back,
        semanticLabel: context.l10n.back,
        size: 24,
      ),
    );
  }
}
