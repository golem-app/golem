import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The chrome layer is the only place that may reach for a platform button.
///
/// Before #131 there were 47 raw `CupertinoButton`s under `features/`, each
/// restating the platform tap minimum by hand — and two of them restating it
/// as a number, which is how the shared chrome shipped 4dp under the Android
/// floor for as long as it existed (#118). A feature now says what kind of
/// control it wants and `core/chrome/` decides how big it has to be.
void main() {
  final features = Directory('lib/features');

  Iterable<File> dartFiles(Directory root) => root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));

  test('no feature reaches past the chrome layer for a button', () {
    final offenders = <String>[];
    for (final file in dartFiles(features)) {
      final source = file.readAsStringSync();
      for (final (index, line) in source.split('\n').indexed) {
        // The word may still appear in prose; only a constructor call counts.
        if (RegExp(r'\bCupertinoButton[.(]').hasMatch(line)) {
          offenders.add('${file.path}:${index + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'use GolemButton for a label, GolemIconButton for a glyph, or '
          'GolemTappable for a bespoke child — they own the platform minimum',
    );
  });

  test('no feature hard-codes a tap target', () {
    final offenders = <String>[];
    // 44 on cupertino, 48 on android: written as a literal, one of the two is
    // always wrong. `GolemChrome.current.minimumTapTarget` is the only source.
    final literal = RegExp(
      r'(Size\.square|Size\.fromHeight|minimumHeight:)\s*\(?\s*(44|48)\b',
    );
    for (final file in dartFiles(features)) {
      final source = file.readAsStringSync();
      for (final (index, line) in source.split('\n').indexed) {
        if (literal.hasMatch(line)) offenders.add('${file.path}:${index + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'the platform minimum has one owner: GolemChrome',
    );
  });
}
