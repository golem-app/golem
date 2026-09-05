#ifndef GOLEM_INFERNO_H
#define GOLEM_INFERNO_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define INFERNO_EXPORT __declspec(dllexport)
#else
#define INFERNO_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// ABI 3: `inferno_engine_generate` additionally receives an ordered array of
/// encoded images. Image bytes are far too large to ride inside the request
/// JSON, so they cross as a separate borrowed buffer array.
///
/// The load payload gains an optional `"projectorPath"`: the multimodal
/// projector that pairs with this model, or null/absent for a text-only load.
///
/// ABI 2 (unchanged): `inferno_engine_load` receives one JSON payload instead
/// of a raw path — {"modelPath": string, "checkTensors": bool, "kvCacheType":
/// "f16"|"q8_0", "threadCount": int|null, "gpuLayers": int|null,
/// "swaFull": bool} — mirroring how generate crosses the boundary. Engines
/// ignore fields that do not apply to them. Error codes remain JSON
/// strings inside INFERNO_EVENT_ERROR payloads.
///
/// ABI 4: the generate request gains an optional `"presencePenalty"`
/// (double|null). Null or absent keeps every penalty out of the sampler
/// chain; a positive value applies an additive presence penalty whose
/// window covers the whole generation (window = maxTokens). A shim that
/// reports 4 must honor the field — dropping it silently reintroduces the
/// budget-length think loop the field exists to break (#80).
///
/// ABI 5: the METRICS payload carries a required `"timingSemanticsVersion"`
/// (int) and three of its numbers change meaning. `timeToFirstTokenSeconds`
/// runs from entry into `inferno_engine_generate` to the first output token —
/// worker dispatch, request parsing, tokenization, allocation and prompt
/// evaluation inside — and is null when no token was produced.
/// `elapsedSeconds` runs from that same entry to the end of the generation
/// loop. `decodeTokensPerSecond` is `generatedTokenCount / (elapsedSeconds -
/// timeToFirstTokenSeconds)`: that window holds one decode step per generated
/// token, the last being the step that ended the reply.
/// `promptTokensPerSecond` keeps its per-engine prompt-evaluation
/// window. The ABI moves with it because the field names do not: only the
/// version check keeps a shim measuring the old windows from feeding
/// corrected-looking numbers to a caller that believes them (#57).
#define INFERNO_ABI_VERSION 5

/// The timing contract the METRICS payload names. It moves with the ABI today
/// and exists separately because records outlive shims: a stored measurement
/// must still say which contract produced it. Absent means 1, the pre-#57
/// post-prefill window.
#define INFERNO_TIMING_SEMANTICS_VERSION 2

typedef struct inferno_engine inferno_engine;

/// One encoded image (the PNG/JPEG/WebP bytes as they sit on disk), decoded by
/// the engine rather than the caller.
///
/// The array and every buffer it points at are **borrowed for the duration of
/// the `inferno_engine_generate` call only**. Generation runs on a native
/// worker thread that outlives the call, so an implementation MUST copy the
/// bytes it needs before returning.
typedef struct inferno_image_input {
  const uint8_t *bytes;
  size_t length;
} inferno_image_input;

typedef enum inferno_event_kind {
  INFERNO_EVENT_TEXT_DELTA = 1,
  INFERNO_EVENT_METRICS = 2,
  INFERNO_EVENT_COMPLETED = 3,
  INFERNO_EVENT_ERROR = 4,
  INFERNO_EVENT_OPERATION_COMPLETED = 5,
  INFERNO_EVENT_TOKEN_IDS = 6
} inferno_event_kind;

/// Callbacks may originate on any native worker thread. Native code allocates
/// `bytes` for asynchronous delivery; the receiver must copy it and release it
/// with `inferno_string_free`. Text deltas may split a UTF-8 scalar across
/// callbacks, while all other payloads are complete UTF-8. Dart receives this
/// through a NativeCallable.listener; native code never enters an isolate
/// synchronously.
typedef void (*inferno_event_callback)(
    uint64_t operation_id,
    int32_t event_kind,
    const uint8_t *bytes,
    size_t length,
    void *user_data);

INFERNO_EXPORT uint32_t inferno_abi_version(void);
INFERNO_EXPORT const char *inferno_probe_json(void);
INFERNO_EXPORT inferno_engine *inferno_engine_create(const char *engine_name);
INFERNO_EXPORT int32_t inferno_engine_load(
    inferno_engine *engine,
    const char *model_path,
    uint64_t operation_id,
    inferno_event_callback callback,
    void *user_data);
/// `images` may be NULL when `image_count` is 0. Both are borrowed; see
/// `inferno_image_input`. The rendered prompt must contain one media marker
/// per image, in the same order.
INFERNO_EXPORT int32_t inferno_engine_generate(
    inferno_engine *engine,
    const char *request_json,
    const inferno_image_input *images,
    size_t image_count,
    uint64_t operation_id,
    inferno_event_callback callback,
    void *user_data);
/// Test/tooling-only raw tokenization. Production consumers use generation.
INFERNO_EXPORT int32_t inferno_engine_tokenize(
    inferno_engine *engine,
    const char *rendered_prompt,
    uint64_t operation_id,
    inferno_event_callback callback,
    void *user_data);
INFERNO_EXPORT int32_t inferno_engine_cancel(inferno_engine *engine);
INFERNO_EXPORT int32_t inferno_engine_unload(
    inferno_engine *engine,
    uint64_t operation_id,
    inferno_event_callback callback,
    void *user_data);
INFERNO_EXPORT void inferno_engine_destroy(inferno_engine *engine);
INFERNO_EXPORT void inferno_string_free(const char *value);

#ifdef __cplusplus
}
#endif

#endif
