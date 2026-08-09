import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/services/chat_template_fingerprint.dart';
import 'package:golem_flutter/core/services/gguf_header.dart';

Uint8List _u32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

Uint8List _u64(int value) =>
    Uint8List(8)..buffer.asByteData().setUint64(0, value, Endian.little);

Uint8List _string(String value) {
  final bytes = utf8.encode(value);
  return Uint8List.fromList([..._u64(bytes.length), ...bytes]);
}

/// One metadata pair: key, value type code, encoded value.
Uint8List _pair(String key, int type, List<int> value) =>
    Uint8List.fromList([..._string(key), ..._u32(type), ...value]);

/// A synthetic GGUF header. Only the metadata block matters here — the tensor
/// section that would follow is never read.
Uint8List _gguf(
  List<Uint8List> pairs, {
  int version = 3,
  int tensorCount = 0,
  List<int> magic = const [0x47, 0x47, 0x55, 0x46],
  int? declaredPairs,
}) => Uint8List.fromList([
  ...magic,
  ..._u32(version),
  ..._u64(tensorCount),
  ..._u64(declaredPairs ?? pairs.length),
  for (final pair in pairs) ...pair,
]);

/// A string array, the shape that makes a real tokenizer's header large.
Uint8List _stringArray(List<String> values) => Uint8List.fromList([
  ..._u32(8),
  ..._u64(values.length),
  for (final value in values) ..._string(value),
]);

Uint8List _numberArray(int count, {int type = 5, int width = 4}) =>
    Uint8List.fromList([
      ..._u32(type),
      ..._u64(count),
      ...Uint8List(count * width),
    ]);

void main() {
  group('rejections', () {
    test('a non-GGUF file is refused, not retried', () {
      final probe = parseGgufHeader(
        _gguf(const [], magic: const [0x50, 0x4b, 0x03, 0x04]),
      );
      expect(probe, isA<GgufUnreadable>());
      expect((probe as GgufUnreadable).reason, contains('not a GGUF'));
    });

    test('an unsupported version is refused', () {
      // v1 sized its strings with 32-bit counts, so parsing on would misread
      // every length rather than fail cleanly.
      for (final version in [0, 1, 4, 99]) {
        final probe = parseGgufHeader(_gguf(const [], version: version));
        expect(probe, isA<GgufUnreadable>(), reason: 'version $version');
      }
      expect(parseGgufHeader(_gguf(const [], version: 2)), isA<GgufComplete>());
      expect(parseGgufHeader(_gguf(const [], version: 3)), isA<GgufComplete>());
    });

    test('an implausible pair count is refused before any allocation', () {
      final probe = parseGgufHeader(_gguf(const [], declaredPairs: 1 << 40));
      expect(probe, isA<GgufUnreadable>());
      expect((probe as GgufUnreadable).reason, contains('pair count'));
    });

    test('an implausible string length is refused, not treated as short', () {
      // The distinction matters: a short window is retried with more bytes, and
      // retrying a bogus 4 GiB length would fetch the whole file.
      final probe = parseGgufHeader(
        _gguf([
          Uint8List.fromList([
            ..._string('general.architecture'),
            ..._u32(8),
            ..._u64(1 << 40),
          ]),
        ]),
      );
      expect(probe, isA<GgufUnreadable>());
      expect((probe as GgufUnreadable).reason, contains('string length'));
    });

    test('an implausible array length is refused', () {
      final probe = parseGgufHeader(
        _gguf([
          Uint8List.fromList([
            ..._string('tokenizer.ggml.tokens'),
            ..._u32(9),
            ..._u32(8),
            ..._u64(1 << 40),
          ]),
        ]),
      );
      expect(probe, isA<GgufUnreadable>());
      expect((probe as GgufUnreadable).reason, contains('array length'));
    });

    test('a nested array is refused rather than recursed', () {
      final probe = parseGgufHeader(
        _gguf([
          Uint8List.fromList([
            ..._string('weird'),
            ..._u32(9),
            ..._u32(9),
            ..._u64(2),
          ]),
        ]),
      );
      expect(probe, isA<GgufUnreadable>());
      expect((probe as GgufUnreadable).reason, contains('nested'));
    });

    test('an unknown value type is refused', () {
      final probe = parseGgufHeader(
        _gguf([_pair('general.architecture', 42, _u32(0))]),
      );
      expect(probe, isA<GgufUnreadable>());
      expect((probe as GgufUnreadable).reason, contains('value type 42'));
    });

    test('a non-UTF-8 metadata string is refused', () {
      final probe = parseGgufHeader(
        _gguf([
          Uint8List.fromList([
            ..._string('general.architecture'),
            ..._u32(8),
            ..._u64(2),
            0xc3, 0x28, // invalid continuation byte
          ]),
        ]),
      );
      expect(probe, isA<GgufUnreadable>());
      expect((probe as GgufUnreadable).reason, contains('UTF-8'));
    });
  });

  group('value types', () {
    test('every fixed-width type is consumed at its own width', () {
      // A type consumed at the wrong width desynchronizes everything after it,
      // so the proof is that a trailing marker pair still reads correctly.
      final widths = <int, List<int>>{
        0: [1], // uint8
        1: [1], // int8
        2: [1, 2], // uint16
        3: [1, 2], // int16
        4: _u32(7), // uint32
        5: _u32(7), // int32
        6: _u32(0), // float32
        7: [1], // bool
        10: _u64(9), // uint64
        11: _u64(9), // int64
        12: _u64(0), // float64
      };
      for (final entry in widths.entries) {
        final probe = parseGgufHeader(
          _gguf([
            _pair('general.architecture', 8, _string('llama')),
            _pair('some.value', entry.key, entry.value),
            _pair('general.name', 8, _string('marker')),
          ]),
        );
        expect(probe, isA<GgufComplete>(), reason: 'type ${entry.key}');
        expect(
          (probe as GgufComplete).metadata.name,
          'marker',
          reason: 'type ${entry.key} desynchronized the block',
        );
      }
    });

    test('a false boolean is a value, not a short read', () {
      // `false` and "ran out of bytes" must never be the same signal.
      final probe = parseGgufHeader(
        _gguf([
          _pair('general.architecture', 8, _string('llama')),
          _pair('some.flag', 7, const [0]),
          _pair('general.name', 8, _string('marker')),
        ]),
      );
      expect(probe, isA<GgufComplete>());
      expect((probe as GgufComplete).metadata.name, 'marker');
    });

    test('string and number arrays are walked and skipped', () {
      final probe = parseGgufHeader(
        _gguf([
          _pair('general.architecture', 8, _string('llama')),
          _pair('tokenizer.ggml.tokens', 9, _stringArray(['a', 'bb', 'ccc'])),
          _pair('tokenizer.ggml.token_type', 9, _numberArray(3)),
          _pair('tokenizer.chat_template', 8, _string('{{ x }}')),
        ]),
      );
      expect(probe, isA<GgufComplete>());
      expect((probe as GgufComplete).metadata.chatTemplate, '{{ x }}');
    });

    test('an empty array is consumed', () {
      final probe = parseGgufHeader(
        _gguf([
          _pair('general.architecture', 8, _string('llama')),
          _pair('empty.strings', 9, _stringArray(const [])),
          _pair('empty.numbers', 9, _numberArray(0)),
          _pair('general.name', 8, _string('marker')),
        ]),
      );
      expect((probe as GgufComplete).metadata.name, 'marker');
    });
  });

  group('metadata', () {
    Uint8List realistic() => _gguf([
      _pair('general.architecture', 8, _string('qwen35')),
      _pair('general.name', 8, _string('Qwen3.5-2B')),
      _pair('qwen35.block_count', 4, _u32(24)),
      _pair('qwen35.embedding_length', 4, _u32(2048)),
      _pair('general.file_type', 4, _u32(2)),
      _pair('tokenizer.ggml.tokens', 9, _stringArray(['a', 'b'])),
      _pair('tokenizer.chat_template', 8, _string('{%- if x %}y{%- endif %}')),
    ]);

    test('the keys the resolver needs are all read', () {
      final probe = parseGgufHeader(realistic());
      final metadata = (probe as GgufComplete).metadata;
      expect(metadata.version, 3);
      expect(metadata.architecture, 'qwen35');
      expect(metadata.name, 'Qwen3.5-2B');
      expect(metadata.blockCount, 24);
      expect(metadata.embeddingLength, 2048);
      expect(metadata.fileType, 2);
      expect(metadata.chatTemplate, '{%- if x %}y{%- endif %}');
      expect(metadata.pairCount, 7);
    });

    test('dimension keys are namespaced by the declared architecture', () {
      // The key is `<arch>.embedding_length`, so a file declaring a different
      // architecture must not have another model's dimensions picked up.
      final probe = parseGgufHeader(
        _gguf([
          _pair('general.architecture', 8, _string('gemma4')),
          _pair('qwen35.embedding_length', 4, _u32(2048)),
        ]),
      );
      final metadata = (probe as GgufComplete).metadata;
      expect(metadata.architecture, 'gemma4');
      expect(metadata.embeddingLength, isNull);
    });
  });

  group('short windows', () {
    test('a window shorter than the file header asks for more', () {
      for (var length = 0; length < 24; length++) {
        final probe = parseGgufHeader(Uint8List(length));
        expect(probe, isA<GgufIncomplete>(), reason: 'length $length');
      }
    });

    test('every truncation of a real-shaped header is incomplete or done', () {
      // The property that matters is that no truncation is ever reported as
      // unreadable: a short read must be retryable, never a rejection.
      final full = _gguf([
        _pair('general.architecture', 8, _string('qwen35')),
        _pair('qwen35.embedding_length', 4, _u32(2048)),
        _pair('tokenizer.ggml.tokens', 9, _stringArray(['aa', 'bbb', 'cccc'])),
        _pair('tokenizer.ggml.token_type', 9, _numberArray(3)),
        _pair('tokenizer.chat_template', 8, _string('{{ template }}')),
      ]);
      for (var length = 0; length <= full.length; length++) {
        final probe = parseGgufHeader(Uint8List.sublistView(full, 0, length));
        expect(
          probe,
          length == full.length ? isA<GgufComplete>() : isA<GgufIncomplete>(),
          reason: 'truncated to $length of ${full.length}',
        );
        if (probe is GgufIncomplete) {
          expect(
            probe.atLeastBytes,
            greaterThan(length),
            reason: 'bound at $length must ask for more than it had',
          );
          expect(probe.atLeastBytes, lessThanOrEqualTo(full.length + 8));
        }
      }
    });

    test('the architecture survives a window too short for the template', () {
      // This is what makes the cheap first pass worthwhile: an unsupported
      // architecture is rejected without fetching the rest of the block. The
      // exact offset is not the point — that it arrives far earlier than the
      // template is.
      final full = _gguf([
        _pair('general.architecture', 8, _string('mamba')),
        _pair('tokenizer.ggml.tokens', 9, _stringArray(List.filled(64, 'tok'))),
        _pair('tokenizer.chat_template', 8, _string('{{ template }}')),
      ]);
      var firstKnown = -1;
      for (var length = 0; length < full.length; length++) {
        final probe = parseGgufHeader(Uint8List.sublistView(full, 0, length));
        if (probe is GgufIncomplete && probe.partial.architecture != null) {
          firstKnown = length;
          break;
        }
      }
      expect(firstKnown, greaterThan(0));
      expect(
        firstKnown,
        lessThan(full.length ~/ 2),
        reason: 'the architecture must be readable well before the template',
      );
      final early = parseGgufHeader(Uint8List.sublistView(full, 0, firstKnown));
      expect((early as GgufIncomplete).partial.architecture, 'mamba');
      expect(early.partial.chatTemplate, isNull);
    });

    test('growing to the reported bound always converges', () {
      // atLeastBytes is documented as a lower bound, not a promise, so the
      // contract that matters is termination: each step must strictly advance,
      // and the loop must reach the end rather than stall.
      final full = _gguf([
        _pair('general.architecture', 8, _string('qwen35')),
        _pair('tokenizer.ggml.tokens', 9, _stringArray(['aa', 'bbb'])),
        _pair('tokenizer.chat_template', 8, _string('a' * 500)),
      ]);
      var window = 24;
      var steps = 0;
      GgufProbe probe;
      while (true) {
        probe = parseGgufHeader(
          Uint8List.sublistView(full, 0, window.clamp(0, full.length)),
        );
        if (probe is! GgufIncomplete) break;
        expect(
          probe.atLeastBytes,
          greaterThan(window),
          reason: 'a bound that does not advance would loop forever',
        );
        window = probe.atLeastBytes;
        steps++;
        expect(steps, lessThan(64), reason: 'did not converge');
      }
      expect(probe, isA<GgufComplete>());
      expect((probe as GgufComplete).metadata.chatTemplate, 'a' * 500);
    });

    test('probe windows grow and stay bounded', () {
      expect(ggufProbeWindows.first, 1024 * 1024);
      expect(
        ggufProbeWindows,
        orderedEquals(<int>[...ggufProbeWindows]..sort()),
      );
      expect(ggufProbeWindows.last, lessThanOrEqualTo(64 * 1024 * 1024));
    });
  });

  group('real artifacts', () {
    /// Each shipping GGUF, with the fixture its embedded template must equal.
    /// This is the provenance check `chat_template_fingerprint_test.dart`
    /// cannot make offline: the manifest pins the whole `.gguf`, not the
    /// template inside it.
    const artifacts = [
      ('INFERNO_GEMMA_GGUF', 'gemma4-gguf.jinja', 'gemma4'),
      ('INFERNO_QWEN_2B_GGUF', 'qwen35-2b-gguf.jinja', 'qwen35'),
      ('INFERNO_QWEN_GGUF', 'qwen35-4b-gguf.jinja', 'qwen35'),
    ];

    for (final (variable, fixture, profileKey) in artifacts) {
      final path = Platform.environment[variable];
      test(
        '$fixture is the template embedded in the shipping GGUF',
        () {
          final handle = File(path!).openSync();
          Uint8List window;
          GgufProbe probe;
          var index = 0;
          do {
            final size = ggufProbeWindows[index];
            handle.setPositionSync(0);
            window = handle.readSync(size);
            probe = parseGgufHeader(window);
            index++;
          } while (probe is GgufIncomplete && index < ggufProbeWindows.length);
          handle.closeSync();

          expect(
            probe,
            isA<GgufComplete>(),
            reason: 'the metadata block did not fit the largest probe window',
          );
          final metadata = (probe as GgufComplete).metadata;
          expect(metadata.chatTemplate, isNotNull);
          expect(
            metadata.chatTemplate,
            File('test/fixtures/chat_templates/$fixture').readAsStringSync(),
          );
          expect(profileKeyForChatTemplate(metadata.chatTemplate!), profileKey);
          expect(metadata.embeddingLength, greaterThan(0));
          expect(metadata.blockCount, greaterThan(0));
        },
        skip: path == null
            ? 'Set $variable to the local $fixture source artifact.'
            : false,
      );
    }
  });
}
