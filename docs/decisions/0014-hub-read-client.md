# Reading Hugging Face: what the app trusts, and what bounds it

Status: decided on `refactor/129-feature-layering` (issue #129)

Advanced mode lets an owner name any Hugging Face repository and add it to the
catalog (#52). Everything about that is a trust decision — the app is about to
map a stranger's file list onto its own container and hand the bytes to a
native engine — and none of it was written down. The code implementing it was
also filed as if it were a platform adapter: a 642-line repository under
`core/services/`, its contract living inside the implementation, an
`HttpClient` nothing ever closed, and a body read with no deadline.

## Transport and repository are two different things

`core/services/hugging_face_api.dart` is the transport, and stays where
platform adapters live. It knows about sockets, status codes, redirects, byte
caps and deadlines, and nothing about models. Its whole vocabulary of failure
is six `HubErrorKind` values, because that is what a transport can honestly
distinguish.

`core/repositories/` holds the repository: the `CustomRepositoryResolver`
contract beside the other repository contracts, `HuggingFaceRepositoryResolver`
which implements it against the Hub, and `DeterministicRepositoryResolver`
which implements it without a network for the fake backend. Its results are
domain types in `core/domain/repository_resolution.dart`, so the contract does
not have to import an implementation to describe what it returns and the
localization layer does not have to import one to word it.

The split is what keeps every resolution rule testable without a socket:
`ScriptedHuggingFaceApi` answers the transport's three methods and the entire
trust policy below runs against it.

## The trust policy

It fails closed. Each rule exists because its absence has a concrete failure:

- **Nothing is inferred from a name.** Not the engine, not the architecture,
  not the quantization, not whether a file holds weights. Everything is read
  from the repository's own metadata, or the repository is rejected.
- **A resolution pins one commit.** The revision the user typed (default
  `main`) resolves to a 40-hex commit sha, and every later fetch names that
  sha. A branch that moves under a download would otherwise mix two models'
  files inside one directory.
- **Only allowlisted files are fetched.** MLX metadata comes from a fixed set
  of thirteen filenames; anything else a repository publishes is simply not
  asked for, so publishing a file cannot get it written into the container.
- **Unsafe weight containers are refused when nothing safe sits beside them.**
  `.bin`, `.ckpt`, `.pt`, `.pth`, `.pkl`, `.h5`, `.msgpack` all execute code or
  need a pickle reader at load time.
- **Sharded weights are refused,** because the installer verifies and
  activates one file.
- **The architecture must be one this app has actually loaded.** The
  allowlists per engine come from the artifacts the app ships, not from a model
  card. Widening either needs evidence.
- **The chat template must fingerprint to a broker profile,** or the entry
  resolves with no profile: it lists and it downloads, but it cannot activate,
  and `loadableModelKeys` withholds it so no label ever names it as runnable.
- **Every refusal is a named reason.** There is no catch-all "invalid
  repository", because that tells the user nothing to change.

And the division of labour that the rest of the pipeline depends on: **this
decides what may be fetched; `RealModelManagementRepository` decides whether
the bytes that arrived are what was promised**, by SHA-256 against the sizes
and digests this resolution recorded.

## Bounds

A read from a stranger's server is bounded in five places, four of which
already existed:

| Bound | Value | Why |
| --- | --- | --- |
| Connect and response-header deadline | 20 s | A server that never answers. |
| JSON body cap | 8 MiB | A revision listing is kilobytes; nothing legitimate approaches this. |
| Text body cap | 4 MiB | Chat templates and configs. |
| Range read | exactly the requested span | A server that ignores `Range` and starts sending a 4 GiB file is `tooLarge`, never a download. |
| **Body-read inactivity deadline** | **20 s** | **New.** |

The last one is the gap this ticket closes. Connecting was bounded and reading
the status line was bounded, but the loop draining the response body was not:
a server that accepted the connection, returned `200`, sent one chunk and then
stalled hung `resolve()` for as long as the socket stayed open — behind a
spinner, with the Add button gone and no way back. It is an *inactivity*
deadline rather than a total one, because a slow but live connection on a bad
network is not a failure. It folds into `HubErrorKind.network` with every other
transport failure, since "the request never completed" is the only distinction
a user can act on.

## The client is not closed on teardown

`HttpClientHuggingFaceApi.close()` existed and nothing called it. Two ways to
fix that; this is the one not taken.

Closing it on `detached` — beside the engine release, the only teardown signal
this app receives (#124) — is wrong, because Flutter permits `detached →
resumed` and the release path is written to be reversible for exactly that
reason. A `close(force: true)` is not reversible: the next resolution after a
returning `detached` would fail against a dead client, and it would fail as
`HubErrorKind.network`, which reads as "your connection" rather than "our bug".

So the client is a process-lifetime singleton, and what would have leaked is
bounded in code instead: `idleTimeout` is set explicitly, so idle keep-alive
sockets are reclaimed rather than held for the life of the process. `close()`
stays, because the loopback suite in `hugging_face_api_test.dart` builds and
tears down a client per test and must not leak one into the next.
