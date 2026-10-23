#!/usr/bin/env bash
# build-ffmpeg-jni.sh — builds the LGPL Media3 FFmpeg decoder extension AAR.
#
# This script is the ONLY supported source of `libffmpegJNI.so` for this app.
# The community prebuilt `org.jellyfin.media3:media3-ffmpeg-decoder` is declared
# GPL-3.0 by its publisher, which conflicts with this repository's
# "All Rights Reserved" LICENSE. We therefore build the Apache-2.0 Media3
# `decoder_ffmpeg` wrapper ourselves against an FFmpeg configured WITHOUT any
# GPL / version3 / nonfree component. See docs/FFMPEG_DECODER_LGPL.md.
#
# What it produces
# ────────────────
#   android/decoder-ffmpeg/libs/media3-decoder-ffmpeg-release.aar
#       Media3 <MEDIA3_TAG> `decoder_ffmpeg` wrapper + libffmpegJNI.so built
#       from FFmpeg <FFMPEG_BRANCH>. The AAR is committed so release builds
#       stay reproducible without an NDK; `abiFilters "arm64-v8a"` in
#       android/app/build.gradle drops every ABI except arm64.
#
#   build/ffmpeg-decoder-lgpl/
#       LGPL compliance bundle: FFmpeg source tarball, wrapper source tarball,
#       LGPL v2.1 + Apache-2.0 license texts, the upstream build script and a
#       BUILD_INFO.txt with exact revisions/decoders/AAR checksum. Attach this
#       bundle to every release that ships the AAR.
#
# Prerequisites
# ─────────────
#   - Android NDK r26+ (tested configuration upstream; the repo pins
#     28.2.13676358 for the app build — any r26+ works here)
#   - Android SDK with CMake 3.21+ (needed by the wrapper's CMake build)
#   - JDK 17+ (JDK 21, same as the app build)
#   - git, make, tar, curl
#   - Linux or macOS host
#
# Usage
# ─────
#   bash android/build-ffmpeg-jni.sh /path/to/ndk/28.2.13676358
#
#   Or set ANDROID_NDK_HOME and run without arguments:
#     export ANDROID_NDK_HOME=/path/to/ndk
#     bash android/build-ffmpeg-jni.sh
#
# Overrides (env vars)
# ────────────────────
#   MEDIA3_TAG     androidx/media tag to build (default 1.11.1, must match
#                  media3_version in android/app/build.gradle)
#   FFMPEG_BRANCH  FFmpeg branch to build (default release/6.0, the branch
#                  Media3 1.11.1 is tested against)
#   ANDROID_API    API level for the native code (default 27 = app minSdk)
#   DECODERS       space-separated FFmpeg decoder names to enable
#                  (default "alac dca mlp truehd vorbis opus")
#
# After the script completes, rebuild the APK:
#   flutter build apk --release
#
# Verify on device (debug log):
#   Ffmpeg: available=true supported=ALAC

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MEDIA3_TAG="${MEDIA3_TAG:-1.11.1}"
FFMPEG_BRANCH="${FFMPEG_BRANCH:-release/6.0}"
ANDROID_API="${ANDROID_API:-27}"
# Formato yang tidak punya decoder MediaCodec yang layak di perangkat target.
# Semuanya tersedia di FFmpeg tanpa komponen GPL.
# shellcheck disable=SC2206
DECODERS=(${DECODERS:-alac dca mlp truehd vorbis opus})

TMP_DIR="${TMPDIR:-/tmp}/musicplayer-ffmpeg-decoder-$MEDIA3_TAG"
MEDIA3_DIR="$TMP_DIR/media3"
FFMPEG_MODULE_PATH="$MEDIA3_DIR/libraries/decoder_ffmpeg/src/main"
JNI_DIR="$FFMPEG_MODULE_PATH/jni"
OUT_AAR="$ROOT/android/decoder-ffmpeg/libs/media3-decoder-ffmpeg-release.aar"
COMPLIANCE_DIR="$ROOT/build/ffmpeg-decoder-lgpl"

# ── 0. Resolve NDK + SDK ─────────────────────────────────────────────────────
NDK_PATH="${1:-${ANDROID_NDK_HOME:-${ANDROID_NDK:-}}}"
if [ -z "$NDK_PATH" ] || [ ! -d "$NDK_PATH" ]; then
    echo "ERROR: Android NDK not found."
    echo ""
    echo "Usage:  bash android/build-ffmpeg-jni.sh /path/to/ndk"
    echo "        (or set ANDROID_NDK_HOME env var)"
    echo ""
    echo "Download NDK: https://developer.android.com/ndk/downloads"
    exit 1
fi
echo "✓ NDK: $NDK_PATH"

SDK_DIR="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$SDK_DIR" ] || [ ! -d "$SDK_DIR" ]; then
    # NDK usually lives inside the SDK; derive it when the env var is unset.
    SDK_DIR="$(cd "$NDK_PATH/../.." 2>/dev/null && pwd || true)"
fi
if [ -z "$SDK_DIR" ] || [ ! -d "$SDK_DIR" ]; then
    echo "ERROR: Android SDK not found. Set ANDROID_SDK_ROOT/ANDROID_HOME."
    exit 1
fi
echo "✓ SDK: $SDK_DIR"

HOST_PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
if [ ! -d "$NDK_PATH/toolchains/llvm/prebuilt/$HOST_PLATFORM" ]; then
    HOST_PLATFORM="$(ls "$NDK_PATH/toolchains/llvm/prebuilt" | head -1)"
fi
if [ -z "$HOST_PLATFORM" ]; then
    echo "ERROR: no LLVM toolchain found under $NDK_PATH/toolchains/llvm/prebuilt"
    exit 1
fi
echo "✓ Host toolchain: $HOST_PLATFORM"

# ── 1. Checkout the pinned androidx/media source ─────────────────────────────
mkdir -p "$TMP_DIR"
if [ -d "$MEDIA3_DIR/.git" ]; then
    echo "✓ Reusing checkout at $MEDIA3_DIR"
    git -C "$MEDIA3_DIR" fetch --depth 1 origin "refs/tags/$MEDIA3_TAG:refs/tags/$MEDIA3_TAG"
    git -C "$MEDIA3_DIR" checkout -f "$MEDIA3_TAG"
else
    echo "[1/5] Cloning androidx/media @ $MEDIA3_TAG ..."
    git clone --depth 1 --branch "$MEDIA3_TAG" \
        https://github.com/androidx/media.git "$MEDIA3_DIR"
fi

if [ ! -d "$JNI_DIR" ]; then
    echo "ERROR: JNI directory not found at $JNI_DIR"
    echo "The Media3 repo layout may have changed. Inspect the repo manually."
    exit 1
fi

# ── 2. FFmpeg source (pinned branch) ─────────────────────────────────────────
echo "[2/5] FFmpeg $FFMPEG_BRANCH ..."
# This script passes the Media3 1.11.x build_ffmpeg.sh argument order
# (<module-path> <ndk> <host> <api> <decoder...>). Older tags used a different
# one; fail early instead of letting configure run against the wrong paths.
if ! grep -q 'FFMPEG_MODULE_PATH="\$1"' "$JNI_DIR/build_ffmpeg.sh"; then
    echo "ERROR: $JNI_DIR/build_ffmpeg.sh has an unexpected argument order."
    echo "This script targets the Media3 1.11.x build_ffmpeg.sh signature."
    echo "Inspect the tag or adapt the invocation before continuing."
    exit 1
fi

if [ ! -d "$JNI_DIR/ffmpeg" ]; then
    git clone --depth 1 --branch "$FFMPEG_BRANCH" \
        https://github.com/FFmpeg/FFmpeg.git "$JNI_DIR/ffmpeg"
fi
FFMPEG_REV="$(git -C "$JNI_DIR/ffmpeg" rev-parse HEAD)"

# ── 3. Build FFmpeg static libs (all ABIs, upstream script) ──────────────────
# Upstream builds armeabi-v7a, arm64-v8a, x86 and x86_64 in one pass and the
# wrapper's CMake project links whichever ABIs Gradle asks for — building all
# four keeps `assembleRelease` working without patching the upstream module.
# x86/x86_64 are configured with --disable-asm, so no nasm/yasm is required.
# No --enable-gpl / --enable-version3 / --enable-nonfree flag exists in
# build_ffmpeg.sh: the result is LGPL. Step 4 verifies this in config.h.
echo "[3/5] Building FFmpeg static libs for API $ANDROID_API (decoders: ${DECODERS[*]}) ..."
(
    cd "$JNI_DIR"
    bash build_ffmpeg.sh \
        "$FFMPEG_MODULE_PATH" \
        "$NDK_PATH" \
        "$HOST_PLATFORM" \
        "$ANDROID_API" \
        "${DECODERS[@]}"
)

# ── 3b. License guard: refuse to package a GPL/version3/nonfree build ────────
CONFIG_H="$JNI_DIR/ffmpeg/config.h"
if [ ! -f "$CONFIG_H" ]; then
    echo "ERROR: $CONFIG_H missing after configure — FFmpeg build did not run."
    exit 1
fi
for flag in GPL VERSION3 NONFREE; do
    if grep -qE "^#define CONFIG_${flag} 1" "$CONFIG_H"; then
        echo "ERROR: FFmpeg was configured with CONFIG_${flag}=1."
        echo "This AAR must stay LGPL; refusing to produce a redistributable artifact."
        exit 1
    fi
done
for decoder in "${DECODERS[@]}"; do
    upper="$(printf '%s' "$decoder" | tr '[:lower:]' '[:upper:]')"
    if ! grep -qE "^#define CONFIG_${upper}_DECODER 1" "$CONFIG_H"; then
        echo "ERROR: decoder '$decoder' is not enabled in the FFmpeg build."
        exit 1
    fi
done
echo "✓ License guard: CONFIG_GPL/VERSION3/NONFREE are all 0; requested decoders enabled"

# ── 4. Build the wrapper AAR (CMake/JNI + jniLibs packaging) ─────────────────
echo "[4/5] Building :libraries:decoder_ffmpeg:assembleRelease ..."
cat > "$MEDIA3_DIR/local.properties" <<EOF
sdk.dir=$SDK_DIR
ndk.dir=$NDK_PATH
EOF

(
    cd "$MEDIA3_DIR"
    ./gradlew :libraries:decoder_ffmpeg:assembleRelease \
        --no-daemon --console=plain
)

AAR_SRC="$MEDIA3_DIR/libraries/decoder_ffmpeg/build/outputs/aar/decoder_ffmpeg-release.aar"
if [ ! -f "$AAR_SRC" ]; then
    AAR_SRC="$(find "$MEDIA3_DIR/libraries/decoder_ffmpeg/build/outputs/aar" \
        -name '*release*.aar' 2>/dev/null | head -1)"
fi
if [ -z "$AAR_SRC" ] || [ ! -f "$AAR_SRC" ]; then
    echo "ERROR: release AAR not found after Gradle build."
    echo "Check the output of 'assembleRelease' above for errors."
    exit 1
fi

mkdir -p "$(dirname "$OUT_AAR")"
cp "$AAR_SRC" "$OUT_AAR"
echo "✓ AAR: $OUT_AAR ($(du -h "$OUT_AAR" | cut -f1))"

# ── 5. LGPL compliance bundle ────────────────────────────────────────────────
echo "[5/5] Writing LGPL compliance bundle ..."
rm -rf "$COMPLIANCE_DIR"
mkdir -p "$COMPLIANCE_DIR"

tar -czf "$COMPLIANCE_DIR/ffmpeg-$FFMPEG_BRANCH.tar.gz" \
    -C "$JNI_DIR" \
    --exclude='ffmpeg/.git' \
    --exclude='ffmpeg/android-libs' \
    --exclude='ffmpeg/**/*.o' \
    --exclude='ffmpeg/**/*.a' \
    ffmpeg

tar -czf "$COMPLIANCE_DIR/media3-decoder_ffmpeg-$MEDIA3_TAG.tar.gz" \
    -C "$MEDIA3_DIR/libraries" \
    --exclude='decoder_ffmpeg/build' \
    decoder_ffmpeg

cp "$JNI_DIR/ffmpeg/COPYING.LGPLv2.1" "$COMPLIANCE_DIR/COPYING.LGPLv2.1"
cp "$MEDIA3_DIR/LICENSE" "$COMPLIANCE_DIR/LICENSE.Apache-2.0"
cp "$JNI_DIR/build_ffmpeg.sh" "$COMPLIANCE_DIR/build_ffmpeg.sh"

NDK_REVISION="$(sed -n 's/^Pkg\.Revision *= *//p' "$NDK_PATH/source.properties" 2>/dev/null || echo unknown)"
AAR_SHA256="$(sha256sum "$OUT_AAR" | cut -d' ' -f1)"
cat > "$COMPLIANCE_DIR/BUILD_INFO.txt" <<EOF
FFmpeg decoder extension — build provenance
===========================================

Built at      : $(date -u +'%Y-%m-%dT%H:%M:%SZ')
Media3 tag    : $MEDIA3_TAG (androidx/media libraries/decoder_ffmpeg, Apache-2.0)
FFmpeg branch : $FFMPEG_BRANCH
FFmpeg commit : $FFMPEG_REV (LGPL v2.1+, no GPL/version3/nonfree components)
Decoders      : ${DECODERS[*]}
Android API   : $ANDROID_API
NDK           : $NDK_PATH (r$NDK_REVISION)
Host          : $HOST_PLATFORM

Artifact      : android/decoder-ffmpeg/libs/media3-decoder-ffmpeg-release.aar
SHA-256       : $AAR_SHA256
Contains      : Media3 decoder_ffmpeg wrapper classes (Apache-2.0) and
                libffmpegJNI.so for armeabi-v7a/arm64-v8a/x86/x86_64, which
                statically includes the FFmpeg libraries listed above.

How to relink / rebuild
-----------------------
1. Extract ffmpeg-$FFMPEG_BRANCH.tar.gz into
   libraries/decoder_ffmpeg/src/main/jni/ffmpeg of the same Media3 tag.
2. Run this repository's android/build-ffmpeg-jni.sh with the same
   MEDIA3_TAG / FFMPEG_BRANCH / ANDROID_API / DECODERS values.
   The script invokes media3-decoder_ffmpeg-$MEDIA3_TAG.tar.gz's
   build_ffmpeg.sh (also bundled) and then assembles the AAR.

The FFmpeg components in this artifact are licensed under LGPL v2.1 or later
(COPYING.LGPLv2.1). The wrapper is Apache-2.0 (LICENSE.Apache-2.0). No GPL,
version3 or nonfree component is enabled (verified from config.h at build
time).
EOF

echo ""
echo "✓ Done."
echo "  AAR        : $OUT_AAR"
echo "  Compliance : $COMPLIANCE_DIR"
echo ""
echo "Next steps:"
echo "  1. Commit android/decoder-ffmpeg/libs/media3-decoder-ffmpeg-release.aar"
echo "     so release builds do not need an NDK."
echo "  2. Attach the compliance bundle to the release that ships this APK"
echo "     (LGPL obligation — see docs/FFMPEG_DECODER_LGPL.md)."
echo "  3. flutter build apk --release"
echo ""
echo "Verify in the debug log:"
echo "  Ffmpeg: available=true supported=ALAC"
