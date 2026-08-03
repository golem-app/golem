import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only app/lib/broker imports package:inferno', () async {
    final lib = Directory('lib');
    final violations = <String>[];
    await for (final entity in lib.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = await entity.readAsString();
      if (source.contains('package:inferno/') &&
          !entity.path.startsWith('lib/broker/')) {
        violations.add(entity.path);
      }
    }
    expect(violations, isEmpty);
  });
}
