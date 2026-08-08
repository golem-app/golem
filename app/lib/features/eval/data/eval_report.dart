import 'dart:convert';
import 'dart:io';

import 'package:golem_flutter/broker/model_profile.dart';
import 'package:golem_flutter/broker/runtime.dart';

import '../application/eval_runner.dart';

/// The pinned artifacts the report can auto-cite.
const _knownArtifacts = <InfernoModelArtifact>[
  gemma4E2BGgufQ4,
  gemma4E2BMlx4Bit,
  qwen35GgufQ4,
  qwen35Mlx4Bit,
];

/// Which profile each pinned repository belongs to. The profile decides the
/// template, stop policy, and sampling — evaluating a pinned artifact under
/// another family's profile produces numbers that describe nothing, so the
/// driver fails loudly on a mismatch instead of recording them.
const _pinnedProfileKeys = <String, String>{
  'unsloth/gemma-4-E2B-it-qat-GGUF': 'gemma4',
  'mlx-community/gemma-4-e2b-it-4bit': 'gemma4',
  'YoozLabs/Qwen3.5-4B-qat-GGUF': 'qwen35',
  'YoozLabs/Qwen3.5-4B-qat-lean-4bit-mlx': 'qwen35',
};

/// The profile family of a pin-cited artifact, or null when the artifact is
/// not a verified pin (unpinned quants cannot be family-checked).
String? profileKeyForPinnedRepository(String? repository) =>
    repository == null ? null : _pinnedProfileKeys[repository];

/// Matches an artifact to a manifest pin. The name alone is not provenance —
/// a requantized file with a pinned filename must not be cited as the pin —
/// so a GGUF must also carry the pinned byte size, and an MLX directory must
/// hold every pinned file at its exact pinned size ([fileSizes] is the
/// on-disk inventory keyed by manifest-relative path; stray extras like
/// `.DS_Store` are ignored). Byte-identity still isn't proven; for that,
/// re-fetch through `tool/fetch_model.dart`, which verifies SHA-256.
InfernoModelArtifact? matchPinnedArtifact({
  required String label,
  required BrokerEngine engine,
  int? sizeBytes,
  Map<String, int>? fileSizes,
}) {
  for (final artifact in _knownArtifacts) {
    final matches = switch (engine) {
      BrokerEngine.llamaCpp =>
        sizeBytes != null &&
            artifact.files.any(
              (file) =>
                  file.path.split('/').last == label && file.bytes == sizeBytes,
            ),
      BrokerEngine.mlx =>
        artifact.repository.split('/').last == label &&
            fileSizes != null &&
            artifact.files.every((file) => fileSizes[file.path] == file.bytes),
    };
    if (matches) return artifact;
  }
  return null;
}

final class EvalArtifactRecord {
  const EvalArtifactRecord({
    required this.label,
    this.sizeBytes,
    this.pinnedRepository,
    this.pinnedRevision,
  });

  final String label;
  final int? sizeBytes;
  final String? pinnedRepository;
  final String? pinnedRevision;

  String get pinSummary => pinnedRepository == null
      ? 'no pin match (name+size)'
      : '$pinnedRepository @ ${pinnedRevision!.substring(0, 8)}';
}

/// Stats an artifact on disk and matches it against the manifest pins. The
/// directory total is informational only — a stray unreadable subdirectory
/// degrades it to null instead of aborting the report, and pin matching
/// stats the pinned paths directly.
EvalArtifactRecord describeArtifact(EvalCombo combo) {
  final entity = FileSystemEntity.isDirectorySync(combo.path)
      ? Directory(combo.path)
      : File(combo.path);
  int? sizeBytes;
  Map<String, int>? fileSizes;
  if (entity is File && entity.existsSync()) {
    sizeBytes = entity.lengthSync();
  } else if (entity is Directory && entity.existsSync()) {
    try {
      sizeBytes = entity
          .listSync(recursive: true)
          .whereType<File>()
          .fold<int>(0, (sum, file) => sum + file.lengthSync());
    } on FileSystemException {
      sizeBytes = null;
    }
    fileSizes = {
      for (final artifact in _knownArtifacts)
        if (artifact.repository.split('/').last == combo.label)
          for (final pinnedFile in artifact.files)
            if (File('${combo.path}/${pinnedFile.path}').existsSync())
              pinnedFile.path: File(
                '${combo.path}/${pinnedFile.path}',
              ).lengthSync(),
    };
  }
  final pinned = matchPinnedArtifact(
    label: combo.label,
    engine: combo.engine,
    sizeBytes: sizeBytes,
    fileSizes: fileSizes,
  );
  return EvalArtifactRecord(
    label: combo.label,
    sizeBytes: sizeBytes,
    pinnedRepository: pinned?.repository,
    pinnedRevision: pinned?.revision,
  );
}

final class EvalRunReport {
  const EvalRunReport({
    required this.createdAt,
    required this.host,
    required this.profile,
    required this.results,
    required this.artifacts,
  });

  final DateTime createdAt;
  final String host;

  /// The run's template profile — an experimental variable, since
  /// mode-specific sampling alone swings a run between an answer and a
  /// budget-exhausted think loop, so the evidence must record it. Combos
  /// that know their own family (catalog installs) record theirs per
  /// result and this one only covers the rest.
  final ModelProfile profile;
  final List<EvalComboResult> results;
  final Map<String, EvalArtifactRecord> artifacts;

  static const _enginePins = <String, String>{
    'llamaCppRelease': llamaCppRelease,
    'llamaCppRevision': llamaCppRevision,
    'mlxSwiftVersion': mlxSwiftVersion,
    'mlxSwiftLmVersion': mlxSwiftLmVersion,
  };

  /// The machine-readable evidence. Like the Markdown, it never carries
  /// absolute paths — artifacts are identified by label, size, and pin — so
  /// both outputs are committable as-is.
  Map<String, Object?> toJson() => {
    'createdAt': createdAt.toIso8601String(),
    'host': host,
    'profile': {
      'key': profile.key,
      'stopSequences': profile.stopSequences,
      'stopTokenIds': profile.stopTokenIds,
      'sampling': {
        for (final MapEntry(:key, :value) in {
          'thinking': profile.sampling(reasoningEnabled: true),
          'direct': profile.sampling(reasoningEnabled: false),
        }.entries)
          key: {
            'maxTokens': value.maxTokens,
            'temperature': value.temperature,
            'topP': value.topP,
          },
      },
    },
    'enginePins': _enginePins,
    'artifacts': [
      for (final record in artifacts.values)
        {
          'label': record.label,
          'sizeBytes': record.sizeBytes,
          'pinnedRepository': record.pinnedRepository,
          'pinnedRevision': record.pinnedRevision,
        },
    ],
    'results': [
      for (final combo in results)
        {
          'artifact': combo.combo.label,
          'engine': combo.combo.engine.name,
          'profile': combo.combo.profileKey ?? profile.key,
          'loadSeconds': combo.loadSeconds,
          'passed': combo.failures.isEmpty,
          'prompts': [
            for (final result in combo.promptResults)
              {
                'id': result.promptId,
                'passed': result.passed,
                'answer': result.answer,
                'reasoning': result.reasoning,
                'stopReason': result.stopReason,
                'fnv1a64': result.rawTextHash,
                'rawTextLength': result.rawTextLength,
                'error': result.error,
                'metrics': switch (result.metrics) {
                  null => null,
                  final m => {
                    'decodeTokensPerSecond': m.decodeTokensPerSecond,
                    'promptTokensPerSecond': m.promptTokensPerSecond,
                    'generatedTokenCount': m.tokenCount,
                    'promptTokenCount': m.promptTokenCount,
                    'timeToFirstTokenSeconds': m.timeToFirstTokenSeconds,
                    'elapsedSeconds': m.elapsedSeconds,
                    'peakPhysicalFootprintBytes': m.peakPhysicalFootprintBytes,
                  },
                },
                'checks': [
                  for (final check in result.checkResults)
                    {
                      'description': check.description,
                      'required': check.required,
                      'passed': check.passed,
                    },
                ],
              },
          ],
        },
    ],
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// The human-readable evidence. Carries labels, never absolute paths, so
  /// a report can be committed under `docs/evals/` as-is.
  String renderMarkdown() {
    final buffer = StringBuffer()
      ..writeln(
        '# Golem model evaluation — '
        '${createdAt.toIso8601String().substring(0, 10)}',
      )
      ..writeln()
      ..writeln('- Host: $host')
      ..writeln(
        '- Template profile: `${profile.key}` — '
        'thinking ${_sampling(profile.sampling(reasoningEnabled: true))}, '
        'direct ${_sampling(profile.sampling(reasoningEnabled: false))}; '
        'stop `${profile.stopSequences.join(' ')}` '
        '${profile.stopTokenIds}',
      )
      ..writeln(
        '- Engine pins: llama.cpp $llamaCppRelease '
        '(`${llamaCppRevision.substring(0, 8)}`), '
        'MLX Swift $mlxSwiftVersion / MLX Swift LM $mlxSwiftLmVersion',
      )
      ..writeln(
        '- Mac numbers serve answer quality and relative comparison only — '
        'never quote them as mobile performance '
        '(`docs/notes/determinism-probe.md`).',
      );
    for (final combo in results) {
      final artifact = artifacts[combo.combo.label];
      buffer
        ..writeln()
        ..writeln('## ${combo.combo.label} · ${combo.combo.engine.name}')
        ..writeln()
        ..writeln(
          '- Artifact: ${combo.combo.label}'
          '${artifact?.sizeBytes == null ? '' : ' (${_gib(artifact!.sizeBytes!)} GiB)'}'
          ' — ${artifact?.pinSummary ?? 'unknown'}',
        )
        ..writeln('- Profile: `${combo.combo.profileKey ?? profile.key}`')
        ..writeln('- Load: ${combo.loadSeconds.toStringAsFixed(1)} s')
        ..writeln(
          '- Result: ${combo.failures.isEmpty ? 'PASS' : 'FAIL'}'
          '${combo.failures.isEmpty ? '' : ' — ${combo.failures.length} failure(s)'}',
        )
        ..writeln()
        ..writeln(
          '| prompt | ok | decode tok/s | prompt tok/s | ttft s | peak GiB '
          '| tokens | stop | fnv1a64 |',
        )
        ..writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
      for (final result in combo.promptResults) {
        final m = result.metrics;
        buffer.writeln(
          '| ${result.promptId} '
          '| ${result.error != null ? 'error' : (result.passed ? 'pass' : 'FAIL')} '
          '| ${m?.decodeTokensPerSecond.toStringAsFixed(1) ?? '—'} '
          '| ${m?.promptTokensPerSecond.toStringAsFixed(1) ?? '—'} '
          '| ${m?.timeToFirstTokenSeconds?.toStringAsFixed(3) ?? '—'} '
          '| ${m?.peakPhysicalFootprintBytes == null ? '—' : _gib(m!.peakPhysicalFootprintBytes!)} '
          '| ${m?.tokenCount ?? '—'} '
          '| ${result.stopReason ?? '—'} '
          '| ${result.rawTextHash == null ? '—' : '`${result.rawTextHash}`'} |',
        );
      }
      buffer
        ..writeln()
        ..writeln('### Answers');
      for (final result in combo.promptResults) {
        buffer
          ..writeln()
          ..writeln(
            '#### ${result.promptId} — '
            '${result.error != null ? 'error' : (result.passed ? 'pass' : 'FAIL')}',
          );
        if (result.error != null) {
          buffer.writeln('> ${result.error}');
          continue;
        }
        for (final check in result.checkResults) {
          buffer.writeln('- ${check.passed ? '✅' : '❌'} ${check.description}');
        }
        buffer
          ..writeln()
          ..writeln(_quote(result.answer));
        if (result.reasoning.isNotEmpty) {
          buffer
            ..writeln()
            ..writeln(
              'Reasoning (${result.reasoning.length} chars): '
              '${_truncate(result.reasoning, 400)}',
            );
        }
      }
    }
    return buffer.toString();
  }

  static String _sampling(ProfileSampling sampling) =>
      '${sampling.maxTokens}/${sampling.temperature}/${sampling.topP}';

  static String _gib(int bytes) =>
      (bytes / (1024 * 1024 * 1024)).toStringAsFixed(2);

  static String _quote(String text) =>
      text.split('\n').map((line) => '> $line').join('\n');

  static String _truncate(String text, int max) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.length <= max) return collapsed;
    return '${collapsed.substring(0, max)}…';
  }
}
