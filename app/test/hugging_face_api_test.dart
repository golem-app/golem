import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/services/hugging_face_api.dart';

/// The Hub transport itself, over a loopback server.
///
/// Every other suite substitutes `ScriptedHuggingFaceApi`, and the only test
/// that reaches `HttpClientHuggingFaceApi` needs `GOLEM_LIVE_HUB=1` and the real
/// internet — so the status-to-[HubErrorKind] mapping a user actually feels was
/// never exercised offline. A local `HttpServer` covers it without a socket
/// leaving the machine.
void main() {
  late HttpServer server;
  late HttpClientHuggingFaceApi api;

  // Cleanup is registered here rather than in a file-level tearDown: the
  // URL-builder group never starts a server, and an unconditional tearDown
  // over `late` fields fails those tests with a LateInitializationError that
  // has nothing to do with what they assert.
  Future<void> serve(
    Future<void> Function(HttpRequest request) handle, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // Swallowed deliberately: two tests make the client abandon a response
    // mid-flight, so `response.close()` in the handler can fail on a socket
    // the client already destroyed. Unhandled, that error would surface
    // against whichever test happens to be running. Every assertion here is
    // on the client side, so a handler that dies has nothing left to say.
    unawaited(server.forEach(handle).catchError((Object _) {}));
    api = HttpClientHuggingFaceApi(timeout: timeout);
    addTearDown(() async {
      api.close();
      await server.close(force: true);
    });
  }

  Uri url([String path = '/thing']) =>
      Uri.parse('http://${server.address.host}:${server.port}$path');

  setUp(() {
    // flutter_test installs an HttpOverrides that answers every request with a
    // 400; this suite is the one place that wants a real socket. Restored
    // after each test so a case added here later that is *not* meant to reach
    // a socket still gets the framework's guard rather than the network.
    final installed = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = installed);
  });

  Future<void> respond(
    HttpRequest request, {
    int status = HttpStatus.ok,
    Object body = '',
  }) async {
    request.response.statusCode = status;
    if (body is List<int>) {
      request.response.add(body);
    } else {
      request.response.write(body);
    }
    await request.response.close();
  }

  group('what a 2xx body has to be', () {
    test('a JSON object is decoded', () async {
      await serve((request) => respond(request, body: '{"sha": "abc"}'));

      expect(await api.json(url()), {'sha': 'abc'});
    });

    test('valid JSON that is not an object is malformed', () async {
      await serve((request) => respond(request, body: '[1, 2, 3]'));

      await expectLater(
        api.json(url()),
        throwsA(
          isA<HubException>().having(
            (error) => error.kind,
            'kind',
            HubErrorKind.malformed,
          ),
        ),
      );
    });

    test('a body that is not JSON at all is malformed', () async {
      await serve((request) => respond(request, body: '<html>nope</html>'));

      await expectLater(
        api.json(url()),
        throwsA(
          isA<HubException>().having(
            (error) => error.kind,
            'kind',
            HubErrorKind.malformed,
          ),
        ),
      );
    });

    // The kind is a label the caller reads; the trace is what a maintainer
    // reads. A plain `throw` would replace the decoder's frames with this
    // file's own, which explain nothing (#130).
    test('a malformed body keeps the decoder in its stack', () async {
      await serve((request) => respond(request, body: '<html>nope</html>'));

      try {
        await api.json(url());
        fail('expected a HubException');
      } on HubException catch (_, stackTrace) {
        expect(
          stackTrace.toString().split('\n').first,
          isNot(contains('HttpClientHuggingFaceApi')),
          reason:
              'the trace begins where the failure did, not where it '
              'was labelled',
        );
      }
    });

    test('text comes back as sent', () async {
      await serve((request) => respond(request, body: 'chat template body'));

      expect(await api.text(url()), 'chat template body');
    });

    test('every request announces it wants JSON', () async {
      final accepted = <String?>[];
      await serve((request) {
        accepted.add(request.headers.value(HttpHeaders.acceptHeader));
        return respond(request, body: '{}');
      });

      await api.json(url());

      expect(accepted, ['application/json']);
    });
  });

  group('what a status means', () {
    Future<void> expectKind(int status, HubErrorKind kind) async {
      await serve((request) => respond(request, status: status, body: 'no'));

      await expectLater(
        api.json(url()),
        throwsA(
          isA<HubException>()
              .having((error) => error.kind, 'kind', kind)
              .having((error) => error.status, 'status', status),
        ),
      );
    }

    // 401 and 404 are the same answer from the Hub — a private repository and a
    // missing one are indistinguishable, and must not be reported as if they
    // were.
    test(
      '401 is not-found-or-private',
      () => expectKind(401, HubErrorKind.notFoundOrPrivate),
    );
    test(
      '403 is not-found-or-private',
      () => expectKind(403, HubErrorKind.notFoundOrPrivate),
    );
    test(
      '404 is not-found-or-private',
      () => expectKind(404, HubErrorKind.notFoundOrPrivate),
    );
    test(
      '429 is rate-limited',
      () => expectKind(429, HubErrorKind.rateLimited),
    );
    test(
      '503 is rate-limited',
      () => expectKind(503, HubErrorKind.rateLimited),
    );
    test(
      '500 is an unexpected status',
      () => expectKind(500, HubErrorKind.unexpectedStatus),
    );
  });

  group('what never becomes a download', () {
    test('a body past the caller ceiling is refused', () async {
      await serve((request) => respond(request, body: 'x' * 4096));

      await expectLater(
        api.text(url(), maxBytes: 8),
        throwsA(
          isA<HubException>().having(
            (error) => error.kind,
            'kind',
            HubErrorKind.tooLarge,
          ),
        ),
      );
    });

    test('a ranged read asks for exactly its span', () async {
      final ranges = <String?>[];
      await serve((request) {
        ranges.add(request.headers.value(HttpHeaders.rangeHeader));
        return respond(
          request,
          status: HttpStatus.partialContent,
          body: Uint8List.fromList(List.generate(16, (index) => index)),
        );
      });

      final bytes = await api.range(url(), start: 0, endInclusive: 15);

      expect(ranges, ['bytes=0-15']);
      expect(bytes, hasLength(16));
    });

    // The documented failure this exists to catch: a server that ignores Range
    // and starts streaming the whole 1.2 GB file.
    test('a server ignoring the range is too large, not a transfer', () async {
      await serve(
        (request) =>
            respond(request, body: Uint8List.fromList(List.filled(4096, 7))),
      );

      await expectLater(
        api.range(url(), start: 0, endInclusive: 15),
        throwsA(
          isA<HubException>().having(
            (error) => error.kind,
            'kind',
            HubErrorKind.tooLarge,
          ),
        ),
      );
    });
  });

  group('transport failures fold to one kind', () {
    // Dropped rather than refused: reaching a dead port means binding a server
    // and closing it, and the OS is free to hand that ephemeral port to
    // something else before the connect — a real flake for a test that would
    // then fail on an unrelated status. Destroying the socket under the client
    // is deterministic and lands in the same catch: no status, kind network.
    test(
      'a connection dropped before the reply is a network failure',
      () async {
        await serve((request) async {
          (await request.response.detachSocket(writeHeaders: false)).destroy();
        });

        await expectLater(
          api.json(url()),
          throwsA(
            isA<HubException>()
                .having((error) => error.kind, 'kind', HubErrorKind.network)
                .having((error) => error.status, 'status', isNull),
          ),
        );
      },
    );

    test('a server that never answers is a network failure', () async {
      await serve(
        (request) async {},
        timeout: const Duration(milliseconds: 200),
      );

      await expectLater(
        api.json(url()),
        throwsA(
          isA<HubException>().having(
            (error) => error.kind,
            'kind',
            HubErrorKind.network,
          ),
        ),
      );
    });

    test('a transport failure keeps its origin in the stack', () async {
      await serve(
        (request) async {},
        timeout: const Duration(milliseconds: 200),
      );

      try {
        await api.json(url());
        fail('expected a HubException');
      } on HubException catch (_, stackTrace) {
        expect(
          stackTrace.toString().split('\n').first,
          isNot(contains('HttpClientHuggingFaceApi')),
          reason:
              'the trace begins where the failure did, not where it '
              'was labelled',
        );
      }
    });

    test('an error body that stalls is still bounded', () async {
      // The status is known here and the body is drained only to free the
      // connection, so a server that answers 403 and then holds the socket
      // open must not hang the caller either.
      await serve((request) async {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.add(utf8.encode('{"error":'));
        await request.response.flush();
        await Completer<void>().future;
      }, timeout: const Duration(milliseconds: 200));

      await expectLater(
        api.json(url()),
        throwsA(
          isA<HubException>()
              .having(
                (error) => error.kind,
                'kind',
                HubErrorKind.notFoundOrPrivate,
              )
              .having((error) => error.status, 'status', HttpStatus.forbidden),
        ),
      );
    });

    test('a body that stalls mid-stream is a network failure', () async {
      // The gap #129 closed: connecting and reading the status line were
      // bounded, draining the body was not. A server that answered 200, sent a
      // chunk and then went quiet hung resolve() for as long as the socket
      // stayed open — a spinner with no way back.
      await serve((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.add(utf8.encode('{"partial":'));
        await request.response.flush();
        // Deliberately never closed.
        await Completer<void>().future;
      }, timeout: const Duration(milliseconds: 200));

      await expectLater(
        api.json(url()),
        throwsA(
          isA<HubException>().having(
            (error) => error.kind,
            'kind',
            HubErrorKind.network,
          ),
        ),
      );
    });
  });

  group('the URLs asked for', () {
    test('a ref keeps its slashes inside one path segment', () {
      final url = hubRevisionUrl('unsloth/Qwen3.5-2B-GGUF', 'refs/pr/3');

      expect(url.host, huggingFaceHost);
      expect(url.pathSegments, [
        'api',
        'models',
        'unsloth',
        'Qwen3.5-2B-GGUF',
        'revision',
        'refs/pr/3',
      ]);
      expect(url.toString(), endsWith('/revision/refs%2Fpr%2F3'));
    });

    test('blobs are requested by query, not by path', () {
      expect(hubRevisionUrl('a/b', 'main').query, isEmpty);
      expect(hubRevisionUrl('a/b', 'main', blobs: true).query, 'blobs=true');
    });

    test('a nested file path stays nested', () {
      final url = hubResolveUrl('a/b', 'deadbeef', 'sub/dir/model.gguf');

      expect(url.pathSegments, [
        'a',
        'b',
        'resolve',
        'deadbeef',
        'sub',
        'dir',
        'model.gguf',
      ]);
    });
  });
}
