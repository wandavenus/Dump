#!/usr/bin/env bash
# build-ffmpeg-jni.sh
#
# Builds libffmpegJNI.so for arm64-v8a from the official androidx/media source,
# configured for ALAC decoding only (minimal .so size).
#
# Prerequisites:
#   - Android NDK r25c or newer (download from https://developer.android.com/ndk/downloads)
#   - git, curl, tar, make, yasm (or nasm)
#   - Linux or macOS host
#
# Usage:
#   bash android/build-ffmpeg-jni.sh /path/to/android-ndk-r25c
#
# Output:
#   android/app/src/main/jniLibs/arm64-v8a/libffmpegJNI.so
#
# After the .so is in place, rebuild the APK:
#   flutter build apk --release

set -euo pipefail

MEDIA3_TAG="1.10.1"
TARGET_ABI="arm64-v8a"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/app/src/main/jniLibs/arm64-v8a"
TMP_DIR="${TMPDIR:-/tmp}/media3-ffmpeg-build"
REPO_DIR="$TMP_DIR/media3"

# ── 0. Resolve NDK path ───────────────────────────────────────────────────────
NDK_PATH="${1:-${ANDROID_NDK_HOME:-${ANDROID_NDK:-}}}"
if [ -z "$NDK_PATH" ] || [ ! -d "$NDK_PATH" ]; then
    echo "ERROR: Android NDK not found."
    echo "Usage: bash build-ffmpeg-jni.sh /path/to/android-ndk-r25c"
    echo "       (or set ANDROID_NDK_HOME env var)"
    exit 1
fi
echo "✓ NDK: $NDK_PATH"

# ── 1. Clone androidx/media @ 1.10.1 ─────────────────────────────────────────
mkdir -p "$TMP_DIR"
if [ -d "$REPO_DIR/.git" ]; then
    echo "✓ Repository already cloned at $REPO_DIR"
else
    echo "[1/5] Cloning androidx/media @ $MEDIA3_TAG (shallow)..."
    git clone --depth 1 \
        --branch "$MEDIA3_TAG" \
        https://github.com/androidx/media.git \
        "$REPO_DIR"
fi

JNI_DIR="$REPO_DIR/libraries/decoder_ffmpeg/src/main/jni"
if [ ! -d "$JNI_DIR" ]; then
    echo "ERROR: JNI directory not found: $JNI_DIR"
    echo "The Media3 repo layout may have changed; inspect the repo manually."
    exit 1
fi
cd "$JNI_DIR"

# ── 2. Build FFmpeg for arm64-v8a, ALAC-only ─────────────────────────────────
echo "[2/5] Building FFmpeg (arm64-v8a, ALAC only)..."
# build_ffmpeg.sh signature: <ndk-path> <host-platform> <abi> [--enable-<codec>...]
# Host auto-detected if not passed; ABI names accepted: arm64, arm, x86, x86_64
# We disable everything and then selectively enable only what ALAC needs:
#   decoder: alac
#   demuxer:  mov (covers .m4a / .mp4 containers), caf
#   parser:   alac
bash build_ffmpeg.sh "$NDK_PATH" arm64 \
    --disable-everything \
    --enable-decoder=alac \
    --enable-demuxer=mov \
    --enable-demuxer=caf \
    --enable-parser=alac \
    --enable-protocol=file

echo "[2/5] FFmpeg static libs built."

# ── 3. ndk-build to produce libffmpegJNI.so ───────────────────────────────────
echo "[3/5] Running ndk-build for $TARGET_ABI..."
"$NDK_PATH/ndk-build" \
    NDK="$NDK_PATH" \
    APP_BUILD_SCRIPT="$JNI_DIR/Android.mk" \
    NDK_PROJECT_PATH=null \
    APP_ABI="$TARGET_ABI" \
    APP_OPTIM=release \
    APP_PLATFORM=android-29 \
    NDK_OUT="$TMP_DIR/obj" \
    NDK_LIBS_OUT="$TMP_DIR/libs" \
    -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

SO_SRC="$TMP_DIR/libs/$TARGET_ABI/libffmpegJNI.so"
if [ ! -f "$SO_SRC" ]; then
    echo "ERROR: ndk-build finished but libffmpegJNI.so not found at $SO_SRC"
    exit 1
fi
echo "[3/5] libffmpegJNI.so built: $(du -h "$SO_SRC" | cut -f1)"

# ── 4. Copy to jniLibs ────────────────────────────────────────────────────────
echo "[4/5] Copying to $OUTPUT_DIR/..."
mkdir -p "$OUTPUT_DIR"
cp "$SO_SRC" "$OUTPUT_DIR/libffmpegJNI.so"

# ── 5. Done ───────────────────────────────────────────────────────────────────
echo ""
echo "✓ Done! Output: $OUTPUT_DIR/libffmpegJNI.so"
echo "  Size: $(du -h "$OUTPUT_DIR/libffmpegJNI.so" | cut -f1)"
echo ""
echo "Next steps:"
echo "  1. flutter build apk --release"
echo "  2. Install on device and check the debug log for:"
echo "     Ffmpeg: available=true supported=ALAC"
