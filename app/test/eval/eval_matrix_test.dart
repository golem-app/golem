import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/runtime.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';

import 'package:golem_flutter/features/eval/data/eval_matrix.dart';

void main() {
  test('degenerate paths are dropped instead of throwing', () {
    // An unset shell variable ("$MODELS/" → "/") must fall through to the
    // driver's deliberate skip, not crash test collection.
    expect(evalMatrixFromDefines(ggufDefine: '/', mlxDefine: '//'), isEmpty);
    expect(evalMatrixFromDefines(ggufDefine: '', mlxDefine: ' , '), isEmpty);
  });

  test('paths map to labeled combos with the right engines', () {
    final combos = evalMatrixFromDefines(
      ggufDefine: '/models/a.gguf, /models/b.gguf',
      mlxDefine: '/models/mlx-dir/',
    );
    expect(combos.map((c) => c.label), ['a.gguf', 'b.gguf', 'mlx-dir']);
    expect(combos.map((c) => c.engine), [
      BrokerEngine.llamaCpp,
      BrokerEngine.llamaCpp,
      BrokerEngine.mlx,
    ]);
    expect(combos[2].path, '/models/mlx-dir/');
  });

  test('colliding basenames are disambiguated by parent directory', () {
    final combos = evalMatrixFromDefines(
      ggufDefine: '/models/q4_0/model.gguf,/models/q4_k_m/model.gguf',
      mlxDefine: '',
    );
    expect(combos.map((c) => c.label), [
      'q4_0/model.gguf',
      'q4_k_m/model.gguf',
    ]);
  });

  test('identical paths fall back to numbered labels', () {
    final combos = evalMatrixFromDefines(
      ggufDefine: '/m/model.gguf,/m/model.gguf',
      mlxDefine: '',
    );
    expect(combos.map((c) => c.label), ['m/model.gguf', 'm/model.gguf#2']);
  });

  test('path defines carry no profile, so the run template applies', () {
    final combos = evalMatrixFromDefines(
      ggufDefine: '/models/a.gguf',
      mlxDefine: '/models/mlx-dir/',
    );
    expect(combos.map((c) => c.profileKey), [isNull, isNull]);
  });

  test('installed keys resolve their own profile, engine, and path', () {
    final combos = installedEvalCombos(
      installedDefine: ' qwen35-gguf , gemma4-mlx ',
      documentsDirectory: '/docs',
    );
    // The profile follows the artifact, never the run template: Qwen
    // rendered and stopped as Gemma would measure nothing.
    expect(combos.map((c) => c.label), ['qwen35-gguf', 'gemma4-mlx']);
    expect(combos.map((c) => c.profileKey), ['qwen35', 'gemma4']);
    expect(combos.map((c) => c.engine), [
      BrokerEngine.llamaCpp,
      BrokerEngine.mlx,
    ]);
    expect(combos.first.path, startsWith('/docs/models/qwen35-gguf/'));
    expect(combos.last.path, '/docs/models/gemma4-mlx');
  });

  test('an unactivatable installed key fails loudly at collection', () {
    expect(
      () => installedEvalCombos(
        installedDefine: 'custom-something',
        documentsDirectory: '/docs',
      ),
      // Activation refusals are typed so the chat surface can render
      // actionable copy rather than a generic engine error (#43).
      throwsA(isA<InferenceException>()),
    );
  });
}
