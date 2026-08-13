# ADR 0012: Platform engines and required-model startup

Status: decided on `fix/110-usable-model-startup-mlx-ios` (issue #110)

## Context

The original v0 policy selected llama.cpp/GGUF on both mobile platforms and
allowed first run to be declined. Reconciliation later began materializing
`notDownloaded` entries for the complete catalog; the first-run classifier
mistook that nonempty map for prior model activity. A clean install could
therefore enter chat, name the configured Gemma artifact as loaded, and fail
the first message because no weights existed.

Subsequent physical-iPhone evidence also changed the engine decision. The
shipping MLX artifacts now pass the app's text, image, switching, persistence,
and failure-path acceptance, while decoding materially faster on the iPhone 17.

## Decision

- `auto` is platform-owned: iOS composes MLX, Android composes llama.cpp/GGUF,
  and macOS retains llama.cpp. Explicit engine, artifact, profile, and path
  overrides continue to win.
- Launch resolves the exact engine before capability probing. Admission,
  catalog composition, recommendation, activation, and inference all consume
  that one answer.
- The consumer shell is unavailable until the composed engine has a compatible
  receipt-verified artifact. This is an app-root, continuously observed
  invariant, not a composer or route check.
- Welcome eligibility is separate from admission. Only zero-byte
  `notDownloaded` entries are pristine; chats, partial transfers, failures, and
  old artifacts are prior activity and resume directly in required setup.
- Consent remains explicit, but declining, pausing, failing, closing, deleting,
  or invalidating the last compatible model cannot bypass setup.
- An operator `GOLEM_MODEL_PATH` counts only after Inferno successfully loads
  it in the current process. A nullable catalog key is not residency, so the
  inference contract separately publishes whether weights are loaded and the
  optional catalog key they represent.
- Installed artifacts for another engine remain visible and deletable. They do
  not satisfy startup and are never silently converted or deleted.
- Unsupported hardware receives a terminal explanation from the all-routes
  shell inside the mounted router. It is not offered a download or a non-model
  shell.

## Consequences

The router, Settings, starter prompts, composer, and their semantics do not
exist while startup is blocked. Deleting the last compatible artifact restores
the gate immediately without changing chats, preferences, or model files.
Catalog artifacts remain lazy-loaded after verification; strict eager loading
is limited to unreceipted operator paths. Download reconciliation remains the
single transfer owner and adopts background work rather than starting a second
writer.

This decision supersedes ADR 0002's mobile single-engine conclusion, ADR
0003's two-platform `auto` mapping and first-need download behavior, and ADR
0007's unsupported-device access to the non-model shell.
