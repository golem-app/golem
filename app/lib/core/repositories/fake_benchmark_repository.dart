import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';
import 'contracts.dart';

/// Reads a bundled text asset. Production passes `rootBundle.loadString`;
/// tests inject a stub so the repository stays Flutter-free.
typedef AssetReader = Future<String> Function(String key);

final class FakeBenchmarkRepository implements BenchmarkRepository {
  FakeBenchmarkRepository(
    this.outputDirectory, {
    required this.readAsset,
    this.delay = const Duration(seconds: 1),
  });
  final Directory outputDirectory;
  final AssetReader readAsset;
  final Duration delay;

  static const _promptTokensPerSecond = 144.0;
  static const _decodeTokensPerSecond = 21.4;
  static const _decodedTokens = 128;

  @override
  Future<BenchmarkRecord> run(String caseId, BenchmarkPhase phase) async {
    final raw = await readAsset('assets/benchmark_prompts/$caseId.json');
    final messages = (jsonDecode(raw) as List)
        .map((item) => Map<String, Object?>.from(item as Map))
        .toList();
    if (messages.isEmpty) {
      throw FormatException('Empty benchmark prompt fixture: $caseId');
    }
    // A fixed 4-characters-per-token estimate keeps the simulated timing
    // deterministic while still deriving it from the real prompt fixture.
    final promptCharacters = messages.fold<int>(
      0,
      (sum, message) => sum + ((message['content'] as String?)?.length ?? 0),
    );
    final promptTokens = (promptCharacters / 4).round();
    final elapsed =
        promptTokens / _promptTokensPerSecond +
        _decodedTokens / _decodeTokensPerSecond;
    await Future<void>.delayed(delay);
    return BenchmarkRecord(
      caseId: caseId,
      phase: phase,
      timestamp: DateTime.now(),
      metrics: InferenceMetrics(
        promptTokensPerSecond: _promptTokensPerSecond,
        decodeTokensPerSecond: _decodeTokensPerSecond,
        tokenCount: _decodedTokens,
        elapsedSeconds: double.parse(elapsed.toStringAsFixed(2)),
      ),
      output:
          'Deterministic simulated benchmark over the $caseId fixture '
          '($promptTokens estimated prompt tokens across '
          '${messages.length} message${messages.length == 1 ? '' : 's'}). '
          'No model was run.',
    );
  }

  @override
  Future<String> export(BenchmarkRecord result) async {
    await outputDirectory.create(recursive: true);
    final safeTime = result.timestamp.toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final file = File(
      '${outputDirectory.path}/$safeTime-${result.caseId}.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result.toJson()),
      flush: true,
    );
    return file.path;
  }
}
