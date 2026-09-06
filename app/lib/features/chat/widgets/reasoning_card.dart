import 'package:flutter/cupertino.dart';

import '../../../core/theme/golem_theme.dart';
import '../../../l10n/bidi.dart';
import '../../../l10n/l10n.dart';

/// The reasoning block at the top of an assistant reply: an amber card with
/// a disclosure header that owns the tap and reports its state, the thoughts
/// when expanded, and — while the reply is still streaming — a peek of the
/// newest lines when collapsed. Pure of providers, so the bench can show a
/// run's reasoning the way chat shows a message's (#58).
class ReasoningCard extends StatefulWidget {
  const ReasoningCard({
    required this.text,
    required this.streaming,
    required this.live,
    required this.initiallyExpanded,
    super.key,
  });
  final String text;
  final bool streaming;

  /// Whether the owning message is still streaming at all. The header's LIVE
  /// state, [streaming], ends earlier — when answer text starts.
  final bool live;
  final bool initiallyExpanded;

  @override
  State<ReasoningCard> createState() => _ReasoningCardState();
}

class _ReasoningCardState extends State<ReasoningCard> {
  // Collapsing a card is ephemeral presentation state, never persisted. Until
  // the user touches it the card follows [ReasoningCard.initiallyExpanded]
  // reactively: preferences resolve a frame after cold start, and an
  // initial-only read would freeze on that pre-resolution frame.
  bool? _userToggle;
  bool get _expanded => _userToggle ?? widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final direction = contentTextDirection(
      widget.text,
      fallback: Directionality.of(context),
    );
    return Semantics(
      // Its own node, or the whole card — header, thoughts, and the answer
      // below it — collapses into the bubble's long-press node as one
      // unreadable run.
      container: true,
      child: Container(
        key: const Key('reasoning-card'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
            GolemTheme.reasoningSurface,
            context,
          ),
          borderRadius: BorderRadius.circular(GolemRadius.notice),
          border: Border.all(
            color: CupertinoDynamicColor.resolve(
              GolemTheme.reasoningBorder,
              context,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The disclosure is the row, not the chevron: labelling the glyph
            // alone left the control itself nameless, and its state readable
            // only as whichever arrow happened to be drawn.
            Semantics(
              key: const Key('reasoning-card-header'),
              container: true,
              button: true,
              label: widget.streaming
                  ? context.l10n.reasoningLive
                  : context.l10n.reasoning,
              value: _expanded ? context.l10n.expanded : context.l10n.collapsed,
              onTap: () => setState(() => _userToggle = !_expanded),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // The wrapper above owns the tap action; left in, this detector
                // adds a second, nameless tappable node over the same row.
                excludeFromSemantics: true,
                onTap: () => setState(() => _userToggle = !_expanded),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.lightbulb_fill,
                        color: GolemTheme.amber,
                        size: 16,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          widget.streaming
                              ? context.l10n.reasoningLiveBadge
                              : context.l10n.reasoning,
                          style: GolemText.footnoteStrong,
                        ),
                      ),
                      Icon(
                        _expanded
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        size: 14,
                        color: CupertinoDynamicColor.resolve(
                          GolemTheme.mutedInk,
                          context,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              Text(
                widget.text,
                textDirection: direction,
                style: GolemText.footnote,
              ),
            ] else if (widget.live) ...[
              const SizedBox(height: 8),
              _ReasoningPeek(text: widget.text, textDirection: direction),
            ],
          ],
        ),
      ),
    );
  }
}

/// The newest three lines of a live card's thoughts, muted under a top fade,
/// so a collapsed card still shows the model thinking. Bottom-anchored: a new
/// line pushes the oldest one up and out, and the card never grows. Nothing
/// here is announced — the header already says the reasoning is live, and a
/// peek that re-read itself on every token would talk over the answer.
class _ReasoningPeek extends StatelessWidget {
  const _ReasoningPeek({required this.text, required this.textDirection});

  final String text;
  final TextDirection textDirection;

  static const _lines = 3;

  /// More than three lines at any text scale (a phone line holds ~45
  /// footnote glyphs at 1×, ~20 at 2×); the rest of a long chain of thought
  /// is never shaped for a peek that clips it anyway. Cut by grapheme, not
  /// code unit, or an emoji on the boundary paints as U+FFFD.
  static const _tailLength = 300;

  @override
  Widget build(BuildContext context) {
    final style = GolemText.footnote;
    final tail = text.characters.length > _tailLength
        ? text.characters.takeLast(_tailLength).toString()
        : text;
    final height =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) *
        style.height! *
        _lines;
    final surface = CupertinoDynamicColor.resolve(
      GolemTheme.reasoningSurface,
      context,
    );
    return ExcludeSemantics(
      child: SizedBox(
        key: const Key('reasoning-peek'),
        height: height,
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            PositionedDirectional(
              bottom: 0,
              start: 0,
              end: 0,
              child: Text(
                tail,
                textDirection: textDirection,
                style: style.copyWith(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                ),
              ),
            ),
            // A painted fade in the card's own colour, not a ShaderMask: the
            // mask forced a saveLayer on every streamed token.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [surface, surface.withValues(alpha: 0)],
                      stops: const [0.0, 0.35],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
