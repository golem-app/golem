import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/app_state.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import 'widgets/chat_canvas.dart';
import 'widgets/conversation_drawer.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _drawerOpen = false;
  bool _showJump = false;
  // Whether the view follows the streaming tail. Only a deliberate upward
  // drag detaches it; growing content never does — distance-based detach
  // made fast responses outrun the animation and stop following mid-answer.
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final distance = _scroll.position.maxScrollExtent - _scroll.offset;
      if (distance < 48 && !_follow) _follow = true;
      final show = distance > 240;
      if (show != _showJump && mounted) setState(() => _showJump = show);
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    _search.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    _follow = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _animateToBottom());
  }

  Future<void> _animateToBottom() async {
    // The list's maxScrollExtent is a lazy-layout estimate that grows as
    // items build, so a single animation can undershoot; chase the extent
    // until the tail is actually reached (or the user drags away).
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
        // The last delta can extend the layout after the final jump; settle
        // flush with the finished answer.
        _scrollToLatest();
      }
    });
    final chat = ref.watch(chatControllerProvider);
    return chat.when(
      loading: () => const CupertinoPageScaffold(
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (error, stack) => CupertinoPageScaffold(
        child: Center(child: Text('Could not load chat history: $error')),
      ),
      data: (value) => _buildShell(context, value),
    );
  }

  Widget _buildShell(BuildContext context, ChatState chat) {
    final blocked =
        chat.generation != GenerationPhase.idle || chat.hasUnsavedAssistant;
    // Canvas, not drawer navy: this is what shows behind the translucent
    // keyboard in both appearances. The navy drawer backdrop is a fading
    // layer inside the stack instead, present only while the drawer shows.
    return CupertinoPageScaffold(
      backgroundColor: GolemTheme.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Matches native GolemTheme.Metrics.drawerWidth (330pt) so both
          // apps leave the same tap-to-dismiss strip of chat visible.
          final drawerWidth = (constraints.maxWidth * 0.9)
              .clamp(0, 330.0)
              .toDouble();
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _drawerOpen ? 1 : 0,
                    duration: const Duration(milliseconds: 360),
                    curve: Curves.easeOutCubic,
                    child: const ColoredBox(color: GolemTheme.drawer),
                  ),
                ),
              ),
              Positioned.fill(
                child: ExcludeSemantics(
                  excluding: _drawerOpen,
                  child: IgnorePointer(
                    ignoring: _drawerOpen,
                    child: AnimatedScale(
                      key: const Key('chat-canvas'),
                      scale: _drawerOpen ? 0.94 : 1,
                      alignment: const Alignment(0.7, 0),
                      duration: const Duration(milliseconds: 360),
                      curve: Curves.easeOutCubic,
                      child: CupertinoPageScaffold(
                        backgroundColor: GolemTheme.canvas,
                        navigationBar: CupertinoNavigationBar(
                          backgroundColor: GolemTheme.canvas,
                          middle: Text(
                            chat.active?.title ?? 'New chat',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Contained glass buttons follow the iOS 26
                          // toolbar style; bare nav-bar glyphs read too
                          // small next to it.
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
                            showJump: _showJump,
                          ),
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
              if (_drawerOpen)
                Positioned.fill(
                  child: GestureDetector(
                    key: const Key('drawer-dismiss'),
                    onTap: () => setState(() => _drawerOpen = false),
                    child: const ColoredBox(color: GolemTheme.scrim),
                  ),
                ),
              AnimatedPositioned(
                key: const Key('conversation-drawer'),
                left: _drawerOpen ? 0 : -drawerWidth - 28,
                top: 0,
                bottom: 0,
                width: drawerWidth,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < -280) {
                      setState(() => _drawerOpen = false);
                    }
                  },
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: GolemTheme.drawer,
                      boxShadow: [
                        BoxShadow(
                          color: GolemTheme.drawerShadow,
                          blurRadius: 30,
                          offset: Offset(12, 0),
                        ),
                      ],
                    ),
                    child: ExcludeSemantics(
                      excluding: !_drawerOpen,
                      child: ConversationDrawer(
                        chat: chat,
                        search: _search,
                        blocked: blocked,
                        close: () => setState(() => _drawerOpen = false),
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
