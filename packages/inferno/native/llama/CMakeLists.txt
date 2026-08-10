cmake_minimum_required(VERSION 3.22)
project(golem_inferno LANGUAGES C CXX)

if(NOT DEFINED LLAMA_SOURCE_DIR)
  message(FATAL_ERROR "LLAMA_SOURCE_DIR is required")
endif()
if(NOT DEFINED INFERNO_OUTPUT_DIR)
  message(FATAL_ERROR "INFERNO_OUTPUT_DIR is required")
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
# libmtmd supplies the vision path (#18). Upstream builds it standalone when
# LLAMA_BUILD_MTMD is on and the tools tree is off, which is exactly this
# configuration: mtmd links only ggml and llama — never llama-common — so it
# costs no extra dependency. Video decoding needs a subprocess helper the app
# has no use for, and it is forced off rather than left to a default.
set(LLAMA_BUILD_MTMD ON CACHE BOOL "" FORCE)
set(MTMD_VIDEO OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_CCACHE OFF CACHE BOOL "" FORCE)

if(APPLE)
  set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
else()
  set(GGML_ACCELERATE OFF CACHE BOOL "" FORCE)
endif()

# Metal ships on every Apple target — iOS and the macOS desktop app alike —
# with the shader library embedded in the dylib so no bundle staging exists.
# Package tests on a Mac therefore exercise the same GPU path the apps run.
if(APPLE)
  set(GGML_METAL ON CACHE BOOL "" FORCE)
  set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
else()
  set(GGML_METAL OFF CACHE BOOL "" FORCE)
endif()

add_subdirectory("${LLAMA_SOURCE_DIR}" llama.cpp EXCLUDE_FROM_ALL)

add_library(inferno SHARED ../src/llama_shim.cpp)
target_compile_features(inferno PRIVATE cxx_std_17)
target_compile_definitions(inferno PRIVATE
  INFERNO_BUILD_LLAMA=1
  $<$<BOOL:${APPLE}>:INFERNO_USE_METAL=1>
)
target_include_directories(inferno PRIVATE
  ../include
  "${LLAMA_SOURCE_DIR}/include"
  "${LLAMA_SOURCE_DIR}/ggml/include"
  "${LLAMA_SOURCE_DIR}/vendor"
)
# mtmd exports its own include directory as PUBLIC, so the shim sees mtmd.h
# and mtmd-helper.h through the link alone.
target_link_libraries(inferno PRIVATE llama mtmd)
set_target_properties(inferno PROPERTIES
  OUTPUT_NAME inferno
  PREFIX "lib"
  LIBRARY_OUTPUT_DIRECTORY "${INFERNO_OUTPUT_DIR}"
  RUNTIME_OUTPUT_DIRECTORY "${INFERNO_OUTPUT_DIR}"
  ARCHIVE_OUTPUT_DIRECTORY "${INFERNO_OUTPUT_DIR}"
  BUILD_WITH_INSTALL_RPATH ON
  INSTALL_RPATH "@loader_path"
)
