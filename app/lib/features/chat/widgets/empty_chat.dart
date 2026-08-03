import 'package:flutter/cupertino.dart';

import '../../../core/theme/golem_theme.dart';

class EmptyChat extends StatelessWidget {
  const EmptyChat({super.key});

  @override
  Widget build(BuildContext context) => Center(
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
            const Text(
              'How can I help?',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Your conversations stay on this device.\nThis Flutter preview uses a simulated model.',
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
