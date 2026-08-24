import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';

import '../theme/golem_theme.dart';
import 'golem_chrome.dart';

OverlayEntry? _currentToast;
Timer? _dismissTimer;

/// A transient confirmation ("Copied to clipboard", "Pinned").
///
/// One design, two chromes: a floating navy pill bottom-center on
/// cupertino, a full-width navy bar on android. Plain confirmations only
/// — no actions — so behavior stays identical across platforms. A new
/// toast replaces the previous one; each dismisses itself after 1.5 s.
void showGolemToast(BuildContext context, String message) {
  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) return;

  _dismissTimer?.cancel();
  _currentToast?.remove();

  // The pill is a non-interactive overlay that removes itself after 1.5 s, so
  // a screen reader would never reach it by exploration. Every confirmation
  // this carries — copied, deleted, pinned, and the save failures — is only
  // ever said once, here.
  SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    Directionality.of(context),
  );

  final entry = OverlayEntry(
    builder: (context) => _GolemToast(message: message),
  );
  _currentToast = entry;
  overlay.insert(entry);
  _dismissTimer = Timer(const Duration(milliseconds: 1500), () {
    if (_currentToast == entry) {
      _currentToast = null;
      entry.remove();
    }
  });
}

final class _GolemToast extends StatefulWidget {
  const _GolemToast({required this.message});
  final String message;

  @override
  State<_GolemToast> createState() => _GolemToastState();
}

final class _GolemToastState extends State<_GolemToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final android = GolemChrome.current == GolemChrome.android;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final toast = DecoratedBox(
      decoration: BoxDecoration(
        color: GolemTheme.toastSurface,
        borderRadius: BorderRadius.circular(android ? 6 : GolemRadius.pill),
        boxShadow: GolemShadow.menu,
      ),
      child: Padding(
        padding: android
            ? const EdgeInsets.symmetric(horizontal: 18, vertical: 15)
            : const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Text(
          widget.message,
          style: (android ? GolemText.footnote : GolemText.footnoteStrong)
              .copyWith(inherit: false, color: GolemTheme.textOnDark),
        ),
      ),
    );
    return Positioned(
      left: android ? GolemSpace.gutter : 0,
      right: android ? GolemSpace.gutter : 0,
      bottom: bottom + (android ? 88 : 102),
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _pop,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(
              CurvedAnimation(parent: _pop, curve: GolemMotion.standard),
            ),
            child: android
                ? KeyedSubtree(key: const Key('golem-toast'), child: toast)
                : Center(
                    child: KeyedSubtree(
                      key: const Key('golem-toast'),
                      child: toast,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
