import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:golem_flutter/main.dart' as app;

/// The repeatable soak regimen for a real backend (#63): twelve sequential
/// turns under a deliberately tiny context budget, crossing the windowing
/// boundary several times, asserting the conversation never bricks (no
/// recovery banner) and the engine's footprint plateaus instead of
/// climbing turn over turn.
///
/// ```sh
/// flutter test integration_test/real_soak_test.dart -d <device> \
///   --flavor qa --dart-define=GOLEM_INFERENCE_BACKEND=auto
/// ```
///
/// A deliberate measurement instrument like the probe: fresh container,
/// installed model, never CI. The tiny budget is seeded through the real
/// settings store before the app boots, so every turn exercises exactly
/// the windowing and sampling enforcement that ships.
const _backend = String.fromEnvironment(
  'GOLEM_INFERENCE_BACKEND',
  defaultValue: 'fake',
);

const _turns = 12;

/// ~600 characters of filler keeps each turn's cost high enough that the
/// 256-token budget (1024 − 256 − 512) evicts history every few turns.
final _filler = 'soak ' * 120;

Future<void> _pumpUntil(
  WidgetTester tester,
  String description,
  bool Function() predicate, {
  Duration timeout = const Duration(minutes: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'twelve real turns across the windowing boundary stay healthy',
    (tester) async {
      // Seed the tiny budget through the real settings store before the
      // app boots: the soak must measure the shipped merge path, not a
      // parallel configuration channel.
      final support = await getApplicationSupportDirectory();
      await File('${support.path}/flutter-prefs-v1.json').writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'models': {
            'gemma4': {'contextLength': 1024, 'maxTokens': 256},
            'qwen35': {'contextLength': 1024, 'maxTokens': 256},
          },
        }),
      );

      // Collect the evidence channel: every completed generation logs one
      // INFERNO_METRICS line through debugPrint.
      final metricsLines = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null && message.startsWith('INFERNO_METRICS')) {
          metricsLines.add(message);
        }
        original(message, wrapWidth: wrapWidth);
      };
      addTearDown(() => debugPrint = original);

      await app.main();
      await _pumpUntil(
        tester,
        'the launch splash to dismiss',
        () => find.byKey(const Key('launch-splash')).evaluate().isEmpty,
      );

      for (var turn = 1; turn <= _turns; turn++) {
        final expected = metricsLines.length + 1;
        await tester.tap(find.byKey(const Key('chat-composer')));
        await tester.enterText(
          find.byKey(const Key('chat-composer')),
          'Turn $turn: $_filler Reply with one word.',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('send-button')));

        // One metrics line per completed generation is the turn boundary;
        // the recovery banner at any point is an immediate failure.
        await _pumpUntil(tester, 'turn $turn to complete', () {
          if (find.byKey(const Key('recovery-banner')).evaluate().isNotEmpty) {
            fail(
              'Turn $turn raised the recovery banner — the soak\'s one '
              'forbidden outcome.',
            );
          }
          return metricsLines.length >= expected;
        });
        // Let the stream teardown settle before the next composer tap.
        await _pumpUntil(
          tester,
          'the composer to go idle after turn $turn',
          () =>
              find.byKey(const Key('send-button')).evaluate().isNotEmpty &&
              find.byKey(const Key('stop-button')).evaluate().isEmpty,
        );
      }

      expect(metricsLines, hasLength(_turns));

      // Footprint must plateau: after the model and caches are warm
      // (turn 2), no later turn may exceed the warm baseline by more than
      // 50%. Reported on Apple platforms only; null elsewhere skips.
      final footprints = metricsLines
          .map(
            (line) => RegExp(
              r'peakPhysicalFootprintBytes=(\d+)',
            ).firstMatch(line)?.group(1),
          )
          .toList();
      if (footprints.every((value) => value != null)) {
        final warm = int.parse(footprints[1]!);
        for (var turn = 3; turn <= _turns; turn++) {
          final value = int.parse(footprints[turn - 1]!);
          expect(
            value,
            lessThan(warm * 3 ~/ 2),
            reason:
                'turn $turn footprint $value grew past 1.5× the warm '
                'baseline $warm',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
    // Self-skips against the default fake backend so a plain integration
    // run cannot start a half-hour soak. (`testWidgets` skip is bool-only,
    // unlike `test`.)
    skip: _backend == 'fake',
  );
}
