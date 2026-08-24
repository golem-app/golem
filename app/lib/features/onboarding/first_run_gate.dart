import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chrome/golem_button.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../l10n/l10n.dart';
import 'application/onboarding_controller.dart';
import 'application/startup_gate_controller.dart';
import 'domain/onboarding_policy.dart';
import 'first_run_screen.dart';

/// The consumer shell's single access boundary. The router stays mounted for
/// recovery and dialogs, while its all-routes shell keeps route content,
/// semantics, and keyboard actions unavailable until this policy admits the
/// process.
///
/// Rendering only (#126): the decision, the sideload load it waits on and the
/// legacy onboarding stamp all belong to [StartupGateController].
class FirstRunGate extends ConsumerWidget {
  const FirstRunGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Which validation is holding the shell decides which copy the blocking
    // panes carry. It is a boot constant, so it reads even while the gate
    // itself is still loading or has failed — which is the only moment the
    // gate cannot say so itself.
    final sideloaded = ref.watch(inferenceBackendProvider).sideloaded;
    final gate = ref.watch(startupGateControllerProvider);
    void retry() => ref.read(startupGateControllerProvider.notifier).retry();
    final waiting = _BlockingProgress(
      key: Key(sideloaded ? 'sideload-validating' : 'first-run-loading'),
    );
    final unavailable = _BlockingFailure(
      key: Key(
        sideloaded ? 'sideload-validation-failure' : 'first-run-read-failure',
      ),
      onRetry: retry,
    );

    // The retained value first, not this provider's own loading flag.
    // Riverpod republishes a refreshing provider as loading with its previous
    // value attached, and the gate has no "briefly undecided" state to render:
    // whatever it last decided still holds until the rebuild says otherwise.
    final decided = gate.value;
    if (decided == null) {
      // "Still deciding" beats "the last decision failed": a refresh keeps the
      // error attached (AsyncError.copyWithPrevious), so reading hasError first
      // leaves the failure pane and its live retry button up for the whole
      // reload — tens of seconds on a real sideload.
      return gate.isLoading ? waiting : unavailable;
    }
    return switch (decided) {
      GateWaiting() => waiting,
      GateUnavailable() => unavailable,
      GateUnsupported() => const FirstRunScreen(
        initialStep: FirstRunStep.unsupported,
      ),
      GateAdmitted() => child,
      GateFirstRun(:final entry) => FirstRunScreen(
        initialStep: switch (entry) {
          FirstRunEntry.fresh => null,
          FirstRunEntry.resumeDownload => FirstRunStep.download,
          FirstRunEntry.chooseModel => FirstRunStep.model,
        },
      ),
    };
  }
}

/// How long a wait must last before it earns an indicator. The store loads
/// an ordinary launch waits on finish in a few milliseconds, and there is no
/// Flutter splash in front of this pane any more (#159): a spinner that
/// appeared for one frame on every launch would be the flash this grace
/// exists to prevent. A sideload validation runs for seconds and shows one.
const blockingIndicatorGrace = Duration(milliseconds: 400);

class _BlockingProgress extends StatefulWidget {
  const _BlockingProgress({super.key});

  @override
  State<_BlockingProgress> createState() => _BlockingProgressState();
}

class _BlockingProgressState extends State<_BlockingProgress> {
  Timer? _grace;
  bool _indicate = false;

  @override
  void initState() {
    super.initState();
    _grace = Timer(blockingIndicatorGrace, () {
      if (mounted) setState(() => _indicate = true);
    });
  }

  @override
  void dispose() {
    _grace?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: Center(
      child: _indicate
          ? const CupertinoActivityIndicator(key: Key('blocking-indicator'))
          : const SizedBox.shrink(),
    ),
  );
}

class _BlockingFailure extends StatelessWidget {
  const _BlockingFailure({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.startupCouldNotFinish,
                textAlign: TextAlign.center,
                style: GolemText.display,
              ),
              const SizedBox(height: 20),
              GolemButton.filled(
                key: const Key('startup-gate-retry'),
                label: context.l10n.tryAgain,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
