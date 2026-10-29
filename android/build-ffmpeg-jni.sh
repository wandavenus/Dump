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
# FFmpeg components are built from LGPL-2.1-or-later code; see packaged notices.
#
# Gradle runs this script automatically from the :decoder-ffmpeg preBuild task
# when the .so is missing or its inputs changed. You can also run it manually:
#
#   bash android/build-ffmpeg-jni.sh              # build if needed
#   bash android/build-ffmpeg-jni.sh --force-link # relink, reuse static libs
#   bash android/build-ffmpeg-jni.sh --clean      # discard all cached output
#
# Environment overrides:
#   ANDROID_NDK_HOME / ANDROID_NDK   optional path to the pinned NDK
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
SO_TMP="$SO_PATH.tmp.$"
trap 'rm -f "$SO_TMP"' EXIT
LICENSE_DIR="$MODULE_DIR/src/main/assets/licenses"
CACHE_DIR="$MODULE_DIR/.ffmpeg-build"

FFMPEG_TAG="${FFMPEG_TAG:-n8.1.3}"
ANDROID_API="${ANDROID_API:-27}"
TARGET_ABI="arm64-v8a"
EXPECTED_NDK_VERSION="28.2.13676358"

# Keep this list aligned with FfmpegCapabilityProbe.PROBE_MIME_TYPES.
# Opus is intentionally absent: Android's MediaCodec/CCodec Opus decoder is
# present on the target device, so FFmpeg only needs the codecs Android lacks.
ENABLED_DECODERS=(alac dca truehd mlp vorbis)

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

if [[ ! "$FFMPEG_TAG" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: invalid FFMPEG_TAG '$FFMPEG_TAG'." >&2
    exit 2
fi
if [[ ! "$ANDROID_API" =~ ^[0-9]+$ ]]; then
    echo "ERROR: ANDROID_API must be numeric, got '$ANDROID_API'." >&2
    exit 2
fi
if [ "$CLEAN" = true ]; then
    echo "Removing FFmpeg build cache and generated JNI output ..."
    rm -rf "$CACHE_DIR" "$SO_DIR"
fi

# ── 0. Resolve NDK ─────────────────────────────────────────────────────────
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
PINNED_NDK_PATH=""
if [ -n "$SDK_ROOT" ] && [ -d "$SDK_ROOT/ndk/$EXPECTED_NDK_VERSION" ]; then
    PINNED_NDK_PATH="$SDK_ROOT/ndk/$EXPECTED_NDK_VERSION"
fi
NDK_PATH="${ANDROID_NDK_HOME:-${ANDROID_NDK:-}}"
if [ -n "$NDK_PATH" ] && [ -n "$PINNED_NDK_PATH" ] && [ "$NDK_PATH" != "$PINNED_NDK_PATH" ]; then
    echo "WARN: ignoring NDK override '$NDK_PATH'; using pinned $PINNED_NDK_PATH." >&2
    NDK_PATH="$PINNED_NDK_PATH"
fi
if [ -z "$NDK_PATH" ]; then
    NDK_PATH="$PINNED_NDK_PATH"
fi
if [ -z "$NDK_PATH" ] || [ ! -d "$NDK_PATH" ]; then
    echo "ERROR: Android NDK $EXPECTED_NDK_VERSION not found." >&2
    echo "Install it with: sdkmanager --install \"ndk;$EXPECTED_NDK_VERSION\"" >&2
    exit 1
fi
NDK_VERSION="$(sed -n 's/^Pkg.Revision *= *//p' "$NDK_PATH/source.properties" | head -n 1)"
if [ "$NDK_VERSION" != "$EXPECTED_NDK_VERSION" ]; then
    echo "ERROR: expected Android NDK $EXPECTED_NDK_VERSION, found '${NDK_VERSION:-unknown}' at $NDK_PATH." >&2
    exit 1
fi

case "$(uname -s)" in
    Linux) HOST_TAG="linux-x86_64" ;;
    Darwin)
        case "$(uname -m)" in
            arm64) HOST_TAG="darwin-arm64" ;;
            *) HOST_TAG="darwin-x86_64" ;;
        esac
        ;;
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

if [ ! -f "$JNI_SOURCE" ]; then
    echo "ERROR: JNI source not found: $JNI_SOURCE" >&2
    exit 1
fi
if [ ! -f "$LICENSE_DIR/COPYING.LGPLv2.1" ] || [ ! -f "$LICENSE_DIR/LICENSE-2.0.txt" ] || [ ! -f "$LICENSE_DIR/THIRD_PARTY_NOTICES.txt" ]; then
    echo "ERROR: bundled third-party license notices are missing from $LICENSE_DIR." >&2
    exit 1
fi

hash_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}
hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

echo "✓ NDK: $NDK_PATH ($NDK_VERSION)"
echo "✓ FFmpeg: $FFMPEG_TAG (arm64-v8a, API $ANDROID_API)"
echo "✓ Decoders: ${ENABLED_DECODERS[*]}"

# ── 1. Fetch FFmpeg source (cached per tag) ────────────────────────────────
FFMPEG_SRC="$CACHE_DIR/ffmpeg-$FFMPEG_TAG"
if [ ! -d "$FFMPEG_SRC/.git" ]; then
    rm -rf "$FFMPEG_SRC"
    mkdir -p "$(dirname "$FFMPEG_SRC")"
    echo "[1/4] Cloning FFmpeg $FFMPEG_TAG ..."
    if ! git clone --depth 1 --branch "$FFMPEG_TAG" \
        https://github.com/FFmpeg/FFmpeg.git "$FFMPEG_SRC"; then
        rm -rf "$FFMPEG_SRC"
        echo "ERROR: failed to clone FFmpeg. Check network access, then retry." >&2
        exit 1
    fi
else
    echo "[1/4] Reusing FFmpeg checkout at $FFMPEG_SRC"
fi
FFMPEG_COMMIT="$(git -C "$FFMPEG_SRC" rev-parse HEAD)"
LIBS_DIR="$CACHE_DIR/install/ffmpeg-$FFMPEG_TAG/$TARGET_ABI"
STATIC_STAMP="$LIBS_DIR/.build-config.sha256"
OUTPUT_STAMP="$CACHE_DIR/output-$FFMPEG_TAG-$TARGET_ABI.sha256"

CONFIGURE_ARGS=(
    --target-os=android
    --arch=aarch64
    --cpu=armv8-a
    --enable-cross-compile
    --cc="$CLANG"
    --cxx="$CLANGXX"
    --ar="$TOOLCHAIN/bin/llvm-ar"
    --nm="$TOOLCHAIN/bin/llvm-nm"
    --ranlib="$TOOLCHAIN/bin/llvm-ranlib"
    --strip="$TOOLCHAIN/bin/llvm-strip"
    --sysroot="$TOOLCHAIN/sysroot"
    --enable-static
    --disable-shared
    --enable-pic
    --disable-everything
    --disable-programs
    --disable-doc
    --disable-avdevice
    --disable-avformat
    --disable-swscale
    --disable-avfilter
    --disable-network
    --disable-autodetect
    --disable-gpl
    --disable-nonfree
    --disable-version3
    --enable-swresample
    "--enable-decoder=$(IFS=,; echo "${ENABLED_DECODERS[*]}")"
    "--libdir=$LIBS_DIR"
)
CLANG_VERSION="$("$CLANG" --version | sed -n '1p')"
STATIC_INPUTS="$(
    {
        printf 'ffmpeg_tag=%s\n' "$FFMPEG_TAG"
        printf 'ffmpeg_commit=%s\n' "$FFMPEG_COMMIT"
        printf 'abi=%s\nandroid_api=%s\nndk_version=%s\n' "$TARGET_ABI" "$ANDROID_API" "$NDK_VERSION"
        printf 'clang_version=%s\n' "$CLANG_VERSION"
        printf 'decoder=%s\n' "${ENABLED_DECODERS[@]}"
        printf 'configure_arg=%s\n' "${CONFIGURE_ARGS[@]}"
        printf 'build_script_sha256=%s\n' "$(hash_file "$0")"
    } | hash_stream
)"
JNI_SOURCE_SHA256="$(hash_file "$JNI_SOURCE")"
OUTPUT_FINGERPRINT="$(printf 'static=%s\njni=%s\n' "$STATIC_INPUTS" "$JNI_SOURCE_SHA256" | hash_stream)"

if [ -f "$SO_PATH" ] && [ -f "$OUTPUT_STAMP" ] && \
   [ "$(cat "$OUTPUT_STAMP")" = "$OUTPUT_FINGERPRINT" ] && \
   [ "$FORCE_LINK" = false ]; then
    echo "✓ libffmpegJNI.so is current ($TARGET_ABI, FFmpeg $FFMPEG_TAG)."
    exit 0
fi

STATIC_LIBS=("$LIBS_DIR/libavcodec.a" "$LIBS_DIR/libswresample.a" "$LIBS_DIR/libavutil.a")
NEED_STATIC_BUILD=false
if [ ! -f "$STATIC_STAMP" ] || [ "$(cat "$STATIC_STAMP" 2>/dev/null || true)" != "$STATIC_INPUTS" ]; then
    NEED_STATIC_BUILD=true
fi
for library in "${STATIC_LIBS[@]}"; do
    if [ ! -f "$library" ]; then NEED_STATIC_BUILD=true; fi
done

if [ "$NEED_STATIC_BUILD" = true ]; then
    echo "[2/4] Building FFmpeg static libraries (configuration cache miss) ..."
    if [ -f "$FFMPEG_SRC/Makefile" ]; then
        (cd "$FFMPEG_SRC" && make distclean) >/dev/null 2>&1 || true
    fi
    rm -rf "$LIBS_DIR"
    mkdir -p "$LIBS_DIR" "$(dirname "$LIBS_DIR")"
    pushd "$FFMPEG_SRC" >/dev/null
    ./configure "${CONFIGURE_ARGS[@]}"
    JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    make -j"$JOBS"
    make install-libs
    popd >/dev/null

    for library in "${STATIC_LIBS[@]}"; do
        if [ ! -f "$library" ]; then
            echo "ERROR: expected FFmpeg static library missing after build: $library" >&2
            exit 1
        fi
    done
    printf '%s\n' "$STATIC_INPUTS" > "$STATIC_STAMP"
else
    echo "[2/4] Reusing static libraries with matching configuration fingerprint."
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
    -o "$SO_TMP"

"$TOOLCHAIN/bin/llvm-strip" --strip-unneeded "$SO_TMP"

echo "[4/4] Verifying temporary native artifact ..."
if ! "$TOOLCHAIN/bin/llvm-nm" -D "$SO_TMP" | awk '$NF == "JNI_OnLoad" { found=1 } END { exit !found }'; then
    echo "ERROR: JNI_OnLoad is not exported from libffmpegJNI.so." >&2
    exit 1
fi
if "$TOOLCHAIN/bin/llvm-readelf" -d "$SO_TMP" | grep -q "libc++_shared"; then
    echo "ERROR: libffmpegJNI.so unexpectedly depends on libc++_shared.so." >&2
    exit 1
fi
for decoder in "${ENABLED_DECODERS[@]}"; do
    if ! strings "$SO_TMP" | grep -F "ff_${decoder}_decoder" >/dev/null; then
        echo "ERROR: decoder '$decoder' is missing from libffmpegJNI.so." >&2
        exit 1
    fi
done
# Replace the previous usable library only after the new artifact passes all checks.
mv "$SO_TMP" "$SO_PATH"
mkdir -p "$CACHE_DIR"
printf '%s\n' "$OUTPUT_FINGERPRINT" > "$OUTPUT_STAMP"

echo ""
echo "✓ Built $SO_PATH ($(du -h "$SO_PATH" | cut -f1))"
echo "  FFmpeg source: https://github.com/FFmpeg/FFmpeg/tree/$FFMPEG_TAG"
echo "  Configuration: FFmpeg LGPL-2.1-or-later components; no GPL/nonfree/version3"
echo "  Notices: packaged from $LICENSE_DIR"
