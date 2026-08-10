/// Turns a Hugging Face repository name into an immutable, inspectable model
/// configuration, or into a bounded reason why it cannot be one (#52).
///
/// This decides *what* may be fetched and pins it to one commit;
/// `RealModelManagementRepository` decides whether the bytes that arrive are
/// good. Fails closed, and never infers from a name, a file name or an engine.
library;

import 'dart:typed_data';

import '../domain/model_catalog.dart';
import '../domain/model_profile_spec.dart';
import '../domain/resolved_repository.dart';
import 'custom_repository_resolver.dart';
import 'chat_template_fingerprint.dart';
import 'gguf_header.dart';
import 'hugging_face_api.dart';

/// Why a repository cannot become a model, with the copy the user sees. No
/// catch-all "invalid repository": that tells a user nothing to change.
enum RepositoryRejection {
  malformedIdentifier(
    'Enter a public repository as owner/name, for example '
    'unsloth/gemma-4-E2B-it-qat-GGUF.',
  ),
  notFoundOrPrivate(
    'That repository could not be read. Check the name, and note that private '
    'repositories are not supported.',
  ),
  gated(
    'That repository requires accepting its licence on Hugging Face. Gated '
    'repositories are not supported.',
  ),
  disabled('That repository has been disabled on Hugging Face.'),
  rateLimited('Hugging Face is rate limiting this device. Try again shortly.'),
  network('Could not reach Hugging Face. Check your connection and try again.'),
  malformedMetadata(
    'Hugging Face returned something unexpected for that '
    'repository. Try again shortly.',
  ),
  unsafePath('That repository contains a file path this app will not write.'),
  noWeights('No weights this engine can load were found in that repository.'),
  shardedWeights(
    'That model is split across multiple weight files, which is not supported '
    'yet. Choose a single-file version.',
  ),
  unsafeWeightFormat(
    'That repository publishes its weights in a format this app will not load. '
    'Only safetensors and GGUF are supported.',
  ),
  missingRequiredFile(
    'That repository is missing files the engine needs to load it.',
  ),
  inconsistentMetadata(
    'That repository\'s file listing disagrees with itself, so it cannot be '
    'pinned safely.',
  ),
  unsupportedArchitecture(
    'This version of Golem cannot run that model architecture.',
  ),
  headerTooLarge('That model\'s metadata is larger than this app will read.'),
  duplicateEntry('That repository has already been added.');

  const RepositoryRejection(this.message);

  /// Never an identifier, a URL or a status code — those belong on the cause.
  final String message;
}

sealed class RepositoryResolution {
  const RepositoryResolution();
}

/// [profile] is null when nothing about the chat template proved a broker
/// profile — normal; the entry still lists and downloads, but cannot activate.
final class RepositoryResolved extends RepositoryResolution {
  const RepositoryResolved({
    required this.resolved,
    required this.profile,
    required this.templateFingerprint,
  });

  final ResolvedRepository resolved;
  final ModelProfileSpec? profile;

  /// The fingerprint that was looked up, present even when it matched nothing —
  /// it is what a future accepted-set addition would have to name.
  final String? templateFingerprint;

  bool get profileResolved => profile != null;
}

/// Several loadable weight files exist; the user picks, this never guesses.
final class RepositoryNeedsWeightChoice extends RepositoryResolution {
  const RepositoryNeedsWeightChoice(this.candidates);

  final List<ResolvedWeightCandidate> candidates;
}

final class ResolvedWeightCandidate {
  const ResolvedWeightCandidate(this.path, this.bytes);

  final String path;
  final int bytes;
}

final class RepositoryRejected extends RepositoryResolution {
  const RepositoryRejected(this.reason, {this.cause});

  final RepositoryRejection reason;

  /// Internal detail for logs — never shown.
  final Object? cause;

  String get message => reason.message;
}

/// The architectures each engine has been *proven* to load here, from the
/// artifacts this app ships. Widening either set needs evidence, not a guess
/// from a model card. Note the engines spell the same model differently: GGUF
/// declares `qwen35` while an MLX `config.json` declares `qwen3_5`, so one
/// shared set would have rejected every Qwen MLX repository.
const supportedArchitectures = <ModelEngine, Set<String>>{
  ModelEngine.gguf: {'gemma4', 'qwen35'},
  ModelEngine.mlx: {'gemma4', 'qwen3_5'},
};

/// An allowlist, so a repository cannot get arbitrary files written into the
/// app container by publishing them; anything unlisted is simply not fetched.
const _mlxMetadataFiles = {
  'added_tokens.json',
  'chat_template.jinja',
  'config.json',
  'generation_config.json',
  'merges.txt',
  'model.safetensors.index.json',
  'preprocessor_config.json',
  'processor_config.json',
  'special_tokens_map.json',
  'tokenizer.json',
  'tokenizer_config.json',
  'video_preprocessor_config.json',
  'vocab.json',
};

/// Weight containers that execute code or need a pickle reader when loaded.
/// Their presence is only fatal when nothing safe is published alongside.
const _unsafeWeightExtensions = {
  '.bin',
  '.ckpt',
  '.h5',
  '.msgpack',
  '.pkl',
  '.pt',
  '.pth',
};

final _identifierPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
final _shardPattern = RegExp(r'-\d{5}-of-\d{5}\.gguf$');
final _commitPattern = RegExp(r'^[0-9a-f]{40}$');

/// One file as the Hub described it.
final class _Sibling {
  const _Sibling(this.path, this.bytes, this.sha256);

  final String path;
  final int bytes;
  final String? sha256;
}

final class HuggingFaceRepositoryResolver implements CustomRepositoryResolver {
  HuggingFaceRepositoryResolver({
    required this.api,
    required this.profiles,
    this.architectures = supportedArchitectures,
  });

  final HuggingFaceApi api;

  /// Broker profiles by key, injected because core never imports the broker.
  final Map<String, ModelProfileSpec> profiles;

  final Map<ModelEngine, Set<String>> architectures;

  /// [existingKeys] are the keys already present, so a colliding repository is
  /// refused before anything is written. [weightsFile] picks one of several
  /// GGUF payloads; without it, ambiguity comes back as a needs-choice outcome.
  @override
  Future<RepositoryResolution> resolve({
    required String repository,
    required ModelEngine engine,
    String ref = 'main',
    String? weightsFile,
    Set<String> existingKeys = const {},
  }) async {
    if (!_validIdentifier(repository) || !_validRef(ref)) {
      return const RepositoryRejected(RepositoryRejection.malformedIdentifier);
    }
    if (existingKeys.contains(customCatalogKeyFor(repository))) {
      return const RepositoryRejected(RepositoryRejection.duplicateEntry);
    }

    final Map<String, Object?> info;
    try {
      info = await api.json(hubRevisionUrl(repository, ref, blobs: true));
    } on HubException catch (error) {
      return RepositoryRejected(_rejectionFor(error), cause: error);
    }

    // Gating is readable from the body: the API answers 200 for a gated
    // repository and only its downloads 401, so this reports the accurate
    // reason instead of "not found".
    final gated = info['gated'];
    if (gated != false && gated != null) {
      return const RepositoryRejected(RepositoryRejection.gated);
    }
    if (info['private'] == true) {
      return const RepositoryRejected(RepositoryRejection.notFoundOrPrivate);
    }
    if (info['disabled'] == true) {
      return const RepositoryRejected(RepositoryRejection.disabled);
    }

    final sha = info['sha'];
    if (sha is! String || !_commitPattern.hasMatch(sha)) {
      return const RepositoryRejected(
        RepositoryRejection.malformedMetadata,
        cause: 'revision endpoint returned no commit sha',
      );
    }

    final (siblings, refusal) = _siblingsOf(info);
    if (siblings == null) {
      return RepositoryRejected(refusal!);
    }
    if (siblings.isEmpty) {
      return const RepositoryRejected(RepositoryRejection.malformedMetadata);
    }

    return switch (engine) {
      ModelEngine.gguf => _resolveGguf(repository, sha, siblings, weightsFile),
      ModelEngine.mlx => _resolveMlx(repository, sha, siblings),
    };
  }

  // ---------------------------------------------------------------- GGUF

  Future<RepositoryResolution> _resolveGguf(
    String repository,
    String sha,
    List<_Sibling> siblings,
    String? weightsFile,
  ) async {
    final ggufs = siblings
        .where((file) => file.path.toLowerCase().endsWith('.gguf'))
        .toList();
    // A projector is a .gguf too, and pairing one with weights is a proven
    // capability (#18): custom entries stay text-only, so projectors are cut.
    final payloads = ggufs
        .where((file) => !_looksLikeProjector(file.path))
        .toList();
    if (payloads.isEmpty) {
      return RepositoryRejected(_unsafeOrMissing(siblings));
    }
    if (payloads.every((file) => _shardPattern.hasMatch(file.path))) {
      return const RepositoryRejected(RepositoryRejection.shardedWeights);
    }
    final whole = payloads
        .where((file) => !_shardPattern.hasMatch(file.path))
        .toList();
    final _Sibling chosen;
    if (weightsFile != null) {
      final match = whole.where((file) => file.path == weightsFile);
      if (match.isEmpty) {
        return const RepositoryRejected(
          RepositoryRejection.missingRequiredFile,
        );
      }
      chosen = match.first;
    } else if (whole.length == 1) {
      chosen = whole.single;
    } else {
      return RepositoryNeedsWeightChoice([
        for (final file in whole)
          ResolvedWeightCandidate(file.path, file.bytes),
      ]);
    }

    // A listing that published no size leaves bytes at 0, which no window can
    // be clamped into. Refuse it here rather than in arithmetic downstream.
    if (chosen.bytes <= 0) {
      return const RepositoryRejected(
        RepositoryRejection.malformedMetadata,
        cause: 'weight file published with no size',
      );
    }

    final probe = await _probeGgufHeader(repository, sha, chosen);
    if (probe is RepositoryRejected) return probe;
    final metadata = (probe as GgufComplete).metadata;

    final architecture = metadata.architecture;
    if (architecture == null ||
        !architectures[ModelEngine.gguf]!.contains(architecture)) {
      return RepositoryRejected(
        RepositoryRejection.unsupportedArchitecture,
        cause: 'architecture "$architecture"',
      );
    }

    return _finish(
      resolved: ResolvedRepository(
        commitSha: sha,
        quantization: _quantizationFromName(chosen.path),
        architecture: architecture,
        displayName: metadata.name,
        files: [
          ModelArtifactFile(
            path: chosen.path,
            bytes: chosen.bytes,
            sha256: chosen.sha256,
            role: ModelFileRole.weights,
          ),
        ],
      ),
      template: metadata.chatTemplate,
    );
  }

  /// Grows the window until the metadata block is readable, returning either a
  /// [GgufComplete] or a [RepositoryRejected]. The first window is deliberately
  /// small so an unsupported architecture — the first pair — costs little.
  Future<Object> _probeGgufHeader(
    String repository,
    String sha,
    _Sibling weights,
  ) async {
    final url = hubResolveUrl(repository, sha, weights.path);
    var index = 0;
    var window = ggufProbeWindows.first;
    while (true) {
      final Uint8List bytes;
      try {
        bytes = await api.range(
          url,
          start: 0,
          endInclusive: window.clamp(1, weights.bytes) - 1,
        );
      } on HubException catch (error) {
        return RepositoryRejected(_rejectionFor(error), cause: error);
      }
      final probe = parseGgufHeader(bytes);
      switch (probe) {
        case GgufComplete():
          return probe;
        case GgufUnreadable(:final reason):
          return RepositoryRejected(
            RepositoryRejection.malformedMetadata,
            cause: reason,
          );
        case GgufIncomplete(:final atLeastBytes, :final partial):
          // Reject on architecture the moment it is known, before widening.
          final architecture = partial.architecture;
          if (architecture != null &&
              !architectures[ModelEngine.gguf]!.contains(architecture)) {
            return RepositoryRejected(
              RepositoryRejection.unsupportedArchitecture,
              cause: 'architecture "$architecture"',
            );
          }
          if (window >= weights.bytes) {
            return const RepositoryRejected(
              RepositoryRejection.malformedMetadata,
              cause: 'metadata block ran past the end of the file',
            );
          }
          index++;
          if (index >= ggufProbeWindows.length) {
            return const RepositoryRejected(RepositoryRejection.headerTooLarge);
          }
          // The bound skips one long value in a step; the ladder converges.
          window = ggufProbeWindows[index] > atLeastBytes
              ? ggufProbeWindows[index]
              : atLeastBytes;
      }
    }
  }

  // ----------------------------------------------------------------- MLX

  Future<RepositoryResolution> _resolveMlx(
    String repository,
    String sha,
    List<_Sibling> siblings,
  ) async {
    final byPath = {for (final file in siblings) file.path: file};
    final safetensors = siblings
        .where((file) => file.path.endsWith('.safetensors'))
        .toList();
    if (safetensors.isEmpty) {
      return RepositoryRejected(_unsafeOrMissing(siblings));
    }
    if (!byPath.containsKey('config.json')) {
      return const RepositoryRejected(RepositoryRejection.missingRequiredFile);
    }
    if (!byPath.containsKey('tokenizer.json') &&
        !byPath.containsKey('tokenizer_config.json')) {
      return const RepositoryRejected(RepositoryRejection.missingRequiredFile);
    }

    // Shards are named by the index, not guessed from the listing: a stray
    // .safetensors that no index references must not be fetched or counted.
    final index = byPath['model.safetensors.index.json'];
    final List<_Sibling> weights;
    if (index != null) {
      final referenced = await _shardsFromIndex(repository, sha, index);
      if (referenced is RepositoryRejected) return referenced;
      final names = referenced as Set<String>;
      final missing = names.where((name) => !byPath.containsKey(name));
      if (missing.isNotEmpty) {
        return RepositoryRejected(
          RepositoryRejection.inconsistentMetadata,
          cause: 'index references absent files: ${missing.join(', ')}',
        );
      }
      weights = [for (final name in names) byPath[name]!];
    } else {
      final single = byPath['model.safetensors'];
      if (single == null) {
        return const RepositoryRejected(
          RepositoryRejection.missingRequiredFile,
          cause: 'no model.safetensors and no index naming shards',
        );
      }
      weights = [single];
    }

    final Map<String, Object?> config;
    try {
      config = await api.json(hubResolveUrl(repository, sha, 'config.json'));
    } on HubException catch (error) {
      return RepositoryRejected(_rejectionFor(error), cause: error);
    }
    final architecture = config['model_type'];
    if (architecture is! String ||
        !architectures[ModelEngine.mlx]!.contains(architecture)) {
      return RepositoryRejected(
        RepositoryRejection.unsupportedArchitecture,
        cause: 'model_type "$architecture"',
      );
    }

    final template = await _mlxTemplate(repository, sha, byPath);
    if (template is RepositoryRejected) return template;

    final metadata = [
      for (final name in _mlxMetadataFiles)
        if (byPath.containsKey(name)) byPath[name]!,
    ];
    return _finish(
      resolved: ResolvedRepository(
        commitSha: sha,
        quantization: _mlxQuantization(config),
        architecture: architecture,
        files: [
          for (final file in weights)
            ModelArtifactFile(
              path: file.path,
              bytes: file.bytes,
              sha256: file.sha256,
              role: ModelFileRole.snapshot,
            ),
          for (final file in metadata)
            ModelArtifactFile(
              path: file.path,
              bytes: file.bytes,
              sha256: file.sha256,
            ),
        ],
      ),
      template: template as String?,
    );
  }

  /// The distinct shard filenames an index's `weight_map` names.
  Future<Object> _shardsFromIndex(
    String repository,
    String sha,
    _Sibling index,
  ) async {
    final Map<String, Object?> body;
    try {
      body = await api.json(hubResolveUrl(repository, sha, index.path));
    } on HubException catch (error) {
      return RepositoryRejected(_rejectionFor(error), cause: error);
    }
    final map = body['weight_map'];
    if (map is! Map || map.isEmpty) {
      return const RepositoryRejected(
        RepositoryRejection.inconsistentMetadata,
        cause: 'safetensors index has no weight_map',
      );
    }
    final names = <String>{};
    for (final value in map.values) {
      if (value is! String || !_safeRelativePath(value)) {
        return const RepositoryRejected(RepositoryRejection.unsafePath);
      }
      names.add(value);
    }
    return names;
  }

  /// The chat template an MLX snapshot publishes, or null when it publishes
  /// none. A `RepositoryRejected` is returned when it cannot be read at all.
  Future<Object?> _mlxTemplate(
    String repository,
    String sha,
    Map<String, _Sibling> byPath,
  ) async {
    try {
      if (byPath.containsKey('chat_template.jinja')) {
        return await api.text(
          hubResolveUrl(repository, sha, 'chat_template.jinja'),
        );
      }
      if (byPath.containsKey('tokenizer_config.json')) {
        final config = await api.json(
          hubResolveUrl(repository, sha, 'tokenizer_config.json'),
        );
        final template = config['chat_template'];
        // A list of named templates is a shape this app does not interpret;
        // treating one of them as "the" template would be a guess.
        return template is String ? template : null;
      }
    } on HubException catch (error) {
      return RepositoryRejected(_rejectionFor(error), cause: error);
    }
    return null;
  }

  // -------------------------------------------------------------- shared

  RepositoryResolution _finish({
    required ResolvedRepository resolved,
    required String? template,
  }) {
    final fingerprint = template == null
        ? null
        : chatTemplateFingerprint(template);
    final key = template == null ? null : profileKeyForChatTemplate(template);
    return RepositoryResolved(
      resolved: resolved,
      profile: key == null ? null : profiles[key],
      templateFingerprint: fingerprint,
    );
  }

  /// "Weights we refuse to load" and "no weights" are different, useful facts.
  RepositoryRejection _unsafeOrMissing(List<_Sibling> siblings) {
    final unsafe = siblings.any(
      (file) => _unsafeWeightExtensions.any(
        (extension) => file.path.toLowerCase().endsWith(extension),
      ),
    );
    return unsafe
        ? RepositoryRejection.unsafeWeightFormat
        : RepositoryRejection.noWeights;
  }

  /// A null list refuses the whole listing, and the rejection names why.
  (List<_Sibling>?, RepositoryRejection?) _siblingsOf(
    Map<String, Object?> info,
  ) {
    final raw = info['siblings'];
    if (raw is! List) return (const [], null);
    final files = <_Sibling>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final path = item['rfilename'];
      if (path is! String) continue;
      if (!_safeRelativePath(path)) {
        return (null, RepositoryRejection.unsafePath);
      }
      final lfs = item['lfs'];
      final declared = item['size'];
      final lfsSize = lfs is Map ? lfs['size'] : null;
      // Two sources for one fact: a disagreement means nothing can be pinned.
      if (declared is int && lfsSize is int && declared != lfsSize) {
        return (null, RepositoryRejection.inconsistentMetadata);
      }
      final sha256 = lfs is Map ? lfs['sha256'] : null;
      final oid = lfs is Map ? lfs['oid'] : null;
      // Tested rather than cast: a non-string hash is a listing this
      // resolver refuses, not an exception thrown past its contract — and
      // not a silent null, which would install the file unverified.
      if (sha256 is! String? || oid is! String?) {
        return (null, RepositoryRejection.malformedMetadata);
      }
      files.add(
        _Sibling(
          path,
          declared is int ? declared : (lfsSize is int ? lfsSize : 0),
          sha256 ?? oid,
        ),
      );
    }
    return (files, null);
  }
}

bool _validIdentifier(String repository) {
  final parts = repository.split('/');
  if (parts.length != 2) return false;
  return parts.every(
    (part) =>
        part.isNotEmpty &&
        part.length <= 96 &&
        _identifierPattern.hasMatch(part),
  );
}

bool _validRef(String ref) =>
    ref.isNotEmpty &&
    ref.length <= 128 &&
    !ref.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);

/// Rejects anything that could escape the install directory.
bool _safeRelativePath(String path) {
  if (path.isEmpty || path.length > 255) return false;
  if (path.startsWith('/') || path.contains('\\')) return false;
  if (path.contains('//')) return false;
  final segments = path.split('/');
  return !segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  );
}

bool _looksLikeProjector(String path) {
  final name = path.split('/').last.toLowerCase();
  return name.contains('mmproj');
}

/// `Qwen3.5-2B-Q4_0.gguf` → `Q4_0`. A display label only; llama.cpp reads the
/// real quantization from the file itself.
String _quantizationFromName(String path) {
  final name = path.split('/').last;
  final match = RegExp(
    r'[-.]((?:IQ|Q)\d+(?:_[A-Za-z0-9]+)*|F16|BF16|F32)(?=\.gguf$)',
    caseSensitive: false,
  ).firstMatch(name);
  return match?.group(1) ?? 'custom';
}

String _mlxQuantization(Map<String, Object?> config) {
  final quantization = config['quantization'];
  if (quantization is Map) {
    final bits = quantization['bits'];
    if (bits is int) return '$bits-bit';
  }
  return 'custom';
}

/// Maps a transport outcome to the reason a user is shown;
/// [HubErrorKind.notFoundOrPrivate] deliberately keeps its ambiguity.
RepositoryRejection _rejectionFor(HubException error) => switch (error.kind) {
  HubErrorKind.notFoundOrPrivate => RepositoryRejection.notFoundOrPrivate,
  HubErrorKind.rateLimited => RepositoryRejection.rateLimited,
  HubErrorKind.network => RepositoryRejection.network,
  HubErrorKind.malformed ||
  HubErrorKind.unexpectedStatus => RepositoryRejection.malformedMetadata,
  HubErrorKind.tooLarge => RepositoryRejection.headerTooLarge,
};
