import 'package:flutter/cupertino.dart';

import '../../../../core/theme/golem_theme.dart';
import 'code_block.dart';
import 'markdown_blocks.dart';

/// Renders a message's markdown subset with Golem tokens.
///
/// Stateful for one reason: the parse is memoized against the text, so
/// during streaming only the growing message re-parses per emission and
/// settled bubbles rebuild from their cached blocks.
final class GolemMarkdown extends StatefulWidget {
  const GolemMarkdown({required this.text, this.streaming = false, super.key});

  final String text;
  final bool streaming;

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
      final cursor = widget.streaming && index == _blocks.length - 1;
      children.add(switch (block) {
        ParagraphData() => _Paragraph(block, cursor: cursor),
        ListData() => _BlockList(block),
        CodeBlockData() => MarkdownCodeBlock(
          code: block.code,
          language: block.language,
        ),
      });
    }
    if (widget.streaming && _blocks.lastOrNull is! ParagraphData) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      children.add(
        const Align(alignment: Alignment.centerLeft, child: _BlinkCursor()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

final class _Paragraph extends StatelessWidget {
  const _Paragraph(this.data, {this.cursor = false});
  final ParagraphData data;
  final bool cursor;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        ...inlineSpans(context, data.spans, emphasized: data.emphasized),
        if (cursor)
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(left: 3),
              child: _BlinkCursor(),
            ),
          ),
      ],
    ),
    style: data.emphasized ? GolemText.bodyStrong : GolemText.body,
  );
}

final class _BlockList extends StatelessWidget {
  const _BlockList(this.data);
  final ListData data;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, item) in data.items.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 7),
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
      ],
    ),
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
            child: Text(span.text, style: GolemText.code),
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

/// The streaming caret: a 9×19 accent block blinking on a hard step,
/// exactly like the prototype's `gmBlink`.
final class _BlinkCursor extends StatefulWidget {
  const _BlinkCursor();

  @override
  State<_BlinkCursor> createState() => _BlinkCursorState();
}

final class _BlinkCursorState extends State<_BlinkCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) =>
        Opacity(opacity: _controller.value < 0.5 ? 1 : 0, child: child),
    child: Container(
      width: 9,
      height: 19,
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(GolemTheme.accent, context),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}
