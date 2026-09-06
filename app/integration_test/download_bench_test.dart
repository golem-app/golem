import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/services/artifact_downloader.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'support/acceptance_hud.dart';
import 'support/foreground_http_downloader.dart';
import 'support/parallel_artifact_downloader.dart';
import 'support/rate_meter.dart';

/// Instrumented download-throughput bench (#36):
///
///   flutter test integration_test/download_bench_test.dart -d DEVICE \
///     --flavor qa --no-uninstall --dart-define=GOLEM_DOWNLOAD_BENCH=true
///
/// Runs each transport against the same pinned artifact in time-capped
/// windows, interleaved round-robin so CDN drift lands on every transport
/// rather than the last one, and reports windowed rates as parseable
/// `DOWNLOAD_BENCH` lines — the instrumentation whose absence made the prior
/// round's in-app numbers uncomparable.
///
/// Transports: `current` (the production `BackgroundArtifactDownloader`),
/// `parallelN` (plugin `ParallelDownloadTask`, N chunks), `httpN`
/// (in-process `dart:io`, N ranged connections; the curl stand-in on iOS).
///
/// `GOLEM_BENCH_COMPLETE=<transport>` afterwards runs that transport to
/// completion once and verifies size and SHA-256 against the pin.
///
/// `GOLEM_BENCH_BACKGROUND=true` runs one extra window per plugin transport
/// in which the HUD asks for the app to be backgrounded; the reported figure
/// is the average across the suspension gap (`mode=background-avg`), never
/// mixed with foreground windows.
///
/// Downloads land in a throwaway `bench-<key>` directory that is deleted in
/// teardown; nothing is installed and no receipt is written. CI never sets
/// the define, so this self-skips there and downloads nothing.
const _enabled = bool.fromEnvironment('GOLEM_DOWNLOAD_BENCH');
const _artifactKey = String.fromEnvironment(
  'GOLEM_BENCH_ARTIFACT',
  defaultValue: 'qwen35-2b-gguf',
);
const _windowSeconds = int.fromEnvironment(
  'GOLEM_BENCH_WINDOW_S',
  defaultValue: 45,
);
const _rounds = int.fromEnvironment('GOLEM_BENCH_ROUNDS', defaultValue: 3);
const _transportSpec = String.fromEnvironment(
  'GOLEM_BENCH_TRANSPORTS',
  defaultValue: 'current,parallel4,http1,http4',
);
const _complete = String.fromEnvironment('GOLEM_BENCH_COMPLETE');
const _background = bool.fromEnvironment('GOLEM_BENCH_BACKGROUND');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Without this, Android defers the HUD's first frame indefinitely (the
  // activity delegate spins on its predraw listener) and the device shows a
  // blank screen for the whole run.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  group(
    'download bench',
    skip: _enabled
        ? false
        : 'Set --dart-define=GOLEM_DOWNLOAD_BENCH=true to run the download '
              'throughput bench.',
    () {
      late String documentsPath;
      late ArtifactFileRef ref;
      late String? expectedSha;
      var ready = false;
      final transports = _transportSpec.split(',');

      /// The `current` transport enqueues into the production `golem-models`
      /// group, and a killed harness leaves that native transfer alive with
      /// no catalog entry to reconcile it — so every run starts and ends by
      /// cancelling any bench-keyed task the platform still holds.
      Future<void> sweepStrayBenchTasks() async {
        final production = BackgroundArtifactDownloader();
        await production.initialize();
        for (final task in await FileDownloader().allTasks(
          group: 'golem-models',
        )) {
          try {
            final meta = jsonDecode(task.metaData) as Map<String, Object?>;
            if ((meta['path'] as String? ?? '').startsWith('bench-')) {
              await FileDownloader().cancelTaskWithId(task.taskId);
            }
          } catch (_) {}
        }
      }

      ArtifactFileDownloader buildTransport(String name) {
        if (name == 'current') return BackgroundArtifactDownloader();
        if (name.startsWith('parallel')) {
          return ParallelArtifactDownloader.forCurrentIdentity(
            chunks: int.parse(name.substring('parallel'.length)),
          );
        }
        if (name.startsWith('http')) {
          return ForegroundHttpDownloader(
            documentsDirectory: documentsPath,
            connections: int.parse(name.substring('http'.length)),
          );
        }
        throw ArgumentError('unknown transport: $name');
      }

      setUpAll(() async {
        final matches = modelCatalog
            .where((each) => each.key == _artifactKey)
            .toList();
        if (matches.isEmpty) {
          fail(
            'GOLEM_BENCH_ARTIFACT "$_artifactKey" is not a catalog key. '
            'Known keys: ${modelCatalog.map((each) => each.key).join(', ')}',
          );
        }
        final entry = matches.single;
        // The weights file: the largest one is the only one worth timing.
        final spec = entry.files.reduce((a, b) => a.bytes >= b.bytes ? a : b);
        expectedSha = spec.sha256;
        documentsPath = (await getApplicationDocumentsDirectory()).path;
        ref = ArtifactFileRef(
          artifactKey: 'bench-$_artifactKey',
          sourceUrl: entry.resolveUrlFor(spec).toString(),
          directory: 'bench-$_artifactKey',
          filename: spec.path.split('/').last,
          expectedBytes: spec.bytes,
        );
        ready = true;
        await sweepStrayBenchTasks();
        AcceptanceHud.takeOver();
      });

      tearDownAll(() async {
        // A failed setUpAll leaves the late fields unset; crashing here with
        // a LateInitializationError would bury the real failure.
        if (!ready) return;
        // Never leaves partials or weights behind, whatever passed or failed.
        await sweepStrayBenchTasks();
        for (final name in transports) {
          await buildTransport(name)
              .cancel(ref)
              .timeout(const Duration(seconds: 30), onTimeout: () => false);
        }
        final dir = Directory('$documentsPath/${ref.directory}');
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      /// One time-capped window: fresh transfer from byte zero, cancel and
      /// discard at the cap, report the meter. Returns the meter for callers
      /// that assert beyond the emitted line.
      Future<RateMeter> window(
        String name,
        int round, {
        bool backgrounded = false,
      }) async {
        final transport = buildTransport(name);
        await transport.initialize();
        // A leftover partial would let a later window start mid-file and
        // overstate the transport — and a fast window can complete the whole
        // file, which would turn every later window into an instant
        // "already complete" with no bytes moved at all.
        await transport.cancel(ref);
        final leftover = File('$documentsPath/${ref.destination}');
        if (await leftover.exists()) await leftover.delete();

        final meter = RateMeter()..start();
        final done = Completer<void>();
        final events = transport.download(ref).listen((event) {
          switch (event) {
            case ArtifactFileProgress(:final bytesReceived):
              meter.record(bytesReceived);
              AcceptanceHud.progress(
                received: bytesReceived,
                total: ref.expectedBytes,
                detail: meter.hudDetail(name, round, _rounds),
              );
            case ArtifactFileComplete():
            case ArtifactFileCanceled():
            case ArtifactFilePaused():
              if (!done.isCompleted) done.complete();
            case ArtifactFileFailed(:final message):
              if (!done.isCompleted) {
                done.completeError(StateError('$name: $message'));
              }
          }
        });

        if (backgrounded) {
          AcceptanceHud.step(
            'BACKGROUND THE APP NOW — return in ~3 minutes ($name)',
          );
          // Completion ends the window early: on a fast link the artifact
          // finishes well inside the cap, and waiting out the timer reads as
          // a hang to whoever is holding the device.
          await Future.any([
            done.future,
            Future<void>.delayed(Duration(seconds: _windowSeconds * 5)),
          ]);
          // On iOS the cap fires the instant the app resumes, but the
          // suspended period's progress arrives as a flush moments later —
          // cancelling immediately would discard exactly the bytes this
          // window exists to count.
          AcceptanceHud.step('Flushing resumed progress ($name)');
          await Future<void>.delayed(const Duration(seconds: 15));
          await transport.cancel(ref);
        } else {
          await Future.any([
            done.future,
            Future<void>.delayed(Duration(seconds: _windowSeconds)),
          ]);
          await transport.cancel(ref);
        }
        await done.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {},
        );
        await events.cancel();

        final line = meter.line(
          transport: name,
          round: round,
          capSeconds: backgrounded ? _windowSeconds * 5 : _windowSeconds,
          mode: backgrounded ? 'background-avg' : 'foreground',
          extra: backgrounded
              ? 'gap_mbs=${meter.largestGapMbs.toStringAsFixed(2)}'
              : '',
        );
        debugPrint(line);
        // Also on stdout: debugPrint is throttled and a release-mode device
        // harness may drop it.
        stdout.writeln(line);
        return meter;
      }

      test(
        'foreground windows, transports interleaved',
        () async {
          for (var round = 0; round < _rounds; round++) {
            for (final name in transports) {
              AcceptanceHud.step('Round ${round + 1}/$_rounds · $name');
              final meter = await window(name, round);
              expect(
                meter.isEmpty,
                isFalse,
                reason: '$name produced no progress in ${_windowSeconds}s',
              );
              // Let sockets and platform tasks settle so the next window
              // starts clean.
              await Future<void>.delayed(const Duration(seconds: 2));
            }
          }
          AcceptanceHud.finish('Bench done');
        },
        timeout: Timeout(
          Duration(seconds: (_windowSeconds + 40) * _rounds * 6),
        ),
      );

      test(
        'backgrounded windows',
        skip: _background
            ? false
            : 'Set --dart-define=GOLEM_BENCH_BACKGROUND=true (device only).',
        () async {
          // Only plugin-backed transports: in-process sockets do not survive
          // suspension, and pricing that is a finding, not a window.
          for (final name in transports.where((t) => !t.startsWith('http'))) {
            await window(name, 0, backgrounded: true);
          }
          AcceptanceHud.finish('Background bench done');
        },
        timeout: Timeout(Duration(seconds: _windowSeconds * 5 * 4 + 300)),
      );

      test(
        'completion and verification',
        skip: _complete.isEmpty
            ? 'Set --dart-define=GOLEM_BENCH_COMPLETE=<transport> to run one '
                  'transport to completion and verify the artifact.'
            : false,
        () async {
          AcceptanceHud.step('Completing via $_complete');
          final transport = buildTransport(_complete);
          await transport.initialize();
          await transport.cancel(ref);
          // A destination completed by an earlier window would make the
          // production transport resolve alreadyComplete and "verify" a
          // download of zero bytes.
          final leftover = File('$documentsPath/${ref.destination}');
          if (await leftover.exists()) await leftover.delete();
          final meter = RateMeter()..start();
          await for (final event in transport.download(ref)) {
            switch (event) {
              case ArtifactFileProgress(:final bytesReceived):
                meter.record(bytesReceived);
                AcceptanceHud.progress(
                  received: bytesReceived,
                  total: ref.expectedBytes,
                  detail: '${meter.steadyMbs.toStringAsFixed(1)} MB/s',
                );
              case ArtifactFileComplete():
                break;
              case final other:
                fail('completion run ended early: $other');
            }
          }
          final line = meter.line(
            transport: _complete,
            round: 0,
            capSeconds: 0,
            mode: 'complete',
          );
          debugPrint(line);
          stdout.writeln(line);

          final file = File('$documentsPath/${ref.destination}');
          expect(await file.length(), ref.expectedBytes);
          if (expectedSha != null) {
            final digest = await sha256.bind(file.openRead()).first;
            expect(digest.toString(), expectedSha);
          }
          await file.delete();
        },
        timeout: const Timeout(Duration(minutes: 60)),
      );
    },
  );
}
