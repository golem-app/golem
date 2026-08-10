import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chrome/golem_nav_bar.dart';
import '../../core/domain/app_state.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/retry_pane.dart';
import 'model_label.dart';
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
  static const _drawerRadius = BorderRadius.horizontal(
    right: Radius.circular(GolemRadius.drawer),
  );

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
    final distance = _scroll.position.maxScrollExtent - _scroll.offset;
    if (distance < 48 && !_follow) _follow = true;
    final show = distance > 240;
    if (show != _showJump && mounted) setState(() => _showJump = show);
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    _follow = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _animateToBottom());
  }

  Future<void> _animateToBottom() async {
    // maxScrollExtent is a lazy-layout estimate that grows as items build, so
    // one animation can undershoot; chase the extent until the tail is really
    // reached (or the user drags away).
    for (var attempt = 0; attempt < 8; attempt++) {
      if (!_scroll.hasClients || !_follow) return;
      final target = _scroll.position.maxScrollExtent;
      if ((target - _scroll.offset).abs() < 1) return;
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
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _onUserScroll(ScrollDirection direction) {
    // Offset shrinking means the user is dragging toward older messages.
    if (direction == ScrollDirection.forward) _follow = false;
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
      if (nextLength != priorLength) {
        _scrollToLatest();
      } else if (!_follow) {
        return;
      } else if (nextValue?.generation == GenerationPhase.streaming) {
        _followTail();
      } else if (priorValue?.generation == GenerationPhase.streaming) {
        // The last delta can extend the layout after the final jump.
        _scrollToLatest();
      }
    });
    final chat = ref.watch(chatControllerProvider);
    return chat.when(
      loading: () => const CupertinoPageScaffold(
        child: Center(child: CupertinoActivityIndicator()),
      ),
      // Fixed copy plus a retry: raw exception text never reaches a surface
      // (§8.1), and the load failure must not brick the root screen for the
      // process lifetime — nothing else ever rebuilds this keepAlive provider.
      error: (error, stack) => CupertinoPageScaffold(
        child: RetryPane(
          key: const Key('chat-load-error'),
          message: "Couldn't load chat history.",
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
                        title: chat.active?.title ?? 'New chat',
                        subtitle: chatModelSubtitle(
                          backend: ref.watch(inferenceBackendProvider),
                          catalog: ref.watch(effectiveModelCatalogProvider),
                          modelKey: chat.active?.modelKey,
                          residentModelKey: ref.watch(residentModelKeyProvider),
                          loadableKeys: ref.watch(loadableModelKeysProvider),
                        ),
                        // Contained glass follows the iOS 26 toolbar style;
                        // bare nav-bar glyphs read too small next to it.
                        leading: CupertinoButton(
                          key: const Key('open-drawer'),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          onPressed: blocked
                              ? null
                              : () {
                                  _focus.unfocus();
                                  setState(() => _drawerOpen = true);
                                },
                          child: const Glass(
                            radius: 20,
                            floating: true,
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(
                                CupertinoIcons.bars,
                                semanticLabel: 'Open conversations',
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                        trailing: CupertinoButton(
                          key: const Key('new-chat-header'),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          onPressed: blocked
                              ? null
                              : () => ref
                                    .read(chatControllerProvider.notifier)
                                    .newChat(),
                          child: const Glass(
                            radius: 20,
                            floating: true,
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(
                                CupertinoIcons.square_pencil,
                                semanticLabel: 'New chat',
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
                          onScrollMetrics: _updateScrollState,
                          showJump: _showJump,
                          picker: widget.picker,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (!_drawerOpen && !blocked)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 24,
                  child: GestureDetector(
                    key: const Key('drawer-edge-swipe'),
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragEnd: (details) {
                      if ((details.primaryVelocity ?? 0) > 280) {
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
                      label: 'Close conversations',
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
              AnimatedPositioned(
                key: const Key('conversation-drawer'),
                left: _drawerOpen ? 0 : -drawerWidth - _drawerHideMargin,
                top: 0,
                bottom: 0,
                width: drawerWidth,
                duration: GolemMotion.medium,
                curve: GolemMotion.standard,
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < -280) {
                      setState(() => _drawerOpen = false);
                    }
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.drawer,
                        context,
                      ),
                      borderRadius: _drawerRadius,
                      boxShadow: GolemShadow.drawer,
                    ),
                    // The panel's own rows round to 12pt, so without this
                    // the topmost and bottommost of them cut the corner.
                    child: ClipRRect(
                      borderRadius: _drawerRadius,
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
