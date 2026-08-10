import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_profile.dart';
import 'package:golem_flutter/broker/model_runtime_config.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/real_model_management_repository.dart';
import 'package:golem_flutter/core/services/artifact_downloader.dart';
import 'package:golem_flutter/core/services/device_storage.dart';
import 'package:golem_flutter/core/services/hugging_face_api.dart';
import 'package:golem_flutter/core/services/repository_resolver.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'support/acceptance_hud.dart';

/// End-to-end acceptance for a **non-pinned** public repository (#52):
///
///   flutter test integration_test/custom_repository_acceptance_test.dart \
///     -d macos --flavor qa --dart-define=GOLEM_CUSTOM_ACCEPTANCE=true
///
/// Resolves a real repository through the production resolver, downloads the
/// payload it names through the production storage stack, verifies it, proves
/// skip-if-valid, checks the entry produces a loadable runtime configuration,
/// and deletes it.
///
/// `--dart-define=GOLEM_KEEP_INSTALL=true` skips the delete, so the installed
/// bytes can be generated from before being cleaned up.
///
/// CI never sets the defines, so this self-skips and downloads nothing.
const _enabled = bool.fromEnvironment('GOLEM_CUSTOM_ACCEPTANCE');
const _keep = bool.fromEnvironment('GOLEM_KEEP_INSTALL');

/// Deliberately not in the Inferno manifest: the point is a repository this app
/// has never pinned, resolved from nothing but its name. Overridable so one test
/// covers both engines.
const _repository = String.fromEnvironment(
  'GOLEM_ACCEPTANCE_REPO',
  defaultValue: 'lmstudio-community/Qwen3.5-2B-GGUF',
);

/// The GGUF payload to install. Empty for MLX, which has no choice to make.
const _payload = String.fromEnvironment(
  'GOLEM_ACCEPTANCE_FILE',
  defaultValue: 'Qwen3.5-2B-Q4_K_M.gguf',
);

final _engine = _payload.isEmpty ? ModelEngine.mlx : ModelEngine.gguf;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a non-pinned repository resolves, downloads, verifies, loads, and deletes',
    skip: _enabled
        ? false
        : 'Set --dart-define=GOLEM_CUSTOM_ACCEPTANCE=true to run the '
              'non-pinned repository acceptance.',
    () async {
      AcceptanceHud.takeOver();
      AcceptanceHud.step('Resolving $_repository');
      final api = HttpClientHuggingFaceApi();
      addTearDown(api.close);
      final outcome =
          await HuggingFaceRepositoryResolver(
            api: api,
            profiles: brokerProfileSpecs,
          ).resolve(
            repository: _repository,
            engine: _engine,
            weightsFile: _payload.isEmpty ? null : _payload,
          );
      expect(outcome, isA<RepositoryResolved>(), reason: '$outcome');
      final resolved = outcome as RepositoryResolved;
      // A template this app recognizes is what makes the entry runnable at all.
      expect(resolved.profile?.key, 'qwen35');
      expect(resolved.resolved.commitSha, matches(RegExp(r'^[0-9a-f]{40}$')));
      if (_engine == ModelEngine.gguf) {
        expect(resolved.resolved.files.single.path, _payload);
        expect(resolved.resolved.files.single.sha256, isNotNull);
      } else {
        // An MLX snapshot is many files, and only the LFS ones carry a hash.
        expect(resolved.resolved.files.length, greaterThan(3));
        expect(resolved.resolved.fullyHashed, isFalse);
      }
      stdout.writeln(
        'GOLEM_ACCEPTANCE resolved $_repository@'
        '${resolved.resolved.commitSha} '
        'quant=${resolved.resolved.quantization} '
        'arch=${resolved.resolved.architecture} '
        'bytes=${resolved.resolved.totalBytes} '
        'profile=${resolved.profile?.key}',
      );

      // Through the same domain object the Advanced card stores.
      final spec = CustomModelSpec(
        repository: _repository,
        engine: _engine,
        profile: resolved.profile,
        resolved: resolved.resolved,
      );
      final entry = spec.toCatalogEntry();
      expect(entry.revision, resolved.resolved.commitSha);
      expect(entry.profileKey, 'qwen35');

      AcceptanceHud.step('Registering the resolved entry');
      final documents = await getApplicationDocumentsDirectory();
      final temp = await Directory.systemTemp.createTemp('golem-custom-state-');
      addTearDown(() => temp.delete(recursive: true));
      final repository = RealModelManagementRepository(
        stateFile: File('${temp.path}/flutter-model-v2.json'),
        documentsDirectory: documents.path,
        catalog: const [],
        downloader: BackgroundArtifactDownloader(),
        diskSpace: const DeviceStorageChannel(),
        backupExclusion: const DeviceStorageChannel(),
      );
      await repository.load();

      // Registering is what the card does after the user confirms.
      final added = await repository.addModel(entry);
      expect(added.statusOf(entry.key).phase, ArtifactPhase.notDownloaded);

      AcceptanceHud.step('Downloading ${entry.files.length} file(s)');
      // Progress comes off the download layer's own status stream, so the
      // screen cannot claim more than the repository has actually banked.
      ModelState? last;
      await for (final state
          in repository
              .download(entry.key)
              .timeout(const Duration(minutes: 20))) {
        last = state;
        AcceptanceHud.progress(
          received: state.statusOf(entry.key).downloadedBytes,
          total: entry.totalBytes,
          detail: state.statusOf(entry.key).phase.name,
        );
      }
      final status = last!.statusOf(entry.key);
      expect(
        status.phase,
        ArtifactPhase.installed,
        reason: 'last failure: ${status.failure}',
      );
      expect(status.downloadedBytes, entry.totalBytes);

      for (final file in entry.files) {
        final installed = File(
          '${documents.path}/${entry.installDirectory}/${file.path}',
        );
        expect(await installed.exists(), isTrue, reason: file.path);
        expect(await installed.length(), file.bytes, reason: file.path);
      }
      stdout.writeln(
        'GOLEM_ACCEPTANCE installed ${entry.files.length} file(s), '
        '${entry.totalBytes} bytes into ${entry.installDirectory}',
      );

      // The receipt is what lets a relaunch trust these bytes without rehashing.
      final receipt = File(
        '${documents.path}/${entry.installDirectory}/.golem-verified.json',
      );
      expect(await receipt.exists(), isTrue);
      final receiptBody = await receipt.readAsString();
      for (final file in entry.files) {
        // Every file is receipted, whether or not the Hub published a hash.
        expect(receiptBody, contains(file.path), reason: file.path);
      }

      AcceptanceHud.step('Checking skip-if-valid and the receipt');
      // Skip-if-valid: a second pass re-downloads nothing.
      final again = await repository.download(entry.key).toList();
      expect(again.last.statusOf(entry.key).phase, ArtifactPhase.installed);

      // A fresh repository reconciles it as installed from disk plus receipt.
      final relaunched = RealModelManagementRepository(
        stateFile: File('${temp.path}/flutter-model-v2.json'),
        documentsDirectory: documents.path,
        catalog: [entry],
        downloader: BackgroundArtifactDownloader(),
        diskSpace: const DeviceStorageChannel(),
        backupExclusion: const DeviceStorageChannel(),
      );
      expect(
        (await relaunched.load()).statusOf(entry.key).phase,
        ArtifactPhase.installed,
      );

      AcceptanceHud.step('Resolving a runtime configuration');
      // It resolves to a runtime configuration, which is what activation needs.
      final runtime = resolveModelRuntimeConfig(
        entry.key,
        catalog: [entry],
        profiles: ProfileRegistry.builtIn,
      );
      expect(runtime.profile.spec.key, 'qwen35');
      expect(
        runtime.modelPath,
        _engine == ModelEngine.gguf
            ? 'documents:${entry.installDirectory}/$_payload'
            : 'documents:${entry.installDirectory}',
      );
      // No projector was adopted, so nothing claims image capability.
      expect(runtime.supportsImages, isFalse);
      expect(runtime.projectorPath, isNull);
      stdout.writeln(
        'GOLEM_ACCEPTANCE runtime path=${runtime.modelPath} '
        'profile=${runtime.profile.spec.key} images=${runtime.supportsImages}',
      );

      if (_keep) {
        AcceptanceHud.finish('Done — install kept for generation');
        stdout.writeln('GOLEM_ACCEPTANCE kept install for generation');
        return;
      }
      AcceptanceHud.step('Deleting the install');
      final deleted = await repository.delete(entry.key);
      expect(deleted.statusOf(entry.key).phase, ArtifactPhase.notDownloaded);
      expect(
        await Directory('${documents.path}/${entry.installDirectory}').exists(),
        isFalse,
      );
      AcceptanceHud.finish('Done — nothing left on this device');
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
