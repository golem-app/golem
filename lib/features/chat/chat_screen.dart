import 'package:flutter/cupertino.dart';
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

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final show =
          _scroll.hasClients &&
          _scroll.position.maxScrollExtent - _scroll.offset > 240;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
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
      if (nextLength != priorLength ||
          nextValue?.generation == GenerationPhase.streaming) {
        if (!_showJump) _scrollToLatest();
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
    return CupertinoPageScaffold(
      backgroundColor: GolemTheme.drawer,
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
