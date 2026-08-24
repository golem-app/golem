// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_note_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The one statement of the note's visibility rule: the artifact is in
/// flight — downloading, or hashing what it downloaded, which a suspended
/// app also stops. Holding through the verify edge keeps the first-run card
/// from re-centring when the note would otherwise leave. Applies in
/// simulated mode too — QA drives the fake backend, and the surfaces already
/// carry their own simulation labeling.

@ProviderFor(downloadNoteVisible)
final downloadNoteVisibleProvider = DownloadNoteVisibleFamily._();

/// The one statement of the note's visibility rule: the artifact is in
/// flight — downloading, or hashing what it downloaded, which a suspended
/// app also stops. Holding through the verify edge keeps the first-run card
/// from re-centring when the note would otherwise leave. Applies in
/// simulated mode too — QA drives the fake backend, and the surfaces already
/// carry their own simulation labeling.

final class DownloadNoteVisibleProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// The one statement of the note's visibility rule: the artifact is in
  /// flight — downloading, or hashing what it downloaded, which a suspended
  /// app also stops. Holding through the verify edge keeps the first-run card
  /// from re-centring when the note would otherwise leave. Applies in
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
    r'be5a483f4e37ea2be6dbdb513c9348680c39e161';

/// The one statement of the note's visibility rule: the artifact is in
/// flight — downloading, or hashing what it downloaded, which a suspended
/// app also stops. Holding through the verify edge keeps the first-run card
/// from re-centring when the note would otherwise leave. Applies in
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

  /// The one statement of the note's visibility rule: the artifact is in
  /// flight — downloading, or hashing what it downloaded, which a suspended
  /// app also stops. Holding through the verify edge keeps the first-run card
  /// from re-centring when the note would otherwise leave. Applies in
  /// simulated mode too — QA drives the fake backend, and the surfaces already
  /// carry their own simulation labeling.

  DownloadNoteVisibleProvider call(String artifactKey) =>
      DownloadNoteVisibleProvider._(argument: artifactKey, from: this);

  @override
  String toString() => r'downloadNoteVisibleProvider';
}
