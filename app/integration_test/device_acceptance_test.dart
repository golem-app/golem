import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/services/image_intake.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/chat/widgets/attach_sheet.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';

import 'package:golem_flutter/main.dart' as app;

/// The real-model chat acceptance for one device/engine cell (#20).
///
/// ```sh
/// flutter test integration_test/device_acceptance_test.dart -d <device> \
///   --flavor qa --dart-define=GOLEM_INFERENCE_BACKEND=auto \
///   --dart-define=GOLEM_DEVICE_ACCEPTANCE=true \
///   --dart-define=GOLEM_ACCEPT_PRIMARY=gemma4-gguf \
///   --dart-define=GOLEM_ACCEPT_SECONDARY=qwen35-2b-gguf \
///   --dart-define=GOLEM_ACCEPT_IMAGE=true
/// ```
///
/// One run covers a cell end to end: install (verifying already-present bytes
/// without network, or downloading them for real), a text turn, a per-chat
/// switch to a second artifact and a turn on it, an image turn where the
/// artifact's vision path is proven, and history surviving on disk.
///
/// Evidence lands on the host console as `GOLEM_CELL` lines beside the
/// `INFERNO_METRICS` lines the broker already emits — the test-harness channel,
/// because a release build's `debugPrint` is privacy-redacted in an iOS syslog
/// capture.
///
/// A device test bundle install preserves the app's data but teardown removes
/// the app, so anything provisioned by hand must be re-provisioned per run.
///
/// CI never sets the defines, so this self-skips and touches no weights.
const _enabled = bool.fromEnvironment('GOLEM_DEVICE_ACCEPTANCE');
const _primary = String.fromEnvironment('GOLEM_ACCEPT_PRIMARY');
const _secondary = String.fromEnvironment('GOLEM_ACCEPT_SECONDARY');
const _image = bool.fromEnvironment('GOLEM_ACCEPT_IMAGE');

/// A 320×320 solid red PNG. Large enough for a vision encoder to see, and its
/// one correct answer is knowable without shipping a photograph.
final _redPng = Uint8List.fromList(
  img.encodePng(
    img.Image(width: 320, height: 320)..clear(img.ColorRgb8(220, 20, 30)),
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final metrics = <String>[];
  late void Function(String?, {int? wrapWidth}) host;

  Future<void> pumpUntil(
    WidgetTester tester,
    String description,
    bool Function() predicate, {
    Duration timeout = const Duration(minutes: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!predicate()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for $description');
      }
      if (find.byKey(const Key('recovery-banner')).evaluate().isNotEmpty) {
        fail('A recovery banner appeared while waiting for $description');
      }
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets(
    'a real model installs, answers, switches, reads an image, and persists',
    (tester) async {
      host = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null && message.startsWith('INFERNO_METRICS')) {
          metrics.add(message);
        }
        host(message, wrapWidth: wrapWidth);
      };
      addTearDown(() => debugPrint = host);

      await app.launch(picker: _RedImagePicker(_redPng));
      await pumpUntil(
        tester,
        'the composer to mount',
        () => find.byKey(const Key('chat-composer')).evaluate().isNotEmpty,
      );
      await pumpUntil(
        tester,
        'the launch splash to dismiss',
        () => find.byKey(const Key('launch-splash')).evaluate().isEmpty,
      );
      final providers = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      final models = providers.read(modelControllerProvider.notifier);
      final chat = providers.read(chatControllerProvider.notifier);

      Future<void> install(String key) async {
        final before = providers
            .read(modelControllerProvider)
            .requireValue
            .statusOf(key);
        host(
          'GOLEM_CELL install $key from=${before.phase.name} '
          'bytes=${before.downloadedBytes}',
        );
        if (before.phase == ArtifactPhase.installed) return;
        models.download(key);
        await pumpUntil(tester, '$key to install', () {
          final status = providers
              .read(modelControllerProvider)
              .requireValue
              .statusOf(key);
          if (status.phase == ArtifactPhase.failed) {
            fail('$key failed to install: ${status.failure}');
          }
          return status.phase == ArtifactPhase.installed;
        }, timeout: const Duration(minutes: 40));
        host('GOLEM_CELL installed $key');
      }

      // Driven through the composer, not the controller: an attachment lives in
      // the composer's tray until its send button carries it, so a
      // controller-level send would silently drop the image turn.
      //
      // A turn is finished when the broker has logged one more metrics line:
      // the same boundary the soak regimen uses.
      Future<String> turn(String prompt) async {
        final expected = metrics.length + 1;
        await tester.tap(find.byKey(const Key('chat-composer')));
        await tester.enterText(find.byKey(const Key('chat-composer')), prompt);
        await tester.pump();
        await tester.tap(find.byKey(const Key('send-button')));
        await pumpUntil(
          tester,
          'a turn to complete',
          () => metrics.length >= expected,
        );
        await pumpUntil(
          tester,
          'the composer to go idle',
          () =>
              providers.read(chatControllerProvider).requireValue.generation ==
              GenerationPhase.idle,
        );
        return providers
            .read(chatControllerProvider)
            .requireValue
            .active!
            .messages
            .last
            .text;
      }

      await install(_primary);
      await chat.newChat();
      await chat.setConversationModel(
        providers.read(chatControllerProvider).requireValue.active!.id,
        _primary,
      );
      expect(
        providers.read(chatControllerProvider).requireValue.active!.modelKey,
        _primary,
        reason: 'the cell under test must be the model the chat actually runs',
      );

      final first = await turn(
        'Name the capital of France. Answer with one word.',
      );
      expect(first, contains('Paris'), reason: first);
      expect(providers.read(residentModelKeyProvider), _primary);
      host('GOLEM_CELL text primary=$_primary answer="${first.trim()}"');

      if (_secondary.isNotEmpty) {
        await install(_secondary);
        await chat.setConversationModel(
          providers.read(chatControllerProvider).requireValue.active!.id,
          _secondary,
        );
        expect(
          providers.read(chatControllerProvider).requireValue.active!.modelKey,
          _secondary,
          reason: 'an installed same-engine artifact must be selectable',
        );
        final switched = await turn(
          'Name the capital of Japan. Answer with one word.',
        );
        expect(switched, contains('Tokyo'), reason: switched);
        expect(
          providers.read(residentModelKeyProvider),
          _secondary,
          reason: 'residency must follow the switch on the device too',
        );
        host(
          'GOLEM_CELL switch secondary=$_secondary '
          'answer="${switched.trim()}"',
        );
      }

      if (_image) {
        // Back to the image-capable artifact, then attach through the real
        // sheet and composer tray rather than a synthetic message part.
        await chat.setConversationModel(
          providers.read(chatControllerProvider).requireValue.active!.id,
          _primary,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('composer-attach')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('attach-photo-library')));
        await pumpUntil(
          tester,
          'the attachment to reach the tray',
          () => find
              .byKey(const Key('composer-attachments'))
              .evaluate()
              .isNotEmpty,
        );
        final described = await turn(
          'What is the dominant colour of this image? Answer with one word.',
        );
        expect(described.toLowerCase(), contains('red'), reason: described);
        host('GOLEM_CELL image primary=$_primary answer="${described.trim()}"');
      }

      // History is on disk, not merely in memory: the turns must survive the
      // next launch, which is what a restart would read.
      final stored = await providers.read(chatHistoryRepositoryProvider).load();
      final persisted = stored.conversations
          .where(
            (item) =>
                item.id ==
                providers.read(chatControllerProvider).requireValue.active!.id,
          )
          .single;
      expect(persisted.messages.length, greaterThanOrEqualTo(2));
      host(
        'GOLEM_CELL persisted messages=${persisted.messages.length} '
        'modelKey=${persisted.modelKey}',
      );
      host('GOLEM_CELL metrics\n${metrics.join('\n')}');
    },
    timeout: const Timeout(Duration(minutes: 90)),
    skip: !_enabled || _primary.isEmpty,
  );
}

final class _RedImagePicker extends AttachmentPicker {
  const _RedImagePicker(this.bytes);
  final Uint8List bytes;

  @override
  Future<PreparedImage?> pick(AttachSource source) async => PreparedImage(
    bytes: bytes,
    mimeType: 'image/png',
    width: 320,
    height: 320,
  );
}
