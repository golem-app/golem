import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/services/chat_template_fingerprint.dart';

/// One reference template kept verbatim under `test/fixtures/chat_templates/`.
///
/// [pinnedIn] names the catalog entry whose manifest-pinned
/// `chat_template.jinja` hash must equal this fixture's, which is what proves
/// the copy is the shipping template and not an edited approximation. It is
/// null for a template embedded in GGUF metadata: the manifest pins the whole
/// `.gguf`, so that provenance is checked by the gated GGUF test in
/// `gguf_header_test.dart` (#52a-2) instead.
final class _Reference {
  const _Reference(this.file, this.profileKey, {this.pinnedIn});

  final String file;
  final String profileKey;
  final String? pinnedIn;

  String get path => 'test/fixtures/chat_templates/$file';
}

const _references = [
  _Reference('gemma4-mlx.jinja', 'gemma4', pinnedIn: 'gemma4-mlx'),
  _Reference('gemma4-gguf.jinja', 'gemma4'),
  _Reference('qwen35-2b-mlx.jinja', 'qwen35', pinnedIn: 'qwen35-2b-mlx'),
  _Reference('qwen35-4b-mlx.jinja', 'qwen35', pinnedIn: 'qwen35-mlx'),
  _Reference('qwen35-2b-gguf.jinja', 'qwen35'),
];

void main() {
  String read(_Reference reference) => File(reference.path).readAsStringSync();

  group('reference templates', () {
    test('every fixture exists and is non-trivial', () {
      for (final reference in _references) {
        final file = File(reference.path);
        expect(file.existsSync(), isTrue, reason: reference.path);
        expect(file.lengthSync(), greaterThan(1000), reason: reference.path);
      }
    });

    test('a pinned fixture hashes to the manifest chat_template.jinja', () {
      // The strongest offline check available: the fixture is not merely
      // template-shaped, it is the exact file the shipping MLX artifact pins.
      for (final reference in _references) {
        final key = reference.pinnedIn;
        if (key == null) continue;
        final entry = modelCatalog.firstWhere((item) => item.key == key);
        final pinned = entry.files.firstWhere(
          (file) => file.path == 'chat_template.jinja',
        );
        final raw = File(reference.path).readAsBytesSync();
        expect(
          sha256.convert(raw).toString(),
          pinned.sha256,
          reason: '${reference.file} is not $key\'s pinned chat_template.jinja',
        );
      }
    });

    test('every fixture proves its profile', () {
      for (final reference in _references) {
        expect(
          profileKeyForChatTemplate(read(reference)),
          reference.profileKey,
          reason: reference.file,
        );
      }
    });

    test('no accepted fingerprint lacks a reference template', () {
      // Guards the direction the previous test cannot: a constant added by
      // hand, with no template in the repository that produces it, would be an
      // unproven claim about what the broker can render.
      final derived = <String>{
        for (final reference in _references)
          chatTemplateFingerprint(read(reference)),
      };
      final declared = <String>{
        for (final set in acceptedTemplateFingerprints.values) ...set,
      };
      expect(declared.difference(derived), isEmpty);
      expect(derived.difference(declared), isEmpty);
    });

    test('the two Qwen 4B artifacts share one template', () {
      // Recorded because it is load-bearing: the GGUF-embedded 4B template is
      // byte-identical to the MLX one, which is why four fixtures cover five
      // shipping artifacts and why the 4B GGUF needs no gated provenance test.
      expect(
        chatTemplateFingerprint(read(_references[3])),
        'a4aee8afcf2e0711942cf848899be66016f8d14a889ff9ede07bca099c28f715',
      );
    });

    test('Qwen 2B and 4B templates really do differ', () {
      // The reason a profile accepts a set of fingerprints rather than one. If
      // this ever became equal, the set could collapse — deliberately, not by
      // accident.
      expect(
        chatTemplateFingerprint(read(_references[2])),
        isNot(chatTemplateFingerprint(read(_references[3]))),
      );
    });
  });

  group('normalization', () {
    test('absorbs line endings and trailing newlines', () {
      const body = "{%- if a %}\n  {{- 'x' }}\n{%- endif %}";
      final expected = chatTemplateFingerprint(body);
      expect(chatTemplateFingerprint('$body\n'), expected);
      expect(chatTemplateFingerprint('$body\n\n\n'), expected);
      expect(chatTemplateFingerprint(body.replaceAll('\n', '\r\n')), expected);
      expect(chatTemplateFingerprint(body.replaceAll('\n', '\r')), expected);
    });

    test('does not absorb interior whitespace', () {
      // Jinja whitespace control makes interior spacing semantic, so two
      // templates differing there are two different templates.
      expect(
        chatTemplateFingerprint("{{- 'x' }}\n{{- 'y' }}"),
        isNot(chatTemplateFingerprint("{{- 'x' }}  \n{{- 'y' }}")),
      );
      expect(
        chatTemplateFingerprint("{{ 'x ' }}"),
        isNot(chatTemplateFingerprint("{{ 'x' }}")),
      );
    });

    test('is stable and hex-encoded', () {
      final fingerprint = chatTemplateFingerprint('anything');
      expect(fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(fingerprint, sha256.convert(utf8.encode('anything')).toString());
    });
  });

  group('resolution', () {
    test('an unknown template proves nothing', () {
      expect(profileKeyForChatTemplate('{{ messages }}'), isNull);
      expect(profileKeyForChatTemplate(''), isNull);
    });

    test('a near-miss on a shipping template is still a miss', () {
      // One changed character must not resolve. Truncation is the cheapest
      // stand-in for the class of "looks like ours but is not".
      final gemma = read(_references[0]);
      expect(profileKeyForChatTemplate(gemma), 'gemma4');
      expect(
        profileKeyForChatTemplate(gemma.substring(0, gemma.length - 1)),
        isNull,
      );
      expect(profileKeyForChatTemplate('x$gemma'), isNull);
    });
  });
}
