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

  test('blockquotes and rules flatten without artifacts', () {
    final blocks = parseMarkdownBlocks('> Quoted advice.\n\n---\n\nPlain.');
    expect(blocks, hasLength(2));
    expect((blocks.first as ParagraphData).spans.single.text, 'Quoted advice.');
  });
}
