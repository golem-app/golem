import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_profile.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/services/hugging_face_api.dart';
import 'package:golem_flutter/core/services/repository_resolver.dart';

import 'support/hub_fixtures.dart';

const _sha = 'f6d5376be1edb4d416d56da11e5397a961aca8ae';
const _repo = 'unsloth/Qwen3.5-2B-GGUF';
const _weights = 'Qwen3.5-2B-Q4_0.gguf';
const _weightsHash =
    'cd70221bebaee0503e0f6717e174250cd7825aa88438b3aabec9ad55731d9bb1';

String _fixture(String name) =>
    File('test/fixtures/chat_templates/$name').readAsStringSync();

String _revisionUrl(String repository, [String ref = 'main']) =>
    hubRevisionUrl(repository, ref, blobs: true).toString();

String _resolveUrl(String repository, String path, [String sha = _sha]) =>
    hubResolveUrl(repository, sha, path).toString();

void main() {
  ScriptedHuggingFaceApi api = ScriptedHuggingFaceApi();

  HuggingFaceRepositoryResolver resolver({
    Map<ModelEngine, Set<String>>? architectures,
  }) => HuggingFaceRepositoryResolver(
    api: api,
    // The real specs, so a resolved profile is the one the broker would render
    // with rather than a stand-in that could diverge.
    profiles: const {'gemma4': gemma4ProfileSpec, 'qwen35': qwen35ProfileSpec},
    architectures: architectures ?? supportedArchitectures,
  );

  setUp(() => api = ScriptedHuggingFaceApi());

  /// A GGUF repository whose embedded template is a real shipping one.
  void scriptGguf({
    String architecture = 'qwen35',
    String? template,
    List<Map<String, Object?>>? siblings,
  }) {
    api.responses[_revisionUrl(_repo)] = revisionInfo(
      sha: _sha,
      siblings:
          siblings ??
          [
            sibling('.gitattributes', 1500),
            sibling('README.md', 4000),
            sibling(_weights, 1214873856, sha256: _weightsHash),
            // A projector lives in plenty of real repositories and must not be
            // adopted: pairing one is a proven capability, not an inference.
            sibling(
              'Qwen3.5-2B.mmproj-q8_0.gguf',
              364664384,
              sha256: 'aa' * 32,
            ),
          ],
    );
    api.responses[_resolveUrl(_repo, _weights)] = ggufHeaderBytes(
      architecture: architecture,
      name: 'Qwen3.5-2B',
      chatTemplate: template ?? _fixture('qwen35-2b-gguf.jinja'),
    );
  }

  group('GGUF resolution', () {
    test('pins the commit, the payload, and the proven profile', () async {
      scriptGguf();
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
      );
      final resolved = (outcome as RepositoryResolved).resolved;
      expect(resolved.commitSha, _sha);
      expect(resolved.quantization, 'Q4_0');
      expect(resolved.architecture, 'qwen35');
      expect(resolved.displayName, 'Qwen3.5-2B');
      expect(resolved.files, hasLength(1));
      expect(resolved.files.single.path, _weights);
      expect(resolved.files.single.bytes, 1214873856);
      expect(resolved.files.single.sha256, _weightsHash);
      expect(resolved.files.single.role, ModelFileRole.weights);
      expect(resolved.fullyHashed, isTrue);
      // The template matched a shipping artifact, so the profile is proven.
      expect(outcome.profile, same(qwen35ProfileSpec));
    });

    test(
      'a moving ref is only ever read through the commit it named',
      () async {
        scriptGguf();
        // Only the commit-addressed URL is scripted; a resolver that fetched by
        // ref would 404 here, which is the point.
        await resolver().resolve(repository: _repo, engine: ModelEngine.gguf);
        expect(
          api.requested.where((url) => url.contains('/resolve/')),
          everyElement(contains('/resolve/$_sha/')),
        );
      },
    );

    test('a ref containing a slash is encoded as one segment', () async {
      api.responses[_revisionUrl(_repo, 'refs/pr/3')] = revisionInfo(
        sha: _sha,
        siblings: [sibling(_weights, 1214873856, sha256: _weightsHash)],
      );
      api.responses[_resolveUrl(_repo, _weights)] = ggufHeaderBytes(
        architecture: 'qwen35',
        chatTemplate: _fixture('qwen35-2b-gguf.jinja'),
      );
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
        ref: 'refs/pr/3',
      );
      expect(outcome, isA<RepositoryResolved>());
      expect(api.requested.first, contains('refs%2Fpr%2F3'));
    });

    test('an unknown template resolves without a profile', () async {
      // The common case for an arbitrary repository, and not an error: the
      // entry is downloadable and deletable, and refuses activation.
      scriptGguf(template: '{{ something else entirely }}');
      final outcome =
          await resolver().resolve(repository: _repo, engine: ModelEngine.gguf)
              as RepositoryResolved;
      expect(outcome.profileResolved, isFalse);
      expect(outcome.profile, isNull);
      // The fingerprint is still reported: it is what adding support would name.
      expect(outcome.templateFingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(outcome.resolved.files, hasLength(1));
    });

    test(
      'an unsupported architecture is refused before the template',
      () async {
        scriptGguf(architecture: 'mamba');
        final outcome = await resolver().resolve(
          repository: _repo,
          engine: ModelEngine.gguf,
        );
        expect(
          (outcome as RepositoryRejected).reason,
          RepositoryRejection.unsupportedArchitecture,
        );
      },
    );

    test('several payloads ask the user instead of guessing', () async {
      scriptGguf(
        siblings: [
          sibling('Qwen3.5-2B-Q4_0.gguf', 100, sha256: 'aa' * 32),
          sibling('Qwen3.5-2B-Q8_0.gguf', 200, sha256: 'bb' * 32),
          sibling('Qwen3.5-2B.mmproj-q8_0.gguf', 50, sha256: 'cc' * 32),
        ],
      );
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
      );
      final choice = outcome as RepositoryNeedsWeightChoice;
      // The projector is not offered as a language model.
      expect(choice.candidates.map((candidate) => candidate.path), [
        'Qwen3.5-2B-Q4_0.gguf',
        'Qwen3.5-2B-Q8_0.gguf',
      ]);
      // Nothing was fetched to decide this.
      expect(api.requested.where((url) => url.contains('/resolve/')), isEmpty);
    });

    test('a named payload selects it', () async {
      api.responses[_revisionUrl(_repo)] = revisionInfo(
        sha: _sha,
        siblings: [
          sibling('a-Q4_0.gguf', 1214873856, sha256: 'aa' * 32),
          sibling('b-Q8_0.gguf', 2214873856, sha256: 'bb' * 32),
        ],
      );
      api.responses[_resolveUrl(_repo, 'b-Q8_0.gguf')] = ggufHeaderBytes(
        architecture: 'qwen35',
        chatTemplate: _fixture('qwen35-2b-gguf.jinja'),
      );
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
        weightsFile: 'b-Q8_0.gguf',
      );
      final resolved = (outcome as RepositoryResolved).resolved;
      expect(resolved.files.single.path, 'b-Q8_0.gguf');
      expect(resolved.quantization, 'Q8_0');
    });

    test('a payload that is not in the listing is refused', () async {
      scriptGguf();
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
        weightsFile: 'somebody-elses.gguf',
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.missingRequiredFile,
      );
    });

    test('sharded weights are refused, not half-supported', () async {
      scriptGguf(
        siblings: [
          sibling('model-00001-of-00003.gguf', 100, sha256: 'aa' * 32),
          sibling('model-00002-of-00003.gguf', 100, sha256: 'bb' * 32),
          sibling('model-00003-of-00003.gguf', 100, sha256: 'cc' * 32),
        ],
      );
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.shardedWeights,
      );
    });

    test('a repository with no GGUF at all is refused', () async {
      scriptGguf(
        siblings: [sibling('README.md', 10), sibling('config.json', 5)],
      );
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.noWeights,
      );
    });

    test('pickle weights are named as such rather than "no weights"', () async {
      scriptGguf(
        siblings: [
          sibling('pytorch_model.bin', 100, sha256: 'aa' * 32),
          sibling('README.md', 10),
        ],
      );
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.unsafeWeightFormat,
      );
    });

    test('a header larger than the ladder allows is refused', () async {
      scriptGguf();
      // Truncated to less than the block needs, and the file claims to be far
      // larger, so every window comes back incomplete.
      api.responses[_resolveUrl(_repo, _weights)] = Uint8List.sublistView(
        ggufHeaderBytes(
          architecture: 'qwen35',
          chatTemplate: _fixture('qwen35-2b-gguf.jinja'),
        ),
        0,
        60,
      );
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.headerTooLarge,
      );
    });

    test('bytes that are not a GGUF are malformed metadata', () async {
      scriptGguf();
      api.responses[_resolveUrl(_repo, _weights)] = Uint8List.fromList(
        List.filled(64, 0x41),
      );
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.malformedMetadata,
      );
    });
  });

  group('MLX resolution', () {
    const mlxRepo = 'mlx-community/Qwen3.5-2B-4bit';
    const mlxSha = '674aaa7240b91e8012fcad5d791b7dfe5ba90207';

    void scriptMlx({
      List<Map<String, Object?>>? siblings,
      Map<String, Object?>? config,
      String? template,
      bool templateFile = true,
    }) {
      api.responses[_revisionUrl(mlxRepo)] = revisionInfo(
        sha: mlxSha,
        siblings:
            siblings ??
            [
              sibling('README.md', 4000),
              if (templateFile) sibling('chat_template.jinja', 7755),
              sibling('config.json', 3113),
              sibling('model.safetensors', 1722271785, sha256: 'dd' * 32),
              sibling('tokenizer.json', 19989343, sha256: 'ee' * 32),
              sibling('tokenizer_config.json', 1139),
              // Not on the allowlist: present in the repository, never fetched.
              sibling('training_args.bin', 4096, sha256: 'ff' * 32),
            ],
      );
      api.responses[_resolveUrl(mlxRepo, 'config.json', mlxSha)] =
          config ??
          {
            'model_type': 'qwen3_5',
            'quantization': {'bits': 4, 'group_size': 64},
          };
      final body = template ?? _fixture('qwen35-2b-mlx.jinja');
      if (templateFile) {
        api.responses[_resolveUrl(mlxRepo, 'chat_template.jinja', mlxSha)] =
            body;
      } else {
        api.responses[_resolveUrl(mlxRepo, 'tokenizer_config.json', mlxSha)] = {
          'chat_template': body,
        };
      }
    }

    test('selects the snapshot allowlist and the proven profile', () async {
      scriptMlx();
      final outcome = await resolver().resolve(
        repository: mlxRepo,
        engine: ModelEngine.mlx,
      );
      final resolved = (outcome as RepositoryResolved).resolved;
      expect(resolved.commitSha, mlxSha);
      expect(resolved.quantization, '4-bit');
      expect(resolved.architecture, 'qwen3_5');
      expect(outcome.profile, same(qwen35ProfileSpec));
      final paths = resolved.files.map((file) => file.path).toSet();
      expect(paths, {
        'model.safetensors',
        'chat_template.jinja',
        'config.json',
        'tokenizer.json',
        'tokenizer_config.json',
      });
      // Never a whole repository: the readme and the stray pickle stay behind.
      expect(paths, isNot(contains('README.md')));
      expect(paths, isNot(contains('training_args.bin')));
      // Mixed hash availability is the normal shape for an MLX snapshot.
      expect(resolved.fullyHashed, isFalse);
      expect(
        resolved.files.firstWhere((file) => file.path == 'config.json').sha256,
        isNull,
      );
    });

    test('the template can come from tokenizer_config instead', () async {
      scriptMlx(templateFile: false);
      final outcome = await resolver().resolve(
        repository: mlxRepo,
        engine: ModelEngine.mlx,
      );
      expect((outcome as RepositoryResolved).profile, same(qwen35ProfileSpec));
    });

    test('a list of named templates is not interpreted', () async {
      scriptMlx(templateFile: false);
      api.responses[_resolveUrl(mlxRepo, 'tokenizer_config.json', mlxSha)] = {
        'chat_template': [
          {'name': 'default', 'template': _fixture('qwen35-2b-mlx.jinja')},
        ],
      };
      final outcome =
          await resolver().resolve(repository: mlxRepo, engine: ModelEngine.mlx)
              as RepositoryResolved;
      // Picking one of several would be a guess about which the app renders.
      expect(outcome.profile, isNull);
      expect(outcome.templateFingerprint, isNull);
    });

    test('shards come from the index, never from the listing', () async {
      scriptMlx(
        siblings: [
          sibling('config.json', 3113),
          sibling('tokenizer.json', 100, sha256: 'ee' * 32),
          sibling('model.safetensors.index.json', 500),
          sibling('model-00001-of-00002.safetensors', 10, sha256: 'a1' * 32),
          sibling('model-00002-of-00002.safetensors', 20, sha256: 'a2' * 32),
          // Present but unreferenced, so it must not be fetched or counted.
          sibling('orphan.safetensors', 999, sha256: 'a3' * 32),
          sibling('chat_template.jinja', 7755),
        ],
      );
      api.responses[_resolveUrl(
        mlxRepo,
        'model.safetensors.index.json',
        mlxSha,
      )] = {
        'weight_map': {
          'a.weight': 'model-00001-of-00002.safetensors',
          'b.weight': 'model-00002-of-00002.safetensors',
          'c.weight': 'model-00001-of-00002.safetensors',
        },
      };
      final resolved =
          (await resolver().resolve(
                    repository: mlxRepo,
                    engine: ModelEngine.mlx,
                  )
                  as RepositoryResolved)
              .resolved;
      final paths = resolved.files.map((file) => file.path).toSet();
      expect(paths, contains('model-00001-of-00002.safetensors'));
      expect(paths, contains('model-00002-of-00002.safetensors'));
      expect(paths, isNot(contains('orphan.safetensors')));
      expect(resolved.totalBytes, 3113 + 100 + 500 + 10 + 20 + 7755);
    });

    test('an index naming an absent shard is inconsistent', () async {
      scriptMlx(
        siblings: [
          sibling('config.json', 3113),
          sibling('tokenizer.json', 100, sha256: 'ee' * 32),
          sibling('model.safetensors.index.json', 500),
          sibling('model-00001-of-00002.safetensors', 10, sha256: 'a1' * 32),
        ],
      );
      api.responses[_resolveUrl(
        mlxRepo,
        'model.safetensors.index.json',
        mlxSha,
      )] = {
        'weight_map': {'b.weight': 'model-00002-of-00002.safetensors'},
      };
      final outcome = await resolver().resolve(
        repository: mlxRepo,
        engine: ModelEngine.mlx,
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.inconsistentMetadata,
      );
    });

    test(
      'an index whose weight map escapes the directory is refused',
      () async {
        scriptMlx(
          siblings: [
            sibling('config.json', 3113),
            sibling('tokenizer.json', 100, sha256: 'ee' * 32),
            sibling('model.safetensors.index.json', 500),
            sibling('model.safetensors', 10, sha256: 'a1' * 32),
          ],
        );
        api.responses[_resolveUrl(
          mlxRepo,
          'model.safetensors.index.json',
          mlxSha,
        )] = {
          'weight_map': {'a.weight': '../../../etc/passwd'},
        };
        final outcome = await resolver().resolve(
          repository: mlxRepo,
          engine: ModelEngine.mlx,
        );
        expect(
          (outcome as RepositoryRejected).reason,
          RepositoryRejection.unsafePath,
        );
      },
    );

    test('a missing config or tokenizer is refused', () async {
      scriptMlx(
        siblings: [sibling('model.safetensors', 10, sha256: 'a1' * 32)],
      );
      expect(
        ((await resolver().resolve(
                  repository: mlxRepo,
                  engine: ModelEngine.mlx,
                ))
                as RepositoryRejected)
            .reason,
        RepositoryRejection.missingRequiredFile,
      );

      api.responses[_revisionUrl(mlxRepo)] = revisionInfo(
        sha: mlxSha,
        siblings: [
          sibling('config.json', 10),
          sibling('model.safetensors', 10, sha256: 'a1' * 32),
        ],
      );
      expect(
        ((await resolver().resolve(
                  repository: mlxRepo,
                  engine: ModelEngine.mlx,
                ))
                as RepositoryRejected)
            .reason,
        RepositoryRejection.missingRequiredFile,
      );
    });

    test('an unsupported model_type is refused', () async {
      // `qwen35` is the GGUF spelling; an MLX config declares `qwen3_5`. The
      // sets are per engine precisely so this is a rejection, not a pass.
      scriptMlx(config: {'model_type': 'qwen35'});
      final outcome = await resolver().resolve(
        repository: mlxRepo,
        engine: ModelEngine.mlx,
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.unsupportedArchitecture,
      );
    });

    test('a safetensors-free repository is refused by format', () async {
      scriptMlx(
        siblings: [
          sibling('config.json', 10),
          sibling('tokenizer.json', 10),
          sibling('pytorch_model.bin', 100, sha256: 'a1' * 32),
        ],
      );
      final outcome = await resolver().resolve(
        repository: mlxRepo,
        engine: ModelEngine.mlx,
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.unsafeWeightFormat,
      );
    });
  });

  group('repository-level refusals', () {
    test('a malformed identifier never reaches the network', () async {
      for (final candidate in [
        'nossslash',
        'too/many/slashes',
        '/leading',
        'trailing/',
        'has space/name',
        'owner/../escape',
        'https://huggingface.co/owner/name',
        'owner/name?query',
        '-leading-dash/name',
      ]) {
        final outcome = await resolver().resolve(
          repository: candidate,
          engine: ModelEngine.gguf,
        );
        expect(
          (outcome as RepositoryRejected).reason,
          RepositoryRejection.malformedIdentifier,
          reason: candidate,
        );
      }
      expect(api.requested, isEmpty);
    });

    test('an empty or control-character ref is refused', () async {
      for (final ref in ['', 'main\n', 'ma in']) {
        final outcome = await resolver().resolve(
          repository: _repo,
          engine: ModelEngine.gguf,
          ref: ref,
        );
        expect(
          (outcome as RepositoryRejected).reason,
          RepositoryRejection.malformedIdentifier,
          reason: 'ref "$ref"',
        );
      }
    });

    test('a duplicate is refused before the network', () async {
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
        existingKeys: {customCatalogKeyFor(_repo)},
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.duplicateEntry,
      );
      expect(api.requested, isEmpty);
    });

    test('gating is read from the body, not from a failed download', () async {
      // The Hub answers 200 for a gated repository, so this costs nothing and
      // gives the accurate reason instead of "not found".
      api.responses[_revisionUrl(
        'meta-llama/Llama-3.1-8B-Instruct',
      )] = revisionInfo(
        sha: _sha,
        siblings: [sibling('a.gguf', 1)],
        gated: 'manual',
      );
      final outcome = await resolver().resolve(
        repository: 'meta-llama/Llama-3.1-8B-Instruct',
        engine: ModelEngine.gguf,
      );
      expect((outcome as RepositoryRejected).reason, RepositoryRejection.gated);
      expect(api.requested.where((url) => url.contains('/resolve/')), isEmpty);
    });

    test('private and disabled are distinguished', () async {
      api.responses[_revisionUrl(_repo)] = revisionInfo(
        sha: _sha,
        siblings: [sibling('a.gguf', 1)],
        private: true,
      );
      expect(
        ((await resolver().resolve(repository: _repo, engine: ModelEngine.gguf))
                as RepositoryRejected)
            .reason,
        RepositoryRejection.notFoundOrPrivate,
      );

      api.responses[_revisionUrl(_repo)] = revisionInfo(
        sha: _sha,
        siblings: [sibling('a.gguf', 1)],
        disabled: true,
      );
      expect(
        ((await resolver().resolve(repository: _repo, engine: ModelEngine.gguf))
                as RepositoryRejected)
            .reason,
        RepositoryRejection.disabled,
      );
    });

    test('transport failures map to their own reasons', () async {
      const cases = {
        HubErrorKind.notFoundOrPrivate: RepositoryRejection.notFoundOrPrivate,
        HubErrorKind.rateLimited: RepositoryRejection.rateLimited,
        HubErrorKind.network: RepositoryRejection.network,
        HubErrorKind.malformed: RepositoryRejection.malformedMetadata,
        HubErrorKind.unexpectedStatus: RepositoryRejection.malformedMetadata,
        HubErrorKind.tooLarge: RepositoryRejection.headerTooLarge,
      };
      for (final entry in cases.entries) {
        api = ScriptedHuggingFaceApi({
          _revisionUrl(_repo): HubException(entry.key),
        });
        final outcome = await resolver().resolve(
          repository: _repo,
          engine: ModelEngine.gguf,
        );
        expect(
          (outcome as RepositoryRejected).reason,
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test('a listing with an escaping path is refused whole', () async {
      // One bad entry condemns the listing: a repository that publishes a path
      // like this cannot be pinned safely even if the rest looks fine.
      api.responses[_revisionUrl(_repo)] = revisionInfo(
        sha: _sha,
        siblings: [
          sibling(_weights, 100, sha256: _weightsHash),
          sibling('../../escape.json', 10),
        ],
      );
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.unsafePath,
      );
    });

    test('a size that disagrees with its own LFS size is refused', () async {
      api.responses[_revisionUrl(_repo)] = revisionInfo(
        sha: _sha,
        siblings: [
          {
            'rfilename': _weights,
            'size': 100,
            'lfs': {'sha256': _weightsHash, 'size': 200},
          },
        ],
      );
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
      );
      // Refused for what it is: a listing disagreeing with itself, not an
      // unsafe path — the copy the user sees must name the actual problem.
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.inconsistentMetadata,
      );
    });

    test('a weight file published with no size is refused', () async {
      // Zero bytes cannot be probed: no read window clamps into an empty file.
      // Both shapes reach it — an explicit zero, and a listing with no size at
      // all — and neither may leave the resolver by throwing.
      for (final entry in [
        {'rfilename': _weights, 'size': 0},
        {'rfilename': _weights},
      ]) {
        api.responses[_revisionUrl(_repo)] = revisionInfo(
          sha: _sha,
          siblings: [entry],
        );
        final outcome = await resolver().resolve(
          repository: _repo,
          engine: ModelEngine.gguf,
        );
        expect(
          (outcome as RepositoryRejected).reason,
          RepositoryRejection.malformedMetadata,
          reason: 'listing $entry',
        );
      }
    });

    test('a non-string LFS hash is refused rather than thrown past', () async {
      // A real size, so the refusal below can only come from the hash check —
      // a zero size would trip the unrelated zero-byte guard first, and a
      // silently null hash would install a multi-gigabyte file unverified.
      api.responses[_revisionUrl(_repo)] = revisionInfo(
        sha: _sha,
        siblings: [
          {
            'rfilename': _weights,
            'size': 4000000000,
            'lfs': {'oid': 42, 'size': 4000000000},
          },
        ],
      );
      final outcome = await resolver().resolve(
        repository: _repo,
        engine: ModelEngine.gguf,
      );
      expect(
        (outcome as RepositoryRejected).reason,
        RepositoryRejection.malformedMetadata,
      );
    });

    test('a missing or non-commit sha is refused', () async {
      for (final sha in [null, 'main', 'abc', '${'0' * 39}g']) {
        api.responses[_revisionUrl(_repo)] = {
          'sha': ?sha,
          'gated': false,
          'siblings': [sibling(_weights, 100, sha256: _weightsHash)],
        };
        final outcome = await resolver().resolve(
          repository: _repo,
          engine: ModelEngine.gguf,
        );
        expect(
          (outcome as RepositoryRejected).reason,
          RepositoryRejection.malformedMetadata,
          reason: 'sha $sha',
        );
      }
    });

    test('every rejection carries copy a user can act on', () async {
      for (final reason in RepositoryRejection.values) {
        expect(reason.message, isNotEmpty, reason: reason.name);
        expect(reason.message, endsWith('.'), reason: reason.name);
        // Copy must not leak identifiers, URLs or status codes.
        expect(reason.message, isNot(contains('http')), reason: reason.name);
        expect(
          reason.message,
          isNot(matches(RegExp(r'\b[45]\d\d\b'))),
          reason: reason.name,
        );
      }
    });
  });

  group('catalog keys', () {
    test('punctuation variants cannot collapse onto one directory', () {
      expect(
        customCatalogKeyFor('org/foo_bar'),
        isNot(customCatalogKeyFor('org/foo-bar')),
      );
      expect(customCatalogKeyFor(_repo), startsWith('custom-'));
      expect(customCatalogKeyFor(_repo), customCatalogKeyFor(_repo));
    });

    test('a key is a safe single path segment', () {
      for (final repository in [
        'org/foo.bar',
        'ORG/Foo_Bar',
        'a/b',
        'org/foo--bar',
      ]) {
        final key = customCatalogKeyFor(repository);
        expect(key, matches(RegExp(r'^custom-[a-z0-9-]+-[0-9a-f]{8}$')));
        expect(key, isNot(contains('/')));
        expect(key, isNot(contains('..')));
      }
    });
  });
}
