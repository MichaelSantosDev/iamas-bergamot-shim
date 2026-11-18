# libimas_bergamot: a small C ABI (bergamot_shim.h) over Mozilla's
# bergamot-translator, statically linked into ONE shared library.
#
#   cmake -S packages/imas_ai/native/bergamot -B build \
#         -DBERGAMOT_SOURCE_DIR=<mozilla/translations checkout>/inference \
#         -DCMAKE_BUILD_TYPE=MinSizeRel
#
# Use build_macos.sh / build_android.sh; they pin the source revision.
cmake_minimum_required(VERSION 3.16)
project(imas_bergamot C CXX)

set(BERGAMOT_SOURCE_DIR "" CACHE PATH "mozilla/translations/inference checkout")
if(NOT EXISTS "${BERGAMOT_SOURCE_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "Set -DBERGAMOT_SOURCE_DIR to <mozilla/translations>/inference (see fetch_sources.sh)")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# Export only bg_* (BG_API); everything else stays internal and strippable.
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

# --- bergamot-translator / marian-fork options (CPU, no GPU, no BLAS libs) ---
set(GIT_SUBMODULE OFF CACHE BOOL "" FORCE)          # sources are fetched by fetch_sources.sh
set(COMPILE_WASM OFF CACHE BOOL "" FORCE)
set(COMPILE_TESTS OFF CACHE BOOL "" FORCE)
set(COMPILE_UNIT_TESTS OFF CACHE BOOL "" FORCE)
set(COMPILE_CUDA OFF CACHE BOOL "" FORCE)
set(COMPILE_CPU ON CACHE BOOL "" FORCE)
set(COMPILE_LIBRARY_ONLY ON CACHE BOOL "" FORCE)
set(COMPILE_EXAMPLES OFF CACHE BOOL "" FORCE)
set(COMPILE_SERVER OFF CACHE BOOL "" FORCE)
set(USE_FBGEMM OFF CACHE BOOL "" FORCE)
set(USE_MKL OFF CACHE BOOL "" FORCE)
set(USE_MPI OFF CACHE BOOL "" FORCE)
set(USE_NCCL OFF CACHE BOOL "" FORCE)
set(USE_CUDNN OFF CACHE BOOL "" FORCE)
set(USE_DOXYGEN OFF CACHE BOOL "" FORCE)
set(USE_SENTENCEPIECE ON CACHE BOOL "" FORCE)
set(USE_STATIC_LIBS ON CACHE BOOL "" FORCE)
set(SPM_ENABLE_SHARED OFF CACHE BOOL "" FORCE)
set(SPM_ENABLE_TCMALLOC OFF CACHE BOOL "" FORCE)
set(SSPLIT_COMPILE_LIBRARY_ONLY ON CACHE BOOL "" FORCE)
set(SSPLIT_USE_INTERNAL_PCRE2 ON CACHE BOOL "" FORCE)
set(BUILD_ARCH "armv8-a" CACHE STRING "" FORCE)    # never -march=native

if(ANDROID)
  # ruy for int8 GEMM and SGEMM; no x86 intgemm, no Apple Accelerate.
  set(USE_APPLE_ACCELERATE OFF CACHE BOOL "" FORCE)
  set(USE_RUY ON CACHE BOOL "" FORCE)
  set(USE_RUY_SGEMM ON CACHE BOOL "" FORCE)
endif()

# Reproducible output: no checkout / build paths in the binary (__FILE__ is
# used by marian's ABORT messages), so the F-Droid build matches ours.
get_filename_component(_bg_src_real "${BERGAMOT_SOURCE_DIR}" REALPATH)
add_compile_options(
  "-ffile-prefix-map=${_bg_src_real}=bergamot"
  "-ffile-prefix-map=${BERGAMOT_SOURCE_DIR}=bergamot"
  "-ffile-prefix-map=${CMAKE_BINARY_DIR}=build"
  "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=shim")

# One section per function/object so the linker can drop what the shim never
# reaches (marian training, CLI, ...). Directory-scoped, so every target below
# inherits it even though marian overwrites CMAKE_CXX_FLAGS.
if(NOT APPLE)
  add_compile_options(-ffunction-sections -fdata-sections)
endif()

add_subdirectory("${BERGAMOT_SOURCE_DIR}" bergamot EXCLUDE_FROM_ALL)

add_library(imas_bergamot SHARED bergamot_shim.cpp)
target_link_libraries(imas_bergamot PRIVATE bergamot-translator-source)

# marian-fork sets its feature macros (ARM, FMA, SSE, COMPILE_CPU,
# USE_RUY_SGEMM, BLAS_FOUND, USE_PTHREADS...) and -flax-vector-conversions
# with directory-scoped add_compile_definitions/options. Its headers depend on
# them, so code outside that directory that includes marian headers (the
# bergamot translator sources and this shim) must see the same set.
get_directory_property(_marian_defs DIRECTORY "${BERGAMOT_SOURCE_DIR}/marian-fork" COMPILE_DEFINITIONS)
get_directory_property(_marian_opts DIRECTORY "${BERGAMOT_SOURCE_DIR}/marian-fork" COMPILE_OPTIONS)
foreach(_t bergamot-translator-source imas_bergamot)
  target_compile_definitions(${_t} PRIVATE ${_marian_defs})
  target_compile_options(${_t} PRIVATE ${_marian_opts})
endforeach()
# marian builds with -Werror; newer clang/NDK warnings must not break us.
target_compile_options(marian PRIVATE -Wno-error)
if(APPLE)
  # marian's bundled zlib 1.2.x defines fdopen(fd,mode) as NULL when
  # TARGET_OS_MAC is set, which breaks the macOS SDK's <stdio.h>; including
  # stdio.h first makes the later #include a no-op (no source patch needed).
  target_compile_options(zlib PRIVATE -include stdio.h)
endif()
target_include_directories(imas_bergamot PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")

if(APPLE)
  set_target_properties(imas_bergamot PROPERTIES INSTALL_NAME_DIR "@rpath")
  target_link_options(imas_bergamot PRIVATE -Wl,-dead_strip)
else()
  # Drop unreferenced sections; no undefined symbols; Android 16 KB pages.
  target_link_options(imas_bergamot PRIVATE
    -Wl,--gc-sections -Wl,--as-needed -Wl,--no-undefined
    -Wl,-z,max-page-size=16384 -Wl,--exclude-libs,ALL
    # The GNU build-id hashes pre-strip inputs (incl. paths of the bundled
    # PCRE2 build), the only byte difference between two checkouts.
    -Wl,--build-id=none)
  if(ANDROID)
    target_link_libraries(imas_bergamot PRIVATE log)
  endif()
endif()

install(TARGETS imas_bergamot LIBRARY DESTINATION lib RUNTIME DESTINATION lib)
