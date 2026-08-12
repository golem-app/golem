import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/services/image_intake.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/chat/widgets/attach_sheet.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';

import 'package:golem_flutter/main.dart' as app;

import 'support/acceptance_hud.dart';

/// The real-model chat acceptance for one device/engine cell (#20).
///
/// ```sh
/// flutter test integration_test/device_acceptance_test.dart -d <device> \
///   --flavor qa --no-uninstall --dart-define=GOLEM_INFERENCE_BACKEND=auto \
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
/// **`--no-uninstall` is not optional on a phone** (#83). Without it the
/// harness uninstalls the app on teardown and takes the container's models with
/// it, so every run pays full provisioning and hands the next one nothing. With
/// it, provisioning is once per device and the offline path — bytes already in
/// the container, verified against the pinned hashes with no network — is what
/// every later run takes. That offline path is the default: fetching from the
/// Hub is the explicit opt-in `--dart-define=GOLEM_ACCEPT_DOWNLOAD=true`, so an
/// unprovisioned device says so instead of quietly spending five gigabytes.
///
/// CI never sets the defines, so this self-skips and touches no weights.
const _enabled = bool.fromEnvironment('GOLEM_DEVICE_ACCEPTANCE');
const _primary = String.fromEnvironment('GOLEM_ACCEPT_PRIMARY');
const _secondary = String.fromEnvironment('GOLEM_ACCEPT_SECONDARY');
const _image = bool.fromEnvironment('GOLEM_ACCEPT_IMAGE');
const _allowDownload = bool.fromEnvironment('GOLEM_ACCEPT_DOWNLOAD');

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
    // One frame before the first check, always. Predicates read controller
    // state, which runs ahead of what is painted, so a wait that happens to be
    // satisfied on entry would otherwise pump nothing and leave the next tap
    // hit-testing the previous frame's tree.
    do {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for $description');
      }
      if (find.byKey(const Key('recovery-banner')).evaluate().isNotEmpty) {
        fail('A recovery banner appeared while waiting for $description');
      }
      await tester.pump(const Duration(milliseconds: 250));
    } while (!predicate());
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
      await AcceptanceHud.attach(tester);
      host(
        'GOLEM_CELL lifecycle download=${_allowDownload ? 'allowed' : 'offline'} '
        '— run with --no-uninstall or teardown deletes these models',
      );
      final providers = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      final models = providers.read(modelControllerProvider.notifier);
      final chat = providers.read(chatControllerProvider.notifier);
      final documents = providers.read(documentsPathProvider);
      final catalog = providers.read(modelCatalogEntriesProvider);

      // A pinned key this build actually carries. The cell names catalog keys
      // on the command line, and a typo deserves the list of what was meant
      // rather than a bare "No element" out of firstWhere.
      ModelCatalogEntry entryFor(String key) {
        for (final entry in catalog) {
          if (entry.key == key) return entry;
        }
        fail(
          '"$key" is not a pinned catalog key. This cell runs the pinned '
          'catalog: ${catalog.map((entry) => entry.key).join(', ')}.',
        );
      }

      // Every file of the entry already on disk at its pinned length. Not a
      // verdict — the download path still hashes them — but enough to know
      // whether this install needs the network at all.
      Future<bool> bytesArePresent(ModelCatalogEntry entry) async {
        for (final spec in entry.files) {
          final file = File(
            '$documents/${entry.installDirectory}/${spec.path}',
          );
          if (!await file.exists() || await file.length() != spec.bytes) {
            return false;
          }
        }
        return true;
      }

      Future<void> install(String key) async {
        final entry = entryFor(key);
        final before = providers
            .read(modelControllerProvider)
            .requireValue
            .statusOf(key);
        // An install already receipted in the container is the whole point of
        // provisioning once: no network, no rehash, straight to the turns.
        if (before.phase == ArtifactPhase.installed) {
          AcceptanceHud.step('$key already installed');
          host(
            'GOLEM_CELL install $key from=installed '
            'bytes=${before.downloadedBytes}',
          );
          return;
        }

        final present = await bytesArePresent(entry);
        if (!present && !_allowDownload) {
          AcceptanceHud.finish('$key is not provisioned on this device');
          fail(
            '$key is not provisioned on this device (phase '
            '${before.phase.name}, ${before.downloadedBytes} of '
            '${entry.totalBytes} bytes). Copy its ${entry.files.length} '
            'pinned file(s) into $documents/${entry.installDirectory}/, or '
            'pass --dart-define=GOLEM_ACCEPT_DOWNLOAD=true to fetch — or '
            'resume — them from the Hub for real. Either way pass '
            '--no-uninstall, or teardown deletes them again.',
          );
        }

        final source = present ? 'present-offline' : 'hub';
        AcceptanceHud.step(
          present ? 'Verifying $key offline' : 'Downloading $key',
        );
        host(
          'GOLEM_CELL install $key from=$source '
          'bytes=${before.downloadedBytes} total=${entry.totalBytes}',
        );
        models.download(key);
        var verifying = false;
        await pumpUntil(tester, '$key to install', () {
          final status = providers
              .read(modelControllerProvider)
              .requireValue
              .statusOf(key);
          if (status.phase == ArtifactPhase.failed) {
            fail('$key failed to install: ${status.failure}');
          }
          verifying |= status.phase == ArtifactPhase.verifying;
          // The offline promise, enforced rather than asserted up front.
          // Every file was present at its pinned length, so the repository
          // hashes them all before it fetches anything; a download phase after
          // a verifying one is it having rejected one and reached for the
          // network. Catch it at the first progress tick instead of after
          // gigabytes.
          if (present &&
              verifying &&
              status.phase == ArtifactPhase.downloading) {
            fail(
              'A sideloaded file of $key is the right size but failed its '
              'pinned SHA-256, and the run is fetching a replacement. Re-copy '
              '$documents/${entry.installDirectory}/ from a trusted source, '
              'or pass --dart-define=GOLEM_ACCEPT_DOWNLOAD=true to allow it.',
            );
          }
          // Straight off the download layer's own status stream, so the screen
          // can never claim more than the repository has banked. Verification
          // credits a whole file before hashing it, so a bar there would sit
          // at 100% for minutes; the byte count is the honest part.
          AcceptanceHud.progress(
            received: status.phase == ArtifactPhase.verifying
                ? null
                : status.downloadedBytes,
            total: status.phase == ArtifactPhase.verifying
                ? null
                : entry.totalBytes,
            detail: status.phase == ArtifactPhase.verifying
                ? 'hashing ${formatBytes(entry.totalBytes)} against the pins'
                : status.phase.name,
          );
          return status.phase == ArtifactPhase.installed;
        }, timeout: const Duration(minutes: 40));
        host('GOLEM_CELL installed $key from=$source');
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
        await pumpUntil(tester, 'a turn to complete', () {
          AcceptanceHud.progress(
            detail: providers
                .read(chatControllerProvider)
                .requireValue
                .generation
                .name,
          );
          return metrics.length >= expected;
        });
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

      // Every destination this cell can need, before the first one is missed:
      // one bootstrap run then prepares the whole sideload in a single pass
      // rather than one directory per failed attempt.
      for (final key in [_primary, if (_secondary.isNotEmpty) _secondary]) {
        await Directory(
          '$documents/${catalog.firstWhere((e) => e.key == key).installDirectory}',
        ).create(recursive: true);
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

      AcceptanceHud.step('Text turn on $_primary');
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
        AcceptanceHud.step('Switch turn on $_secondary');
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
        AcceptanceHud.step('Image turn on $_primary');
        await chat.setConversationModel(
          providers.read(chatControllerProvider).requireValue.active!.id,
          _primary,
        );
        // Waits, not pumpAndSettle: the HUD's liveness pulse never stops
        // scheduling frames, so settling is not a state this screen reaches.
        // The composer must repaint before the tap — attach is mounted even
        // mid-generation but refuses the press, so tapping the frame the last
        // turn left behind would be swallowed.
        await pumpUntil(
          tester,
          'the composer to leave the last turn behind',
          () =>
              find.byKey(const Key('stop-button')).evaluate().isEmpty &&
              find.byKey(const Key('send-button')).evaluate().isNotEmpty,
        );
        await tester.tap(find.byKey(const Key('composer-attach')));
        await pumpUntil(
          tester,
          'the attach sheet to open',
          () => find
              .byKey(const Key('attach-photo-library'))
              .evaluate()
              .isNotEmpty,
        );
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

      AcceptanceHud.step('Reading the chat back off disk');
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
      AcceptanceHud.finish('Done — cell passed, models kept on this device');
    },
    timeout: const Timeout(Duration(minutes: 90)),
    skip: !_enabled || _primary.isEmpty,
  );
}

final class _RedImagePicker extends AttachmentPicker {
  const _RedImagePicker(this.bytes);
  final Uint8List bytes;

  @override
  Future<PreparedImage?> pick(
    AttachSource source, {
    String filesLabel = 'Images',
  }) async => PreparedImage(
    bytes: bytes,
    mimeType: 'image/png',
    width: 320,
    height: 320,
  );
}
