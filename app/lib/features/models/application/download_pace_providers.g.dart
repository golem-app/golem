// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_pace_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The wall clock the pace notifier samples with, injectable so tests can
/// script byte/time pairs instead of racing real timers.

@ProviderFor(paceClock)
final paceClockProvider = PaceClockProvider._();

/// The wall clock the pace notifier samples with, injectable so tests can
/// script byte/time pairs instead of racing real timers.

final class PaceClockProvider
    extends
        $FunctionalProvider<
          DateTime Function(),
          DateTime Function(),
          DateTime Function()
        >
    with $Provider<DateTime Function()> {
  /// The wall clock the pace notifier samples with, injectable so tests can
  /// script byte/time pairs instead of racing real timers.
  PaceClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'paceClockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$paceClockHash();

  @$internal
  @override
  $ProviderElement<DateTime Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DateTime Function() create(Ref ref) {
    return paceClock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime Function()>(value),
    );
  }
}

String _$paceClockHash() => r'3006b2ff67ca2d0bc66966a59d23d5118d1a4623';

/// Live rate/ETA for the single in-flight artifact, derived by sampling
/// [ModelController]'s byte counts against the injected clock — transferred
/// bytes while downloading, hashed bytes while verifying, each phase its own
/// window. `null` until the trailing window can quote an honest figure, and
/// again the moment the artifact leaves both phases — surfaces render nothing
/// rather than a stale or fabricated number.
///
/// KeepAlive: the estimator's sample window lives in notifier fields, and the
/// model stream must stay observed across screens the way the controller
/// itself does. Timer-free by design — state only moves when the controller
/// publishes a tick, which keeps goldens and `pumpAndSettle` deterministic.

@ProviderFor(DownloadPace)
final downloadPaceProvider = DownloadPaceProvider._();

/// Live rate/ETA for the single in-flight artifact, derived by sampling
/// [ModelController]'s byte counts against the injected clock — transferred
/// bytes while downloading, hashed bytes while verifying, each phase its own
/// window. `null` until the trailing window can quote an honest figure, and
/// again the moment the artifact leaves both phases — surfaces render nothing
/// rather than a stale or fabricated number.
///
/// KeepAlive: the estimator's sample window lives in notifier fields, and the
/// model stream must stay observed across screens the way the controller
/// itself does. Timer-free by design — state only moves when the controller
/// publishes a tick, which keeps goldens and `pumpAndSettle` deterministic.
final class DownloadPaceProvider
    extends $NotifierProvider<DownloadPace, DownloadPaceSnapshot?> {
  /// Live rate/ETA for the single in-flight artifact, derived by sampling
  /// [ModelController]'s byte counts against the injected clock — transferred
  /// bytes while downloading, hashed bytes while verifying, each phase its own
  /// window. `null` until the trailing window can quote an honest figure, and
  /// again the moment the artifact leaves both phases — surfaces render nothing
  /// rather than a stale or fabricated number.
  ///
  /// KeepAlive: the estimator's sample window lives in notifier fields, and the
  /// model stream must stay observed across screens the way the controller
  /// itself does. Timer-free by design — state only moves when the controller
  /// publishes a tick, which keeps goldens and `pumpAndSettle` deterministic.
  DownloadPaceProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'downloadPaceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$downloadPaceHash();

  @$internal
  @override
  DownloadPace create() => DownloadPace();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DownloadPaceSnapshot? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DownloadPaceSnapshot?>(value),
    );
  }
}

String _$downloadPaceHash() => r'd8b76d122a5520e03649171f9ec8beab414291ab';

/// Live rate/ETA for the single in-flight artifact, derived by sampling
/// [ModelController]'s byte counts against the injected clock — transferred
/// bytes while downloading, hashed bytes while verifying, each phase its own
/// window. `null` until the trailing window can quote an honest figure, and
/// again the moment the artifact leaves both phases — surfaces render nothing
/// rather than a stale or fabricated number.
///
/// KeepAlive: the estimator's sample window lives in notifier fields, and the
/// model stream must stay observed across screens the way the controller
/// itself does. Timer-free by design — state only moves when the controller
/// publishes a tick, which keeps goldens and `pumpAndSettle` deterministic.

abstract class _$DownloadPace extends $Notifier<DownloadPaceSnapshot?> {
  DownloadPaceSnapshot? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DownloadPaceSnapshot?, DownloadPaceSnapshot?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DownloadPaceSnapshot?, DownloadPaceSnapshot?>,
              DownloadPaceSnapshot?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
