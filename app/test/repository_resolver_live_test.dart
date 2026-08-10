@Tags(['live-hub'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_profile.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/services/hugging_face_api.dart';
import 'package:golem_flutter/core/services/repository_resolver.dart';

/// Resolution against the real Hugging Face Hub.
///
/// Skipped unless `GOLEM_LIVE_HUB=1`, so CI stays offline and model-free (#52).
/// Everything else about the resolver is covered by
/// `repository_resolver_test.dart` against scripted responses; what only a live
/// run can prove is that the shapes this implementation reads are the shapes the
/// Hub actually returns.
///
/// No weights are downloaded. The GGUF case ranged-reads the head of a file to
/// reach its embedded chat template — about 16 MiB, not the 1.2 GB payload.
void main() {
  final live = Platform.environment['GOLEM_LIVE_HUB'] == '1';
  final skip = live ? false : 'Set GOLEM_LIVE_HUB=1 to reach Hugging Face.';

  late HttpClientHuggingFaceApi api;
  setUp(() => api = HttpClientHuggingFaceApi());
  tearDown(() => api.close());

  HuggingFaceRepositoryResolver resolver() =>
      HuggingFaceRepositoryResolver(api: api, profiles: brokerProfileSpecs);

  test(
    'a real GGUF repository offers its quantizations and hides projectors',
    () async {
      // A quantization repository publishing one payload is the exception, not
      // the rule: this one carries 22 language builds and 3 projectors.
      final outcome = await resolver().resolve(
        repository: 'unsloth/Qwen3.5-2B-GGUF',
        engine: ModelEngine.gguf,
      );
      final choice = outcome as RepositoryNeedsWeightChoice;
      final paths = choice.candidates.map((candidate) => candidate.path);
      expect(paths, contains('Qwen3.5-2B-Q4_0.gguf'));
      expect(paths.length, greaterThan(5));
      // A projector is a .gguf too, and offering one as a language model would
      // produce a load failure the user could not diagnose.
      expect(paths.where((path) => path.contains('mmproj')), isEmpty);
      expect(
        choice.candidates.every((candidate) => candidate.bytes > 0),
        isTrue,
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a chosen GGUF payload resolves, and its embedded template is recognized',
    () async {
      final outcome = await resolver().resolve(
        repository: 'unsloth/Qwen3.5-2B-GGUF',
        engine: ModelEngine.gguf,
        weightsFile: 'Qwen3.5-2B-Q4_0.gguf',
      );
      expect(outcome, isA<RepositoryResolved>(), reason: '$outcome');
      final resolved = (outcome as RepositoryResolved).resolved;
      expect(resolved.commitSha, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(resolved.architecture, 'qwen35');
      expect(resolved.quantization, 'Q4_0');
      expect(resolved.files, hasLength(1));
      expect(resolved.files.single.role, ModelFileRole.weights);
      // The Hub's LFS hash for this exact file is the one the manifest pins,
      // which ties live resolution to the artifact this app already ships.
      expect(
        resolved.files.single.sha256,
        'cd70221bebaee0503e0f6717e174250cd7825aa88438b3aabec9ad55731d9bb1',
      );
      expect(resolved.fullyHashed, isTrue);
      // The end-to-end point: a real repository's real embedded template,
      // ranged-read out of the file head, matches a fingerprint taken from a
      // shipping artifact.
      expect(outcome.profile?.key, 'qwen35');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'an MLX snapshot resolves to its allowlisted files',
    () async {
      final outcome = await resolver().resolve(
        repository: 'mlx-community/Qwen3.5-2B-4bit',
        engine: ModelEngine.mlx,
      );
      expect(outcome, isA<RepositoryResolved>(), reason: '$outcome');
      final resolved = (outcome as RepositoryResolved).resolved;
      expect(resolved.architecture, 'qwen3_5');
      expect(resolved.quantization, '4-bit');
      final paths = resolved.files.map((file) => file.path).toSet();
      expect(paths, contains('config.json'));
      expect(paths, contains('model.safetensors'));
      expect(paths, isNot(contains('README.md')));
      // Large files carry an LFS hash, small metadata files do not: the mix this
      // repository's optional-hash verification exists for.
      expect(resolved.fullyHashed, isFalse);
      expect(outcome.profile?.key, 'qwen35');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a gated repository is refused from the API body',
    () async {
      // The Hub answers 200 here and only 401 on the files, so this must be
      // caught before any download is attempted.
      final outcome = await resolver().resolve(
        repository: 'meta-llama/Llama-3.1-8B-Instruct',
        engine: ModelEngine.gguf,
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.gated,
        reason: '$outcome',
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a repository that does not exist is not distinguished from private',
    () async {
      final outcome = await resolver().resolve(
        repository: 'golem-app/definitely-not-a-real-repository-xyz',
        engine: ModelEngine.gguf,
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.notFoundOrPrivate,
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
