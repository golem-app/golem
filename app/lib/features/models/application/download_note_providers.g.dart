// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_note_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Which artifacts' foreground-speed notes the user has waved away, scoped to
/// the download attempt: an artifact re-entering `downloading` — a fresh
/// download, a resume, a retry — clears its dismissal, so the note returns
/// exactly when the trade-off becomes live again. In-memory on purpose; the
/// note is situational advice, not a preference.
///
/// KeepAlive: dismissal must survive navigation between the surfaces that
/// share it (first-run, Settings, the chat setup banner).

@ProviderFor(DownloadNoteDismissal)
final downloadNoteDismissalProvider = DownloadNoteDismissalProvider._();

/// Which artifacts' foreground-speed notes the user has waved away, scoped to
/// the download attempt: an artifact re-entering `downloading` — a fresh
/// download, a resume, a retry — clears its dismissal, so the note returns
/// exactly when the trade-off becomes live again. In-memory on purpose; the
/// note is situational advice, not a preference.
///
/// KeepAlive: dismissal must survive navigation between the surfaces that
/// share it (first-run, Settings, the chat setup banner).
final class DownloadNoteDismissalProvider
    extends $NotifierProvider<DownloadNoteDismissal, Set<String>> {
  /// Which artifacts' foreground-speed notes the user has waved away, scoped to
  /// the download attempt: an artifact re-entering `downloading` — a fresh
  /// download, a resume, a retry — clears its dismissal, so the note returns
  /// exactly when the trade-off becomes live again. In-memory on purpose; the
  /// note is situational advice, not a preference.
  ///
  /// KeepAlive: dismissal must survive navigation between the surfaces that
  /// share it (first-run, Settings, the chat setup banner).
  DownloadNoteDismissalProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'downloadNoteDismissalProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$downloadNoteDismissalHash();

  @$internal
  @override
  DownloadNoteDismissal create() => DownloadNoteDismissal();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$downloadNoteDismissalHash() =>
    r'2a94bdb6b211b54aa81e22193835724e1f7bb0ed';

/// Which artifacts' foreground-speed notes the user has waved away, scoped to
/// the download attempt: an artifact re-entering `downloading` — a fresh
/// download, a resume, a retry — clears its dismissal, so the note returns
/// exactly when the trade-off becomes live again. In-memory on purpose; the
/// note is situational advice, not a preference.
///
/// KeepAlive: dismissal must survive navigation between the surfaces that
/// share it (first-run, Settings, the chat setup banner).

abstract class _$DownloadNoteDismissal extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The byte count each downloading artifact had when its current attempt
/// began, frozen so the note's "about X instead of about Y" comparison keeps
/// one pair of figures for the whole attempt instead of counting down under
/// the reader. Re-recorded at the same boundary that resurrects a dismissed
/// note; seeded from the current state so a surface opened mid-transfer
/// still gets a stable figure.

@ProviderFor(DownloadNoteFigures)
final downloadNoteFiguresProvider = DownloadNoteFiguresProvider._();

/// The byte count each downloading artifact had when its current attempt
/// began, frozen so the note's "about X instead of about Y" comparison keeps
/// one pair of figures for the whole attempt instead of counting down under
/// the reader. Re-recorded at the same boundary that resurrects a dismissed
/// note; seeded from the current state so a surface opened mid-transfer
/// still gets a stable figure.
final class DownloadNoteFiguresProvider
    extends $NotifierProvider<DownloadNoteFigures, Map<String, int>> {
  /// The byte count each downloading artifact had when its current attempt
  /// began, frozen so the note's "about X instead of about Y" comparison keeps
  /// one pair of figures for the whole attempt instead of counting down under
  /// the reader. Re-recorded at the same boundary that resurrects a dismissed
  /// note; seeded from the current state so a surface opened mid-transfer
  /// still gets a stable figure.
  DownloadNoteFiguresProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'downloadNoteFiguresProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$downloadNoteFiguresHash();

  @$internal
  @override
  DownloadNoteFigures create() => DownloadNoteFigures();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, int> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, int>>(value),
    );
  }
}

String _$downloadNoteFiguresHash() =>
    r'ab26b207f51260312d50e7c7cccb30fa40c5a15e';

/// The byte count each downloading artifact had when its current attempt
/// began, frozen so the note's "about X instead of about Y" comparison keeps
/// one pair of figures for the whole attempt instead of counting down under
/// the reader. Re-recorded at the same boundary that resurrects a dismissed
/// note; seeded from the current state so a surface opened mid-transfer
/// still gets a stable figure.

abstract class _$DownloadNoteFigures extends $Notifier<Map<String, int>> {
  Map<String, int> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Map<String, int>, Map<String, int>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, int>, Map<String, int>>,
              Map<String, int>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The one statement of the note's visibility rule: an artifact is actively
/// downloading and its note has not been dismissed this attempt. Applies in
/// simulated mode too — QA drives the fake backend, and the surfaces already
/// carry their own simulation labeling.

@ProviderFor(downloadNoteVisible)
final downloadNoteVisibleProvider = DownloadNoteVisibleFamily._();

/// The one statement of the note's visibility rule: an artifact is actively
/// downloading and its note has not been dismissed this attempt. Applies in
/// simulated mode too — QA drives the fake backend, and the surfaces already
/// carry their own simulation labeling.

final class DownloadNoteVisibleProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// The one statement of the note's visibility rule: an artifact is actively
  /// downloading and its note has not been dismissed this attempt. Applies in
  /// simulated mode too — QA drives the fake backend, and the surfaces already
  /// carry their own simulation labeling.
  DownloadNoteVisibleProvider._({
    required DownloadNoteVisibleFamily super.from,
    required String super.argument,
  }) : super(
         retry: noRetry,
         name: r'downloadNoteVisibleProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$downloadNoteVisibleHash();

  @override
  String toString() {
    return r'downloadNoteVisibleProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    final argument = this.argument as String;
    return downloadNoteVisible(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DownloadNoteVisibleProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$downloadNoteVisibleHash() =>
    r'f8dda7e245ef1620af88769ae74fdb8d8645f2d5';

/// The one statement of the note's visibility rule: an artifact is actively
/// downloading and its note has not been dismissed this attempt. Applies in
/// simulated mode too — QA drives the fake backend, and the surfaces already
/// carry their own simulation labeling.

final class DownloadNoteVisibleFamily extends $Family
    with $FunctionalFamilyOverride<bool, String> {
  DownloadNoteVisibleFamily._()
    : super(
        retry: noRetry,
        name: r'downloadNoteVisibleProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The one statement of the note's visibility rule: an artifact is actively
  /// downloading and its note has not been dismissed this attempt. Applies in
  /// simulated mode too — QA drives the fake backend, and the surfaces already
  /// carry their own simulation labeling.

  DownloadNoteVisibleProvider call(String artifactKey) =>
      DownloadNoteVisibleProvider._(argument: artifactKey, from: this);

  @override
  String toString() => r'downloadNoteVisibleProvider';
}
