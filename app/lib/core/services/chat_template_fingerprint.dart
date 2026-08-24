/// How a repository earns a broker profile (#52).
///
/// The broker renders prompts in Dart and never executes a repository's Jinja,
/// so a template is only evidence of family. A profile accepts a *set* of
/// fingerprints because the shipped artifacts disagree byte-for-byte: Qwen 2B
/// and 4B emit the reasoning primer under opposite `enable_thinking` defaults,
/// and a GGUF's embedded template differs from the same model's MLX one.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Absorbs only differences that cannot change what a template renders: line
/// endings, and the trailing newline a file has where a GGUF-extracted string
/// does not. Interior whitespace is left alone — Jinja makes it semantic.
String normalizeChatTemplate(String template) => template
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll(RegExp(r'\n+$'), '');

String chatTemplateFingerprint(String template) =>
    sha256.convert(utf8.encode(normalizeChatTemplate(template))).toString();

/// Fingerprints that prove a broker profile. Every entry traces to an artifact
/// this app ships and has evaluated, so adding one needs the same evidence as a
/// new pin; the tests re-derive these from `test/fixtures/chat_templates/`.
const acceptedTemplateFingerprints = <String, Set<String>>{
  'gemma4': {
    // mlx-community/gemma-4-e2b-it-4bit, chat_template.jinja.
    '2f1b4d75d067bae3fe44e676721c7f077d243bc007156cb9c2f8b5836613d082',
    // unsloth/gemma-4-E2B-it-qat-GGUF, embedded in the .gguf.
    '74a88f94c57c14e22dcdbe08e94127f42b87c6f584cb73838e73e32126f3f6b3',
  },
  'qwen35': {
    // mlx-community/Qwen3.5-2B-4bit, chat_template.jinja.
    '273d8e0e683b885071fb17e08d71e5f2a5ddfb5309756181681de4f5a1822d80',
    // mlx-community/Qwen3.5-4B-MLX-4bit, byte-identical to the template
    // embedded in YoozLabs/Qwen3.5-4B-qat-GGUF.
    'a4aee8afcf2e0711942cf848899be66016f8d14a889ff9ede07bca099c28f715',
    // unsloth/Qwen3.5-2B-GGUF, embedded in the .gguf.
    '7f0e529032c25183bcd66c7f238da2d377f43be754a94e2725a58c4e16d2ed67',
  },
};

/// The profile key [template] proves, or null — the ordinary answer for an
/// arbitrary repository, not an error.
String? profileKeyForChatTemplate(String template) {
  final fingerprint = chatTemplateFingerprint(template);
  for (final entry in acceptedTemplateFingerprints.entries) {
    if (entry.value.contains(fingerprint)) return entry.key;
  }
  return null;
}
