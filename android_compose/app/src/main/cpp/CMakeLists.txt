cmake_minimum_required(VERSION 3.22)
project(music_player_native LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

include(FetchContent)

# ── libnative_audio_runtime.so ────────────────────────────────────────────────
set(NATIVE_AUDIO_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../native_audio_runtime/src")

add_library(native_audio_runtime SHARED
    ${NATIVE_AUDIO_SRC_DIR}/native_dsp_jni.c
    ${NATIVE_AUDIO_SRC_DIR}/dsp_pipeline.c
    ${NATIVE_AUDIO_SRC_DIR}/biquad_filter.c
    ${NATIVE_AUDIO_SRC_DIR}/comp_processor.c
    ${NATIVE_AUDIO_SRC_DIR}/crossfeed_processor.c
    ${NATIVE_AUDIO_SRC_DIR}/gain_processor.c
    ${NATIVE_AUDIO_SRC_DIR}/limiter_processor.c
    ${NATIVE_AUDIO_SRC_DIR}/loudness_processor.c
    ${NATIVE_AUDIO_SRC_DIR}/native_audio_runtime.c
    ${NATIVE_AUDIO_SRC_DIR}/replaygain_processor.c
    ${NATIVE_AUDIO_SRC_DIR}/soft_clipper_processor.c
    ${NATIVE_AUDIO_SRC_DIR}/audio_buffer.c
    ${NATIVE_AUDIO_SRC_DIR}/aaudio_probe.c
    ${NATIVE_AUDIO_SRC_DIR}/neon_kernels.S
)

target_include_directories(native_audio_runtime PRIVATE
    ${NATIVE_AUDIO_SRC_DIR}
)

target_link_libraries(native_audio_runtime PRIVATE
    log
    android
    aaudio
)

target_compile_options(native_audio_runtime PRIVATE -Wall -O3)

# ── libebur128 & TagLib for ReplayGain ───────────────────────────────────────
FetchContent_Declare(
    libebur128
    GIT_REPOSITORY https://github.com/jiixyj/libebur128.git
    GIT_TAG        v1.2.6
)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(ENABLE_INTERNAL_QUEUE_H ON CACHE BOOL "Use bundled queue.h" FORCE)
FetchContent_MakeAvailable(libebur128)

FetchContent_Declare(
    taglib
    GIT_REPOSITORY https://github.com/taglib/taglib.git
    GIT_TAG        v2.3
)
set(BUILD_TESTING    OFF CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES   OFF CACHE BOOL "" FORCE)
set(BUILD_BINDINGS   OFF CACHE BOOL "" FORCE)
set(WITH_MP4         OFF CACHE BOOL "" FORCE)
set(WITH_ASF         OFF CACHE BOOL "" FORCE)
set(WITH_DSF         OFF CACHE BOOL "" FORCE)
set(WITH_MATROSKA    OFF CACHE BOOL "" FORCE)
set(WITH_MOD         OFF CACHE BOOL "" FORCE)
set(WITH_RIFF        OFF CACHE BOOL "" FORCE)
set(WITH_SHORTEN     OFF CACHE BOOL "" FORCE)
set(WITH_TRUEAUDIO   OFF CACHE BOOL "" FORCE)
set(WITH_APE         OFF CACHE BOOL "" FORCE)
set(WITH_VORBIS      ON  CACHE BOOL "Needed for FLAC / Ogg Vorbis / Opus" FORCE)
set(WITH_ZLIB        OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(taglib)

set(ANDROID_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../android/app/src/main/cpp")

add_library(replaygain_native SHARED
    ${ANDROID_CPP_DIR}/replaygain/replaygain_jni.cpp
    ${ANDROID_CPP_DIR}/replaygain/ebur128_analyzer.cpp
    ${ANDROID_CPP_DIR}/replaygain/tag_writer.cpp
    ${ANDROID_CPP_DIR}/replaygain/metadata_region.cpp
)

target_include_directories(replaygain_native PRIVATE
    ${libebur128_SOURCE_DIR}/ebur128
    ${taglib_SOURCE_DIR}/taglib
    ${taglib_SOURCE_DIR}/taglib/toolkit
    ${taglib_SOURCE_DIR}/taglib/mpeg
    ${taglib_SOURCE_DIR}/taglib/mpeg/id3v2
    ${taglib_SOURCE_DIR}/taglib/mpeg/id3v2/frames
    ${taglib_SOURCE_DIR}/taglib/ogg
    ${taglib_SOURCE_DIR}/taglib/ogg/vorbis
    ${taglib_SOURCE_DIR}/taglib/ogg/opus
    ${taglib_SOURCE_DIR}/taglib/flac
    ${CMAKE_CURRENT_BINARY_DIR}/_deps/taglib-build
)

target_link_libraries(replaygain_native PRIVATE
    ebur128
    tag
    log
)

target_compile_options(replaygain_native PRIVATE -Wall -Wextra -fvisibility=hidden)

# ── Signalsmith Stretch ──────────────────────────────────────────────────────
FetchContent_Declare(
    signalsmith_linear
    GIT_REPOSITORY https://github.com/Signalsmith-Audio/linear.git
    GIT_TAG        0.3.1
)
FetchContent_GetProperties(signalsmith_linear)
if(NOT signalsmith_linear_POPULATED)
    FetchContent_Populate(signalsmith_linear)
endif()

FetchContent_Declare(
    signalsmith_stretch
    GIT_REPOSITORY https://github.com/Signalsmith-Audio/signalsmith-stretch.git
    GIT_TAG        1.1.0
)
FetchContent_GetProperties(signalsmith_stretch)
if(NOT signalsmith_stretch_POPULATED)
    FetchContent_Populate(signalsmith_stretch)
endif()

add_library(stretch_native SHARED
    ${ANDROID_CPP_DIR}/stretch/stretch_jni.cpp
)

target_include_directories(stretch_native PRIVATE
    ${signalsmith_stretch_SOURCE_DIR}
    ${signalsmith_linear_SOURCE_DIR}/include
)

target_compile_options(stretch_native PRIVATE -Wall -Wextra -fvisibility=hidden -O3 -fstack-protector-strong)
target_link_libraries(stretch_native PRIVATE log)
