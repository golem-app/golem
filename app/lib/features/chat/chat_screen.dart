import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, ScrollDirection;
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_tappable.dart';
import '../../core/domain/app_state.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/retry_pane.dart';
import '../../l10n/l10n.dart';
import '../models/application/model_providers.dart';
import '../models/model_label.dart';
import 'application/active_model_providers.dart';
import 'application/chat_providers.dart';
import 'widgets/attach_sheet.dart';
import 'widgets/chat_canvas.dart';
import 'widgets/conversation_drawer.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({this.picker = const AttachmentPicker(), super.key});

  final AttachmentPicker picker;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  /// How far past its own width the closed drawer parks, so that
  /// [GolemShadow.drawer] does not bleed back over the canvas.
  static const _drawerHideMargin = 52.0;

  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _drawerOpen = false;
  bool _showJump = false;
  // Only a deliberate upward drag detaches the tail-follow; growing content
  // never does — distance-based detach made fast responses outrun the
  // animation and stop following mid-answer.
  bool _follow = true;

  /// The question the reader most recently asked, held at the top of the
  /// viewport while its answer streams in below it. Ephemeral and set only by
  /// a send in this session: a transcript nobody has sent into — a reopened
  /// conversation, a seeded one — carries no anchor and no spacer.
  final GlobalKey _anchorKey = GlobalKey();
  String? _anchorId;
  String? _anchorConversationId;

  /// The measured scroll offset that puts the anchored question's top edge at
  /// the top of the viewport. Null until it has been measured, and the only
  /// thing that separates holding the question still from following the tail.
  double? _anchorOffset;

  /// Height of the list's trailing spacer, chosen so that the scrollable's
  /// own end *is* the anchored position: with the turn shorter than the
  /// viewport the spacer makes up the difference, so `maxScrollExtent`
  /// equals the offset that puts the question's top edge at the top of the
  /// screen. Following the tail and holding the question still are then the
  /// same instruction, and the switch between them needs no mode.
  ///
  /// A notifier rather than plain state: it changes on every delta of an
  /// anchored turn, and a `setState` for each one rebuilt the nav bar, the
  /// drawer and the banners to move one box at the end of a list.
  final ValueNotifier<double> _spacer = ValueNotifier<double>(0);

  /// One measurement per frame. Several deltas can queue their callbacks
  /// against a single frame, and the later ones would then weigh a spacer
  /// this frame's layout has not used yet against an extent that predates
  /// it — the sum oscillates a delta at a time instead of settling.
  bool _measureQueued = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateScrollState);
  }

  /// Also recomputed on content growth: while detached, a streaming response
  /// moves the tail away with no offset change, and the jump affordance must
  /// still appear.
  void _updateScrollState() {
    if (!_scroll.hasClients) return;
    final show = _scroll.position.maxScrollExtent - _scroll.offset > 240;
    if (show != _showJump && mounted) setState(() => _showJump = show);
  }

  /// Re-attaching belongs to the reader, so it happens only once a scroll has
  /// come to rest at the tail. Proximity alone used to do it from
  /// [_updateScrollState], which content growth re-enters on every delta: a
  /// drag that had travelled less than the window was undone by the next
  /// token, which put the finger back at the tail, where the rest of the same
  /// drag started over (#147).
  /// Content growth and viewport changes both land here. The anchor is
  /// re-measured from either, so a turn that settled while the reader was
  /// away — or a keyboard that opened afterwards — cannot leave the spacer
  /// sized for a viewport that no longer exists.
  void _onScrollMetrics() {
    _updateScrollState();
    _scheduleAnchorMeasure();
  }

  void _onScrollSettled() {
    // Coming to rest can bring an evicted anchor back into the builder's
    // cache, which is the only chance to measure it again.
    _scheduleAnchorMeasure();
    if (!_scroll.hasClients || _follow) return;
    // A hair, not a window: the reader has to actually come back to the end
    // to hand following back. A generous window re-attached anyone whose drag
    // had not yet cleared it, which is every drag at the moment it starts.
    if (_followTarget() - _scroll.offset <= 8) _follow = true;
  }

  @override
  void dispose() {
    _composer.dispose();
    _spacer.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    _follow = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _animateToBottom());
  }

  /// Whether this change is a turn the reader started here, rather than a
  /// transcript arriving or shrinking: a conversation opened, switched to, or
  /// restored on launch must render exactly as it always has, with no anchor
  /// and no spacer, and so must one a message was just deleted from
  /// (`deleteMessage`, `removeFailedTurn`) — both shorten the list without
  /// leaving the conversation, which a plain "the count changed" test read as
  /// a send. Sending into a fresh session does count, even though it
  /// materializes the conversation as it goes.
  static bool _startedHere(
    ChatState? prior,
    ChatState? next, {
    required bool grew,
  }) =>
      grew &&
      prior != null &&
      (prior.active == null || prior.active?.id == next?.active?.id);

  /// Anchors the turn the reader just started: the newest user message, which
  /// is also the right one after a regenerate, where only an assistant draft
  /// is appended and the question stands.
  void _anchorTo(ChatState? state) {
    final active = state?.active;
    final question = active?.messages.reversed
        .where((message) => message.role == MessageRole.user)
        .firstOrNull;
    if (active == null || question == null) return;
    _anchorId = question.id;
    _anchorConversationId = active.id;
    _scheduleAnchorMeasure();
  }

  void _scheduleAnchorMeasure() {
    if (_anchorId == null || _measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      _measureAnchor();
    });
  }

  /// Re-sizes the spacer to `anchorOffset + spacer - maxScrollExtent`, which
  /// is the viewport remainder below the anchored turn. Both inputs are
  /// independent of the spacer itself — the anchor offset measures what is
  /// above it and the extent already contains the current value — so this
  /// settles in one frame rather than chasing itself.
  ///
  /// A measurement is skipped, not zeroed, when the anchor has scrolled out
  /// of the builder's cache: the turn's height has not changed, so the
  /// standing value is still the right one.
  void _measureAnchor() {
    if (!mounted || _anchorId == null || !_scroll.hasClients) return;
    final anchor = _anchorKey.currentContext?.findRenderObject();
    if (anchor is! RenderBox || !anchor.hasSize) return;
    final viewport = RenderAbstractViewport.maybeOf(anchor);
    if (viewport == null) return;
    final position = _scroll.position;
    final reveal = viewport.getOffsetToReveal(anchor, 0).offset;
    _anchorOffset = reveal;
    final needed = (reveal + _spacer.value - position.maxScrollExtent).clamp(
      0.0,
      position.viewportDimension,
    );
    if ((needed - _spacer.value).abs() < 0.5) return;
    _spacer.value = needed;
  }

  /// The anchor belongs to one conversation and one message; leaving either
  /// takes the spacer with it, so a transcript the reader merely opened never
  /// carries dead space at its end.
  void _syncAnchor(ChatState? state) {
    final active = state?.active;
    final gone =
        active == null ||
        active.id != _anchorConversationId ||
        !active.messages.any((message) => message.id == _anchorId);
    if (!gone || _anchorId == null) return;
    _anchorId = null;
    _anchorConversationId = null;
    _anchorOffset = null;
    _spacer.value = 0;
  }

  /// Where the view belongs while it is following: the anchored offset for as
  /// long as the spacer is still giving up room for it, and the end of the
  /// scrollable once the turn has outgrown the screen. Taking the smaller of
  /// the two is what lets the handover between them need no state of its own,
  /// and it absorbs the frame in which the answer has already grown but the
  /// spacer has not yet given the room back.
  double _followTarget() {
    final extent = _scroll.position.maxScrollExtent;
    final anchor = _anchorOffset;
    // No spacer left means the turn has outgrown the screen and there is
    // nothing to hold the question up any more: follow the tail.
    if (anchor == null || _spacer.value <= 0) return extent;
    return anchor < extent ? anchor : extent;
  }

  Future<void> _animateToBottom() async {
    // maxScrollExtent is a lazy-layout estimate that grows as items build, so
    // one animation can undershoot; chase the extent until the tail is really
    // reached (or the user drags away).
    for (var attempt = 0; attempt < 8; attempt++) {
      if (!_scroll.hasClients || !_follow) return;
      final target = _followTarget();
      if ((target - _scroll.offset).abs() < 1) {
        final anchor = _anchorOffset;
        // Reached the end of a scrollable whose spacer has not finished
        // growing, so the anchor is still out of reach: let the frame that
        // resizes it land, then look again.
        if (anchor == null || anchor <= _scroll.position.maxScrollExtent) {
          return;
        }
        _measureAnchor();
        // A frame, not a timer: a pending timer outlives a disposed tree.
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
        continue;
      }
      await _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Streamed deltas arrive faster than a restarted animation can settle, so
  /// the tail is followed with a post-frame jump to the fresh extent.
  void _followTail() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || !_follow) return;
      _scroll.jumpTo(_followTarget());
    });
  }

  void _onUserScroll(ScrollDirection direction) {
    // Offset shrinking means the user is dragging toward older messages.
    if (direction == ScrollDirection.forward) _follow = false;
  }

  /// Streaming is a purely visual event — a caret, a growing bubble, a pill —
  /// so without this a screen-reader user gets no signal that a turn started or
  /// ended. Only the two edges are spoken: the listener behind this fires on
  /// every delta, and narrating each one would talk over the answer itself. A
  /// failure stays silent here because the recovery banner is a live region and
  /// carries the actual reason.
  static bool _busy(GenerationPhase? phase) =>
      phase == GenerationPhase.preparing || phase == GenerationPhase.streaming;

  void _announceGeneration(
    BuildContext context,
    GenerationPhase? before,
    GenerationPhase? after,
  ) {
    if (before == null || after == null) return;
    if (_busy(before) == _busy(after)) return;
    final message = _busy(after)
        ? context.l10n.golemResponding
        : after == GenerationPhase.idle
        ? context.l10n.responseFinished
        : null;
    if (message == null) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatControllerProvider, (previous, next) {
      final priorValue = previous?.hasValue == true
          ? previous!.requireValue
          : null;
      final nextValue = next.hasValue ? next.requireValue : null;
      final priorLength = priorValue?.active?.messages.length ?? 0;
      final nextLength = nextValue?.active?.messages.length ?? 0;
      _syncAnchor(nextValue);
      _announceGeneration(
        context,
        priorValue?.generation,
        nextValue?.generation,
      );
      if (nextLength != priorLength) {
        if (_startedHere(
          priorValue,
          nextValue,
          grew: nextLength > priorLength,
        )) {
          _anchorTo(nextValue);
        }
        _scrollToLatest();
      } else if (!_follow) {
        _scheduleAnchorMeasure();
      } else if (nextValue?.generation == GenerationPhase.streaming) {
        _scheduleAnchorMeasure();
        _followTail();
      } else if (priorValue?.generation == GenerationPhase.streaming) {
        // The last delta can extend the layout after the final jump.
        _scheduleAnchorMeasure();
        _scrollToLatest();
      }
    });
    final chat = ref.watch(chatControllerProvider);
    return chat.when(
      loading: () => const CupertinoPageScaffold(
        child: Center(child: CupertinoActivityIndicator()),
      ),
      // Fixed copy plus a retry: raw exception text never reaches a surface
      // (handbook v5.0 §8.1), and the load failure must not brick the root
      // screen for the process lifetime — nothing else ever rebuilds this
      // keepAlive provider.
      error: (error, stack) => CupertinoPageScaffold(
        child: RetryPane(
          key: const Key('chat-load-error'),
          message: context.l10n.chatHistoryLoadFailed,
          actionLabel: context.l10n.tryAgain,
          onRetry: () => ref.invalidate(chatControllerProvider),
        ),
      ),
      data: (value) => _buildShell(context, value),
    );
  }

  Widget _buildShell(BuildContext context, ChatState chat) {
    final blocked =
        chat.generation != GenerationPhase.idle || chat.hasUnsavedAssistant;
    // Canvas, not drawer: this shows behind the translucent keyboard.
    return CupertinoPageScaffold(
      backgroundColor: GolemTheme.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rtl = Directionality.of(context) == TextDirection.rtl;
          final drawerRadius = BorderRadius.only(
            topLeft: rtl
                ? const Radius.circular(GolemRadius.drawer)
                : Radius.zero,
            bottomLeft: rtl
                ? const Radius.circular(GolemRadius.drawer)
                : Radius.zero,
            topRight: rtl
                ? Radius.zero
                : const Radius.circular(GolemRadius.drawer),
            bottomRight: rtl
                ? Radius.zero
                : const Radius.circular(GolemRadius.drawer),
          );
          // Capped at 330pt so a tap-to-dismiss strip of chat stays visible on
          // phone widths — deliberately wider than the handoff's ~307pt, which
          // read cramped on device against the conversation titles.
          final drawerWidth = (constraints.maxWidth * 0.9)
              .clamp(0, 330.0)
              .toDouble();
          return Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  excluding: _drawerOpen,
                  child: IgnorePointer(
                    key: const Key('chat-canvas'),
                    ignoring: _drawerOpen,
                    child: CupertinoPageScaffold(
                      backgroundColor: GolemTheme.canvas,
                      navigationBar: GolemNavBar(
                        backgroundColor: GolemTheme.canvas,
                        title: chat.active == null || chat.active!.title.isEmpty
                            ? context.l10n.newChat
                            : chat.active!.title,
                        subtitle: modelSubtitle(
                          backend: ref.watch(inferenceBackendProvider),
                          catalog: ref.watch(effectiveModelCatalogProvider),
                          activeKey: ref.watch(activeModelKeyProvider),
                          runsModels: ref.watch(
                            deviceEligibilityProvider.select(
                              (value) => value.runsModels,
                            ),
                          ),
                          unsupportedLabel: context.l10n.unsupportedDevice,
                          simulatedLabel: context.l10n.simulated,
                          onDeviceLabel: context.l10n.onDevice,
                        ),
                        // Contained glass follows the iOS 26 toolbar style;
                        // bare nav-bar glyphs read too small next to it.
                        leading: GolemTappable(
                          key: const Key('open-drawer'),
                          padding: EdgeInsets.zero,
                          onPressed: blocked
                              ? null
                              : () {
                                  _focus.unfocus();
                                  setState(() => _drawerOpen = true);
                                },
                          child: Glass(
                            radius: 20,
                            floating: true,
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(
                                CupertinoIcons.bars,
                                semanticLabel: context.l10n.openConversations,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                        trailing: GolemTappable(
                          key: const Key('new-chat-header'),
                          padding: EdgeInsets.zero,
                          onPressed: blocked
                              ? null
                              : () => ref
                                    .read(chatControllerProvider.notifier)
                                    .newChat(),
                          child: Glass(
                            radius: 20,
                            floating: true,
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(
                                CupertinoIcons.square_pencil,
                                semanticLabel: context.l10n.newChat,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: ChatCanvas(
                          chat: chat,
                          composer: _composer,
                          focus: _focus,
                          scroll: _scroll,
                          scrollToLatest: _scrollToLatest,
                          onUserScroll: _onUserScroll,
                          onScrollMetrics: _onScrollMetrics,
                          onScrollSettled: _onScrollSettled,
                          showJump: _showJump,
                          tailSpacer: _spacer,
                          anchorKey: _anchorKey,
                          anchorId: _anchorId,
                          picker: widget.picker,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (!_drawerOpen && !blocked)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: 24,
                  child: GestureDetector(
                    key: const Key('drawer-edge-swipe'),
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (rtl ? velocity < -280 : velocity > 280) {
                        _focus.unfocus();
                        setState(() => _drawerOpen = true);
                      }
                    },
                  ),
                ),
              // Always mounted so it can fade with the panel. Mounting it on
              // _drawerOpen made it pop in and out against a 250ms slide.
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_drawerOpen,
                  child: AnimatedOpacity(
                    opacity: _drawerOpen ? 1 : 0,
                    duration: GolemMotion.medium,
                    curve: GolemMotion.standard,
                    // Labelled like the modal barrier it is, so the
                    // screen-sized tap target announces itself; the dismiss
                    // action lets the screen-reader escape gesture close it.
                    child: Semantics(
                      button: true,
                      label: context.l10n.closeConversations,
                      onDismiss: () => setState(() => _drawerOpen = false),
                      child: GestureDetector(
                        key: const Key('drawer-dismiss'),
                        onTap: () => setState(() => _drawerOpen = false),
                        child: const ColoredBox(color: GolemTheme.drawerScrim),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedPositionedDirectional(
                key: const Key('conversation-drawer'),
                start: _drawerOpen ? 0 : -drawerWidth - _drawerHideMargin,
                top: 0,
                bottom: 0,
                width: drawerWidth,
                duration: GolemMotion.medium,
                curve: GolemMotion.standard,
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (rtl ? velocity > 280 : velocity < -280) {
                      setState(() => _drawerOpen = false);
                    }
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.drawer,
                        context,
                      ),
                      borderRadius: drawerRadius,
                      boxShadow: GolemShadow.drawer(context),
                    ),
                    // The panel's own rows round to 12pt, so without this
                    // the topmost and bottommost of them cut the corner.
                    child: ClipRRect(
                      borderRadius: drawerRadius,
                      child: ExcludeSemantics(
                        excluding: !_drawerOpen,
                        child: ConversationDrawer(
                          chat: chat,
                          blocked: blocked,
                          close: () => setState(() => _drawerOpen = false),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
