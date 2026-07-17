# ─────────────────────────────────────────────────────────────────────────────
# Native ReplayGain module — CMake build script
# ─────────────────────────────────────────────────────────────────────────────
#
# Builds `libreplaygain_native.so`, which bundles:
#
#   • libebur128 (vendored via FetchContent, MIT license) — EBU R128 /
#     ITU-R BS.1770-4 loudness measurement (integrated LUFS, loudness range,
#     true peak). This replaces the previous hand-rolled Kotlin K-weighting
#     implementation with the reference C library used by ffmpeg, Rockbox,
#     foobar2000's ReplayGain 2.0 scanner, etc.
#
#   • TagLib (vendored via FetchContent, LGPL v2.1 / MPL 1.1 dual license) —
#     metadata-only tag reading/writing for MP3 (ID3v2), FLAC (Vorbis comment
#     + picture blocks), Ogg Vorbis, and Ogg Opus. TagLib guarantees it never
#     touches the audio-frame data when saving — only tag/metadata regions are
#     rewritten — which satisfies the "never re-encode audio" requirement and
#     avoids the file-corruption/AWT-ImageIO pitfalls of pure-JVM tagging
#     libraries (e.g. jaudiotagger) on Android. TagLib has no Android-specific
#     dependencies: no javax.imageio, no AWT — artwork is handled as opaque
#     byte blobs, which is exactly what we want for byte-for-byte preservation.
#
# NOTE for whoever builds this for the first time: this sandbox environment
# has no Android SDK/NDK, so this CMake script has never been executed here.
# The first real Gradle build (Android Studio / CI) will fetch and configure
# both dependencies via FetchContent. If the exported CMake target names
# ("ebur128"/"ebur128_static" or "tag") change in a future release, pin the
# GIT_TAG below to the versions this file was written against and re-verify.

cmake_minimum_required(VERSION 3.22)
project(replaygain_native LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

include(FetchContent)

# ── libebur128 ────────────────────────────────────────────────────────────────
FetchContent_Declare(
    libebur128
    GIT_REPOSITORY https://github.com/jiixyj/libebur128.git
    GIT_TAG        v1.2.6
)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(ENABLE_INTERNAL_QUEUE_H ON CACHE BOOL "Use bundled queue.h (avoids BSD sys/queue.h ABI issues on Android)" FORCE)
FetchContent_MakeAvailable(libebur128)

# ── TagLib ────────────────────────────────────────────────────────────────────
FetchContent_Declare(
    taglib
    GIT_REPOSITORY https://github.com/taglib/taglib.git
    GIT_TAG        v2.3
)
set(BUILD_TESTING    OFF CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES   OFF CACHE BOOL "" FORCE)
set(BUILD_BINDINGS   OFF CACHE BOOL "" FORCE)   # no C bindings needed — we link libtag.a directly from C++
set(WITH_MP4         OFF CACHE BOOL "MP4/M4A handled by ExoMetadataReader already; skip to shrink binary" FORCE)
set(WITH_ASF         OFF CACHE BOOL "" FORCE)
set(WITH_DSF         OFF CACHE BOOL "" FORCE)
set(WITH_MATROSKA    OFF CACHE BOOL "" FORCE)
set(WITH_MOD         OFF CACHE BOOL "" FORCE)
set(WITH_RIFF        OFF CACHE BOOL "" FORCE)
set(WITH_SHORTEN     OFF CACHE BOOL "" FORCE)
set(WITH_TRUEAUDIO   OFF CACHE BOOL "" FORCE)
set(WITH_APE         OFF CACHE BOOL "" FORCE)
set(WITH_VORBIS      ON  CACHE BOOL "Needed for FLAC / Ogg Vorbis / Opus" FORCE)
set(WITH_ZLIB        OFF CACHE BOOL "No zlib on this NDK toolchain path; only affects ID3v2 APIC image compression, which we never re-compress" FORCE)
FetchContent_MakeAvailable(taglib)

# ── Our JNI + analysis/tag-writing sources ───────────────────────────────────
add_library(replaygain_native SHARED
    replaygain/replaygain_jni.cpp
    replaygain/ebur128_analyzer.cpp
    replaygain/tag_writer.cpp
    replaygain/metadata_region.cpp
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
    ${CMAKE_CURRENT_BINARY_DIR}/_deps/taglib-build  # generated config.h / taglib_config.h
)

target_link_libraries(replaygain_native PRIVATE
    ebur128
    tag
    log
)

target_compile_options(replaygain_native PRIVATE -Wall -Wextra -fvisibility=hidden)

# ─────────────────────────────────────────────────────────────────────────────
# Signalsmith Stretch module — pitch-shift / time-stretch playback engine
# ─────────────────────────────────────────────────────────────────────────────
#
# Builds `libstretch_native.so`, wrapping Signalsmith Stretch (MIT license,
# https://github.com/Signalsmith-Audio/signalsmith-stretch) — a header-only
# C++11 STFT-based pitch/time library. Chosen to fully replace ExoPlayer's
# built-in SonicAudioProcessor for BOTH speed and pitch, because Sonic's
# WSOLA-ish algorithm gets noticeably robotic/gritty away from 1.0x, while
# Signalsmith Stretch stays clean across a much wider pitch/rate range.
#
# Signalsmith Stretch itself depends on header-only "Signalsmith Linear"
# (also MIT) for its FFT/STFT plumbing. Both are pinned to the exact tags
# their own upstream CMakeLists.txt were pinned to at integration time —
# do not casually bump without re-checking the API surface below still
# matches (process()/flush()/setTransposeSemitones() signatures).
#
# NOTE: same caveat as replaygain_native above — this sandbox has no
# Android SDK/NDK, so this section has never actually been built here.
# The include-directory layout below was verified by inspecting the
# fetched repos' structure directly (GitHub API), not by compiling.
#
# We deliberately do NOT add_subdirectory() either upstream repo (which is
# what their own CMakeLists.txt normally does via FetchContent_MakeAvailable):
#   - both require cmake_minimum_required(3.24), higher than this project's
#     3.22 floor (matching the cmake version pinned in app/build.gradle);
#   - their CMakeLists.txt also probes Apple Accelerate / Intel IPP / PFFFT,
#     none of which apply to this Android-only build.
# Instead we FetchContent_Populate() just the sources and wire up our own
# minimal include paths — both libraries are header-only, so no upstream
# build step is actually needed.
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
    stretch/stretch_jni.cpp
)

target_include_directories(stretch_native PRIVATE
    ${signalsmith_stretch_SOURCE_DIR}          # signalsmith-stretch.h (repo root)
    ${signalsmith_linear_SOURCE_DIR}/include   # signalsmith-linear/{fft,linear,stft}.h
)

target_compile_options(stretch_native PRIVATE -Wall -Wextra -fvisibility=hidden -O3 -fstack-protector-strong)

target_link_libraries(stretch_native PRIVATE log)
