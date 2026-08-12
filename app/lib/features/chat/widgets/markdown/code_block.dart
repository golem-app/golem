import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/highlight.dart' as hl show Node;

import '../../../../core/chrome/golem_toast.dart';
import '../../../../core/theme/golem_theme.dart';
import '../../../../l10n/l10n.dart';

/// Header text for a fence that carried no language.
///
/// Untagged fences deliberately stay neutral. The obvious move is to ask
/// `highlight` to auto-detect, but its relevance score does not separate
/// code from anything else. Measured against the registry this app loads:
/// three lines of server log score 13 (as YAML) and an ordinary English
/// paragraph scores 10 (as SQL), while real Go scores 4, real JavaScript
/// 3, and `SELECT 1;` scores 2. No threshold splits those, and the
/// best-vs-runner-up margin does not either. Guessing would mislabel prose
/// far more often than it would help code, so the card says what it knows
/// and nothing more.
/// Fence tags models write that `highlight` does not register. Without
/// these the card prints a language header over a body it never actually
/// colorized — `tsx` in particular is everywhere in React answers.
const _languageAliases = <String, String>{
  'tsx': 'typescript',
  'jsx': 'javascript',
  'jsonc': 'json',
  'json5': 'json',
  'objective-c': 'objectivec',
  'obj-c': 'objectivec',
  'c': 'cpp',
  'c++': 'cpp',
  'c#': 'cs',
  'golang': 'go',
  'yml': 'yaml',
};

/// The transcript's fenced-code card, with an uppercase language header
/// and a Copy chip. The card tracks the appearance: navy in dark, a cool
/// grey in light, with a hairline in both.
final class MarkdownCodeBlock extends StatefulWidget {
  const MarkdownCodeBlock({required this.code, this.language, super.key});

  final String code;
  final String? language;

  @override
  State<MarkdownCodeBlock> createState() => _MarkdownCodeBlockState();
}

final class _MarkdownCodeBlockState extends State<MarkdownCodeBlock> {
  final ScrollController _controller = ScrollController();
  late List<hl.Node>? _nodes = _parse(widget.code, widget.language);

  @override
  void didUpdateWidget(covariant MarkdownCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code == widget.code &&
        oldWidget.language == widget.language) {
      return;
    }
    // Memoized against exactly the two values `_parse` reads. This spares
    // ancestor-driven rebuilds; a *streaming* body still reparses per
    // token, because its text genuinely changes each time.
    _nodes = _parse(widget.code, widget.language);
    // `ChatCanvas` builds bubbles positionally, so this State can be
    // recycled for a different message's snippet. A streamed body only
    // ever grows, so an append keeps the reader's scroll position while a
    // wholesale replacement rewinds it.
    if (!widget.code.startsWith(oldWidget.code) && _controller.hasClients) {
      _controller.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Resolved once per build rather than once per highlight node: each
    // resolve walks three inherited widgets, and a long block has thousands
    // of nodes.
    final palette = _CodePalette.of(context);
    return Container(
      key: const Key('code-block'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: palette.header,
            child: ConstrainedBox(
              key: const Key('code-header'),
              // The band declares its own floor so it does not depend on
              // the Copy chip's measurement to hold the iOS minimum.
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (widget.language ?? context.l10n.code).toUpperCase(),
                        style: GolemText.codeLanguage.copyWith(
                          inherit: false,
                          color: palette.headerInk,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _CopyChip(code: widget.code, palette: palette),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            // Horizontal insets belong to the viewport, not the scrolled
            // content: inside the scroll view they would slide out of sight
            // and leave the code flush against the card edge.
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: RawScrollbar(
              controller: _controller,
              thumbVisibility: true,
              thickness: 3,
              radius: const Radius.circular(1.5),
              thumbColor: palette.headerInk,
              // Purely a cue. Interactive scrollbars inflate their 3pt
              // thumb to a 48pt hit circle, which on a short card blankets
              // the whole body and beats the transcript's vertical drag to
              // the gesture arena.
              interactive: false,
              child: SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                child: Padding(
                  // Keeps the thumb clear of the last line's descenders.
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text.rich(
                    TextSpan(
                      style: GolemText.codeBlock.copyWith(
                        inherit: false,
                        color: palette.ink,
                      ),
                      children: _spansFrom(palette, _nodes, widget.code),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _CopyChip extends StatelessWidget {
  const _CopyChip({required this.code, required this.palette});
  final String code;
  final _CodePalette palette;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    key: const Key('code-copy'),
    // The chip paints at its handoff size; `minimumSize` expands only the
    // tap target around it to the iOS minimum.
    padding: const EdgeInsets.symmetric(horizontal: 11),
    minimumSize: const Size(44, 44),
    onPressed: () async {
      await Clipboard.setData(ClipboardData(text: code));
      if (context.mounted) {
        showGolemToast(context, context.l10n.copiedToClipboard);
      }
    },
    child: Semantics(
      label: context.l10n.copyCode,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.chip,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.doc_on_doc, size: 13, color: palette.chipInk),
              const SizedBox(width: 5),
              Text(
                context.l10n.copy,
                style: GolemText.caption.copyWith(
                  inherit: false,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  height: 1,
                  color: palette.chipInk,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The card's colors, resolved once per build.
final class _CodePalette {
  const _CodePalette({
    required this.surface,
    required this.border,
    required this.header,
    required this.headerInk,
    required this.chip,
    required this.chipInk,
    required this.ink,
    required this.keyword,
    required this.callable,
    required this.string,
    required this.comment,
  });

  factory _CodePalette.of(BuildContext context) => _CodePalette(
    surface: CupertinoDynamicColor.resolve(GolemTheme.codeSurface, context),
    border: CupertinoDynamicColor.resolve(GolemTheme.codeBorder, context),
    header: CupertinoDynamicColor.resolve(GolemTheme.codeHeader, context),
    headerInk: CupertinoDynamicColor.resolve(GolemTheme.codeHeaderInk, context),
    chip: CupertinoDynamicColor.resolve(GolemTheme.codeChip, context),
    chipInk: CupertinoDynamicColor.resolve(GolemTheme.codeChipInk, context),
    ink: CupertinoDynamicColor.resolve(GolemTheme.codeInk, context),
    keyword: CupertinoDynamicColor.resolve(GolemTheme.codeKeyword, context),
    callable: CupertinoDynamicColor.resolve(GolemTheme.codeCallable, context),
    string: CupertinoDynamicColor.resolve(GolemTheme.codeString, context),
    comment: CupertinoDynamicColor.resolve(GolemTheme.codeComment, context),
  );

  final Color surface;
  final Color border;
  final Color header;
  final Color headerInk;
  final Color chip;
  final Color chipInk;
  final Color ink;
  final Color keyword;
  final Color callable;
  final Color string;
  final Color comment;
}

/// Parses a tagged fence, returning null when the body should render
/// plain — an untagged fence, or a grammar that threw.
///
/// The catch is not decoration: `highlight` swallows only its own
/// `Illegal…` errors and rethrows everything else, the bodies are
/// model-generated, and this runs from `didUpdateWidget` where the
/// framework does not contain the throw. A grammar failure degrades one
/// card to plain text rather than taking down the transcript.
List<hl.Node>? _parse(String code, String? language) {
  if (language == null) return null;
  final resolved = _languageAliases[language.toLowerCase()] ?? language;
  try {
    return highlight.parse(code, language: resolved).nodes;
  } catch (_) {
    return null;
  }
}

/// Syntax colorization mapped onto the handoff's restrained palette:
/// keywords, callable names, strings, and muted comments — everything
/// else stays base ink. Untagged fences render plain.
List<InlineSpan> _spansFrom(
  _CodePalette palette,
  List<hl.Node>? nodes,
  String code,
) {
  if (nodes == null) return [TextSpan(text: code)];
  return nodes.map((node) => _spanFrom(palette, node)).toList(growable: false);
}

InlineSpan _spanFrom(_CodePalette palette, hl.Node node) {
  final color = switch (node.className) {
    'keyword' || 'literal' => palette.keyword,
    'title' || 'built_in' || 'type' || 'function' => palette.callable,
    'string' || 'number' || 'symbol' || 'regexp' => palette.string,
    'comment' || 'meta' || 'doctag' => palette.comment,
    _ => null,
  };
  final children = node.children;
  return TextSpan(
    text: node.value,
    style: color == null ? null : TextStyle(color: color),
    children: children == null || children.isEmpty
        ? null
        : children
              .map((child) => _spanFrom(palette, child))
              .toList(growable: false),
  );
}
