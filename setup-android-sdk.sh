#!/usr/bin/env bash
# setup-android-sdk.sh
# Install Android SDK (API 30 / build-tools 30.0.3) ke /home/runner/android-sdk/
# kalau belum ada. Idempotent — aman dipanggil berulang kali.
# Jalankan: bash setup-android-sdk.sh

set -e

SDK_ROOT="/home/runner/android-sdk"
CMDLINE_VERSION="11076708"
CMDLINE_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_VERSION}_latest.zip"
PLATFORM="android-30"
BUILD_TOOLS="30.0.3"

SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

if [ -x "$SDKMANAGER" ] && [ -d "$SDK_ROOT/platforms/$PLATFORM" ] && [ -d "$SDK_ROOT/build-tools/$BUILD_TOOLS" ]; then
  echo "✓ Android SDK sudah terinstall di $SDK_ROOT (platform $PLATFORM, build-tools $BUILD_TOOLS)"
  exit 0
fi

echo "Android SDK tidak lengkap, menyiapkan di $SDK_ROOT ..."
mkdir -p "$SDK_ROOT/cmdline-tools"
cd "$SDK_ROOT/cmdline-tools"

if [ ! -x "$SDKMANAGER" ]; then
  echo "Mengunduh Android command-line tools..."
  curl -# -L "$CMDLINE_URL" -o cmdline-tools.zip
  rm -rf tmp_extract latest
  mkdir -p tmp_extract
  unzip -q cmdline-tools.zip -d tmp_extract
  # Zip mengekstrak ke folder "cmdline-tools/" — pindahkan isinya jadi "latest/"
  mv tmp_extract/cmdline-tools latest
  rm -rf tmp_extract cmdline-tools.zip
fi

export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(which java)")")")}"

echo "Menerima semua lisensi SDK..."
yes | "$SDKMANAGER" --sdk_root="$SDK_ROOT" --licenses > /dev/null 2>&1 || true

echo "Menginstall platform-tools, platforms;$PLATFORM, build-tools;$BUILD_TOOLS ..."
"$SDKMANAGER" --sdk_root="$SDK_ROOT" \
  "platform-tools" \
  "platforms;$PLATFORM" \
  "build-tools;$BUILD_TOOLS" \
  > /dev/null

echo ""
echo "✓ Android SDK berhasil diinstall di $SDK_ROOT"
echo "  ANDROID_HOME=$SDK_ROOT"
echo "  Platform: $PLATFORM, Build-tools: $BUILD_TOOLS"
