#include "inferno.h"

#include "ggml-backend.h"
#include "llama.h"
#include "nlohmann/json.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

#if defined(__APPLE__)
#include <mach/mach.h>
#endif

using json = nlohmann::json;
using steady_clock = std::chrono::steady_clock;

struct inferno_engine {
  std::mutex mutex;
  std::thread worker;
  std::atomic<bool> cancel_requested{false};
  std::atomic<bool> busy{false};
  llama_model *model = nullptr;
};

namespace {

std::once_flag backend_once;

void initialize_backend() {
  std::call_once(backend_once, [] {
    llama_log_set(
        [](enum ggml_log_level level, const char *text, void *) {
          if (level == GGML_LOG_LEVEL_ERROR && text != nullptr) {
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
    if (copy == nullptr) return;
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
  if (engine == nullptr || engine->busy.exchange(true)) return -1;
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
      engine->busy.store(false);
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
                            const char *model_path,
                            uint64_t operation_id,
                            inferno_event_callback callback,
                            void *user_data) {
  if (engine == nullptr || model_path == nullptr || engine->model != nullptr) return -1;
  const std::string path(model_path);
  return start_worker(engine, [=] {
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
    params.check_tensors = true;
    params.progress_callback = [](float, void *context) {
      return !static_cast<inferno_engine *>(context)->cancel_requested.load();
    };
    params.progress_callback_user_data = engine;
    llama_model *loaded = nullptr;
    try {
      loaded = llama_model_load_from_file(path.c_str(), params);
    } catch (const std::exception &error) {
      emit_error(callback, operation_id, "load_failed", error.what(), user_data);
      return;
    } catch (...) {
      emit_error(callback,
                 operation_id,
                 "load_failed",
                 "llama.cpp rejected the model.",
                 user_data);
      return;
    }
    if (engine->cancel_requested.load()) {
      if (loaded != nullptr) llama_model_free(loaded);
      emit_error(callback, operation_id, "cancelled", "Model loading was cancelled.", user_data);
      return;
    }
    if (loaded == nullptr) {
      emit_error(callback,
                 operation_id,
                 "incompatible_model",
                 "llama.cpp could not load this GGUF model.",
                 user_data);
      return;
    }
    engine->model = loaded;
    emit(callback, operation_id, INFERNO_EVENT_OPERATION_COMPLETED, "", user_data);
  });
}

int32_t inferno_engine_generate(inferno_engine *engine,
                                const char *request_json,
                                uint64_t operation_id,
                                inferno_event_callback callback,
                                void *user_data) {
  if (engine == nullptr || engine->model == nullptr || request_json == nullptr) return -1;
  const std::string encoded(request_json);
  return start_worker(engine, [=] {
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
    const uint32_t seed = request["seed"].is_null()
                              ? LLAMA_DEFAULT_SEED
                              : request.value("seed", LLAMA_DEFAULT_SEED);
    const auto stop_sequences = request.value("stopSequences", std::vector<std::string>{});
    const auto stop_ids_vector = request.value("stopTokenIds", std::vector<llama_token>{});
    const std::unordered_set<llama_token> stop_ids(stop_ids_vector.begin(),
                                                   stop_ids_vector.end());
    if (prompt.empty() || max_tokens <= 0 || temperature < 0 || top_p <= 0 || top_p > 1) {
      emit_error(callback,
                 operation_id,
                 "generation_failed",
                 "The generation request is invalid.",
                 user_data);
      return;
    }

    const llama_vocab *vocab = llama_model_get_vocab(engine->model);
    const auto prompt_tokens = tokenize(vocab, prompt);
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
    const int32_t model_context = llama_model_n_ctx_train(engine->model);
    const int64_t requested_context =
        static_cast<int64_t>(prompt_tokens.size()) + max_tokens;
    if (requested_context > model_context) {
      emit_error(callback,
                 operation_id,
                 "generation_failed",
                 "The rendered prompt and max tokens exceed the model context.",
                 user_data);
      return;
    }

    llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = static_cast<uint32_t>(std::max<int64_t>(requested_context, 64));
    context_params.n_batch = static_cast<uint32_t>(
        std::max<size_t>(1, std::min<size_t>(prompt_tokens.size(), 512)));
    context_params.n_ubatch = context_params.n_batch;
    context_params.no_perf = false;
    context_params.abort_callback = [](void *context) {
      return static_cast<inferno_engine *>(context)->cancel_requested.load();
    };
    context_params.abort_callback_data = engine;
    llama_context *context = llama_init_from_model(engine->model, context_params);
    if (context == nullptr) {
      emit_error(callback,
                 operation_id,
                 "generation_failed",
                 "llama.cpp could not allocate a generation context.",
                 user_data);
      return;
    }

    llama_sampler *sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));

    const auto operation_start = steady_clock::now();
    bool decode_failed = false;
    for (size_t offset = 0; offset < prompt_tokens.size();) {
      if (engine->cancel_requested.load()) break;
      const size_t count = std::min<size_t>(context_params.n_batch,
                                            prompt_tokens.size() - offset);
      llama_batch batch = llama_batch_get_one(
          const_cast<llama_token *>(prompt_tokens.data() + offset),
          static_cast<int32_t>(count));
      if (llama_decode(context, batch) != 0) {
        decode_failed = true;
        break;
      }
      offset += count;
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
        if (llama_decode(context, next) != 0) {
          decode_failed = true;
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
           prompt_seconds > 0 ? prompt_tokens.size() / prompt_seconds : 0},
          {"generatedTokenCount", generated},
          {"elapsedSeconds", elapsed_seconds},
          {"promptTokenCount", prompt_tokens.size()},
          {"timeToFirstTokenSeconds",
           first_token == steady_clock::time_point{}
               ? json(nullptr)
               : json(seconds_between(prompt_end, first_token))},
          {"peakPhysicalFootprintBytes", peak_footprint}};
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
  if (engine->model != nullptr) llama_model_free(engine->model);
  delete engine;
}

void inferno_string_free(const char *value) {
  std::free(const_cast<char *>(value));
}

}  // extern "C"
