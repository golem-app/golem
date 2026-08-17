import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/generation_settings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';

part 'settings_providers.g.dart';

/// Only user-set values are stored; profile defaults resolve at the consumer.
/// KeepAlive: a handbook v5.0 §3.2 client-state owner — the session's sole
/// in-memory read owner over write-through persistence.
@Riverpod(keepAlive: true, retry: noRetry)
class SettingsController extends _$SettingsController {
  /// The last state known to be on disk — what a failed commit snaps back
  /// to. Rolling back to the merely-previous state would restore another
  /// commit's unpersisted optimistic value when failures overlap.
  late GenerationSettings _persisted;

  @override
  Future<GenerationSettings> build() async {
    final loaded = await ref.read(settingsRepositoryProvider).load();
    _persisted = loaded;
    return loaded;
  }

  GenerationSettings get _value => state.requireValue;

  /// False means the write failed and the presented state snapped back to
  /// the last persisted value — the caller owns telling the user. Commands
  /// never throw, so fire-and-forget call sites stay safe.
  Future<bool> updateModel(
    String profileKey,
    SamplingOverrides overrides,
  ) async {
    // A tap can land in the cold-start load window; dropping it beats throwing
    // on requireValue while the store is still reading.
    if (!state.hasValue) return false;
    final next = _value.withModel(profileKey, overrides);
    state = AsyncData(next);
    try {
      await ref.read(settingsRepositoryProvider).save(next);
      _persisted = next;
      return true;
    } on Exception {
      // Roll back only while this commit is still the presented one; a newer
      // commit owns the presentation (and its own outcome) otherwise.
      if (ref.mounted && identical(state.value, next)) {
        state = AsyncData(_persisted);
      }
      return false;
    }
  }

  Future<bool> resetModel(String profileKey) =>
      updateModel(profileKey, const SamplingOverrides());
}
