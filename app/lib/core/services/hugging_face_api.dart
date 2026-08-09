/// The Hugging Face Hub read seam (#52).
///
/// Deliberately tiny and transport-only: three GETs, no knowledge of models,
/// engines or capability. The resolver decides what to ask for and what an
/// answer means, which keeps every resolution rule testable without a network.
///
/// `dart:io`'s `HttpClient` rather than a new dependency — the same choice
/// `packages/inferno/tool/verify_pins.dart` already makes. Weights do not come
/// through here: multi-gigabyte transfers stay with `ArtifactFileDownloader`,
/// which survives backgrounding and can resume.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Why a Hub request could not be answered.
enum HubErrorKind {
  /// HTTP 401/404. The Hub answers identically for a repository that does not
  /// exist and one that is private, so these cannot be told apart and must not
  /// be reported as if they could.
  notFoundOrPrivate,

  /// HTTP 429 or 503. Retryable, and the user should be told to wait rather
  /// than that their repository is wrong.
  rateLimited,

  /// The request never completed: no route, DNS failure, timeout, reset.
  network,

  /// A 2xx whose body was not what the endpoint promises.
  malformed,

  /// A response larger than the caller allowed.
  tooLarge,

  /// Any other status.
  unexpectedStatus,
}

final class HubException implements Exception {
  const HubException(this.kind, {this.status, this.cause});

  final HubErrorKind kind;
  final int? status;
  final Object? cause;

  @override
  String toString() =>
      'HubException($kind${status == null ? '' : ', HTTP $status'})';
}

abstract interface class HuggingFaceApi {
  /// The decoded JSON object at [url].
  Future<Map<String, Object?>> json(Uri url);

  /// The whole document at [url] as text, refused past [maxBytes] so a file
  /// that is unexpectedly enormous cannot be pulled into memory.
  Future<String> text(Uri url, {int maxBytes});

  /// Bytes `[start, endInclusive]` of [url].
  ///
  /// A server that ignores the range and sends the whole file is treated as
  /// [HubErrorKind.tooLarge] rather than silently downloading it.
  Future<Uint8List> range(
    Uri url, {
    required int start,
    required int endInclusive,
  });
}

/// The Hub's public read API. Hosts are fixed here, not taken from input: no
/// caller can redirect resolution at an arbitrary server.
const huggingFaceHost = 'huggingface.co';

/// Builds a Hub URL from discrete segments.
///
/// `pathSegments` rather than a joined path string, because a git ref
/// legitimately contains `/` (`refs/pr/3`, `feature/x`) and must stay one
/// segment. Pre-encoding it instead would be double-encoded here — `Uri.https`
/// escapes the `%` — and the request would ask for a ref literally named
/// `refs%2Fpr%2F3`.
Uri _hubUrl(List<String> segments, [Map<String, String>? query]) => Uri(
  scheme: 'https',
  host: huggingFaceHost,
  pathSegments: segments,
  queryParameters: query,
);

Uri hubRevisionUrl(String repository, String ref, {bool blobs = false}) =>
    _hubUrl([
      'api',
      'models',
      ...repository.split('/'),
      'revision',
      ref,
    ], blobs ? const {'blobs': 'true'} : null);

Uri hubResolveUrl(String repository, String commitSha, String path) => _hubUrl([
  ...repository.split('/'),
  'resolve',
  commitSha,
  ...path.split('/'),
]);

final class HttpClientHuggingFaceApi implements HuggingFaceApi {
  HttpClientHuggingFaceApi({
    HttpClient? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? (HttpClient()..userAgent = 'golem-app');

  final HttpClient _client;
  final Duration timeout;

  void close() => _client.close(force: true);

  @override
  Future<Map<String, Object?>> json(Uri url) async {
    final body = await _get(url, maxBytes: 8 * 1024 * 1024);
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map) {
        throw const HubException(HubErrorKind.malformed);
      }
      return Map<String, Object?>.from(decoded);
    } on FormatException catch (error) {
      throw HubException(HubErrorKind.malformed, cause: error);
    }
  }

  @override
  Future<String> text(Uri url, {int maxBytes = 4 * 1024 * 1024}) async {
    final body = await _get(url, maxBytes: maxBytes);
    try {
      return utf8.decode(body);
    } on FormatException catch (error) {
      throw HubException(HubErrorKind.malformed, cause: error);
    }
  }

  @override
  Future<Uint8List> range(
    Uri url, {
    required int start,
    required int endInclusive,
  }) async {
    final span = endInclusive - start + 1;
    // One extra byte of slack: a server may legitimately return less, and
    // exactly the span is the normal case, but never more than asked for.
    return _get(
      url,
      maxBytes: span,
      headers: {HttpHeaders.rangeHeader: 'bytes=$start-$endInclusive'},
    );
  }

  Future<Uint8List> _get(
    Uri url, {
    required int maxBytes,
    Map<String, String> headers = const {},
  }) async {
    HttpClientResponse response;
    try {
      final request = await _client.getUrl(url).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      headers.forEach(request.headers.set);
      request.followRedirects = true;
      response = await request.close().timeout(timeout);
    } on Object catch (error) {
      // Every transport failure folds to one kind: the distinctions between a
      // socket error, a timeout and a bad host are not actionable for a user.
      throw HubException(HubErrorKind.network, cause: error);
    }
    final status = response.statusCode;
    if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
      await response.drain<void>().catchError((_) {});
      throw HubException(_kindFor(status), status: status);
    }
    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw const HubException(HubErrorKind.tooLarge);
        }
      }
    } on HubException {
      rethrow;
    } on Object catch (error) {
      throw HubException(HubErrorKind.network, cause: error);
    }
    return builder.takeBytes();
  }

  static HubErrorKind _kindFor(int status) => switch (status) {
    HttpStatus.unauthorized ||
    HttpStatus.forbidden ||
    HttpStatus.notFound => HubErrorKind.notFoundOrPrivate,
    HttpStatus.tooManyRequests ||
    HttpStatus.serviceUnavailable => HubErrorKind.rateLimited,
    _ => HubErrorKind.unexpectedStatus,
  };
}
