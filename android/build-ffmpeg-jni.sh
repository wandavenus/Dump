#!/usr/bin/env bash
# build-ffmpeg-jni.sh — builds the local Media3 FFmpeg decoder JNI library.
#
# PRODUCTION BUILD PATH
# ─────────────────────
# android/decoder-ffmpeg/ compiles the Media3 FFmpeg extension wrapper
# (vendored Apache-2.0 sources) and packages the libffmpegJNI.so produced by
# this script. The app no longer consumes the Jellyfin prebuilt AAR
# (org.jellyfin.media3:media3-ffmpeg-decoder, GPL v3).
#
# The script cross-compiles FFmpeg from source for arm64-v8a only (the app's
# only supported ABI) and links ffmpeg_jni.cc against the static libraries.
# FFmpeg is configured with --disable-gpl --disable-nonfree --disable-version3,
# so the resulting binary contains LGPL-2.1-or-later code only.
#
# Gradle runs this script automatically from the :decoder-ffmpeg preBuild task
# when the .so is missing or its inputs changed. You can also run it manually:
#
#   bash android/build-ffmpeg-jni.sh              # build if needed
#   bash android/build-ffmpeg-jni.sh --force-link # relink, reuse static libs
#   bash android/build-ffmpeg-jni.sh --clean      # discard all cached output
#
# Environment overrides:
#   ANDROID_NDK_HOME / ANDROID_NDK   NDK path (default: newest NDK in SDK)
#   FFMPEG_TAG                       FFmpeg git tag (default: n8.1.3)
#
# Prerequisites: Android NDK 28.2.13676358, git, make, bash, a Linux or macOS
# host, and network access for the first FFmpeg checkout.
#
# Output:
#   android/decoder-ffmpeg/src/main/jniLibs/arm64-v8a/libffmpegJNI.so
#   android/decoder-ffmpeg/.ffmpeg-build/ffmpeg-<tag>/  (cached build tree)
#
# Verify on device after install:
#   adb logcat | grep -E "Ffmpeg|ffmpeg_jni"
# The startup log should report available=true and the supported codecs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$SCRIPT_DIR/decoder-ffmpeg"
JNI_SOURCE="$MODULE_DIR/src/main/jni/ffmpeg_jni.cc"
SO_DIR="$MODULE_DIR/src/main/jniLibs/arm64-v8a"
SO_PATH="$SO_DIR/libffmpegJNI.so"

FFMPEG_TAG="${FFMPEG_TAG:-n8.1.3}"
ANDROID_API="${ANDROID_API:-27}" # matches app minSdk 27
TARGET_ABI="arm64-v8a"

# Containers first, then lossless/hi-res audio. This matches the formats the
# Kotlin capability probe advertises (FfmpegCapabilityProbe.PROBE_MIME_TYPES).
ENABLED_DECODERS=(alac dca truehd mlp vorbis opus)

FORCE_LINK=false
CLEAN=false

usage() {
    sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
    case "$arg" in
        --force-link) FORCE_LINK=true ;;
        --clean) CLEAN=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $arg (use --help)" >&2; exit 2 ;;
    esac
done

if [ "$CLEAN" = true ]; then
    echo "Removing cached FFmpeg build tree and JNI library ..."
    rm -rf "$MODULE_DIR/.ffmpeg-build" "$SO_DIR"
fi

if [ -f "$SO_PATH" ] && [ "$FORCE_LINK" = false ]; then
    echo "✓ libffmpegJNI.so already exists at $SO_PATH"
    echo "  Use --force-link to relink or --clean to rebuild FFmpeg from scratch."
    exit 0
fi

# ── 0. Resolve NDK ─────────────────────────────────────────────────────────
NDK_PATH="${ANDROID_NDK_HOME:-${ANDROID_NDK:-}}"
if [ -z "$NDK_PATH" ]; then
    SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
    if [ -n "$SDK_ROOT" ] && [ -d "$SDK_ROOT/ndk" ]; then
        # Prefer the version pinned by android/app/build.gradle.
        if [ -d "$SDK_ROOT/ndk/28.2.13676358" ]; then
            NDK_PATH="$SDK_ROOT/ndk/28.2.13676358"
        else
            NDK_PATH="$(find "$SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d -print -quit)"
        fi
    fi
fi
if [ -z "$NDK_PATH" ] || [ ! -d "$NDK_PATH" ]; then
    echo "ERROR: Android NDK not found." >&2
    echo "Set ANDROID_NDK_HOME or install NDK 28.2.13676358 via sdkmanager." >&2
    exit 1
fi

case "$(uname -s)" in
    Linux) HOST_TAG="linux-x86_64" ;;
    Darwin) HOST_TAG="darwin-x86_64" ;;
    *) echo "ERROR: unsupported host OS $(uname -s)." >&2; exit 1 ;;
esac

TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/$HOST_TAG"
CLANG="$TOOLCHAIN/bin/aarch64-linux-android${ANDROID_API}-clang"
CLANGXX="$TOOLCHAIN/bin/aarch64-linux-android${ANDROID_API}-clang++"
if [ ! -x "$CLANGXX" ]; then
    echo "ERROR: NDK toolchain not found at $TOOLCHAIN" >&2
    echo "Install NDK 28.2.13676358 (Flutter's default) and retry." >&2
    exit 1
fi

echo "✓ NDK: $NDK_PATH"
echo "✓ FFmpeg: $FFMPEG_TAG (arm64-v8a, API $ANDROID_API)"
echo "✓ Decoders: ${ENABLED_DECODERS[*]}"

# ── 1. Fetch FFmpeg source (cached per tag) ────────────────────────────────
FFMPEG_SRC="$MODULE_DIR/.ffmpeg-build/ffmpeg-$FFMPEG_TAG"
if [ ! -d "$FFMPEG_SRC/.git" ]; then
    mkdir -p "$(dirname "$FFMPEG_SRC")"
    echo "[1/4] Cloning FFmpeg $FFMPEG_TAG ..."
    if ! git clone --depth 1 --branch "$FFMPEG_TAG" \
        https://github.com/FFmpeg/FFmpeg.git "$FFMPEG_SRC"; then
        echo "ERROR: failed to clone FFmpeg. Check network access, then retry." >&2
        exit 1
    fi
else
    echo "[1/4] Reusing FFmpeg checkout at $FFMPEG_SRC"
fi

LIBS_DIR="$FFMPEG_SRC/android-libs/$TARGET_ABI"
if [ ! -f "$LIBS_DIR/libavcodec.a" ]; then
    # ── 2. Cross-compile FFmpeg static libraries ───────────────────────────
    echo "[2/4] Configuring and building FFmpeg (this takes a few minutes on first run) ..."
    pushd "$FFMPEG_SRC" >/dev/null

    ./configure \
        --target-os=android \
        --arch=aarch64 \
        --cpu=armv8-a \
        --enable-cross-compile \
        --cc="$CLANG" \
        --cxx="$CLANGXX" \
        --ar="$TOOLCHAIN/bin/llvm-ar" \
        --nm="$TOOLCHAIN/bin/llvm-nm" \
        --ranlib="$TOOLCHAIN/bin/llvm-ranlib" \
        --strip="$TOOLCHAIN/bin/llvm-strip" \
        --sysroot="$TOOLCHAIN/sysroot" \
        --enable-static \
        --disable-shared \
        --enable-pic \
        --disable-everything \
        --disable-programs \
        --disable-doc \
        --disable-avdevice \
        --disable-avformat \
        --disable-swscale \
        --disable-avfilter \
        --disable-network \
        --disable-autodetect \
        --disable-gpl \
        --disable-nonfree \
        --disable-version3 \
        --enable-swresample \
        --enable-decoder="$(IFS=,; echo "${ENABLED_DECODERS[*]}")" \
        --libdir="$LIBS_DIR"

    JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    make -j"$JOBS"
    make install-libs
    popd >/dev/null

    if [ ! -f "$LIBS_DIR/libavcodec.a" ]; then
        echo "ERROR: FFmpeg static libraries were not installed at $LIBS_DIR" >&2
        exit 1
    fi
else
    echo "[2/4] Reusing cached FFmpeg static libraries"
fi

# ── 3. Compile the JNI wrapper ─────────────────────────────────────────────
echo "[3/4] Linking libffmpegJNI.so ..."
mkdir -p "$SO_DIR"
"$CLANGXX" \
    -shared \
    -fPIC \
    -O2 \
    -fvisibility=hidden \
    -fvisibility-inlines-hidden \
    -std=c++17 \
    -I "$FFMPEG_SRC" \
    "$JNI_SOURCE" \
    "$LIBS_DIR/libavcodec.a" \
    "$LIBS_DIR/libswresample.a" \
    "$LIBS_DIR/libavutil.a" \
    -landroid -llog -lm -ldl \
    -nostdlib++ \
    -Wl,-Bsymbolic \
    -Wl,--gc-sections \
    -Wl,--no-undefined \
    -o "$SO_PATH"

"$TOOLCHAIN/bin/llvm-strip" --strip-unneeded "$SO_PATH"

# ── 4. Verify the artifact ─────────────────────────────────────────────────
echo "[4/4] Verifying $SO_PATH ..."
if ! "$TOOLCHAIN/bin/llvm-nm" -D "$SO_PATH" | grep " JNI_OnLoad$" >/dev/null; then
    echo "ERROR: JNI_OnLoad is not exported from libffmpegJNI.so" >&2
    exit 1
fi
if "$TOOLCHAIN/bin/llvm-readelf" -d "$SO_PATH" | grep "libc++_shared" >/dev/null; then
    echo "ERROR: libffmpegJNI.so depends on libc++_shared.so" >&2
    exit 1
fi
for decoder in "${ENABLED_DECODERS[@]}"; do
    if ! strings "$SO_PATH" | grep "ff_${decoder}_decoder" >/dev/null; then
        echo "ERROR: decoder '$decoder' is missing from libffmpegJNI.so" >&2
        exit 1
    fi
done

echo ""
echo "✓ Built $SO_PATH ($(du -h "$SO_PATH" | cut -f1))"
echo "  FFmpeg:   $FFMPEG_TAG (LGPL-2.1-or-later, no GPL/nonfree/version3 code)"
echo "  License:  FFmpeg COPYING.LGPLv2.1 and the archive URL for the exact tag"
echo "            must accompany distributed APKs."
