// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(FirstRunController)
final firstRunControllerProvider = FirstRunControllerProvider._();

final class FirstRunControllerProvider
    extends $NotifierProvider<FirstRunController, FirstRunState> {
  FirstRunControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'firstRunControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$firstRunControllerHash();

  @$internal
  @override
  FirstRunController create() => FirstRunController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FirstRunState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FirstRunState>(value),
    );
  }
}

String _$firstRunControllerHash() =>
    r'47c89c1f62683e5e098d24564bd696625e42921e';

abstract class _$FirstRunController extends $Notifier<FirstRunState> {
  FirstRunState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<FirstRunState, FirstRunState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FirstRunState, FirstRunState>,
              FirstRunState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
