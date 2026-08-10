#include "inferno.h"

#include "ggml-backend.h"
#include "llama.h"
#include "mtmd-helper.h"
#include "mtmd.h"
#include "nlohmann/json.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

#if defined(__APPLE__)
#include <mach/mach.h>
#endif

#if defined(__linux__) && defined(__aarch64__)
#include <sys/auxv.h>
#ifndef HWCAP_ASIMDDP
#define HWCAP_ASIMDDP (1 << 20)
#endif
#endif

using json = nlohmann::json;
using steady_clock = std::chrono::steady_clock;

struct inferno_engine {
  std::mutex mutex;
  std::condition_variable idle;
  std::thread worker;
  std::atomic<bool> cancel_requested{false};
  std::atomic<bool> busy{false};
  llama_model *model = nullptr;
  // The multimodal projector, when this model was loaded with one (ABI 3).
  // Owned here and freed before the model it was initialized against.
  mtmd_context *mtmd = nullptr;
  // Load options that apply per generation context (ABI 2). Written once
  // by the load worker before `model` becomes non-null, read by generate.
  ggml_type kv_cache_type = GGML_TYPE_F16;
  int32_t thread_count = 0;  // 0 = engine default
  bool swa_full = false;
};

namespace {

std::once_flag backend_once;

// The last ERROR line llama.cpp logged, kept so a failure event can carry
// the native diagnostic instead of losing it to stderr. Guarded because
// log callbacks and workers run on arbitrary threads.
std::mutex log_error_mutex;
std::string last_log_error;

std::string consume_log_error() {
  std::lock_guard<std::mutex> lock(log_error_mutex);
  std::string taken = last_log_error;
  last_log_error.clear();
  return taken;
}

// Appends the buffered native diagnostic to a failure message; the result
// is diagnostic evidence for logs, never user-facing copy.
std::string with_log_detail(const std::string &message) {
  const std::string detail = consume_log_error();
  if (detail.empty()) return message;
  return message + " [" + detail + "]";
}

// ggml selects its ARM kernels at compile time, so the Android arm64 build
// bakes in the extensions its `-march` names (docs/device_floor.md): a
// device without them would not run slower, it would take SIGILL inside the
// first matmul. Refuse the load instead, while the failure can still be
// reported. Other targets build at their toolchain baseline and pass.
bool cpu_meets_floor() {
#if defined(__linux__) && defined(__aarch64__)
  return (getauxval(AT_HWCAP) & HWCAP_ASIMDDP) != 0;
#else
  return true;
#endif
}

void initialize_backend() {
  std::call_once(backend_once, [] {
    llama_log_set(
        [](enum ggml_log_level level, const char *text, void *) {
          if (level == GGML_LOG_LEVEL_ERROR && text != nullptr) {
            {
              std::lock_guard<std::mutex> lock(log_error_mutex);
              std::string line(text);
              while (!line.empty() &&
                     (line.back() == '\n' || line.back() == '\r')) {
                line.pop_back();
              }
              if (!line.empty()) last_log_error = line;
            }
            std::fputs(text, stderr);
          }
        },
        nullptr);
    llama_backend_init();
    ggml_backend_load_all();
  });
}

void emit(inferno_event_callback callback,
          uint64_t operation_id,
          inferno_event_kind kind,
          const std::string &payload,
          void *user_data) {
  if (callback == nullptr) return;
  uint8_t *copy = nullptr;
  if (!payload.empty()) {
    copy = static_cast<uint8_t *>(std::malloc(payload.size()));
    if (copy == nullptr) {
      // Allocation failed at the worst moment — memory exhaustion. A
      // dropped terminal event would hang the Dart completer forever, so
      // deliver the event with an empty payload instead; the Dart side
      // maps a payloadless error to its out-of-memory code.
      callback(operation_id, static_cast<int32_t>(kind), nullptr, 0,
               user_data);
      return;
    }
    std::memcpy(copy, payload.data(), payload.size());
  }
  callback(operation_id,
           static_cast<int32_t>(kind),
           copy,
           payload.size(),
           user_data);
}

void emit_error(inferno_event_callback callback,
                uint64_t operation_id,
                const char *code,
                const std::string &message,
                void *user_data) {
  emit(callback,
       operation_id,
       INFERNO_EVENT_ERROR,
       json{{"code", code}, {"message", message}}.dump(),
       user_data);
}

bool read_gguf_header(const std::string &path,
                      std::string &error_code,
                      std::string &error_message) {
  std::ifstream input(path, std::ios::binary | std::ios::ate);
  if (!input) {
    error_code = "invalid_model_path";
    error_message = "The GGUF model file cannot be opened.";
    return false;
  }
  const auto length = input.tellg();
  if (length < 32) {
    error_code = "corrupt_model";
    error_message = "The GGUF model is truncated.";
    return false;
  }
  input.seekg(0);
  uint8_t header[8]{};
  input.read(reinterpret_cast<char *>(header), sizeof(header));
  if (input.gcount() != static_cast<std::streamsize>(sizeof(header)) ||
      std::memcmp(header, "GGUF", 4) != 0) {
    error_code = "corrupt_model";
    error_message = "The model does not have a valid GGUF header.";
    return false;
  }
  const uint32_t version = static_cast<uint32_t>(header[4]) |
                           (static_cast<uint32_t>(header[5]) << 8U) |
                           (static_cast<uint32_t>(header[6]) << 16U) |
                           (static_cast<uint32_t>(header[7]) << 24U);
  if (version < 2 || version > 3) {
    error_code = "incompatible_model";
    error_message = "The GGUF version is not supported by this runtime.";
    return false;
  }
  return true;
}

template <typename Work>
int32_t start_worker(inferno_engine *engine, Work work) {
  if (engine == nullptr) return -1;
  std::unique_lock<std::mutex> guard(engine->mutex);
  // Terminal events are emitted before the worker finishes unwinding, so a
  // caller reacting to one can arrive while busy is still set. Give the
  // outgoing worker a moment to clear instead of rejecting the follow-on
  // call; only a genuinely concurrent operation still fails.
  engine->idle.wait_for(guard, std::chrono::seconds(2), [engine] {
    return !engine->busy.load();
  });
  if (engine->busy.exchange(true)) return -1;
  if (engine->worker.joinable()) engine->worker.join();
  engine->cancel_requested.store(false);
  try {
    engine->worker = std::thread([engine, work = std::move(work)]() mutable {
      try {
        work();
      } catch (const std::exception &error) {
        // Each operation emits its own typed failure. Reaching this catch
        // means the operation violated that boundary, so only clear state.
        (void)error;
      } catch (...) {
      }
      {
        // Clearing busy under the mutex keeps the store from slipping
        // between a waiter's predicate check and its condvar enqueue —
        // a lost wakeup there costs the waiter the full timeout.
        std::lock_guard<std::mutex> guard(engine->mutex);
        engine->busy.store(false);
      }
      engine->idle.notify_all();
    });
  } catch (...) {
    engine->busy.store(false);
    return -2;
  }
  return 0;
}

std::vector<llama_token> tokenize(const llama_vocab *vocab,
                                  const std::string &text) {
  const int32_t required = llama_tokenize(
      vocab, text.data(), static_cast<int32_t>(text.size()), nullptr, 0, false, true);
  if (required >= 0) return {};
  std::vector<llama_token> tokens(static_cast<size_t>(-required));
  const int32_t count = llama_tokenize(vocab,
                                       text.data(),
                                       static_cast<int32_t>(text.size()),
                                       tokens.data(),
                                       static_cast<int32_t>(tokens.size()),
                                       false,
                                       true);
  if (count < 0) return {};
  tokens.resize(static_cast<size_t>(count));
  return tokens;
}

std::string token_piece(const llama_vocab *vocab, llama_token token) {
  const int32_t required = llama_token_to_piece(vocab, token, nullptr, 0, 0, true);
  if (required >= 0) return {};
  std::string piece(static_cast<size_t>(-required), '\0');
  const int32_t written = llama_token_to_piece(
      vocab, token, piece.data(), static_cast<int32_t>(piece.size()), 0, true);
  if (written < 0) return {};
  piece.resize(static_cast<size_t>(written));
  return piece;
}

size_t held_stop_prefix(const std::string &pending,
                        const std::vector<std::string> &stops) {
  size_t held = 0;
  for (const auto &stop : stops) {
    if (stop.empty()) continue;
    const size_t maximum = std::min(pending.size(), stop.size() - 1);
    for (size_t length = maximum; length > held; --length) {
      if (pending.compare(pending.size() - length, length, stop, 0, length) == 0) {
        held = length;
        break;
      }
    }
  }
  return held;
}

bool emit_visible_piece(std::string &pending,
                        const std::string &piece,
                        const std::vector<std::string> &stops,
                        inferno_event_callback callback,
                        uint64_t operation_id,
                        void *user_data) {
  pending += piece;
  size_t earliest = std::string::npos;
  for (const auto &stop : stops) {
    if (stop.empty()) continue;
    earliest = std::min(earliest, pending.find(stop));
  }
  if (earliest != std::string::npos) {
    if (earliest > 0) {
      emit(callback,
           operation_id,
           INFERNO_EVENT_TEXT_DELTA,
           pending.substr(0, earliest),
           user_data);
    }
    pending.clear();
    return true;
  }
  const size_t held = held_stop_prefix(pending, stops);
  const size_t emit_count = pending.size() - held;
  if (emit_count > 0) {
    emit(callback,
         operation_id,
         INFERNO_EVENT_TEXT_DELTA,
         pending.substr(0, emit_count),
         user_data);
    pending.erase(0, emit_count);
  }
  return false;
}

double seconds_between(steady_clock::time_point start,
                       steady_clock::time_point end) {
  return std::chrono::duration<double>(end - start).count();
}

// Owning handles for the multimodal inputs, so every early return on the
// error paths below releases them exactly once.
struct MtmdBitmapDeleter {
  void operator()(mtmd_bitmap *bitmap) const { mtmd_bitmap_free(bitmap); }
};
using MtmdBitmap = std::unique_ptr<mtmd_bitmap, MtmdBitmapDeleter>;

struct MtmdChunksDeleter {
  void operator()(mtmd_input_chunks *chunks) const {
    mtmd_input_chunks_free(chunks);
  }
};
using MtmdChunks = std::unique_ptr<mtmd_input_chunks, MtmdChunksDeleter>;

uint64_t physical_footprint_bytes() {
#if defined(__APPLE__)
  task_vm_info_data_t info{};
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  const kern_return_t result = task_info(
      mach_task_self(),
      TASK_VM_INFO,
      reinterpret_cast<task_info_t>(&info),
      &count);
  return result == KERN_SUCCESS ? info.phys_footprint : 0;
#else
  return 0;
#endif
}

}  // namespace

extern "C" {

uint32_t inferno_abi_version(void) { return INFERNO_ABI_VERSION; }

const char *inferno_probe_json(void) {
  const std::string payload = json{
#if defined(__ANDROID__)
      {"operatingSystem", "android"},
#elif defined(__linux__)
      {"operatingSystem", "linux"},
#elif defined(__APPLE__)
      {"operatingSystem", "apple"},
#else
      {"operatingSystem", "unknown"},
#endif
      {"engines",
       json::array({{{"name", "llama_cpp"},
                     {"available", true},
                     {"detail", "llama.cpp b10241"}}})}}
                                  .dump();
  auto *copy = static_cast<char *>(std::malloc(payload.size() + 1));
  if (copy == nullptr) return nullptr;
  std::memcpy(copy, payload.c_str(), payload.size() + 1);
  return copy;
}

inferno_engine *inferno_engine_create(const char *engine_name) {
  if (engine_name == nullptr || std::strcmp(engine_name, "llama_cpp") != 0) {
    return nullptr;
  }
  initialize_backend();
  try {
    return new inferno_engine();
  } catch (...) {
    return nullptr;
  }
}

int32_t inferno_engine_load(inferno_engine *engine,
                            const char *load_json,
                            uint64_t operation_id,
                            inferno_event_callback callback,
                            void *user_data) {
  if (engine == nullptr || load_json == nullptr || engine->model != nullptr) return -1;
  const std::string encoded(load_json);
  return start_worker(engine, [=] {
    if (!cpu_meets_floor()) {
      emit_error(callback,
                 operation_id,
                 "unsupported_device",
                 "This device's processor lacks the ARM dot-product "
                 "extension the local engine requires.",
                 user_data);
      return;
    }
    std::string path;
    std::string projector_path;
    bool check_tensors = false;
    int32_t gpu_layers_override = INT32_MIN;
    try {
      const json request = json::parse(encoded);
      path = request.at("modelPath").get<std::string>();
      if (request.contains("projectorPath") &&
          !request["projectorPath"].is_null()) {
        projector_path = request["projectorPath"].get<std::string>();
      }
      check_tensors = request.value("checkTensors", false);
      const std::string kv = request.value("kvCacheType", "f16");
      engine->kv_cache_type = kv == "q8_0" ? GGML_TYPE_Q8_0 : GGML_TYPE_F16;
      if (request.contains("threadCount") && !request["threadCount"].is_null()) {
        engine->thread_count = request["threadCount"].get<int32_t>();
      }
      if (request.contains("gpuLayers") && !request["gpuLayers"].is_null()) {
        gpu_layers_override = request["gpuLayers"].get<int32_t>();
      }
      engine->swa_full = request.value("swaFull", false);
    } catch (const std::exception &error) {
      emit_error(callback,
                 operation_id,
                 "load_failed",
                 std::string("The load request is invalid: ") + error.what(),
                 user_data);
      return;
    }
    std::string code;
    std::string message;
    if (!read_gguf_header(path, code, message)) {
      emit_error(callback, operation_id, code.c_str(), message, user_data);
      return;
    }
    llama_model_params params = llama_model_default_params();
#if defined(INFERNO_USE_METAL)
    params.n_gpu_layers = -1;
#else
    params.n_gpu_layers = 0;
#endif
    if (gpu_layers_override != INT32_MIN) {
      // The #13 escape hatch: 0 forces CPU-only on Metal builds.
      params.n_gpu_layers = gpu_layers_override;
    }
    // Upstream default (false). True validates every tensor — a full
    // page-in of the mmapped weights — kept as an opt-in triage tool.
    params.check_tensors = check_tensors;
    params.progress_callback = [](float, void *context) {
      return !static_cast<inferno_engine *>(context)->cancel_requested.load();
    };
    params.progress_callback_user_data = engine;
    consume_log_error();
    llama_model *loaded = nullptr;
    try {
      loaded = llama_model_load_from_file(path.c_str(), params);
    } catch (const std::exception &error) {
      emit_error(callback,
                 operation_id,
                 "load_failed",
                 with_log_detail(error.what()),
                 user_data);
      return;
    } catch (...) {
      emit_error(callback,
                 operation_id,
                 "load_failed",
                 with_log_detail("llama.cpp rejected the model."),
                 user_data);
      return;
    }
    if (engine->cancel_requested.load()) {
      if (loaded != nullptr) llama_model_free(loaded);
      emit_error(callback, operation_id, "cancelled", "Model loading was cancelled.", user_data);
      return;
    }
    if (loaded == nullptr) {
      // llama.cpp's own log line distinguishes an allocation failure from
      // a genuinely broken file; carry it so "damaged" is never claimed
      // blind.
      emit_error(callback,
                 operation_id,
                 "incompatible_model",
                 with_log_detail("llama.cpp could not load this GGUF model."),
                 user_data);
      return;
    }
    if (!projector_path.empty()) {
      // Ask the projector what it can do before spending anything on it: a
      // file that carries no vision tower can never make this model
      // image-capable, and saying so here beats failing at the first image.
      const mtmd_caps caps = mtmd_get_cap_from_file(projector_path.c_str());
      if (!caps.inp_vision) {
        llama_model_free(loaded);
        emit_error(callback,
                   operation_id,
                   "incompatible_model",
                   with_log_detail(
                       "The image projector does not provide a vision encoder."),
                   user_data);
        return;
      }
      mtmd_context_params projector_params = mtmd_context_params_default();
      projector_params.print_timings = false;
      projector_params.n_threads =
          engine->thread_count > 0 ? engine->thread_count : 4;
#if defined(INFERNO_USE_METAL)
      projector_params.use_gpu = true;
#else
      projector_params.use_gpu = false;
#endif
      consume_log_error();
      mtmd_context *projector = nullptr;
      try {
        projector =
            mtmd_init_from_file(projector_path.c_str(), loaded, projector_params);
      } catch (...) {
        projector = nullptr;
      }
      if (projector == nullptr) {
        // The usual cause is a projector built for a different model: its
        // output dimension has to match this model's embedding width, and
        // mtmd refuses the pairing rather than producing noise.
        llama_model_free(loaded);
        emit_error(callback,
                   operation_id,
                   "incompatible_model",
                   with_log_detail(
                       "The image projector does not match this model."),
                   user_data);
        return;
      }
      engine->mtmd = projector;
    }
    engine->model = loaded;
    emit(callback, operation_id, INFERNO_EVENT_OPERATION_COMPLETED, "", user_data);
  });
}

int32_t inferno_engine_generate(inferno_engine *engine,
                                const char *request_json,
                                const inferno_image_input *images,
                                size_t image_count,
                                uint64_t operation_id,
                                inferno_event_callback callback,
                                void *user_data) {
  if (engine == nullptr || engine->model == nullptr || request_json == nullptr) return -1;
  if (image_count > 0 && images == nullptr) return -1;
  const std::string encoded(request_json);
  // The caller lends these buffers for this call only, and generation runs on
  // a worker that outlives it — so the bytes are copied here, before the
  // worker starts, not read from the caller's memory later.
  std::vector<std::vector<uint8_t>> image_bytes;
  image_bytes.reserve(image_count);
  for (size_t index = 0; index < image_count; ++index) {
    const inferno_image_input &image = images[index];
    if (image.bytes == nullptr || image.length == 0) return -1;
    image_bytes.emplace_back(image.bytes, image.bytes + image.length);
  }
  return start_worker(engine, [=, image_bytes = std::move(image_bytes)] {
    json request;
    try {
      request = json::parse(encoded);
    } catch (const std::exception &error) {
      emit_error(callback, operation_id, "generation_failed", error.what(), user_data);
      return;
    }
    const std::string prompt = request.value("prompt", "");
    const int32_t max_tokens = request.value("maxTokens", 0);
    const float temperature = request.value("temperature", 1.0F);
    const float top_p = request.value("topP", 0.95F);
    // topK and contextLength are absent-or-null when unset: 0 disables the
    // top-k sampler / falls back to the model's trained context window.
    const int32_t top_k =
        (!request.contains("topK") || request["topK"].is_null())
            ? 0
            : request["topK"].get<int32_t>();
    const int64_t context_length =
        (!request.contains("contextLength") || request["contextLength"].is_null())
            ? 0
            : request["contextLength"].get<int64_t>();
    const uint32_t seed = request["seed"].is_null()
                              ? LLAMA_DEFAULT_SEED
                              : request.value("seed", LLAMA_DEFAULT_SEED);
    const auto stop_sequences = request.value("stopSequences", std::vector<std::string>{});
    const auto stop_ids_vector = request.value("stopTokenIds", std::vector<llama_token>{});
    const std::unordered_set<llama_token> stop_ids(stop_ids_vector.begin(),
                                                   stop_ids_vector.end());
    if (prompt.empty() || max_tokens <= 0 || temperature < 0 || top_p <= 0 || top_p > 1 ||
        top_k < 0 || context_length < 0) {
      emit_error(callback,
                 operation_id,
                 "generation_failed",
                 "The generation request is invalid.",
                 user_data);
      return;
    }

    const bool has_images = !image_bytes.empty();
    if (has_images && engine->mtmd == nullptr) {
      emit_error(callback,
                 operation_id,
                 "generation_failed",
                 "This model was not loaded with an image projector.",
                 user_data);
      return;
    }

    const llama_vocab *vocab = llama_model_get_vocab(engine->model);

    // Text-only prompts keep the original path byte for byte; the recorded
    // cross-engine token fixtures assert against exactly this tokenization.
    std::vector<llama_token> prompt_tokens;
    // Owned by this operation whenever images are present.
    MtmdChunks chunks;
    std::vector<MtmdBitmap> bitmaps;
    size_t prompt_token_count = 0;

    if (has_images) {
      bitmaps.reserve(image_bytes.size());
      for (const auto &encoded_image : image_bytes) {
        const mtmd_helper_bitmap_wrapper wrapper =
            mtmd_helper_bitmap_init_from_buf(engine->mtmd,
                                             encoded_image.data(),
                                             encoded_image.size(),
                                             false);
        if (wrapper.video_ctx != nullptr) {
          mtmd_helper_video_free(wrapper.video_ctx);
        }
        if (wrapper.bitmap == nullptr) {
          emit_error(callback,
                     operation_id,
                     "generation_failed",
                     "An attached image could not be decoded.",
                     user_data);
          return;
        }
        bitmaps.emplace_back(wrapper.bitmap);
      }
      std::vector<const mtmd_bitmap *> bitmap_pointers;
      bitmap_pointers.reserve(bitmaps.size());
      for (const auto &bitmap : bitmaps) bitmap_pointers.push_back(bitmap.get());

      chunks.reset(mtmd_input_chunks_init());
      if (chunks.get() == nullptr) {
        emit_error(callback, operation_id, "out_of_memory", "", user_data);
        return;
      }
      mtmd_input_text text{};
      text.text = prompt.c_str();
      text.text_len = prompt.size();
      // The broker renders the whole prompt, media markers included, and both
      // engines tokenize with automatic BOS insertion disabled.
      text.add_special = false;
      text.parse_special = true;
      const int32_t tokenized = mtmd_tokenize(engine->mtmd,
                                              chunks.get(),
                                              &text,
                                              bitmap_pointers.data(),
                                              bitmap_pointers.size());
      if (tokenized != 0) {
        emit_error(
            callback,
            operation_id,
            "generation_failed",
            tokenized == 1
                ? "The prompt does not carry one image marker per image."
                : "An attached image could not be prepared for this model.",
            user_data);
        return;
      }
      prompt_token_count = mtmd_helper_get_n_tokens(chunks.get());
      if (prompt_token_count == 0) {
        emit_error(callback,
                   operation_id,
                   "generation_failed",
                   "The rendered prompt could not be tokenized.",
                   user_data);
        return;
      }
    } else {
      prompt_tokens = tokenize(vocab, prompt);
      if (prompt_tokens.empty()) {
        emit_error(callback,
                   operation_id,
                   "generation_failed",
                   "The rendered prompt could not be tokenized.",
                   user_data);
        return;
      }
      const llama_token bos = llama_vocab_bos(vocab);
      if (prompt_tokens.size() > 1 && prompt_tokens[0] == bos && prompt_tokens[1] == bos) {
        emit_error(callback,
                   operation_id,
                   "generation_failed",
                   "The rendered prompt contains a duplicated BOS token.",
                   user_data);
        return;
      }
      prompt_token_count = prompt_tokens.size();
    }
    const int32_t model_context = llama_model_n_ctx_train(engine->model);
    // The caller's context budget can only tighten the trained window, never
    // widen it; the same budget check runs in the MLX shim so a too-small
    // budget fails identically on both engines.
    const int64_t context_budget =
        context_length > 0 ? std::min<int64_t>(context_length, model_context)
                           : model_context;
    const int64_t requested_context =
        static_cast<int64_t>(prompt_token_count) + max_tokens;
    if (requested_context > context_budget) {
      emit_error(callback,
                 operation_id,
                 "context_exhausted",
                 "The rendered prompt and max tokens exceed the context budget.",
                 user_data);
      return;
    }

    llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = static_cast<uint32_t>(std::max<int64_t>(requested_context, 64));
    context_params.n_batch = static_cast<uint32_t>(
        std::max<size_t>(1, std::min<size_t>(prompt_token_count, 512)));
    context_params.n_ubatch = context_params.n_batch;
    context_params.no_perf = false;
    // Load-time knobs stored on the engine (ABI 2). A quantized value
    // cache requires flash attention; AUTO may fall back to CPU-off
    // paths, so force it on when q8_0 is requested.
    context_params.type_k = engine->kv_cache_type;
    context_params.type_v = engine->kv_cache_type;
    if (engine->kv_cache_type != GGML_TYPE_F16) {
      context_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
    }
    if (engine->thread_count > 0) {
      context_params.n_threads = engine->thread_count;
      context_params.n_threads_batch = engine->thread_count;
    }
    // Off by default (upstream tooling default): a full-size SWA cache
    // buys only rollback ability these per-generate contexts never use,
    // at real KV cost on SWA models like Gemma.
    context_params.swa_full = engine->swa_full;
    context_params.abort_callback = [](void *context) {
      return static_cast<inferno_engine *>(context)->cancel_requested.load();
    };
    context_params.abort_callback_data = engine;
    llama_context *context = llama_init_from_model(engine->model, context_params);
    if (context == nullptr) {
      // The KV cache and compute buffers are the allocation here; a null
      // return on a valid model is memory exhaustion, not a model defect.
      emit_error(callback,
                 operation_id,
                 "out_of_memory",
                 with_log_detail(
                     "llama.cpp could not allocate a generation context."),
                 user_data);
      return;
    }

    llama_sampler *sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (top_k > 0) {
      llama_sampler_chain_add(sampler, llama_sampler_init_top_k(top_k));
    }
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));

    const auto operation_start = steady_clock::now();
    bool decode_failed = false;
    if (has_images) {
      // mtmd interleaves the prompt's text runs with encoded image
      // embeddings and decodes them in order, leaving logits on the last
      // token exactly as the text prefill below does.
      llama_pos evaluated = 0;
      const int32_t status =
          mtmd_helper_eval_chunks(engine->mtmd,
                                  context,
                                  chunks.get(),
                                  /*n_past=*/0,
                                  /*seq_id=*/0,
                                  static_cast<int32_t>(context_params.n_batch),
                                  /*logits_last=*/true,
                                  &evaluated);
      decode_failed = status != 0 && !engine->cancel_requested.load();
    } else {
      for (size_t offset = 0; offset < prompt_tokens.size();) {
        if (engine->cancel_requested.load()) break;
        const size_t count = std::min<size_t>(context_params.n_batch,
                                              prompt_tokens.size() - offset);
        llama_batch batch = llama_batch_get_one(
            const_cast<llama_token *>(prompt_tokens.data() + offset),
            static_cast<int32_t>(count));
        // llama_decode returns 2 when the abort callback fired — that is the
        // caller's own cancellation tripping mid-decode, not a failure.
        if (const int32_t status = llama_decode(context, batch); status != 0) {
          decode_failed = status != 2;
          break;
        }
        offset += count;
      }
    }
    const auto prompt_end = steady_clock::now();

    std::string pending;
    std::string stop_reason = "max_tokens";
    int32_t generated = 0;
    uint64_t peak_footprint = physical_footprint_bytes();
    steady_clock::time_point first_token{};
    if (!decode_failed && !engine->cancel_requested.load()) {
      while (generated < max_tokens) {
        if (engine->cancel_requested.load()) {
          stop_reason = "cancelled";
          break;
        }
        const llama_token token = llama_sampler_sample(sampler, context, -1);
        if (llama_vocab_is_eog(vocab, token)) {
          stop_reason = "end_of_sequence";
          break;
        }
        if (stop_ids.find(token) != stop_ids.end()) {
          stop_reason = "stop_token";
          break;
        }
        generated++;
        peak_footprint = std::max(peak_footprint, physical_footprint_bytes());
        const std::string piece = token_piece(vocab, token);
        if (first_token == steady_clock::time_point{}) first_token = steady_clock::now();
        if (emit_visible_piece(
                pending, piece, stop_sequences, callback, operation_id, user_data)) {
          stop_reason = "stop_sequence";
          break;
        }
        llama_batch next = llama_batch_get_one(const_cast<llama_token *>(&token), 1);
        if (const int32_t status = llama_decode(context, next); status != 0) {
          decode_failed = status != 2;
          break;
        }
      }
    }
    const auto generation_end = steady_clock::now();
    if (!pending.empty() && stop_reason != "stop_sequence") {
      emit(callback, operation_id, INFERNO_EVENT_TEXT_DELTA, pending, user_data);
    }

    if (engine->cancel_requested.load()) stop_reason = "cancelled";
    if (decode_failed) {
      emit_error(callback,
                 operation_id,
                 "generation_failed",
                 "llama.cpp failed while evaluating tokens.",
                 user_data);
    } else {
      const double prompt_seconds = seconds_between(operation_start, prompt_end);
      const double decode_seconds = seconds_between(prompt_end, generation_end);
      const double elapsed_seconds = seconds_between(operation_start, generation_end);
      const json metrics{
          {"decodeTokensPerSecond", decode_seconds > 0 ? generated / decode_seconds : 0},
          {"promptTokensPerSecond",
           prompt_seconds > 0 ? prompt_token_count / prompt_seconds : 0},
          {"generatedTokenCount", generated},
          {"elapsedSeconds", elapsed_seconds},
          {"promptTokenCount", prompt_token_count},
          {"timeToFirstTokenSeconds",
           first_token == steady_clock::time_point{}
               ? json(nullptr)
               : json(seconds_between(prompt_end, first_token))},
          {"peakPhysicalFootprintBytes",
           peak_footprint > 0 ? json(peak_footprint) : json(nullptr)}};
      emit(callback, operation_id, INFERNO_EVENT_METRICS, metrics.dump(), user_data);
      emit(callback, operation_id, INFERNO_EVENT_COMPLETED, stop_reason, user_data);
      emit(callback, operation_id, INFERNO_EVENT_OPERATION_COMPLETED, "", user_data);
    }

    llama_sampler_free(sampler);
    llama_free(context);
  });
}

int32_t inferno_engine_tokenize(inferno_engine *engine,
                                const char *rendered_prompt,
                                uint64_t operation_id,
                                inferno_event_callback callback,
                                void *user_data) {
  if (engine == nullptr || engine->model == nullptr || rendered_prompt == nullptr) {
    return -1;
  }
  const std::string prompt(rendered_prompt);
  return start_worker(engine, [=] {
    const llama_vocab *vocab = llama_model_get_vocab(engine->model);
    const auto tokens = tokenize(vocab, prompt);
    if (tokens.empty()) {
      emit_error(callback,
                 operation_id,
                 "generation_failed",
                 "The rendered prompt could not be tokenized.",
                 user_data);
      return;
    }
    emit(callback,
         operation_id,
         INFERNO_EVENT_TOKEN_IDS,
         json(tokens).dump(),
         user_data);
    emit(callback,
         operation_id,
         INFERNO_EVENT_OPERATION_COMPLETED,
         "",
         user_data);
  });
}

int32_t inferno_engine_cancel(inferno_engine *engine) {
  if (engine == nullptr) return -1;
  engine->cancel_requested.store(true);
  return 0;
}

int32_t inferno_engine_unload(inferno_engine *engine,
                              uint64_t operation_id,
                              inferno_event_callback callback,
                              void *user_data) {
  if (engine == nullptr) return -1;
  return start_worker(engine, [=] {
    // The projector holds references into the model it was initialized
    // against, so it goes first.
    if (engine->mtmd != nullptr) {
      mtmd_free(engine->mtmd);
      engine->mtmd = nullptr;
    }
    if (engine->model != nullptr) {
      llama_model_free(engine->model);
      engine->model = nullptr;
    }
    emit(callback, operation_id, INFERNO_EVENT_OPERATION_COMPLETED, "", user_data);
  });
}

void inferno_engine_destroy(inferno_engine *engine) {
  if (engine == nullptr) return;
  engine->cancel_requested.store(true);
  if (engine->worker.joinable()) engine->worker.join();
  if (engine->mtmd != nullptr) mtmd_free(engine->mtmd);
  if (engine->model != nullptr) llama_model_free(engine->model);
  delete engine;
}

void inferno_string_free(const char *value) {
  std::free(const_cast<char *>(value));
}

}  // extern "C"
