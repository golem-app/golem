import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// An on-screen sign that a device is under automation.
///
/// A long acceptance run takes over the phone and otherwise shows nothing at
/// all, which is indistinguishable from a hang or a crash to whoever is holding
/// it. This paints what the run is doing and keeps moving, so the screen is
/// visibly alive.
///
/// Two mounts, because the instruments come in two shapes. A plain `test()`
/// leaves the screen empty, so [takeOver] owns it outright. A `testWidgets`
/// instrument has the real app mounted and drives it through finders, so
/// [attach] slips an ignore-pointer band above it instead — `runApp` there
/// would tear the app tree down mid-run.
///
/// Test-only, and never linked into the app.
abstract final class AcceptanceHud {
  static final ValueNotifier<String> _status = ValueNotifier('Starting…');
  static final ValueNotifier<List<String>> _done = ValueNotifier(const []);
  static final ValueNotifier<HudProgress?> _progress = ValueNotifier(null);
  static DateTime _stepStartedAt = DateTime.now();
  static bool _running = false;

  /// Owns the whole screen. For instruments that mount no app.
  static void takeOver() {
    if (_running) return;
    _running = true;
    runApp(const _HudScreen());
  }

  /// Paints a band above the running app, leaving it interactive.
  ///
  /// The band goes into the app's own root overlay, so it survives route
  /// pushes; a modal sheet briefly covers it, which is the price of not
  /// intercepting the taps the instrument still has to make.
  ///
  /// Once this is mounted the pulse schedules a frame forever, so
  /// `pumpAndSettle` can never return — wait on a predicate instead.
  static Future<void> attach(WidgetTester tester) async {
    if (_running) return;
    // First in tree order is the outermost, which is the root overlay a nested
    // navigator would otherwise shadow. Deliberately not an exactly-one
    // assertion: a shell route added later must not fail every instrument
    // before it reaches its first assertion.
    final overlays = find.byType(Overlay).evaluate();
    if (overlays.isEmpty) {
      fail('The HUD band found no Overlay to attach to; is the app mounted?');
    }
    _running = true;
    final overlay = (overlays.first as StatefulElement).state as OverlayState;
    final entry = OverlayEntry(builder: (context) => const _HudBand());
    overlay.insert(entry);
    // Leave nothing attached to a tree the harness is about to unmount, and let
    // a second test in the same file mount its own band on its own app.
    addTearDown(() {
      entry.remove();
      entry.dispose();
      reset();
    });
    await tester.pump();
  }

  /// Forgets every step and unlatches the mount, so the next one starts clean.
  static void reset() {
    _running = false;
    _status.value = 'Starting…';
    _done.value = const [];
    _progress.value = null;
    _stepStartedAt = DateTime.now();
  }

  /// Shows [status] as the current step, clearing any per-step progress.
  static void step(String status) {
    if (_status.value != 'Starting…') {
      _done.value = [..._done.value, _status.value];
    }
    _status.value = status;
    _progress.value = null;
    _stepStartedAt = DateTime.now();
  }

  /// Reports how far the current step has come.
  ///
  /// [received] and [total] are bytes, straight off the download layer's own
  /// status stream; [detail] carries anything that is not a byte count, like
  /// which turn of a soak is running.
  static void progress({int? received, int? total, String? detail}) =>
      _progress.value = HudProgress(
        received: received,
        total: total,
        detail: detail,
      );

  /// Replaces the step list with a terminal message.
  static void finish(String status) {
    _done.value = [..._done.value, _status.value];
    _status.value = status;
    _progress.value = null;
    _stepStartedAt = DateTime.now();
  }
}

@immutable
final class HudProgress {
  const HudProgress({this.received, this.total, this.detail});

  final int? received;
  final int? total;
  final String? detail;

  double? get fraction => received != null && total != null && total! > 0
      ? (received! / total!).clamp(0.0, 1.0)
      : null;

  /// Verification has meaningful activity but no trustworthy fraction.
  bool get indeterminate => fraction == null && caption.isNotEmpty;

  /// The caption under the current step: bytes when they are known, the free
  /// text otherwise, both when both were given. A count without a total still
  /// reads as the count — dropping it would paint an empty line.
  String get caption {
    final bytes = switch ((received, total)) {
      (final received?, final total?) =>
        '${formatBytes(received)} / ${formatBytes(total)}',
      (final received?, null) => formatBytes(received),
      _ => null,
    };
    return [?bytes, ?detail].join(' · ');
  }
}

/// Two significant decimals of GB, or MB below a gigabyte — a download that
/// reads "0.00 GB" for its first minute is no more informative than silence.
String formatBytes(int bytes) => bytes >= 1000000000
    ? '${(bytes / 1e9).toStringAsFixed(2)} GB'
    : '${(bytes / 1e6).toStringAsFixed(0)} MB';

String formatElapsed(Duration elapsed) {
  final minutes = elapsed.inMinutes;
  final seconds = elapsed.inSeconds - minutes * 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

const _ink = Color(0xFFF2F5FA);
const _muted = Color(0xFF8B9AB4);
const _accent = Color(0xFF2F6BFF);
const _ground = Color(0xFF0E1729);

/// The pulse every mount shares: the one element that separates a live screen
/// from a frozen one, and the clock's rebuild signal.
///
/// The elapsed time is read off the wall clock here and handed down rather
/// than computed inside the clock widget — a `const` widget is canonicalized to
/// one instance, and an element whose widget is identical never rebuilds, so a
/// self-timing clock would freeze at the first value it ever painted.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.builder});

  final Widget Function(BuildContext context, double opacity, Duration elapsed)
  builder;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => widget.builder(
      context,
      0.25 + 0.75 * _controller.value,
      DateTime.now().difference(AcceptanceHud._stepStartedAt),
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot(this.opacity, {this.size = 12});

  final double opacity;
  final double size;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: opacity,
    child: Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
    ),
  );
}

/// The elapsed heartbeat, re-read on every pulse frame rather than off a timer,
/// so a step that genuinely stops still visibly ages.
class _Elapsed extends StatelessWidget {
  const _Elapsed(this.elapsed, {this.style});

  final Duration elapsed;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    formatElapsed(elapsed),
    style:
        style ??
        const TextStyle(
          color: _muted,
          fontSize: 14,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
  );
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar(this.fraction);

  final double fraction;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      height: 4,
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: 4,
            color: const Color(0x332F6BFF),
          ),
          FractionallySizedBox(
            widthFactor: fraction,
            child: Container(height: 4, color: _accent),
          ),
        ],
      ),
    ),
  );
}

class _ProgressCaption extends StatelessWidget {
  const _ProgressCaption(this.progress, {required this.compact});

  final HudProgress progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      progress.caption,
      maxLines: compact ? 1 : null,
      overflow: compact ? TextOverflow.ellipsis : null,
      style: TextStyle(color: _muted, fontSize: compact ? 12 : 14),
    );
    if (!progress.indeterminate) return text;
    return Row(
      children: [
        CupertinoActivityIndicator(
          key: const Key('acceptance-hud-indeterminate-progress'),
          radius: compact ? 7 : 9,
          color: _accent,
        ),
        SizedBox(width: compact ? 7 : 9),
        Expanded(child: text),
      ],
    );
  }
}

class _HudScreen extends StatelessWidget {
  const _HudScreen();

  @override
  Widget build(BuildContext context) => CupertinoApp(
    debugShowCheckedModeBanner: false,
    home: ColoredBox(
      color: _ground,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _Pulse(
            builder: (context, opacity, elapsed) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Dot(opacity),
                    const SizedBox(width: 10),
                    const Text(
                      'Golem acceptance run',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'This device is under automation. Leave it unlocked.',
                  style: TextStyle(color: _muted, fontSize: 14),
                ),
                const SizedBox(height: 26),
                // Scrollable and yielding: the step list has no bound, and a
                // RenderFlex overflow here would fail an acceptance run from
                // inside the thing that exists to report on it.
                Flexible(
                  child: ValueListenableBuilder<List<String>>(
                    valueListenable: AcceptanceHud._done,
                    builder: (context, done, _) => SingleChildScrollView(
                      reverse: true,
                      child: Column(
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
                  ),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: AcceptanceHud._status,
                  builder: (context, status, _) => Row(
                    children: [
                      const CupertinoActivityIndicator(
                        radius: 9,
                        color: _accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _Elapsed(elapsed),
                    ],
                  ),
                ),
                ValueListenableBuilder<HudProgress?>(
                  valueListenable: AcceptanceHud._progress,
                  builder: (context, progress, _) => progress == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(left: 28, top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ProgressCaption(progress, compact: false),
                              if (progress.fraction case final fraction?) ...[
                                const SizedBox(height: 8),
                                _ProgressBar(fraction),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The band form: everything the screen form says, compressed to two lines so
/// the app under test stays visible and legible underneath it.
class _HudBand extends StatelessWidget {
  const _HudBand();

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    // The instrument still has to tap the app below; a band that ate pointers
    // would break every finder it covers.
    child: IgnorePointer(
      child: ColoredBox(
        // Opaque: at anything less the app's own header bleeds through the
        // caption and the two sets of words read as one.
        color: _ground,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: _Pulse(
              builder: (context, opacity, elapsed) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Dot(opacity, size: 9),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ValueListenableBuilder<String>(
                          valueListenable: AcceptanceHud._status,
                          builder: (context, status, _) => Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Elapsed(
                        elapsed,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  ValueListenableBuilder<HudProgress?>(
                    valueListenable: AcceptanceHud._progress,
                    builder: (context, progress, _) => progress == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(left: 17, top: 3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ProgressCaption(progress, compact: true),
                                if (progress.fraction case final fraction?) ...[
                                  const SizedBox(height: 5),
                                  _ProgressBar(fraction),
                                ],
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
