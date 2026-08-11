#!/usr/bin/env bash
# build-ffmpeg-jni.sh — FALLBACK ONLY (do not run for normal builds)
#
# ⚠️  PRODUCTION BUILD PATH: the app consumes the Jellyfin prebuilt AAR
#     (org.jellyfin.media3:media3-ffmpeg-decoder) declared in
#     android/app/build.gradle. The local :decoder-ffmpeg sub-module is NOT
#     included by android/settings.gradle and is NOT used by normal builds.
#
#     Run this script ONLY as a fallback if the Jellyfin AAR becomes
#     unavailable (see .agents/memory/ffmpeg-decoder-phase9.md). It builds
#     the Media3 FFmpeg decoder extension as a local Gradle module at
#     android/decoder-ffmpeg/ from the androidx/media source tree.
#
#     After running it you MUST manually re-wire the module before it takes
#     effect (the automated wiring was removed when the Jellyfin AAR
#     replaced it):
#       1. Add `include ":decoder-ffmpeg"` to android/settings.gradle
#       2. Replace the Jellyfin dependency in android/app/build.gradle with
#          `implementation project(':decoder-ffmpeg')`
#     Also note the module is built against media3 $MEDIA3_TAG, which may
#     differ from the app's pinned media3 version — verify on first use.
#
# Why this script exists
# ──────────────────────
# androidx.media3:media3-decoder-ffmpeg is NOT published on any public Maven
# repository. The AAR (Java/Kotlin wrapper + native libffmpegJNI.so) must be
# built from the androidx/media source tree using Android NDK.
#
# Prerequisites
# ─────────────
#   - Android NDK r25c or newer
#     Download: https://developer.android.com/ndk/downloads
#   - Java 17+ (same JDK used for the main project)
#   - git, curl, tar, make, yasm or nasm
#   - Linux or macOS host
#
# Usage
# ─────
#   bash android/build-ffmpeg-jni.sh /path/to/android-ndk-r25c
#
#   Or set ANDROID_NDK_HOME and run without args:
#   export ANDROID_NDK_HOME=/path/to/ndk
#   bash android/build-ffmpeg-jni.sh
#
# Output
# ──────
#   android/decoder-ffmpeg/          ← Gradle sub-module (gitignored)
#     build.gradle
#     libs/
#       media3-decoder-ffmpeg-release.aar  ← AAR with libffmpegJNI.so inside
#
# After the script completes, rebuild the APK:
#   flutter build apk --release
#
# To verify FFmpeg is active, check the debug log for:
#   Ffmpeg: available=true supported=ALAC

set -euo pipefail

MEDIA3_TAG="1.10.1"
TARGET_ABI="arm64-v8a"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_MODULE="$SCRIPT_DIR/decoder-ffmpeg"
TMP_DIR="${TMPDIR:-/tmp}/media3-ffmpeg-build-$MEDIA3_TAG"
REPO_DIR="$TMP_DIR/media3"

# ── 0. Resolve NDK path ───────────────────────────────────────────────────────
NDK_PATH="${1:-${ANDROID_NDK_HOME:-${ANDROID_NDK:-}}}"
if [ -z "$NDK_PATH" ] || [ ! -d "$NDK_PATH" ]; then
    echo "ERROR: Android NDK not found."
    echo ""
    echo "Usage:  bash android/build-ffmpeg-jni.sh /path/to/android-ndk-r25c"
    echo "        (or set ANDROID_NDK_HOME env var)"
    echo ""
    echo "Download NDK: https://developer.android.com/ndk/downloads"
    exit 1
fi
echo "✓ NDK: $NDK_PATH"

# ── 1. Clone androidx/media @ 1.10.1 (shallow) ───────────────────────────────
mkdir -p "$TMP_DIR"
if [ -d "$REPO_DIR/.git" ]; then
    echo "✓ Repository already cloned at $REPO_DIR"
else
    echo "[1/5] Cloning androidx/media @ $MEDIA3_TAG ..."
    git clone --depth 1 \
        --branch "$MEDIA3_TAG" \
        https://github.com/androidx/media.git \
        "$REPO_DIR"
fi

JNI_DIR="$REPO_DIR/libraries/decoder_ffmpeg/src/main/jni"
if [ ! -d "$JNI_DIR" ]; then
    echo "ERROR: JNI directory not found at $JNI_DIR"
    echo "The Media3 repo layout may have changed. Inspect the repo manually."
    exit 1
fi

# ── 2. Build FFmpeg native libs (arm64, ALAC-only) ───────────────────────────
echo "[2/5] Building FFmpeg static libs (ALAC only, $TARGET_ABI) ..."
cd "$JNI_DIR"
bash build_ffmpeg.sh "$NDK_PATH" arm64 \
    --disable-everything \
    --enable-decoder=alac \
    --enable-demuxer=mov \
    --enable-demuxer=caf \
    --enable-parser=alac \
    --enable-protocol=file

# ── 3. ndk-build → libffmpegJNI.so ───────────────────────────────────────────
echo "[3/5] ndk-build for $TARGET_ABI ..."
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
    echo "ERROR: libffmpegJNI.so not found at $SO_SRC after ndk-build"
    exit 1
fi
echo "✓ libffmpegJNI.so: $(du -h "$SO_SRC" | cut -f1)"

# ── 4. Build the AAR via Gradle ───────────────────────────────────────────────
echo "[4/5] Building Media3 FFmpeg decoder AAR via Gradle ..."
cd "$REPO_DIR"

# Copy the .so into the jniLibs location the Gradle module expects
SO_DEST="$REPO_DIR/libraries/decoder_ffmpeg/src/main/jniLibs/$TARGET_ABI/libffmpegJNI.so"
mkdir -p "$(dirname "$SO_DEST")"
cp "$SO_SRC" "$SO_DEST"

# Build the release AAR for the decoder_ffmpeg module only
./gradlew \
    :libraries:decoder_ffmpeg:assembleRelease \
    -PandroidNdkVersion="$(basename "$NDK_PATH")" \
    --no-daemon

AAR_SRC="$REPO_DIR/libraries/decoder_ffmpeg/build/outputs/aar/decoder_ffmpeg-release.aar"
if [ ! -f "$AAR_SRC" ]; then
    # Some versions use a different output name; try to find it
    AAR_SRC="$(find "$REPO_DIR/libraries/decoder_ffmpeg/build/outputs/aar" -name '*release*.aar' 2>/dev/null | head -1)"
fi
if [ -z "$AAR_SRC" ] || [ ! -f "$AAR_SRC" ]; then
    echo "ERROR: release AAR not found after Gradle build."
    echo "Check output of 'assembleRelease' above for errors."
    exit 1
fi
echo "✓ AAR: $(du -h "$AAR_SRC" | cut -f1)"

# ── 5. Assemble the local Gradle module ───────────────────────────────────────
echo "[5/5] Writing android/decoder-ffmpeg/ local module ..."
mkdir -p "$OUTPUT_MODULE/libs"
cp "$AAR_SRC" "$OUTPUT_MODULE/libs/media3-decoder-ffmpeg-release.aar"

# Minimal build.gradle for the wrapper module
cat > "$OUTPUT_MODULE/build.gradle" << 'GRADLE'
// android/decoder-ffmpeg/build.gradle
//
// Thin wrapper that exposes the locally-built media3-decoder-ffmpeg AAR
// (with libffmpegJNI.so embedded) as a Gradle project dependency.
// Generated by android/build-ffmpeg-jni.sh — do not edit manually.
configurations.maybeCreate("default")
artifacts.add("default", file("libs/media3-decoder-ffmpeg-release.aar"))
GRADLE

echo ""
echo "✓ Done!  android/decoder-ffmpeg/ is ready."
echo "  AAR size: $(du -h "$OUTPUT_MODULE/libs/media3-decoder-ffmpeg-release.aar" | cut -f1)"
echo ""
echo "⚠️  FALLBACK MODULE — not wired into the build by default."
echo "Next steps (manual, required):"
echo "  1. Add include \":decoder-ffmpeg\" to android/settings.gradle"
echo "  2. Replace the Jellyfin AAR dependency in android/app/build.gradle"
echo "     with: implementation project(':decoder-ffmpeg')"
echo "  3. flutter build apk --release"
echo ""
echo "Verify in the debug log:"
echo "  Ffmpeg: available=true supported=ALAC"
