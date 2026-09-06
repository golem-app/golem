import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/app/launch_composition.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Golem Model Lab keeps its models in its own container (ADR 0021). On a
/// real lab build this proves the composition resolves that container, that
/// the repository verifies provisioned bytes there, and that nothing touches
/// the consumer flavors' shared documents directory. The downloader's own
/// destination is pinned by `artifact_task_metadata_test.dart` — provisioned
/// files never reach the plugin, since the repository skips a file whose size
/// already matches:
///
///   flutter test integration_test/lab_storage_test.dart -d macos \
///     --flavor lab --dart-define=GOLEM_LAB_STORAGE=true
///
/// Provision the artifact first — hard links from a fetched copy are enough:
///
///   LAB="$HOME/Library/Application Support/app.golem.lab/Documents/models"
///   mkdir -p "$LAB/qwen35-gguf" && ln WEIGHTS PROJECTOR "$LAB/qwen35-gguf/"
///
/// Download then verifies the bytes in place with no network. Any transfer at
/// all is the failure this test exists to catch: the plugin looking somewhere
/// the repository does not. CI never sets the define, so this self-skips.
const _enabled = bool.fromEnvironment('GOLEM_LAB_STORAGE');
const _artifactKey = String.fromEnvironment(
  'GOLEM_LAB_STORAGE_ARTIFACT',
  defaultValue: 'qwen35-gguf',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the lab verifies a provisioned artifact in its own container, offline',
    skip: _enabled
        ? false
        : 'Set --dart-define=GOLEM_LAB_STORAGE=true on a --flavor lab build.',
    () async {
      expect(
        AppIdentity.current.isLab,
        isTrue,
        reason: 'build with --flavor lab',
      );
      expect(kLabBuild, isTrue);
      final support = await getApplicationSupportDirectory();
      final platformDocuments = await getApplicationDocumentsDirectory();

      final dependencies = await composeLaunch(identity: AppIdentity.current);
      expect(dependencies.documentsPath, '${support.path}/Documents');
      expect(dependencies.backendConfig.simulatedInference, isFalse);

      final entry = modelCatalog.firstWhere((e) => e.key == _artifactKey);
      final root = '${dependencies.documentsPath}/${entry.installDirectory}';
      for (final spec in entry.files) {
        final file = File('$root/${spec.path}');
        expect(
          file.existsSync() && file.lengthSync() == spec.bytes,
          isTrue,
          reason: 'provision ${spec.path} (${spec.bytes} bytes) under $root',
        );
      }
      final consumerInstall = Directory(
        '${platformDocuments.path}/${entry.installDirectory}',
      );
      // Every file's size and modification time: the lab must not add to,
      // rewrite or receipt the consumer flavors' copy, present or not.
      Map<String, (int, DateTime)> consumerListing() =>
          consumerInstall.existsSync()
          ? {
              for (final file
                  in consumerInstall
                      .listSync(recursive: true)
                      .whereType<File>())
                file.path: (file.lengthSync(), file.lastModifiedSync()),
            }
          : const {};
      final consumerBefore = consumerListing();

      final repository = dependencies.modelManagementRepository;
      await repository.load();
      ModelState? last;
      var sawVerifying = false;
      await for (final state
          in repository
              .download(_artifactKey)
              .timeout(const Duration(minutes: 5))) {
        last = state;
        final status = state.statusOf(_artifactKey);
        if (status.phase == ArtifactPhase.verifying) sawVerifying = true;
        // The repository publishes one downloading snapshot before it hashes;
        // bytes moving after that would be the network filling the plugin's
        // destination because it is not the repository's. Stop it at once.
        if (status.phase == ArtifactPhase.downloading &&
            status.downloadedBytes > entry.totalBytes) {
          await repository.cancel(_artifactKey);
          fail('the downloader fetched bytes for files already on disk');
        }
      }
      final status = last!.statusOf(_artifactKey);
      expect(
        status.phase,
        ArtifactPhase.installed,
        reason: 'last failure: ${status.failure}',
      );
      expect(sawVerifying, isTrue, reason: 'the bytes were hashed in place');
      expect(File('$root/.golem-verified.json').existsSync(), isTrue);
      // Nothing reached the consumer flavors' shared documents directory.
      expect(consumerListing(), consumerBefore);
      // The plugin's own idea of the destination is the repository's: a second
      // pass finds the receipt and does nothing at all.
      final again = await repository
          .download(_artifactKey)
          .timeout(const Duration(minutes: 1))
          .toList();
      expect(again.last.statusOf(_artifactKey).phase, ArtifactPhase.installed);
      expect(
        again.where(
          (s) => s.statusOf(_artifactKey).phase == ArtifactPhase.verifying,
        ),
        isEmpty,
        reason: 'a receipted install is not re-hashed',
      );
      stdout.writeln(
        'GOLEM_LAB_STORAGE artifact=$_artifactKey root=$root '
        'bytes=${entry.totalBytes} verified=offline',
      );
    },
  );
}
