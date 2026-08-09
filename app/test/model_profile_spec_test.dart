import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/broker/gemma4_chat_template.dart';
import 'package:golem_flutter/broker/model_profile.dart';
import 'package:golem_flutter/broker/qwen35_chat_template.dart';

Map<String, Object?> _validChatMl() => {
  'strategy': 'chatMl',
  'turnOpen': '<|im_start|>',
  'turnClose': '<|im_end|>',
  'systemRole': 'system',
  'userRole': 'user',
  'assistantRole': 'assistant',
  'historyStrip': 'thinkBlocks',
  'thinkStart': '<think>',
  'thinkEnd': '</think>',
  'reasoningPrimer': '<think>\n',
  'directPrimer': '<think>\n\n</think>\n\n',
};

Map<String, Object?> _validProfile({Map<String, Object?>? template}) => {
  'schemaVersion': 1,
  'key': 'custom-chatml',
  'template': template ?? _validChatMl(),
  'parser': 'thinkTags',
  'stopSequences': ['<|im_end|>'],
  'stopTokenIds': [7],
  'reasoningSampling': {'maxTokens': 64, 'temperature': 0.6, 'topP': 0.95},
  'directSampling': {'maxTokens': 32, 'temperature': 0.7, 'topP': 0.8},
};

void main() {
  group('the pinned profiles are expressible as data', () {
    test('both built-ins round-trip through JSON unchanged', () {
      for (final spec in [gemma4ProfileSpec, qwen35ProfileSpec]) {
        final restored = ModelProfileSpec.fromJson(spec.toJson());
        expect(restored.toJson(), spec.toJson(), reason: spec.key);
      }
    });

    test('control markers match the sets the hand-written templates used', () {
      // Gemma stripped bos, both turn markers, the thought control, and both
      // channel markers; Qwen stripped both turn markers and both think tags.
      // Both also strip the broker-only media marker from pasted text.
      expect(gemma4ProfileSpec.template.controlMarkers, [
        Gemma4ChatTemplate.bos,
        Gemma4ChatTemplate.turnStart,
        Gemma4ChatTemplate.turnEnd,
        Gemma4ChatTemplate.thoughtControl,
        ReasoningStreamParser.channelStart,
        ReasoningStreamParser.channelEnd,
        // The media marker is a control marker too: pasted text must not be
        // able to claim an image slot with no picture behind it.
        '<__media__>',
      ]);
      expect(qwen35ProfileSpec.template.controlMarkers, [
        Qwen35ChatTemplate.imStart,
        Qwen35ChatTemplate.imEnd,
        Qwen35ChatTemplate.thinkStart,
        Qwen35ChatTemplate.thinkEnd,
        '<__media__>',
      ]);
    });

    test('both pinned templates can express an image', () {
      // A profile says what its *template* can express; whether a given
      // artifact accepts one is the catalog entry's call (#18).
      expect(gemma4ProfileSpec.supportsImages, isTrue);
      expect(gemma4ProfileSpec.template.mediaMarker, '<__media__>');
      expect(gemma4ProfileSpec.imageTokenCost, greaterThan(0));

      expect(qwen35ProfileSpec.supportsImages, isTrue);
      expect(qwen35ProfileSpec.template.mediaMarker, '<__media__>');
      expect(qwen35ProfileSpec.imageTokenCost, 1280);
    });

    test('sampling follows the reasoning mode', () {
      expect(
        qwen35ProfileSpec.samplingFor(reasoningEnabled: true).temperature,
        0.6,
      );
      expect(
        qwen35ProfileSpec.samplingFor(reasoningEnabled: true).pinned,
        isTrue,
      );
      expect(
        qwen35ProfileSpec.samplingFor(reasoningEnabled: false).temperature,
        0.7,
      );
      // Gemma's sampling is mode-independent.
      expect(
        gemma4ProfileSpec.samplingFor(reasoningEnabled: true).toJson(),
        gemma4ProfileSpec.samplingFor(reasoningEnabled: false).toJson(),
      );
    });
  });

  group('a spec that cannot be represented safely is rejected', () {
    void rejects(String reason, Map<String, Object?> json) {
      test(reason, () {
        expect(
          () => ModelProfileSpec.fromJson(json),
          throwsA(isA<FormatException>()),
          reason: reason,
        );
      });
    }

    rejects(
      'an unknown schema version',
      _validProfile()..['schemaVersion'] = 2,
    );
    rejects('an unknown parser mode', _validProfile()..['parser'] = 'jinja');
    // These once escaped as a TypeError, which the preferences guard does not
    // catch — one bad profile would have quarantined the whole file.
    rejects('a missing template object', _validProfile()..remove('template'));
    rejects('a non-object template', _validProfile()..['template'] = 'chatMl');
    rejects(
      'a missing sampling block',
      _validProfile()..remove('reasoningSampling'),
    );
    rejects(
      'a non-object sampling block',
      _validProfile()..['directSampling'] = 7,
    );
    rejects('a missing key', _validProfile()..remove('key'));
    rejects('an empty key', _validProfile()..['key'] = '');
    rejects(
      'a non-integer stop token id',
      _validProfile()..['stopTokenIds'] = ['7'],
    );
    rejects(
      'an unknown template strategy',
      _validProfile(template: _validChatMl()..['strategy'] = 'llama2'),
    );
    rejects(
      'an unknown history-strip mode',
      _validProfile(template: _validChatMl()..['historyStrip'] = 'regex'),
    );
    rejects(
      'colliding user and assistant roles',
      _validProfile(template: _validChatMl()..['assistantRole'] = 'user'),
    );
    rejects(
      'a chatMl template with no generation primers',
      _validProfile(template: _validChatMl()..remove('reasoningPrimer')),
    );
    rejects(
      'a gemmaTurns template with no thought control',
      _validProfile(
        template: _validChatMl()
          ..['strategy'] = 'gemmaTurns'
          ..['historyStrip'] = 'none',
      ),
    );
    rejects(
      'think-tag parsing with no think markers',
      _validProfile(
        template: _validChatMl()
          ..remove('thinkStart')
          ..remove('thinkEnd')
          ..['historyStrip'] = 'none',
      ),
    );
    rejects(
      'declared image input with no media marker',
      _validProfile()..['inputModalities'] = ['text', 'image'],
    );
    rejects(
      'channel parsing with no channel markers',
      _validProfile()..['parser'] = 'channels',
    );
    rejects(
      'think-block stripping with no think markers',
      _validProfile(template: _validChatMl()..remove('thinkEnd')),
    );
    rejects(
      'a non-positive token budget',
      _validProfile()
        ..['directSampling'] = {'maxTokens': 0, 'temperature': 1, 'topP': 0.9},
    );
    rejects(
      'a top-p outside (0, 1]',
      _validProfile()
        ..['directSampling'] = {'maxTokens': 8, 'temperature': 1, 'topP': 1.5},
    );
    rejects(
      'a negative temperature',
      _validProfile()
        ..['directSampling'] = {'maxTokens': 8, 'temperature': -1, 'topP': 0.9},
    );
  });

  group('a supported custom spec', () {
    test('round-trips and drives the proven ChatML implementation', () {
      final spec = ModelProfileSpec.fromJson(_validProfile());
      expect(spec.key, 'custom-chatml');
      expect(spec.inputModalities, {ModelInputModality.text});
      expect(ModelProfileSpec.fromJson(spec.toJson()).toJson(), spec.toJson());

      final profile = DataModelProfile(spec);
      expect(
        profile.render([
          PromptMessage.text('user', 'Hi'),
        ], reasoningEnabled: true),
        '<|im_start|>user\nHi<|im_end|>\n<|im_start|>assistant\n<think>\n',
      );
      expect(profile.stopSequences, ['<|im_end|>']);
      expect(profile.sampling(reasoningEnabled: true).maxTokens, 64);
    });

    test('declared image capability survives serialization', () {
      // A template that declares image input must say how an image enters
      // the prompt, so this carries a media marker.
      final spec = ModelProfileSpec.fromJson(
        _validProfile(template: _validChatMl()..['mediaMarker'] = '<__media__>')
          ..['inputModalities'] = ['text', 'image']
          ..['imageTokenCost'] = 256,
      );
      expect(spec.supportsImages, isTrue);
      expect(spec.imageTokenCost, 256);
      expect(spec.template.mediaMarker, '<__media__>');
      expect(ModelProfileSpec.fromJson(spec.toJson()).inputModalities, {
        ModelInputModality.text,
        ModelInputModality.image,
      });
    });

    test('historyStrip decides what history keeps, not the strategy', () {
      final history = [
        PromptMessage.text('user', 'Q'),
        PromptMessage.text('assistant', '<think>secret</think>A'),
        PromptMessage.text('user', 'Q2'),
      ];

      // thinkBlocks: the model's own reasoning never returns to the prompt.
      final stripping = DataModelProfile(
        ModelProfileSpec.fromJson(_validProfile()),
      ).render(history, reasoningEnabled: false);
      expect(stripping, isNot(contains('secret')));
      expect(stripping, contains('<|im_start|>assistant\nA<|im_end|>'));

      // none: the field is honoured rather than decorative.
      final keeping = DataModelProfile(
        ModelProfileSpec.fromJson(
          _validProfile(template: _validChatMl()..['historyStrip'] = 'none'),
        ),
      ).render(history, reasoningEnabled: false);
      expect(keeping, contains('secret'));
    });

    test('a spec declaring a BOS has it stripped from pasted content', () {
      // controlMarkers is the union of declared markers, so a chatMl spec
      // that declares a BOS cannot have it forged from user text.
      final spec = ModelProfileSpec.fromJson(
        _validProfile(template: _validChatMl()..['bos'] = '<s>'),
      );
      expect(spec.template.controlMarkers, contains('<s>'));
      final rendered = DataModelProfile(spec).render([
        PromptMessage.text('user', 'hi <s> there'),
      ], reasoningEnabled: false);
      // Exactly one BOS: the one the template emitted.
      expect('<s>'.allMatches(rendered).length, 1);
      expect(rendered, startsWith('<s>'));
    });

    test('its parser splits reasoning from the answer', () {
      final parser = DataModelProfile(
        ModelProfileSpec.fromJson(_validProfile()),
      ).newParser(reasoningEnabled: true);
      final first = parser.consume('weighing it up</think>\n\nDone.');
      expect(first.reasoning, 'weighing it up');
      expect(first.answer, 'Done.');
    });
  });
}
