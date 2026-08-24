import 'package:flutter/cupertino.dart';

import '../../../../core/theme/golem_theme.dart';
import '../../../../l10n/bidi.dart';
import 'code_block.dart';
import 'markdown_blocks.dart';

/// Renders a message's markdown subset with Golem tokens.
///
/// Stateful for one reason: the parse is memoized against the text, so
/// during streaming only the growing message re-parses per emission and
/// settled bubbles rebuild from their cached blocks.
final class GolemMarkdown extends StatefulWidget {
  const GolemMarkdown({required this.text, super.key});

  final String text;

  @override
  State<GolemMarkdown> createState() => _GolemMarkdownState();
}

final class _GolemMarkdownState extends State<GolemMarkdown> {
  String? _parsedText;
  List<MarkdownBlockData> _blocks = const [];

  @override
  Widget build(BuildContext context) {
    if (_parsedText != widget.text) {
      _blocks = parseMarkdownBlocks(widget.text);
      _parsedText = widget.text;
    }
    final children = <Widget>[];
    for (final (index, block) in _blocks.indexed) {
      if (index > 0) children.add(const SizedBox(height: 10));
      children.add(switch (block) {
        ParagraphData() => _DirectedBlock(
          text: block.spans.map((span) => span.text).join(),
          child: _Paragraph(block),
        ),
        ListData() => _BlockList(block),
        CodeBlockData() => Directionality(
          textDirection: TextDirection.ltr,
          child: MarkdownCodeBlock(code: block.code, language: block.language),
        ),
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

final class _DirectedBlock extends StatelessWidget {
  const _DirectedBlock({required this.text, required this.child});

  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: contentTextDirection(
      text,
      fallback: Directionality.of(context),
    ),
    child: Align(alignment: AlignmentDirectional.centerStart, child: child),
  );
}

final class _Paragraph extends StatelessWidget {
  const _Paragraph(this.data);
  final ParagraphData data;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: inlineSpans(context, data.spans, emphasized: data.emphasized),
    ),
    style: data.emphasized ? GolemText.bodyStrong : GolemText.body,
  );
}

final class _BlockList extends StatelessWidget {
  const _BlockList(this.data);
  final ListData data;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (index, item) in data.items.indexed)
        _DirectedBlock(
          text: item.map((span) => span.text).join(),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: 4,
              top: index == 0 ? 0 : 7,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    data.ordered ? '${data.start + index}.' : '•',
                    style: GolemText.body,
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: inlineSpans(context, item)),
                    style: GolemText.body,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

List<InlineSpan> inlineSpans(
  BuildContext context,
  List<InlineData> spans, {
  bool emphasized = false,
}) => [
  for (final span in spans)
    if (span.code)
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoDynamicColor.resolve(GolemTheme.field, context),
            border: Border.all(
              color: CupertinoDynamicColor.resolve(GolemTheme.divider, context),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(span.text, style: GolemText.code),
            ),
          ),
        ),
      )
    else
      TextSpan(
        text: span.text,
        style: TextStyle(
          fontWeight: span.bold || emphasized ? FontWeight.w600 : null,
          fontStyle: span.italic ? FontStyle.italic : null,
          color: span.link
              ? CupertinoDynamicColor.resolve(GolemTheme.accent, context)
              : null,
        ),
      ),
];
