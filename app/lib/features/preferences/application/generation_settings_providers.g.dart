// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'generation_settings_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Only user-set values are stored; profile defaults resolve at the consumer.
/// KeepAlive: a handbook v5.0 §3.2 client-state owner — the session's sole
/// in-memory read owner over write-through persistence.

@ProviderFor(SettingsController)
final settingsControllerProvider = SettingsControllerProvider._();

/// Only user-set values are stored; profile defaults resolve at the consumer.
/// KeepAlive: a handbook v5.0 §3.2 client-state owner — the session's sole
/// in-memory read owner over write-through persistence.
final class SettingsControllerProvider
    extends $AsyncNotifierProvider<SettingsController, GenerationSettings> {
  /// Only user-set values are stored; profile defaults resolve at the consumer.
  /// KeepAlive: a handbook v5.0 §3.2 client-state owner — the session's sole
  /// in-memory read owner over write-through persistence.
  SettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'settingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsControllerHash();

  @$internal
  @override
  SettingsController create() => SettingsController();
}

String _$settingsControllerHash() =>
    r'16471fb186699675ede268459ed08748adb14234';

/// Only user-set values are stored; profile defaults resolve at the consumer.
/// KeepAlive: a handbook v5.0 §3.2 client-state owner — the session's sole
/// in-memory read owner over write-through persistence.

abstract class _$SettingsController extends $AsyncNotifier<GenerationSettings> {
  FutureOr<GenerationSettings> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<GenerationSettings>, GenerationSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<GenerationSettings>, GenerationSettings>,
              AsyncValue<GenerationSettings>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
