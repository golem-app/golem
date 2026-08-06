import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/highlight.dart' as hl show Node;

import '../../../../core/chrome/golem_toast.dart';
import '../../../../core/theme/golem_theme.dart';

/// The transcript's fenced-code card: deliberately dark in both themes,
/// with an uppercase language header and a Copy chip.
final class MarkdownCodeBlock extends StatelessWidget {
  const MarkdownCodeBlock({required this.code, this.language, super.key});

  final String code;
  final String? language;

  @override
  Widget build(BuildContext context) => ClipRRect(
    key: const Key('code-block'),
    borderRadius: BorderRadius.circular(14),
    child: ColoredBox(
      color: GolemTheme.codeSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: GolemTheme.codeHeader,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 5, 6, 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      (language ?? 'code').toUpperCase(),
                      style: GolemText.codeLanguage.copyWith(
                        inherit: false,
                        color: GolemTheme.codeHeaderInk,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _CopyChip(code: code),
                ],
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(14),
            child: Text.rich(
              TextSpan(
                style: GolemText.codeBlock.copyWith(
                  inherit: false,
                  color: GolemTheme.codeInk,
                ),
                children: _highlightSpans(code, language),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _CopyChip extends StatelessWidget {
  const _CopyChip({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    key: const Key('code-copy'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    minimumSize: Size.zero,
    onPressed: () async {
      await Clipboard.setData(ClipboardData(text: code));
      if (context.mounted) showGolemToast(context, 'Copied to clipboard');
    },
    child: Semantics(
      label: 'Copy code',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: GolemTheme.codeChip,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.doc_on_doc,
                size: 13,
                color: GolemTheme.codeChipInk,
              ),
              const SizedBox(width: 5),
              Text(
                'Copy',
                style: GolemText.caption.copyWith(
                  inherit: false,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: GolemTheme.codeChipInk,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Syntax colorization mapped onto the handoff's restrained palette:
/// keywords, callable names, strings, and muted comments — everything
/// else stays base ink. Unknown languages render plain.
List<InlineSpan> _highlightSpans(String code, String? language) {
  if (language == null) return [TextSpan(text: code)];
  try {
    final nodes = highlight.parse(code, language: language).nodes;
    if (nodes == null) return [TextSpan(text: code)];
    return nodes.map(_spanFrom).toList(growable: false);
  } catch (_) {
    return [TextSpan(text: code)];
  }
}

InlineSpan _spanFrom(hl.Node node) {
  final color = switch (node.className) {
    'keyword' || 'literal' => GolemTheme.codeKeyword,
    'title' || 'built_in' || 'type' || 'function' => GolemTheme.codeCallable,
    'string' || 'number' || 'symbol' || 'regexp' => GolemTheme.codeString,
    'comment' || 'meta' || 'doctag' => GolemTheme.codeHeaderInk,
    _ => null,
  };
  final children = node.children;
  return TextSpan(
    text: node.value,
    style: color == null ? null : TextStyle(color: color),
    children: children == null || children.isEmpty
        ? null
        : children.map(_spanFrom).toList(growable: false),
  );
}
