import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:integration_test/integration_test.dart';

import 'package:golem_flutter/main.dart' as app;

/// Drives one real on-device generation through the app's own chat UI, for
/// the cross-device determinism probe and for validating a real backend where
/// no OS-level UI automation exists (macOS). Run it against a build carrying
/// real-backend dart-defines, e.g.:
///
/// ```sh
/// flutter test integration_test/real_backend_probe_test.dart -d macos \
///   --flavor qa \
///   --dart-define=GOLEM_INFERENCE_BACKEND=llama \
///   --dart-define=GOLEM_MODEL_PATH=/abs/path/model.gguf \
///   --dart-define=GOLEM_SAMPLING_SEED=7
/// ```
///
/// The `INFERNO_METRICS` and `INFERNO_PROBE` lines land in the test log; the
/// probe line's hash is the value compared across devices. The prompt must
/// stay byte-identical between the runs being compared.
///
/// This is a deliberate measurement instrument, not routine automation:
/// run it against a freshly installed container (real model-load timing and
/// persisted conversations add environmental variance that fake-backend
/// automation deliberately avoids), and never wire it into CI.
const _backend = String.fromEnvironment(
  'GOLEM_INFERENCE_BACKEND',
  defaultValue: 'fake',
);

const _prompt = 'Name the largest planet in the solar system.';

/// The splash and a real model load animate for an unbounded stretch, so
/// `pumpAndSettle` is unsafe here; poll a predicate instead and fail with
/// the thing that was awaited, not with whatever assertion runs next.
Future<void> _pumpUntil(
  WidgetTester tester,
  String description,
  bool Function() predicate, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(minutes: 2),
}) => _pumpUntil(
  tester,
  '$finder',
  () => finder.evaluate().isNotEmpty,
  timeout: timeout,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'one seeded generation through the real backend',
    (tester) async {
      await app.main();
      // Wait the splash out. Polling for the composer is not enough:
      // StartupGate keeps the whole chat tree mounted beneath the splash
      // overlay, so the composer is findable while the launch splash still
      // covers the screen — and a tap there lands on the splash.
      await _pumpUntilFound(tester, find.byKey(const Key('chat-composer')));
      await _pumpUntil(
        tester,
        'the launch splash to dismiss',
        () => find.byKey(const Key('launch-splash')).evaluate().isEmpty,
      );

      // The probe must run in a fresh chat: every turn re-prefills the whole
      // conversation, so history would change the rendered prompt and the
      // hash. On a fresh container the active chat is already empty.
      if (find.byKey(const Key('empty-chat')).evaluate().isEmpty) {
        await tester.tap(find.byKey(const Key('new-chat-header')));
        await _pumpUntilFound(tester, find.byKey(const Key('empty-chat')));
      }

      await tester.tap(find.byKey(const Key('chat-composer')));
      await tester.enterText(find.byKey(const Key('chat-composer')), _prompt);
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-button')));

      // A message landing in the active chat is the proof the send
      // registered; without it the idle poll below would treat "never
      // started" as "finished". (The composer's own text would fool a
      // widget-finder here, so ask the controller.)
      final providers = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      await _pumpUntil(
        tester,
        'the sent message to reach the active chat',
        () =>
            providers
                .read(chatControllerProvider)
                .requireValue
                .active
                ?.messages
                .isNotEmpty ??
            false,
      );

      // A real model load plus generation takes tens of seconds on a phone;
      // poll until the composer is idle again (send button back, no stop).
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      var completed = false;
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 500));
        final stopped = find.byKey(const Key('stop-button')).evaluate().isEmpty;
        final sendBack = find
            .byKey(const Key('send-button'))
            .evaluate()
            .isNotEmpty;
        if (stopped && sendBack && tester.binding.transientCallbackCount == 0) {
          completed = true;
          break;
        }
      }
      if (!completed) {
        fail('The generation never finished within the five-minute deadline.');
      }

      // The reply bubble must carry a real answer (the probe line in the log
      // carries the hash; this asserts the UI surfaced the same generation).
      expect(find.textContaining('Jupiter'), findsWidgets);
    },
    // Self-skips against the default fake backend so a plain
    // `flutter test integration_test` run cannot burn the poll deadline.
    skip: _backend == 'fake',
  );
}
