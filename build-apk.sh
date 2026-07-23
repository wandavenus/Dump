#!/usr/bin/env bash
# build-apk.sh — Setup Android env lengkap + flutter build apk
# Jalankan via workflow: bash setup-flutter.sh && bash build-apk.sh
#
# Yang di-install otomatis jika belum ada:
#   - /home/runner/workspace/jdk17/              (JDK 17 Temurin x64)  ← oleh setup-flutter.sh
#   - /home/runner/workspace/android-sdk/        (Android SDK: platform-36, build-tools 36.0.0, platform-tools)
#   - /home/runner/workspace/ndk/28.2.13676358/  (NDK r28c — includes clang arm64)
#   - /home/runner/workspace/cmake-3.22.1/       (CMake + Ninja prebuilt)

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# ──────────────────────────────────────────────────
# 0. Redirect HOME & tmp → workspace
#    /home/runner/ quota penuh; Dart/Gradle/JVM
#    semuanya mencoba tulis ke $HOME.
# ──────────────────────────────────────────────────
export HOME="/home/runner/workspace"
export PUB_CACHE="/home/runner/.pub-cache"
export GRADLE_USER_HOME="/home/runner/workspace/.gradle"
export FLUTTER_SUPPRESS_ANALYTICS=true
export DART_SUPPRESS_ANALYTICS=true
mkdir -p "/home/runner/workspace/tmp"
export TMPDIR="/home/runner/workspace/tmp"
export TEMP="/home/runner/workspace/tmp"
export TMP="/home/runner/workspace/tmp"
export _JAVA_OPTIONS="-Djava.io.tmpdir=/home/runner/workspace/tmp -Duser.home=/home/runner/workspace"

ANDROID_SDK_DIR="/home/runner/workspace/android-sdk"
FLUTTER_DIR="/home/runner/workspace/flutter-ws/flutter"
JDK_DIR="/home/runner/workspace/jdk17"
NDK_VERSION="28.2.13676358"
NDK_DIR="/home/runner/workspace/ndk/$NDK_VERSION"   # definisikan di atas agar export tersedia lebih awal
CMAKE_VERSION="3.22.1"
CMAKE_DIR="/home/runner/workspace/cmake-$CMAKE_VERSION"
CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"
LOCAL_PROPS="$PROJECT_ROOT/android/local.properties"

# ──────────────────────────────────────────────────
# 1. Flutter PATH
# ──────────────────────────────────────────────────
export PATH="$FLUTTER_DIR/bin:$PATH"
if [ ! -x "$FLUTTER_DIR/bin/flutter" ] || [ ! -f "$FLUTTER_DIR/bin/internal/shared.sh" ]; then
  echo "✗ ERROR: Flutter workspace copy tidak lengkap: $FLUTTER_DIR"
  echo "  Jalankan bash setup-flutter.sh untuk membuat ulang copy secara atomik."
  exit 1
fi
echo "✓ Flutter: $("$FLUTTER_DIR/bin/flutter" --version 2>/dev/null | head -1)"

# ──────────────────────────────────────────────────
# 2. Java — JDK 17 Temurin
# ──────────────────────────────────────────────────
if [ ! -x "$JDK_DIR/bin/java" ] || [ ! -f "$JDK_DIR/lib/jli/libjli.so" ] || ! "$JDK_DIR/bin/java" -version >/dev/null 2>&1; then
  JDK_CANDIDATE="/nix/store/bk2hgshkd3a9v4hrs9gjmxfkzvflgydx-openjdk-17.0.15+6"
  if [ -z "$JDK_CANDIDATE" ]; then
    echo "✗ ERROR: JDK 17 tervalidasi tidak ditemukan."
    exit 1
  fi
  if [ ! -x "$JDK_CANDIDATE/bin/java" ] || ! "$JDK_CANDIDATE/bin/java" -version >/dev/null 2>&1; then
    echo "✗ ERROR: JDK fallback tidak bisa dijalankan: $JDK_CANDIDATE"
    exit 1
  fi
  JDK_DIR="$JDK_CANDIDATE"
  echo "⚠ Memakai JDK fallback: $JDK_DIR"
fi
export JAVA_HOME="$JDK_DIR"
export PATH="$JAVA_HOME/bin:$PATH"
echo "✓ Java: $(java -version 2>&1 | head -1)"

# ──────────────────────────────────────────────────
# 3. Android SDK — cmdline-tools + komponen
# ──────────────────────────────────────────────────
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
SDKMANAGER="$ANDROID_SDK_DIR/cmdline-tools/latest/bin/sdkmanager"

if [ -f "$SDKMANAGER" ]; then
  echo "✓ Android cmdline-tools sudah ada"
else
  echo "▶ Mengunduh Android cmdline-tools (~135 MB)..."
  mkdir -p "$ANDROID_SDK_DIR/cmdline-tools"
  cd "$PROJECT_ROOT"
  curl -# -L "$CMDLINE_TOOLS_URL" -o cmdline_tools.zip
  echo "Extracting cmdline-tools..."
  unzip -q cmdline_tools.zip -d "$ANDROID_SDK_DIR/cmdline-tools"
  # Google mengemas sebagai 'cmdline-tools/', sdkmanager butuh dir bernama 'latest'
  mv "$ANDROID_SDK_DIR/cmdline-tools/cmdline-tools" "$ANDROID_SDK_DIR/cmdline-tools/latest"
  rm cmdline_tools.zip
  echo "✓ Android cmdline-tools berhasil diinstall"
fi

export ANDROID_HOME="$ANDROID_SDK_DIR"
export ANDROID_SDK_ROOT="$ANDROID_SDK_DIR"
export PATH="$ANDROID_SDK_DIR/cmdline-tools/latest/bin:$ANDROID_SDK_DIR/platform-tools:$PATH"

# Install SDK components yang belum ada
NEED_INSTALL=false
[ ! -d "$ANDROID_SDK_DIR/platforms/android-36" ]      && NEED_INSTALL=true
[ ! -d "$ANDROID_SDK_DIR/build-tools/36.0.0" ]        && NEED_INSTALL=true
[ ! -f "$ANDROID_SDK_DIR/platform-tools/adb" ]        && NEED_INSTALL=true

if [ "$NEED_INSTALL" = "true" ]; then
  echo "▶ Menerima lisensi Android SDK..."
  yes | "$SDKMANAGER" --sdk_root="$ANDROID_SDK_DIR" --licenses > /dev/null 2>&1 || true

  echo "▶ Menginstall: platform-tools, platforms;android-36, build-tools;36.0.0"
  echo "  (download ~300 MB, harap tunggu...)"
  "$SDKMANAGER" --sdk_root="$ANDROID_SDK_DIR" \
    "platform-tools" \
    "platforms;android-36" \
    "build-tools;36.0.0"
  echo "✓ Android SDK components berhasil diinstall"
else
  echo "✓ Android SDK components sudah ada (platform-36, build-tools 36.0.0, platform-tools)"
fi

# ──────────────────────────────────────────────────
# 4. NDK 28.2.13676358 (r28c) — clang arm64 ada di dalamnya
# ──────────────────────────────────────────────────
NDK_DIR="/home/runner/workspace/ndk/$NDK_VERSION"
NDK_URL="https://dl.google.com/android/repository/android-ndk-r28c-linux.zip"

if [ -f "$NDK_DIR/source.properties" ]; then
  echo "✓ NDK $NDK_VERSION sudah ada"
else
  echo "▶ Mengunduh NDK r28c (~1.3 GB)..."
  mkdir -p /home/runner/workspace/ndk
  cd "$PROJECT_ROOT"
  cd /home/runner/workspace/ndk
  curl -# -L "$NDK_URL" -o ndk_r28c.zip
  echo "Extracting NDK (besar, ~2 menit)..."
  unzip -q ndk_r28c.zip
  rm ndk_r28c.zip
  NDK_EXTRACTED=$(ls -d /home/runner/workspace/ndk/android-ndk-r28c 2>/dev/null | head -1)
  if [ -n "$NDK_EXTRACTED" ]; then
    mv "$NDK_EXTRACTED" "$NDK_DIR"
    echo "✓ NDK r28c berhasil diinstall"
    echo "  clang: $NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
  else
    echo "✗ Gagal extract NDK" && exit 1
  fi
fi

# NDK env vars — dibutuhkan oleh Dart native_toolchain_c (hook/build.dart).
# Didefinisikan SETELAH NDK terverifikasi/terdownload agar nilainya pasti valid.
# native_toolchain_c mencari NDK via ANDROID_HOME (Glob ndk/*/),
# lalu ANDROID_NDK / ANDROID_NDK_HOME / ANDROID_NDK_ROOT sebagai fallback.
export ANDROID_NDK_ROOT="$NDK_DIR"
export ANDROID_NDK_HOME="$NDK_DIR"
export ANDROID_NDK="$NDK_DIR"
# Symlink NDK ke dalam android-sdk/ndk/ agar lookup via ANDROID_HOME juga work
mkdir -p "$ANDROID_SDK_DIR/ndk"
[ -L "$ANDROID_SDK_DIR/ndk/$NDK_VERSION" ] || \
  ln -sf "$NDK_DIR" "$ANDROID_SDK_DIR/ndk/$NDK_VERSION"
echo "✓ NDK env: ANDROID_NDK_ROOT=$NDK_DIR"

# Pastikan local.properties ada sebelum ditulis
mkdir -p "$(dirname "$LOCAL_PROPS")"
touch "$LOCAL_PROPS"

# Arahkan Gradle ke NDK via local.properties
if grep -q "^ndk.dir=" "$LOCAL_PROPS" 2>/dev/null; then
  sed -i "s|^ndk.dir=.*|ndk.dir=$NDK_DIR|" "$LOCAL_PROPS"
else
  echo "ndk.dir=$NDK_DIR" >> "$LOCAL_PROPS"
fi

# ──────────────────────────────────────────────────
# 5. CMake 3.22.1 + Ninja (prebuilt dari cmake.org)
# ──────────────────────────────────────────────────
if [ -f "$CMAKE_DIR/bin/cmake" ]; then
  echo "✓ CMake $CMAKE_VERSION sudah ada"
else
  echo "▶ Mengunduh CMake $CMAKE_VERSION (~50 MB)..."
  cd "$PROJECT_ROOT"
  curl -# -L "$CMAKE_URL" -o cmake_tmp.tar.gz
  echo "Extracting CMake..."
  tar -xzf cmake_tmp.tar.gz
  rm cmake_tmp.tar.gz
  EXTRACTED=$(ls -d /home/runner/workspace/cmake-${CMAKE_VERSION}-linux-x86_64 2>/dev/null | head -1)
  if [ -n "$EXTRACTED" ]; then
    mv "$EXTRACTED" "$CMAKE_DIR"
    echo "✓ CMake $CMAKE_VERSION berhasil diinstall"
  else
    echo "✗ Gagal extract CMake" && exit 1
  fi
fi
export PATH="$CMAKE_DIR/bin:$PATH"
NINJA_BIN="$(command -v ninja || true)"
if [ -z "$NINJA_BIN" ] || [ ! -x "$NINJA_BIN" ]; then
  echo "✗ Ninja tidak ditemukan di PATH."
  echo "  Install dependency sistem 'ninja' sebelum menjalankan build APK."
  exit 1
fi
# Android Gradle Plugin juga mencari Ninja di folder CMake yang dikonfigurasi.
# Tautkan binary sistem agar konfigurasi CMake native konsisten.
ln -sf "$NINJA_BIN" "$CMAKE_DIR/bin/ninja"

# Arahkan Gradle ke CMake + SDK via local.properties
if grep -q "^cmake.dir=" "$LOCAL_PROPS" 2>/dev/null; then
  sed -i "s|^cmake.dir=.*|cmake.dir=$CMAKE_DIR|" "$LOCAL_PROPS"
else
  echo "cmake.dir=$CMAKE_DIR" >> "$LOCAL_PROPS"
fi
if grep -q "^sdk.dir=" "$LOCAL_PROPS" 2>/dev/null; then
  sed -i "s|^sdk.dir=.*|sdk.dir=$ANDROID_SDK_DIR|" "$LOCAL_PROPS"
else
  echo "sdk.dir=$ANDROID_SDK_DIR" >> "$LOCAL_PROPS"
fi

# ──────────────────────────────────────────────────
# 6. Ringkasan environment
# ──────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo " Environment check"
echo "══════════════════════════════════════════════"
echo "  flutter  : $(which flutter)"
echo "  java     : $(which java)"
echo "  cmake    : $CMAKE_DIR/bin/cmake [$(cmake --version 2>/dev/null | head -1)]"
echo "  ninja    : $CMAKE_DIR/bin/ninja [$(ninja --version)]"
echo "  clang    : $NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
echo "  ndk.dir  : $NDK_DIR"
echo "  sdk.dir  : $ANDROID_SDK_DIR"
echo ""

# ──────────────────────────────────────────────────
# 7. flutter doctor
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
cd "$PROJECT_ROOT"
flutter build apk --debug 2>&1
echo ""
echo "✓ Build selesai!"
ls -lh build/app/outputs/flutter-apk/*.apk 2>/dev/null || true
