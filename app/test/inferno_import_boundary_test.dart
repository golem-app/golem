import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only app/lib/broker imports package:inferno', () async {
    final violations = await _libFilesContaining('package:inferno/');
    violations.removeWhere((path) => path.startsWith('lib/broker/'));
    expect(violations, isEmpty);
  });

  test('the acceptance HUD is never linked into the app', () async {
    // It exists to take over a device during a gated run. Reaching it from
    // lib/ would ship an automation banner to a user.
    expect(await _libFilesContaining('acceptance_hud'), isEmpty);
  });

  test(
    'no Material import, because nothing supplies MaterialLocalizations',
    () async {
      // The app dropped flutter_localizations (#74) on the strength of this
      // being empty: CupertinoApp contributes only Default{Cupertino,Widgets}
      // Localizations, so the first Material widget calling
      // MaterialLocalizations.of(context) throws at runtime, on that surface
      // only — invisible to analyze and to every other test here.
      expect(
        await _libFilesContaining('package:flutter/material.dart'),
        isEmpty,
      );
    },
  );
}

Future<List<String>> _libFilesContaining(String needle) async {
  final matches = <String>[];
  await for (final entity in Directory('lib').list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if ((await entity.readAsString()).contains(needle)) {
      matches.add(entity.path);
    }
  }
  return matches;
}
