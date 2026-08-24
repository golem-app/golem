/// The Hugging Face Hub read seam (#52).
///
/// Transport-only: the resolver decides what to ask for and what an answer
/// means, which keeps every resolution rule testable without a network. Weights
/// do not come through here — multi-gigabyte transfers stay with
/// `ArtifactFileDownloader`, which survives backgrounding and can resume.
/// `dart:io`'s `HttpClient` rather than a new dependency.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum HubErrorKind {
  /// HTTP 401/404. The Hub answers identically for a missing repository and a
  /// private one, so these must not be reported as if they could be told apart.
  notFoundOrPrivate,

  /// HTTP 429 or 503. Retryable: tell the user to wait, not that they erred.
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
  Future<Map<String, Object?>> json(Uri url);

  /// Refused past [maxBytes] so an enormous file cannot be pulled into memory.
  Future<String> text(Uri url, {int maxBytes});

  /// Bytes `[start, endInclusive]` of [url]. A server that ignores the range
  /// and sends the whole file is [HubErrorKind.tooLarge], never a download.
  Future<Uint8List> range(
    Uri url, {
    required int start,
    required int endInclusive,
  });
}

/// Fixed here, never from input: no caller can redirect at another server.
const huggingFaceHost = 'huggingface.co';

/// `pathSegments` rather than a joined path, because a git ref legitimately
/// contains `/` (`refs/pr/3`) and must stay one segment. Pre-encoding would be
/// double-encoded — `Uri.https` escapes the `%` — asking for `refs%2Fpr%2F3`.
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
  }) : _client =
           client ??
           (HttpClient()
             ..userAgent = 'golem-app'
             // dart:io's own default, pinned here so the only bound on what a
             // process-lifetime client retains is stated where that lifetime
             // is. Nothing closes this one: `detached` is the only teardown
             // signal the app gets and Flutter permits `detached -> resumed`,
             // so a forced close there would fail the next resolution as a
             // network error (ADR 0014).
             ..idleTimeout = const Duration(seconds: 15));

  final HttpClient _client;

  /// Applies to connecting, to reading the response head, and — as an
  /// inactivity deadline — between body chunks.
  final Duration timeout;

  /// For tests, which build and tear down a client per case. Production keeps
  /// one for the life of the process; see the constructor.
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
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        HubException(HubErrorKind.malformed, cause: error),
        stackTrace,
      );
    }
  }

  @override
  Future<String> text(Uri url, {int maxBytes = 4 * 1024 * 1024}) async {
    final body = await _get(url, maxBytes: maxBytes);
    try {
      return utf8.decode(body);
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        HubException(HubErrorKind.malformed, cause: error),
        stackTrace,
      );
    }
  }

  @override
  Future<Uint8List> range(
    Uri url, {
    required int start,
    required int endInclusive,
  }) async {
    final span = endInclusive - start + 1;
    // Exactly the span is normal; a server may return less, never more.
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
    } on Object catch (error, stackTrace) {
      // Every transport failure folds to one kind: socket error, timeout and
      // bad host are not actionable distinctions for a user. The origin trace
      // still travels with it, or a socket fault reads as if it began here
      // (#130).
      Error.throwWithStackTrace(
        HubException(HubErrorKind.network, cause: error),
        stackTrace,
      );
    }
    final status = response.statusCode;
    if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
      // Deadlined like the success path below, and for the same reason: a
      // server that answers 4xx/5xx and then holds the socket open would
      // otherwise hang here, where the status is already known and the body
      // is being drained only to free the connection.
      await response.drain<void>().timeout(timeout).catchError((Object _) {});
      throw HubException(_kindFor(status), status: status);
    }
    final builder = BytesBuilder(copy: false);
    try {
      // Deadlined per chunk, not for the whole body: a slow but live
      // connection on a bad network is not a failure, while a server that
      // answers 200 and then stalls used to hang resolve() for as long as the
      // socket stayed open — behind a spinner, with no way back (ADR 0014).
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw const HubException(HubErrorKind.tooLarge);
        }
      }
    } on HubException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        HubException(HubErrorKind.network, cause: error),
        stackTrace,
      );
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
