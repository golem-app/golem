import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
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
const _backend = String.fromEnvironment(
  'GOLEM_INFERENCE_BACKEND',
  defaultValue: 'fake',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'one seeded generation through the real backend',
    (tester) async {
      await app.main();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      if (find.byKey(const Key('empty-chat')).evaluate().isEmpty) {
        await tester.tap(find.byKey(const Key('new-chat-header')));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byKey(const Key('chat-composer')));
      await tester.enterText(
        find.byKey(const Key('chat-composer')),
        'Name the largest planet in the solar system.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-button')));

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
      await tester.pumpAndSettle();

      // The reply bubble must carry a real answer (the probe line in the log
      // carries the hash; this asserts the UI surfaced the same generation).
      expect(find.textContaining('Jupiter'), findsWidgets);
    },
    // Self-skips against the default fake backend so a plain
    // `flutter test integration_test` run cannot burn the poll deadline.
    skip: _backend == 'fake',
  );
}
