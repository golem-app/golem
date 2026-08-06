import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/theme/golem_theme.dart';

class EmptyChat extends ConsumerWidget {
  const EmptyChat({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Copy stays honest in both directions: only the fake backend may call
    // itself simulated.
    final simulated = ref.watch(inferenceBackendProvider).simulatedInference;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Semantics(
          key: const Key('empty-chat'),
          label: 'Start a private conversation',
          child: Column(
            children: [
              Image.asset(
                'assets/images/golem_mascot.png',
                width: 112,
                height: 112,
              ),
              const SizedBox(height: 22),
              const Text('How can I help?', style: GolemText.display),
              const SizedBox(height: 10),
              Text(
                simulated
                    ? 'Your conversations stay on this device.\nThis Flutter preview uses a simulated model.'
                    : 'Your conversations stay on this device.\nGolem generates with a local on-device model.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.4,
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
