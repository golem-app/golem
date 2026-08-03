import 'package:inferno/inferno.dart';
import 'package:test/test.dart';

void main() {
  test('the build hook supplies the pinned native ABI', () async {
    final inferno = Inferno.native();
    final probe = await inferno.probe();
    expect(probe.supports(InfernoEngineKind.llamaCpp), isTrue);
    expect(probe.engines.single.detail, contains(llamaCppRelease));
  });
}
