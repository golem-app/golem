import 'package:markdown/markdown.dart' as md;

/// The transcript's markdown subset, parsed into plain data.
///
/// This layer is deliberately Flutter-free so mid-stream stability (an
/// unclosed fence must stay one code block) and structure mapping are
/// provable in cheap unit tests; `GolemMarkdown` renders the result.
sealed class MarkdownBlockData {
  const MarkdownBlockData();
}

/// A paragraph (headings flatten here with [emphasized] set — LLMs emit
/// headings constantly and the bubble ramp has no display sizes).
final class ParagraphData extends MarkdownBlockData {
  const ParagraphData(this.spans, {this.emphasized = false});
  final List<InlineData> spans;
  final bool emphasized;
}

final class ListData extends MarkdownBlockData {
  const ListData(this.items, {required this.ordered, this.start = 1});
  final List<List<InlineData>> items;
  final bool ordered;
  final int start;
}

final class CodeBlockData extends MarkdownBlockData {
  const CodeBlockData(this.code, {this.language});
  final String code;
  final String? language;
}

/// One styled run of inline text.
final class InlineData {
  const InlineData(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.link = false,
  });
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final bool link;
}

List<MarkdownBlockData> parseMarkdownBlocks(String text) {
  if (text.trim().isEmpty) return const [];
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  // The CommonMark default set covers the whole transcript subset
  // (paragraphs, emphasis, inline code, fenced code, lists, headings);
  // GFM extras like tables stay out on purpose. One Document per parse:
  // Document accumulates link references across parseLines calls, so a
  // shared instance would leak `[label]: url` definitions between
  // messages for the process lifetime.
  final nodes = md.Document(encodeHtml: false).parseLines(lines);
  final blocks = <MarkdownBlockData>[];
  for (final node in nodes) {
    blocks.addAll(_blockFrom(node));
  }
  return blocks;
}

List<MarkdownBlockData> _blockFrom(md.Node node) {
  if (node is! md.Element) {
    final text = node.textContent;
    return text.trim().isEmpty
        ? const []
        : [
            ParagraphData([InlineData(text)]),
          ];
  }
  switch (node.tag) {
    case 'p':
      final spans = _inlineFrom(node.children ?? const []);
      return spans.isEmpty ? const [] : [ParagraphData(spans)];
    case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
      final spans = _inlineFrom(node.children ?? const []);
      return spans.isEmpty
          ? const []
          : [ParagraphData(spans, emphasized: true)];
    case 'ul' || 'ol':
      final items = <List<InlineData>>[
        for (final child in node.children ?? const <md.Node>[])
          if (child is md.Element && child.tag == 'li')
            _inlineFrom(child.children ?? const []),
      ];
      return items.isEmpty
          ? const []
          : [
              ListData(
                items,
                ordered: node.tag == 'ol',
                start: int.tryParse(node.attributes['start'] ?? '1') ?? 1,
              ),
            ];
    case 'pre':
      final code = node.children?.firstOrNull;
      final language = code is md.Element
          ? code.attributes['class']?.replaceFirst('language-', '')
          : null;
      final body = (code?.textContent ?? node.textContent);
      return [
        CodeBlockData(
          body.endsWith('\n') ? body.substring(0, body.length - 1) : body,
          language: (language?.isEmpty ?? true) ? null : language,
        ),
      ];
    case 'blockquote':
      // Flattened: quoting has no bubble treatment in the handoff.
      return [
        for (final child in node.children ?? const <md.Node>[])
          ..._blockFrom(child),
      ];
    case 'hr':
      return const [];
    default:
      final spans = _inlineFrom(node.children ?? const []);
      return spans.isEmpty ? const [] : [ParagraphData(spans)];
  }
}

List<InlineData> _inlineFrom(
  List<md.Node> nodes, {
  bool bold = false,
  bool italic = false,
  bool link = false,
}) {
  final spans = <InlineData>[];
  for (final node in nodes) {
    if (node is md.Element) {
      switch (node.tag) {
        case 'strong':
          spans.addAll(
            _inlineFrom(
              node.children ?? const [],
              bold: true,
              italic: italic,
              link: link,
            ),
          );
        case 'em':
          spans.addAll(
            _inlineFrom(
              node.children ?? const [],
              bold: bold,
              italic: true,
              link: link,
            ),
          );
        case 'code':
          spans.add(InlineData(node.textContent, code: true));
        case 'a':
          spans.addAll(
            _inlineFrom(
              node.children ?? const [],
              bold: bold,
              italic: italic,
              link: true,
            ),
          );
        case 'br':
          spans.add(const InlineData('\n'));
        default:
          spans.addAll(
            _inlineFrom(
              node.children ?? const [],
              bold: bold,
              italic: italic,
              link: link,
            ),
          );
      }
    } else {
      spans.add(
        InlineData(node.textContent, bold: bold, italic: italic, link: link),
      );
    }
  }
  return spans;
}
