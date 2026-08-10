import 'package:flutter/widgets.dart';

import '../../core/chrome/golem_toast.dart';

/// Awaits a controller mutation outcome and toasts when the write failed —
/// the control has already snapped back to the persisted value, so the
/// control itself is the retry affordance.
Future<void> announceFailedSave(
  BuildContext context,
  Future<bool> pending, {
  String message = "Couldn't save. Try again.",
}) async {
  final saved = await pending;
  if (!saved && context.mounted) showGolemToast(context, message);
}
