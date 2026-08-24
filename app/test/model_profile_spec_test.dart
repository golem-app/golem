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
        // The objects, not just their maps: comparing only `toJson()` left
        // every field comparison in the three `operator ==` implementations
        // unasserted, and a spec that survives a round-trip while comparing
        // unequal breaks provider caching rather than anything visible (#120).
        expect(restored, spec, reason: spec.key);
        expect(restored.hashCode, spec.hashCode, reason: spec.key);
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
        1,
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

    rejects(
      'a non-positive presence penalty',
      _validProfile()
        ..['reasoningSampling'] = {
          'maxTokens': 64,
          'temperature': 0.6,
          'topP': 0.95,
          'presencePenalty': 0,
        },
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

  // Every field of these two carries identity: two specs differing in one knob
  // are two different profiles, and treating them as one would serve sampling
  // the model was never evaluated with.
  group('every field decides identity', () {
    const baseline = ProfileSampling(
      maxTokens: 64,
      temperature: 0.6,
      topP: 0.95,
      topK: 20,
      contextLength: 4096,
      presencePenalty: 1.5,
      pinned: true,
    );

    const variants = <String, ProfileSampling>{
      'maxTokens': ProfileSampling(
        maxTokens: 65,
        temperature: 0.6,
        topP: 0.95,
        topK: 20,
        contextLength: 4096,
        presencePenalty: 1.5,
        pinned: true,
      ),
      'temperature': ProfileSampling(
        maxTokens: 64,
        temperature: 0.7,
        topP: 0.95,
        topK: 20,
        contextLength: 4096,
        presencePenalty: 1.5,
        pinned: true,
      ),
      'topP': ProfileSampling(
        maxTokens: 64,
        temperature: 0.6,
        topP: 0.9,
        topK: 20,
        contextLength: 4096,
        presencePenalty: 1.5,
        pinned: true,
      ),
      'topK': ProfileSampling(
        maxTokens: 64,
        temperature: 0.6,
        topP: 0.95,
        contextLength: 4096,
        presencePenalty: 1.5,
        pinned: true,
      ),
      'contextLength': ProfileSampling(
        maxTokens: 64,
        temperature: 0.6,
        topP: 0.95,
        topK: 20,
        presencePenalty: 1.5,
        pinned: true,
      ),
      'presencePenalty': ProfileSampling(
        maxTokens: 64,
        temperature: 0.6,
        topP: 0.95,
        topK: 20,
        contextLength: 4096,
        pinned: true,
      ),
      'pinned': ProfileSampling(
        maxTokens: 64,
        temperature: 0.6,
        topP: 0.95,
        topK: 20,
        contextLength: 4096,
        presencePenalty: 1.5,
      ),
    };

    // Through fromJson, not a second const literal: Dart canonicalizes equal
    // const expressions to one instance, so `operator ==` would compare an
    // object with itself and a dropped field comparison would still pass.
    test('sampling compares equal to its own copy', () {
      final copy = ProfileSampling.fromJson(baseline.toJson());

      expect(identical(copy, baseline), isFalse);
      expect(copy, baseline);
      expect(copy.hashCode, baseline.hashCode);
    });

    variants.forEach((field, variant) {
      test('sampling differing in $field is a different block', () {
        expect(variant, isNot(baseline));
        expect(baseline, isNot(variant));
      });
    });

    ChatTemplateSpec template([Map<String, Object?> Function()? build]) =>
        ChatTemplateSpec.fromJson(build?.call() ?? _validChatMl());

    test('a template compares equal to its own copy', () {
      expect(template(), template());
      expect(template().hashCode, template().hashCode);
    });

    // The key *is* the field written. Carrying the name twice would let a
    // rename touch one and not the other, leaving a test whose name says one
    // field while it mutates another — the named field silently uncovered.
    const templateVariants = <String, Object>{
      'turnOpen': '<|start|>',
      'turnClose': '<|end|>',
      'systemRole': 'sys',
      'userRole': 'human',
      'assistantRole': 'bot',
      'historyStrip': 'none',
      'bos': '<s>',
      'thoughtControl': '<|think|>',
      'channelStart': '<|channel>',
      'channelEnd': '<channel|>',
      'thinkStart': '<thought>',
      'thinkEnd': '</thought>',
      'reasoningPrimer': '<think>\n\n',
      'directPrimer': '<think></think>',
      'mediaMarker': '<image>',
    };

    templateVariants.forEach((field, value) {
      test('a template differing in $field is a different template', () {
        final variant = template(() => _validChatMl()..[field] = value);
        expect(variant, isNot(template()));
      });
    });

    test('a template differing in strategy is a different template', () {
      final gemma = ChatTemplateSpec.fromJson({
        ..._validChatMl(),
        'strategy': 'gemmaTurns',
        'thoughtControl': '<|think|>',
      });
      expect(gemma, isNot(template()));
    });
  });

  group('the boundaries the parser refuses', () {
    void rejectsWith(String reason, String message, Map<String, Object?> json) {
      test(reason, () {
        expect(
          () => ModelProfileSpec.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              message,
            ),
          ),
        );
      });
    }

    Map<String, Object?> sampling(Map<String, Object?> extra) => {
      'maxTokens': 64,
      'temperature': 0.6,
      'topP': 0.95,
      ...extra,
    };

    // topP's window is open at zero and closed at one, so both ends and the
    // negative side have to be refused — a `< 0` guard would let 0 through and
    // an `== 0` guard would let -0.5 through, and neither is a probability.
    rejectsWith(
      'topP at zero',
      'topP must be in (0, 1]',
      _validProfile()..['reasoningSampling'] = sampling({'topP': 0}),
    );
    rejectsWith(
      'topP below zero',
      'topP must be in (0, 1]',
      _validProfile()..['reasoningSampling'] = sampling({'topP': -0.5}),
    );
    rejectsWith(
      'topP above one',
      'topP must be in (0, 1]',
      _validProfile()..['reasoningSampling'] = sampling({'topP': 1.1}),
    );
    test('topP at one is accepted', () {
      expect(
        ModelProfileSpec.fromJson(
          _validProfile()..['reasoningSampling'] = sampling({'topP': 1}),
        ).reasoningSampling.topP,
        1,
      );
    });

    rejectsWith(
      'a negative presence penalty',
      'presencePenalty must be positive',
      _validProfile()
        ..['reasoningSampling'] = sampling({'presencePenalty': -1}),
    );

    rejectsWith(
      'an empty key',
      'key must be a non-empty string',
      _validProfile()..['key'] = '',
    );
    rejectsWith(
      'an empty required marker',
      'turnOpen must be a non-empty string',
      _validProfile(template: _validChatMl()..['turnOpen'] = ''),
    );

    // Half a pair is the interesting case: a parser needs both ends, so an
    // "either is missing" guard is required and a "both are missing" one would
    // pass a spec that cannot close what it opens. historyStrip goes to none so
    // the stripping guard does not fire first and hide the parser's.
    rejectsWith(
      'think parsing with only an opening tag',
      'thinkTags parsing requires thinkStart and thinkEnd',
      _validProfile(
        template: _validChatMl()
          ..remove('thinkEnd')
          ..['historyStrip'] = 'none',
      ),
    );
    rejectsWith(
      'think parsing with only a closing tag',
      'thinkTags parsing requires thinkStart and thinkEnd',
      _validProfile(
        template: _validChatMl()
          ..remove('thinkStart')
          ..['historyStrip'] = 'none',
      ),
    );
    rejectsWith(
      'channel parsing with only an opening marker',
      'channels parsing requires channelStart and channelEnd',
      _validProfile(template: _validChatMl()..['channelStart'] = '<|channel>')
        ..['parser'] = 'channels',
    );
    rejectsWith(
      'channel parsing with only a closing marker',
      'channels parsing requires channelStart and channelEnd',
      _validProfile(template: _validChatMl()..['channelEnd'] = '<channel|>')
        ..['parser'] = 'channels',
    );

    rejectsWith(
      'stripping think blocks with only an opening tag',
      'thinkBlocks stripping requires thinkStart and thinkEnd',
      _validProfile(
        template: _validChatMl()
          ..remove('thinkEnd')
          ..['thinkStart'] = '<think>',
      )..['parser'] = 'none',
    );
    rejectsWith(
      'stripping reasoning channels with only an opening marker',
      'reasoningChannels stripping requires channelStart and channelEnd',
      _validProfile(
        template: _validChatMl()
          ..['historyStrip'] = 'reasoningChannels'
          ..['channelStart'] = '<|channel>',
      )..['parser'] = 'none',
    );

    rejectsWith(
      'image input with no way to mark an image',
      'a template declaring image input must define mediaMarker',
      _validProfile()..['inputModalities'] = ['text', 'image'],
    );

    // fromJson validates on the way in; a const-built spec has to be told to,
    // and that second entry point had no test at all — every case above
    // reaches the inline checks instead.
    group('a const spec validated by hand', () {
      const template = ChatTemplateSpec(
        strategy: ChatTemplateStrategy.chatMl,
        turnOpen: '<|im_start|>',
        turnClose: '<|im_end|>',
        systemRole: 'system',
        userRole: 'user',
        assistantRole: 'assistant',
        historyStrip: HistoryStripMode.thinkBlocks,
        thinkStart: '<think>',
        thinkEnd: '</think>',
        reasoningPrimer: '<think>\n',
        directPrimer: '<think>\n\n</think>\n\n',
      );
      const sampling = ProfileSampling(
        maxTokens: 64,
        temperature: 0.6,
        topP: 0.95,
      );

      ModelProfileSpec spec({
        String key = 'const-chatml',
        Set<ModelInputModality> modalities = const {ModelInputModality.text},
        List<String> stopSequences = const ['<|im_end|>'],
      }) => ModelProfileSpec(
        key: key,
        template: template,
        parser: ReasoningParserMode.thinkTags,
        stopSequences: stopSequences,
        stopTokenIds: const [7],
        reasoningSampling: sampling,
        directSampling: sampling,
        inputModalities: modalities,
      );

      void refuses(String reason, String message, ModelProfileSpec subject) {
        test(reason, () {
          expect(
            subject.validate,
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'message',
                message,
              ),
            ),
          );
        });
      }

      test('a sound one validates silently', () {
        expect(spec().validate, returnsNormally);
      });

      refuses(
        'image input with no media marker',
        'a template declaring image input must define mediaMarker',
        spec(modalities: {ModelInputModality.text, ModelInputModality.image}),
      );
      refuses('an empty key', 'key must be a non-empty string', spec(key: ''));
      refuses(
        'an empty stop sequence',
        'stop sequences must not be empty',
        spec(stopSequences: const ['<|im_end|>', '']),
      );
    });
    test('image input with a media marker is accepted', () {
      final spec = ModelProfileSpec.fromJson(
        _validProfile(template: _validChatMl()..['mediaMarker'] = '<image>')
          ..['inputModalities'] = ['text', 'image'],
      );
      expect(spec.supportsImages, isTrue);
    });
  });
}
