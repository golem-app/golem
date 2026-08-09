/// How a repository earns a broker profile (#52).
///
/// The broker renders prompts in Dart and never executes a repository's Jinja,
/// so a template is only ever *evidence of family* — never something we run.
/// That makes the safe question narrow: is this byte-for-byte a template we
/// already ship and have proven a renderer for? Anything else stays
/// `unresolvedProfileKey`, which lists and deletes normally but refuses
/// activation with actionable copy (#43). A repository slug, file name, or
/// architecture string is never accepted as proof.
///
/// A profile accepts a *set* of fingerprints rather than one, because the
/// artifacts we already ship do not agree byte-for-byte:
///
/// - Qwen 2B and 4B emit the reasoning primer under opposite `enable_thinking`
///   defaults, yet share the `qwen35` profile correctly — the broker emits that
///   primer itself, so the template's own default never runs.
/// - A GGUF's template is embedded in its metadata by whoever converted the
///   weights, and commonly differs from the same model's MLX
///   `chat_template.jinja`.
///
/// Matching a single reference would therefore reject repositories this app
/// already ships.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Cosmetic normalization applied before fingerprinting.
///
/// Deliberately minimal: only differences that cannot change what a template
/// renders are absorbed.
///
/// - Line endings, because a checkout, a text editor, or a conversion tool can
///   rewrite them without touching a single token.
/// - Trailing newlines at the very end, because a file on disk conventionally
///   ends with one while a string extracted from GGUF metadata does not. The
///   Gemma GGUF template differs from nothing else but this.
///
/// Notably *not* normalized: whitespace inside or between lines. Jinja
/// whitespace control (`{%-`, `-%}`) makes interior spacing semantic, and
/// guessing that two templates are equivalent is exactly the hazard this
/// module exists to avoid.
String normalizeChatTemplate(String template) => template
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll(RegExp(r'\n+$'), '');

/// The SHA-256 of [template] after [normalizeChatTemplate], as lowercase hex.
String chatTemplateFingerprint(String template) =>
    sha256.convert(utf8.encode(normalizeChatTemplate(template))).toString();

/// Fingerprints that prove a broker profile, keyed by profile key.
///
/// Every entry traces to an artifact this app ships and has evaluated, so
/// accepting one never widens what the broker claims to render. Adding a
/// fingerprint is a deliberate act that needs the same evidence a new pinned
/// artifact needs.
///
/// The templates themselves are kept verbatim under
/// `test/fixtures/chat_templates/`, and `chat_template_fingerprint_test.dart`
/// re-derives every value below from them — three of the four are additionally
/// checked against the `chat_template.jinja` SHA-256 pinned in the Inferno
/// manifest, so those fixtures cannot drift from the shipping artifact without
/// failing offline.
const acceptedTemplateFingerprints = <String, Set<String>>{
  'gemma4': {
    // mlx-community/gemma-4-e2b-it-4bit, chat_template.jinja (17,336 B).
    // Equal to the manifest-pinned file hash: this template has no trailing
    // newline, so normalization is a no-op for it.
    '2f1b4d75d067bae3fe44e676721c7f077d243bc007156cb9c2f8b5836613d082',
    // unsloth/gemma-4-E2B-it-qat-GGUF, tokenizer.chat_template embedded in
    // gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf (18,809 B normalized from 18,810).
    // The one entry whose provenance is a gated test rather than a pinned
    // file hash — the manifest pins the whole .gguf, not the template inside.
    '74a88f94c57c14e22dcdbe08e94127f42b87c6f584cb73838e73e32126f3f6b3',
  },
  'qwen35': {
    // mlx-community/Qwen3.5-2B-4bit, chat_template.jinja (7,755 B). Emits the
    // reasoning primer only when `enable_thinking is true`.
    '273d8e0e683b885071fb17e08d71e5f2a5ddfb5309756181681de4f5a1822d80',
    // mlx-community/Qwen3.5-4B-MLX-4bit, chat_template.jinja (7,756 B), which
    // is byte-identical to the template embedded in
    // YoozLabs/Qwen3.5-4B-qat-GGUF. Emits the primer unless
    // `enable_thinking is false` — the opposite default to 2B above, and
    // harmless because the broker never runs either.
    'a4aee8afcf2e0711942cf848899be66016f8d14a889ff9ede07bca099c28f715',
    // unsloth/Qwen3.5-2B-GGUF, tokenizer.chat_template embedded in
    // Qwen3.5-2B-Q4_0.gguf (7,816 B). Gated-test provenance, as above.
    '7f0e529032c25183bcd66c7f238da2d377f43be754a94e2725a58c4e16d2ed67',
  },
};

/// The profile key [template] proves, or null when nothing does.
///
/// Null is the common answer for an arbitrary repository and is not an error:
/// the caller records the entry as unresolved so it can still be listed and
/// deleted, and activation refuses it.
String? profileKeyForChatTemplate(String template) {
  final fingerprint = chatTemplateFingerprint(template);
  for (final entry in acceptedTemplateFingerprints.entries) {
    if (entry.value.contains(fingerprint)) return entry.key;
  }
  return null;
}
