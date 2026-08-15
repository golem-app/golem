import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/history_strip.dart';
import 'package:golem_flutter/core/domain/model_profile_spec.dart';

/// Reasoning never goes back to the model, and this is the only thing that
/// makes that true. It had no test of its own — both renderers exercised it in
/// passing, which asserted the rendered prompt and not the rule (#120).
const _channels = ChatTemplateSpec(
  strategy: ChatTemplateStrategy.gemmaTurns,
  turnOpen: '<|turn>',
  turnClose: '<turn|>',
  systemRole: 'system',
  userRole: 'user',
  assistantRole: 'model',
  historyStrip: HistoryStripMode.reasoningChannels,
  thoughtControl: '<|think|>',
  channelStart: '<|channel>',
  channelEnd: '<channel|>',
);

const _thinkTags = ChatTemplateSpec(
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

void main() {
  group('the mode decides the form, not the strategy', () {
    test('none keeps the text exactly as it stands', () {
      const spec = ChatTemplateSpec(
        strategy: ChatTemplateStrategy.chatMl,
        turnOpen: '<|im_start|>',
        turnClose: '<|im_end|>',
        systemRole: 'system',
        userRole: 'user',
        assistantRole: 'assistant',
        historyStrip: HistoryStripMode.none,
        thinkStart: '<think>',
        thinkEnd: '</think>',
        reasoningPrimer: '<think>\n',
        directPrimer: '<think>\n\n</think>\n\n',
      );
      expect(
        stripHistoryReasoning('  <think>a</think> b  ', spec),
        '  <think>a</think> b  ',
      );
    });

    test('each mode routes to its own stripper', () {
      expect(
        stripHistoryReasoning('a<|channel>r<channel|>b', _channels),
        stripReasoningChannels('a<|channel>r<channel|>b', _channels),
      );
      expect(
        stripHistoryReasoning('a<think>r</think>b', _thinkTags),
        stripThinkBlocks('a<think>r</think>b', _thinkTags),
      );
    });
  });

  group('reasoning channels', () {
    test('a complete channel is removed and the rest joins up', () {
      expect(
        stripReasoningChannels(
          'before<|channel>secret<channel|>after',
          _channels,
        ),
        'beforeafter',
      );
    });

    test('two channels both go', () {
      expect(
        stripReasoningChannels(
          'a<|channel>one<channel|>b<|channel>two<channel|>c',
          _channels,
        ),
        'abc',
      );
    });

    // The search for the closing marker starts *after* the opening one. A
    // search that started before it would match a stray close to the left and
    // then resume mid-text, duplicating what it had already emitted.
    test('a stray closing marker before a channel does not misalign it', () {
      expect(
        stripReasoningChannels(
          'keep<channel|>more<|channel>hidden<channel|>tail',
          _channels,
        ),
        'keep<channel|>moretail',
      );
    });

    test('an unterminated channel swallows the remainder', () {
      expect(
        stripReasoningChannels('visible<|channel>truncated', _channels),
        'visible',
      );
    });

    test('a template with no channel markers only trims', () {
      const spec = ChatTemplateSpec(
        strategy: ChatTemplateStrategy.gemmaTurns,
        turnOpen: '<|turn>',
        turnClose: '<turn|>',
        systemRole: 'system',
        userRole: 'user',
        assistantRole: 'model',
        historyStrip: HistoryStripMode.reasoningChannels,
        thoughtControl: '<|think|>',
      );
      expect(stripReasoningChannels('  plain  ', spec), 'plain');
    });
  });

  group('think blocks', () {
    test('a complete span is removed', () {
      expect(stripThinkBlocks('a<think>r</think>b', _thinkTags), 'ab');
    });

    test('a span across lines is removed whole', () {
      expect(stripThinkBlocks('a<think>line\nline</think>b', _thinkTags), 'ab');
    });

    test('the shortest span wins, so two blocks both go', () {
      expect(
        stripThinkBlocks('a<think>1</think>b<think>2</think>c', _thinkTags),
        'abc',
      );
    });

    // Deliberately not trimmed and deliberately literal: a stray marker is the
    // caller's sanitize pass, and the ChatML renderer trims last.
    test('an unterminated block is left alone', () {
      expect(
        stripThinkBlocks(' a<think>dangling', _thinkTags),
        ' a<think>dangling',
      );
    });
  });
}
