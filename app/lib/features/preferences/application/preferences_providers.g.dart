// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'preferences_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Persisted app-wide preferences. Every command follows the settings idiom —
/// drop taps that land in the cold-start load window, publish, then save —
/// and returns false after rolling back a failed write, never throwing.
/// KeepAlive: a handbook v5.0 §3.2 client-state owner; theme and text scale
/// drive the app root on every frame.

@ProviderFor(PreferencesController)
final preferencesControllerProvider = PreferencesControllerProvider._();

/// Persisted app-wide preferences. Every command follows the settings idiom —
/// drop taps that land in the cold-start load window, publish, then save —
/// and returns false after rolling back a failed write, never throwing.
/// KeepAlive: a handbook v5.0 §3.2 client-state owner; theme and text scale
/// drive the app root on every frame.
final class PreferencesControllerProvider
    extends $AsyncNotifierProvider<PreferencesController, AppPreferences> {
  /// Persisted app-wide preferences. Every command follows the settings idiom —
  /// drop taps that land in the cold-start load window, publish, then save —
  /// and returns false after rolling back a failed write, never throwing.
  /// KeepAlive: a handbook v5.0 §3.2 client-state owner; theme and text scale
  /// drive the app root on every frame.
  PreferencesControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'preferencesControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$preferencesControllerHash();

  @$internal
  @override
  PreferencesController create() => PreferencesController();
}

String _$preferencesControllerHash() =>
    r'f9341d7d71f9fe76a5b604799462a2ea2e27ba05';

/// Persisted app-wide preferences. Every command follows the settings idiom —
/// drop taps that land in the cold-start load window, publish, then save —
/// and returns false after rolling back a failed write, never throwing.
/// KeepAlive: a handbook v5.0 §3.2 client-state owner; theme and text scale
/// drive the app root on every frame.

abstract class _$PreferencesController extends $AsyncNotifier<AppPreferences> {
  FutureOr<AppPreferences> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<AppPreferences>, AppPreferences>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AppPreferences>, AppPreferences>,
              AsyncValue<AppPreferences>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
