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

#define INFERNO_ABI_VERSION 1

typedef struct inferno_engine inferno_engine;

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
INFERNO_EXPORT int32_t inferno_engine_generate(
    inferno_engine *engine,
    const char *request_json,
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
