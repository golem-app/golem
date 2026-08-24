import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/features/chat/widgets/markdown/markdown_blocks.dart';

void main() {
  test('paragraphs, emphasis, inline code, and links map to spans', () {
    final blocks = parseMarkdownBlocks(
      'Use the built-in `csv` module with **bold** and *calm* '
      '[docs](https://example.com) text.',
    );
    final paragraph = blocks.single as ParagraphData;
    expect(paragraph.emphasized, isFalse);
    expect(paragraph.spans.firstWhere((s) => s.code).text, 'csv');
    expect(paragraph.spans.firstWhere((s) => s.bold).text, 'bold');
    expect(paragraph.spans.firstWhere((s) => s.italic).text, 'calm');
    expect(paragraph.spans.firstWhere((s) => s.link).text, 'docs');
  });

  test('fenced code keeps language, body, and trailing shape', () {
    final blocks = parseMarkdownBlocks(
      'Before.\n\n```python\nimport csv\n\nprint(csv)\n```\n\nAfter.',
    );
    expect(blocks, hasLength(3));
    final code = blocks[1] as CodeBlockData;
    expect(code.language, 'python');
    expect(code.code, 'import csv\n\nprint(csv)');
    expect((blocks.last as ParagraphData).spans.single.text, 'After.');
  });

  test('an unclosed fence mid-stream is one growing code block', () {
    // Streaming text sits mid-fence half the time; the layout must not
    // flip between paragraph and code per token.
    final partial = parseMarkdownBlocks('Intro.\n\n```python\nimport csv');
    expect(partial, hasLength(2));
    final code = partial.last as CodeBlockData;
    expect(code.language, 'python');
    expect(code.code, 'import csv');

    final longer = parseMarkdownBlocks(
      'Intro.\n\n```python\nimport csv\nprint(',
    );
    expect(longer, hasLength(2));
    expect((longer.last as CodeBlockData).code, 'import csv\nprint(');
  });

  test('bullet and numbered lists carry per-item spans', () {
    final blocks = parseMarkdownBlocks(
      '- `newline` stops mangling.\n- Swap in **DictReader**.\n\n'
      '1. First\n2. Second',
    );
    expect(blocks, hasLength(2));
    final bullets = blocks.first as ListData;
    expect(bullets.ordered, isFalse);
    expect(bullets.items, hasLength(2));
    expect(bullets.items.first.first.code, isTrue);
    final numbered = blocks.last as ListData;
    expect(numbered.ordered, isTrue);
    expect(numbered.start, 1);
    expect(numbered.items.map((i) => i.single.text), ['First', 'Second']);
  });

  test('headings flatten to emphasized paragraphs', () {
    final blocks = parseMarkdownBlocks('## Two things\n\nBody text.');
    expect((blocks.first as ParagraphData).emphasized, isTrue);
    expect((blocks.first as ParagraphData).spans.single.text, 'Two things');
    expect((blocks.last as ParagraphData).emphasized, isFalse);
  });

  test('empty and whitespace input renders nothing', () {
    expect(parseMarkdownBlocks(''), isEmpty);
    expect(parseMarkdownBlocks('   \n \n'), isEmpty);
  });

  test('link references never leak between parses', () {
    // One message defines a reference; a later, unrelated message using
    // the same label must not resolve it (a shared Document accumulates
    // linkReferences across parseLines calls).
    final first = parseMarkdownBlocks(
      'See [docs].\n\n[docs]: https://example.com',
    );
    expect(
      (first.first as ParagraphData).spans.any((s) => s.link),
      isTrue,
      reason: 'the defining message itself links',
    );
    final second = parseMarkdownBlocks('Unrelated [docs] mention.');
    final spans = (second.single as ParagraphData).spans;
    expect(spans.any((s) => s.link), isFalse);
  });

  test('blockquotes and rules flatten without artifacts', () {
    final blocks = parseMarkdownBlocks('> Quoted advice.\n\n---\n\nPlain.');
    expect(blocks, hasLength(2));
    expect((blocks.first as ParagraphData).spans.single.text, 'Quoted advice.');
  });

  // The reply the simulated backend streams, in one piece: a paragraph, one
  // carrying inline code, a fenced block and a list — every shape the
  // transcript renders, in the order a real answer produces them.
  const answer =
      'This is a deterministic response from Golem\u2019s simulated backend '
      '\u2014 no model is loaded and nothing measures this device.\n\n'
      'Use the built-in `csv` module. It streams row by row, so memory '
      'stays flat no matter how big the file is.\n\n'
      '```python\nimport csv\n\ndef rows(path):\n'
      '    with open(path, newline="") as file:\n'
      '        yield from csv.reader(file)\n```\n\n'
      'Two things worth knowing:\n\n'
      '- `newline=""` stops Python mangling quoted line breaks.\n'
      '- Swap in **DictReader** if the file has a header row.';

  test('a streamed prefix never re-shapes a block already on screen', () {
    // The renderer re-parses the whole message on every emission, which is
    // only safe if the parse of a prefix agrees with the parse of everything
    // that follows it about the blocks before the last. Anything else moves
    // lines the reader is in the middle of reading (#147).
    var previous = <String>[];
    for (var length = 1; length <= answer.length; length++) {
      final shapes = parseMarkdownBlocks(
        answer.substring(0, length),
      ).map(_shape).toList();
      final settled = previous.length - 1;
      if (settled > 0) {
        expect(
          shapes.take(settled),
          orderedEquals(previous.take(settled)),
          reason: 'a prefix of $length characters re-shaped a settled block',
        );
      }
      previous = shapes;
    }
    expect(previous, hasLength(5));
  });
}

/// Everything the renderer draws from one block, flattened so two parses can
/// be compared for sameness rather than identity.
String _shape(MarkdownBlockData block) => switch (block) {
  ParagraphData(:final spans, :final emphasized) =>
    'p($emphasized)'
        '${spans.map((s) => '${s.text}|${s.bold}${s.italic}${s.code}${s.link}').join(',')}',
  ListData(:final items, :final ordered, :final start) =>
    'l($ordered,$start)'
        '${items.map((item) => item.map((s) => s.text).join()).join('||')}',
  CodeBlockData(:final code, :final language) => 'c($language)$code',
};
