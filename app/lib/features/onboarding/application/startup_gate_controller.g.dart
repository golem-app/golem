// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'startup_gate_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app root's admission decision (#126). It was a widget state machine:
/// sideload validation ran from a post-frame callback into `setState`, the
/// pristine-at-launch latch was mutated inside `build`, and the legacy
/// onboarding stamp was a write scheduled from `build`. Correctness depended
/// on how many frames pumped and none of it was observable through a provider.
///
/// KeepAlive: [_pristineAtLaunch] means what it says. A disposed element would
/// relatch it against whatever the stores hold later in the session, which is
/// the one thing the latch exists to prevent.

@ProviderFor(StartupGateController)
final startupGateControllerProvider = StartupGateControllerProvider._();

/// The app root's admission decision (#126). It was a widget state machine:
/// sideload validation ran from a post-frame callback into `setState`, the
/// pristine-at-launch latch was mutated inside `build`, and the legacy
/// onboarding stamp was a write scheduled from `build`. Correctness depended
/// on how many frames pumped and none of it was observable through a provider.
///
/// KeepAlive: [_pristineAtLaunch] means what it says. A disposed element would
/// relatch it against whatever the stores hold later in the session, which is
/// the one thing the latch exists to prevent.
final class StartupGateControllerProvider
    extends $AsyncNotifierProvider<StartupGateController, StartupGate> {
  /// The app root's admission decision (#126). It was a widget state machine:
  /// sideload validation ran from a post-frame callback into `setState`, the
  /// pristine-at-launch latch was mutated inside `build`, and the legacy
  /// onboarding stamp was a write scheduled from `build`. Correctness depended
  /// on how many frames pumped and none of it was observable through a provider.
  ///
  /// KeepAlive: [_pristineAtLaunch] means what it says. A disposed element would
  /// relatch it against whatever the stores hold later in the session, which is
  /// the one thing the latch exists to prevent.
  StartupGateControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'startupGateControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$startupGateControllerHash();

  @$internal
  @override
  StartupGateController create() => StartupGateController();
}

String _$startupGateControllerHash() =>
    r'cadf614d4a37f1094bebde62ab318f3d3b52d508';

/// The app root's admission decision (#126). It was a widget state machine:
/// sideload validation ran from a post-frame callback into `setState`, the
/// pristine-at-launch latch was mutated inside `build`, and the legacy
/// onboarding stamp was a write scheduled from `build`. Correctness depended
/// on how many frames pumped and none of it was observable through a provider.
///
/// KeepAlive: [_pristineAtLaunch] means what it says. A disposed element would
/// relatch it against whatever the stores hold later in the session, which is
/// the one thing the latch exists to prevent.

abstract class _$StartupGateController extends $AsyncNotifier<StartupGate> {
  FutureOr<StartupGate> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<StartupGate>, StartupGate>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<StartupGate>, StartupGate>,
              AsyncValue<StartupGate>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
