import 'package:flutter/cupertino.dart';

/// An on-screen sign that a device is under automation.
///
/// A long acceptance run takes over the phone and otherwise shows nothing at
/// all, which is indistinguishable from a hang or a crash to whoever is holding
/// it. This paints what the run is doing and keeps moving, so the screen is
/// visibly alive.
///
/// Test-only, and never linked into the app.
abstract final class AcceptanceHud {
  static final ValueNotifier<String> _status = ValueNotifier('Starting…');
  static final ValueNotifier<List<String>> _done = ValueNotifier(const []);
  static bool _running = false;

  /// Shows [status] as the current step, mounting the display on first call.
  static void step(String status) {
    if (_status.value != 'Starting…') {
      _done.value = [..._done.value, _status.value];
    }
    _status.value = status;
    if (_running) return;
    _running = true;
    runApp(const _Hud());
  }

  /// Replaces the step list with a terminal message.
  static void finish(String status) {
    _done.value = [..._done.value, _status.value];
    _status.value = status;
  }
}

class _Hud extends StatefulWidget {
  const _Hud();

  @override
  State<_Hud> createState() => _HudState();
}

class _HudState extends State<_Hud> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoApp(
    debugShowCheckedModeBanner: false,
    home: ColoredBox(
      color: const Color(0xFF0E1729),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FadeTransition(
                    opacity: _pulse.drive(Tween(begin: 0.25, end: 1)),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2F6BFF),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Golem acceptance run',
                    style: TextStyle(
                      color: Color(0xFFF2F5FA),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'This device is under automation. Leave it unlocked.',
                style: TextStyle(color: Color(0xFF8B9AB4), fontSize: 14),
              ),
              const SizedBox(height: 26),
              ValueListenableBuilder<List<String>>(
                valueListenable: AcceptanceHud._done,
                builder: (context, done, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final step in done)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '✓  $step',
                          style: const TextStyle(
                            color: Color(0xFF5C7A5C),
                            fontSize: 15,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ValueListenableBuilder<String>(
                valueListenable: AcceptanceHud._status,
                builder: (context, status, _) => Row(
                  children: [
                    // The indicator is the liveness signal: a frozen screen and
                    // a working one look the same without it.
                    const CupertinoActivityIndicator(
                      radius: 9,
                      color: Color(0xFF2F6BFF),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        status,
                        style: const TextStyle(
                          color: Color(0xFFF2F5FA),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
