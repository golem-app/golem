// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'startup_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// KeepAlive: the startup outcome is process-lifetime. This is the scripted
/// splash theatre (minimum hold, progress ticks, injected demo scenarios);
/// real launch failures and their retry live before this scope exists, in
/// the bootstrap gate (docs/decisions/0006-launch-bootstrap.md).

@ProviderFor(StartupController)
final startupControllerProvider = StartupControllerProvider._();

/// KeepAlive: the startup outcome is process-lifetime. This is the scripted
/// splash theatre (minimum hold, progress ticks, injected demo scenarios);
/// real launch failures and their retry live before this scope exists, in
/// the bootstrap gate (docs/decisions/0006-launch-bootstrap.md).
final class StartupControllerProvider
    extends $AsyncNotifierProvider<StartupController, StartupState> {
  /// KeepAlive: the startup outcome is process-lifetime. This is the scripted
  /// splash theatre (minimum hold, progress ticks, injected demo scenarios);
  /// real launch failures and their retry live before this scope exists, in
  /// the bootstrap gate (docs/decisions/0006-launch-bootstrap.md).
  StartupControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'startupControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$startupControllerHash();

  @$internal
  @override
  StartupController create() => StartupController();
}

String _$startupControllerHash() => r'08284a007c45251308e5f2fc134927daf7eefd00';

/// KeepAlive: the startup outcome is process-lifetime. This is the scripted
/// splash theatre (minimum hold, progress ticks, injected demo scenarios);
/// real launch failures and their retry live before this scope exists, in
/// the bootstrap gate (docs/decisions/0006-launch-bootstrap.md).

abstract class _$StartupController extends $AsyncNotifier<StartupState> {
  FutureOr<StartupState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<StartupState>, StartupState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<StartupState>, StartupState>,
              AsyncValue<StartupState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
