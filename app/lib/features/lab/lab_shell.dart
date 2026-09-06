import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chrome/golem_sheet.dart';
import '../../core/widgets/section_header.dart';
import '../../l10n/l10n.dart';
import '../../l10n/presentation_messages.dart';
import 'application/lab_bench_controller.dart';
import 'domain/lab_run.dart';
import 'lab_theme.dart';
import 'widgets/lab_composer.dart';
import 'widgets/lab_sidebar.dart';
import 'widgets/metrics_footer.dart';
import 'widgets/prompt_tray.dart';
import 'widgets/rig_bar.dart';
import 'widgets/run_card.dart';
import 'widgets/run_settings_sheet.dart';

/// The bench (#58): sidebar, Rig, transcript, tray, composer and footer. The
/// composer owns focus; keyboard shortcuts live here so they work wherever
/// focus is: ⌘↩ runs, Escape stops, ⌘N starts a conversation.
class LabShell extends ConsumerStatefulWidget {
  const LabShell({this.clock, super.key});

  /// The clock elapsed figures read against; a test pins it so goldens hold.
  final DateTime Function()? clock;

  @override
  ConsumerState<LabShell> createState() => _LabShellState();
}

class _LabShellState extends ConsumerState<LabShell> {
  final _composer = TextEditingController();
  final _composerFocus = FocusNode(debugLabel: 'lab-composer');
  final _scroll = ScrollController();
  late final List<TrayPrompt> _tray = trayPrompts();

  /// Whether the transcript follows the run. A run that grows keeps the view
  /// at the end until the reader scrolls back up, and again once they reach
  /// the end — the rule chat follows too. Read from the reader's own
  /// scrolls, never from the position alone: a card that grows under a
  /// still view moves the end away without anyone scrolling.
  bool _atEnd = true;
  String? _followedRunId;

  bool _onScroll(ScrollNotification notification) {
    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.forward) {
      _atEnd = false;
    } else if (notification is ScrollEndNotification &&
        notification.metrics.extentAfter < LabSize.trayRow) {
      // Judged where a scroll ends, not along the way: a drag up starts at
      // the end, and the updates it emits there are not an arrival.
      _atEnd = true;
    }
    return false;
  }

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final sent = await ref.read(labBenchControllerProvider.notifier).send(text);
    if (sent && mounted) {
      _composer.clear();
      _composerFocus.requestFocus();
      _scrollToEnd();
    }
  }

  void _stop() => ref.read(labBenchControllerProvider.notifier).stop();

  void _newConversation() {
    ref.read(labBenchControllerProvider.notifier).newConversation();
    _composerFocus.requestFocus();
  }

  void _pick(TrayPrompt prompt) {
    _composer.text = prompt.text;
    _composerFocus.requestFocus();
  }

  Future<void> _showAllPrompts() => showGolemSheet<void>(
    context: context,
    sheetKey: const Key('lab-tray-sheet'),
    builder: (context) => Padding(
      padding: const EdgeInsets.all(LabSpace.s8),
      child: SingleChildScrollView(
        child: PromptTrayGrid(
          prompts: _tray,
          onPick: (prompt) {
            Navigator.of(context).pop();
            _pick(prompt);
          },
        ),
      ),
    ),
  );

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      _atEnd = true;
    });
  }

  /// Run edges are announced once each; every other status change stays
  /// visual, so a stream of chips never talks over the answer.
  void _announce(LabBenchState? before, LabBenchState after) {
    final wasLocked = before?.locked ?? false;
    if (wasLocked == after.locked) return;
    final message = after.locked
        ? context.l10n.labRunStarted
        : context.l10n.labRunFinished;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  /// A new run always comes into view; a growing one is followed only while
  /// the view is already at the end.
  void _follow(LabBenchState? before, LabBenchState after) {
    _announce(before, after);
    final run = after.activeRun;
    if (run == null) return;
    if (run.id != _followedRunId) {
      _followedRunId = run.id;
      _scrollToEnd();
    } else if (_atEnd) {
      // Including the terminal publish: the result line, or Retry, lands
      // at the bottom of a card the view was already following.
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(labBenchControllerProvider, _follow);
    final bench = ref.watch(labBenchControllerProvider);
    final locked = bench.locked;
    final now = widget.clock?.call() ?? DateTime.now();
    final conversations = bench.session.conversations;
    final hasRuns = bench.session.runCount > 0;
    final canSend = bench.armed != null && !locked;
    final lastRun = bench.session.active?.last;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter, meta: true): _SendIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _StopIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            _NewConversationIntent(),
      },
      child: Actions(
        actions: {
          _SendIntent: CallbackAction<_SendIntent>(
            onInvoke: (_) {
              if (canSend) _send();
              return null;
            },
          ),
          _StopIntent: CallbackAction<_StopIntent>(
            onInvoke: (_) {
              if (locked) _stop();
              return null;
            },
          ),
          _NewConversationIntent: CallbackAction<_NewConversationIntent>(
            onInvoke: (_) {
              if (!locked) _newConversation();
              return null;
            },
          ),
        },
        child: FocusTraversalGroup(
          child: CupertinoPageScaffold(
            key: const Key('lab-shell'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LabSidebar(),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RigBar(
                        onOpenSettings: () => showRunSettingsSheet(context),
                      ),
                      Expanded(
                        child: hasRuns
                            ? _Transcript(
                                controller: _scroll,
                                onScroll: _onScroll,
                                conversations: conversations,
                                now: now,
                                onRetry: locked
                                    ? null
                                    : () => ref
                                          .read(
                                            labBenchControllerProvider.notifier,
                                          )
                                          .retry(),
                              )
                            : _EmptyBench(
                                prompts: _tray,
                                onPick: locked ? null : _pick,
                              ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(
                          LabSpace.gutter,
                          LabSpace.s4,
                          LabSpace.gutter,
                          LabSpace.s4,
                        ),
                        decoration: BoxDecoration(
                          color: context.surface,
                          border: Border(
                            top: BorderSide(color: context.divider),
                          ),
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: LabSize.transcriptMaxWidth,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (hasRuns) ...[
                                  PromptTrayRow(
                                    prompts: _tray,
                                    onPick: locked ? null : _pick,
                                    onShowAll: locked ? null : _showAllPrompts,
                                  ),
                                  const SizedBox(height: LabSpace.s3),
                                ],
                                LabComposer(
                                  controller: _composer,
                                  focusNode: _composerFocus,
                                  locked: locked,
                                  canSend: canSend,
                                  onSend: _send,
                                  onStop: _stop,
                                  onNewConversation: _newConversation,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      MetricsFooter(run: bench.activeRun ?? lastRun),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}

class _StopIntent extends Intent {
  const _StopIntent();
}

class _NewConversationIntent extends Intent {
  const _NewConversationIntent();
}

class _EmptyBench extends StatelessWidget {
  const _EmptyBench({required this.prompts, required this.onPick});

  final List<TrayPrompt> prompts;
  final ValueChanged<TrayPrompt>? onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: LabSpace.gutter * 2,
          vertical: LabSpace.s9,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: LabSize.transcriptMaxWidth,
          ),
          child: Column(
            key: const Key('lab-empty'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.labEmptyTitle,
                style: LabText.headline.copyWith(color: context.ink),
              ),
              const SizedBox(height: LabSpace.s2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  l10n.labEmptyBody,
                  style: LabText.body.copyWith(color: context.mutedInk),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  LabSpace.s9,
                  0,
                  LabSpace.s3,
                ),
                child: SectionHeader(
                  l10n.labPromptTray,
                  style: LabText.overline,
                ),
              ),
              PromptTrayGrid(prompts: prompts, onPick: onPick),
              const SizedBox(height: LabSpace.s7),
              Row(
                children: [
                  Icon(
                    CupertinoIcons.lab_flask,
                    size: 13,
                    color: context.mutedInk,
                  ),
                  const SizedBox(width: LabSpace.s2),
                  Expanded(
                    child: Text(
                      l10n.labMeasuredOnThisMac,
                      style: LabText.detail.copyWith(color: context.mutedInk),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({
    required this.controller,
    required this.onScroll,
    required this.conversations,
    required this.now,
    required this.onRetry,
  });

  final ScrollController controller;
  final bool Function(ScrollNotification) onScroll;
  final List<LabConversation> conversations;
  final DateTime now;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Flattened so the list builds only what is on screen: a conversation
    // is not one child but a header and its runs, and only the live run
    // reads the clock.
    final lastConversation = conversations.last;
    final entries = <Widget Function()>[];
    for (final conversation in conversations) {
      if (conversation.runs.isEmpty) continue;
      final first = conversation.runs.first.configuration;
      entries.add(
        () => Padding(
          padding: const EdgeInsets.only(bottom: LabSpace.s4),
          child: SectionHeader(
            l10n.labConversationHeader(
              first.displayName,
              engineLabel(first.engine),
              conversation.runs.length,
            ),
            style: LabText.overline,
          ),
        ),
      );
      for (final run in conversation.runs) {
        final last =
            identical(conversation, lastConversation) &&
            identical(run, conversation.last);
        entries.add(
          () => Padding(
            padding: const EdgeInsets.only(bottom: LabSpace.s8),
            child: RepaintBoundary(
              child: RunCard(
                key: ValueKey(run.id),
                run: run,
                now: run.isTerminal ? run.endedAt ?? now : now,
                onRetry:
                    last &&
                        (run.phase == LabRunPhase.failed ||
                            run.phase == LabRunPhase.cancelled)
                    ? onRetry
                    : null,
              ),
            ),
          ),
        );
      }
    }
    return NotificationListener<ScrollNotification>(
      onNotification: onScroll,
      child: ListView.builder(
        key: const Key('lab-transcript'),
        controller: controller,
        padding: const EdgeInsets.symmetric(
          horizontal: LabSpace.gutter * 2,
          vertical: LabSpace.s8,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: LabSize.transcriptMaxWidth,
            ),
            child: entries[index](),
          ),
        ),
      ),
    );
  }
}
