#!/usr/bin/env bash
# build-apk.sh — Setup Android env + download cmake 3.22.1 + flutter build apk
# Jalankan via workflow: bash setup-flutter.sh && bash build-apk.sh
#
# Requires (sudah ada atau di-install oleh setup-flutter.sh):
#   - /home/runner/flutter/             (Flutter 3.44.5)
#   - /home/runner/workspace/jdk17/     (JDK 17 Temurin x64)
#   - /home/runner/android-sdk/         (Android SDK, NDK 28.2.13676358, build-tools 36.0.0)

set -e

# Redirect HOME ke workspace — /home/runner/ quota penuh, Dart tools
# mencoba tulis ke $HOME/.dart-tool/, $HOME/.config/flutter/, $HOME/.gradle/
# yang semuanya ada di /home/runner/ dan tidak bisa ditulis.
# PUB_CACHE tetap ke /home/runner/.pub-cache/ agar packages tidak re-download.
export HOME="/home/runner/workspace"
export PUB_CACHE="/home/runner/.pub-cache"
export GRADLE_USER_HOME="/home/runner/workspace/.gradle"
export FLUTTER_SUPPRESS_ANALYTICS=true
export DART_SUPPRESS_ANALYTICS=true
# /tmp hanya 4MB — redirect semua temp files ke workspace
mkdir -p "/home/runner/workspace/tmp"
export TMPDIR="/home/runner/workspace/tmp"
export TEMP="/home/runner/workspace/tmp"
export TMP="/home/runner/workspace/tmp"
# JVM juga perlu diarahkan ke workspace tmp
export _JAVA_OPTIONS="-Djava.io.tmpdir=/home/runner/workspace/tmp -Duser.home=/home/runner/workspace"

ANDROID_HOME_DIR="/home/runner/android-sdk"
FLUTTER_DIR="/home/runner/workspace/flutter-ws"   # workspace copy — bisa tulis ke bin/cache/
JDK_DIR="/home/runner/workspace/jdk17"
NDK_VERSION="28.2.13676358"
CMAKE_VERSION="3.22.1"
CMAKE_DIR="/home/runner/workspace/cmake-$CMAKE_VERSION"
# cmake.org prebuilt tarball — berisi bin/cmake + bin/ninja
CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"
LOCAL_PROPS="$(dirname "$0")/android/local.properties"

# ──────────────────────────────────────────────────
# 1. Flutter PATH
# ──────────────────────────────────────────────────
export PATH="$FLUTTER_DIR/bin:$PATH"
echo "✓ Flutter: $("$FLUTTER_DIR/bin/flutter" --version 2>/dev/null | head -1)"

# ──────────────────────────────────────────────────
# 2. Java — JDK 17 Temurin
# ──────────────────────────────────────────────────
if [ ! -f "$JDK_DIR/bin/java" ]; then
  echo "✗ ERROR: $JDK_DIR/bin/java tidak ditemukan."
  echo "  Jalankan: bash setup-flutter.sh  terlebih dahulu."
  exit 1
fi
export JAVA_HOME="$JDK_DIR"
export PATH="$JAVA_HOME/bin:$PATH"
echo "✓ Java: $(java -version 2>&1 | head -1)"
echo "  JAVA_HOME=$JAVA_HOME"

# ──────────────────────────────────────────────────
# 3. Android SDK / NDK PATH
# ──────────────────────────────────────────────────
export ANDROID_HOME="$ANDROID_HOME_DIR"
export ANDROID_SDK_ROOT="$ANDROID_HOME_DIR"
export PATH="$ANDROID_HOME_DIR/cmdline-tools/latest/bin:$ANDROID_HOME_DIR/platform-tools:$PATH"
echo "✓ ANDROID_HOME=$ANDROID_HOME"
echo "✓ NDK: $NDK_VERSION $([ -d "$ANDROID_HOME_DIR/ndk/$NDK_VERSION" ] && echo '(ada)' || echo '(TIDAK ADA!)')"

# ──────────────────────────────────────────────────
# 4a. NDK 28.2.13676358 (r28c) — download ke workspace
#     NDK di /home/runner/android-sdk/ndk/28.2.13676358 kosong (tidak terdownload).
#     /home/runner/ quota penuh, jadi download ke workspace.
#     Gradle diarahkan via ndk.dir di local.properties.
# ──────────────────────────────────────────────────
NDK_VERSION="28.2.13676358"
NDK_DIR="/home/runner/workspace/ndk/$NDK_VERSION"
NDK_URL="https://dl.google.com/android/repository/android-ndk-r28c-linux.zip"

if [ -f "$NDK_DIR/source.properties" ]; then
  echo "✓ NDK $NDK_VERSION sudah ada di workspace"
else
  echo "▶ Mengunduh NDK r28c ($NDK_VERSION) ke workspace (~1.3GB)..."
  mkdir -p /home/runner/workspace/ndk
  cd /home/runner/workspace/ndk
  curl -# -L "$NDK_URL" -o ndk_r28c.zip
  echo "Extracting NDK..."
  unzip -q ndk_r28c.zip
  rm ndk_r28c.zip
  # Folder hasil extract biasanya android-ndk-r28c
  NDK_EXTRACTED=$(ls -d /home/runner/workspace/ndk/android-ndk-r28c 2>/dev/null | head -1)
  if [ -n "$NDK_EXTRACTED" ]; then
    mv "$NDK_EXTRACTED" "$NDK_DIR"
    echo "✓ NDK r28c berhasil diinstall di $NDK_DIR"
    echo "  $(cat "$NDK_DIR/source.properties" | grep Pkg.Revision)"
  else
    echo "✗ Gagal extract NDK" && exit 1
  fi
fi

# Arahkan Gradle ke NDK workspace via local.properties
if grep -q "^ndk.dir=" "$LOCAL_PROPS" 2>/dev/null; then
  sed -i "s|^ndk.dir=.*|ndk.dir=$NDK_DIR|" "$LOCAL_PROPS"
else
  echo "ndk.dir=$NDK_DIR" >> "$LOCAL_PROPS"
fi
echo "✓ local.properties: ndk.dir=$NDK_DIR"

# ──────────────────────────────────────────────────
# 4b. cmake 3.22.1 — download langsung dari cmake.org ke workspace
#    (sdkmanager tidak bisa dipakai: SDK XML v4 + /home/runner/ quota penuh)
#    Gradle diarahkan via cmake.dir di local.properties
# ──────────────────────────────────────────────────
if [ -f "$CMAKE_DIR/bin/cmake" ]; then
  echo "✓ cmake $CMAKE_VERSION sudah ada di $CMAKE_DIR"
else
  echo "▶ Mengunduh cmake $CMAKE_VERSION dari cmake.org..."
  cd /home/runner/workspace
  curl -# -L "$CMAKE_URL" -o cmake_tmp.tar.gz
  echo "Extracting..."
  tar -xzf cmake_tmp.tar.gz
  rm cmake_tmp.tar.gz
  EXTRACTED=$(ls -d /home/runner/workspace/cmake-${CMAKE_VERSION}-linux-x86_64 2>/dev/null | head -1)
  if [ -n "$EXTRACTED" ]; then
    mv "$EXTRACTED" "$CMAKE_DIR"
    echo "✓ cmake $CMAKE_VERSION berhasil diinstall di $CMAKE_DIR"
  else
    echo "✗ Gagal extract cmake — folder tidak ditemukan" && exit 1
  fi
fi
export PATH="$CMAKE_DIR/bin:$PATH"

# ──────────────────────────────────────────────────
# 5. Arahkan Gradle ke cmake via local.properties
# ──────────────────────────────────────────────────
if grep -q "^cmake.dir=" "$LOCAL_PROPS" 2>/dev/null; then
  # Update nilai yang sudah ada
  sed -i "s|^cmake.dir=.*|cmake.dir=$CMAKE_DIR|" "$LOCAL_PROPS"
else
  echo "cmake.dir=$CMAKE_DIR" >> "$LOCAL_PROPS"
fi
echo "✓ local.properties: cmake.dir=$CMAKE_DIR"

# ──────────────────────────────────────────────────
# 6. Ringkasan env sebelum build
# ──────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo " Environment check"
echo "══════════════════════════════════════════════"
echo "  flutter : $(which flutter)"
echo "  java    : $(which java)"
echo "  cmake   : $CMAKE_DIR/bin/cmake [$(cmake --version 2>/dev/null | head -1)]"
echo "  ninja   : $CMAKE_DIR/bin/ninja"
echo ""

# ──────────────────────────────────────────────────
# 7. flutter doctor (singkat)
# ──────────────────────────────────────────────────
echo "══════════════════════════════════════════════"
echo " flutter doctor"
echo "══════════════════════════════════════════════"
flutter doctor 2>&1 || true

# ──────────────────────────────────────────────────
# 8. flutter build apk --debug
# ──────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo " flutter build apk --debug"
echo "══════════════════════════════════════════════"
flutter build apk --debug 2>&1
echo ""
echo "✓ Build selesai!"
ls -lh build/app/outputs/flutter-apk/*.apk 2>/dev/null || true
