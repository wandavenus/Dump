#!/usr/bin/env bash
set -euo pipefail

EXPECTED_NDK_VERSION="28.2.13676358"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

if [ ! -x "$SDKMANAGER" ]; then
    SDKMANAGER="$(find "$SDK_ROOT/cmdline-tools" -type f -path '*/bin/sdkmanager' 2>/dev/null | sort -V | tail -n 1)"
fi
if [ -z "$SDKMANAGER" ] || [ ! -x "$SDKMANAGER" ]; then
    SDKMANAGER="$(command -v sdkmanager || true)"
fi
if [ -z "$SDKMANAGER" ] || [ ! -x "$SDKMANAGER" ]; then
    echo "ERROR: sdkmanager not found; Android SDK root was '$SDK_ROOT'." >&2
    exit 1
fi

# Hosted runners generally pre-accept Android licenses. Attempt acceptance in
# case the runner image changes; installation below remains the hard failure.
yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
"$SDKMANAGER" --install "ndk;$EXPECTED_NDK_VERSION"

NDK_DIR="$SDK_ROOT/ndk/$EXPECTED_NDK_VERSION"
if [ ! -f "$NDK_DIR/source.properties" ]; then
    echo "ERROR: NDK installation did not create $NDK_DIR/source.properties." >&2
    exit 1
fi
ACTUAL_NDK_VERSION="$(sed -n 's/^Pkg.Revision *= *//p' "$NDK_DIR/source.properties" | head -n 1)"
if [ "$ACTUAL_NDK_VERSION" != "$EXPECTED_NDK_VERSION" ]; then
    echo "ERROR: expected NDK $EXPECTED_NDK_VERSION, found '${ACTUAL_NDK_VERSION:-unknown}'." >&2
    exit 1
fi
echo "Android NDK $ACTUAL_NDK_VERSION ready at $NDK_DIR."
