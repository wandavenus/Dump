#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# .devcontainer/setup.sh
#
# Setup toolchain yang idempoten untuk Codespaces:
#   - devcontainer normal (Ubuntu 24.04)
#   - recovery container Alpine (binary glibc dijalankan lewat gcompat)
#
# Pemakaian:
#   bash .devcontainer/setup.sh          # setup / perbaikan penuh
#   bash .devcontainer/setup.sh --quick  # cek cepat, setup penuh kalau rusak
#
# Script ini aman dijalankan berulang kali. Bagian yang sudah benar dilewati.
# ---------------------------------------------------------------------------

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.7}"
FLUTTER_HOME="${FLUTTER_HOME:-/opt/flutter}"
FLUTTER_RELEASES_URL="${FLUTTER_RELEASES_URL:-https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json}"
PUB_CACHE="${PUB_CACHE:-/opt/pub-cache}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
NDK_VERSION="${NDK_VERSION:-28.2.13676358}"
CMAKE_VERSION="${CMAKE_VERSION:-3.22.1}"
BUILD_TOOLS_VERSION="${BUILD_TOOLS_VERSION:-36.0.0}"
PLATFORM_VERSION="${PLATFORM_VERSION:-36}"
CMDLINE_TOOLS_VERSION="${CMDLINE_TOOLS_VERSION:-13114758}"

# SHA256 rilis Flutter 3.47.7. Dipakai sebagai fallback kalau manifest tidak
# bisa diunduh. Kalau FLUTTER_VERSION diganti, isi FLUTTER_SHA256 juga.
if [ -z "${FLUTTER_SHA256:-}" ] && [ "$FLUTTER_VERSION" = "3.47.7" ]; then
  FLUTTER_SHA256="af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230"
fi

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: bash .devcontainer/setup.sh [--quick|--full]

  --quick  Cek toolchain. Kalau sudah lengkap, keluar cepat.
           Kalau rusak, jalankan setup penuh.
  --full   Paksa setup / perbaikan penuh (default).
EOF
}

QUICK=0
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1 ;;
    --full)  QUICK=0 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Argumen tidak dikenal: $arg" ;;
  esac
done

# ---------------------------------------------------------------------------
# User yang memiliki toolchain. postCreate/postStart biasanya sudah vscode.
# ---------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
  elif id vscode >/dev/null 2>&1; then
    TARGET_USER="vscode"
  else
    TARGET_USER="root"
  fi
else
  TARGET_USER="$(id -un)"
fi

TARGET_HOME="$(awk -F: -v u="$TARGET_USER" '$1 == u { print $6; exit }' /etc/passwd)"
[ -n "$TARGET_HOME" ] || TARGET_HOME="$HOME"
TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || id -gn)"

export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$TARGET_HOME/.gradle}"
export CCACHE_DIR="${CCACHE_DIR:-$TARGET_HOME/.ccache}"

# Kalau script dipanggil sebagai root, jalankan ulang sebagai user target agar
# file .dart_tool/build tidak jadi milik root.
if [ "$(id -u)" -eq 0 ] && [ "$TARGET_USER" != "root" ] && command -v sudo >/dev/null 2>&1; then
  exec sudo -u "$TARGET_USER" -H env \
    HOME="$TARGET_HOME" \
    PATH="$PATH" \
    FLUTTER_VERSION="$FLUTTER_VERSION" \
    FLUTTER_HOME="$FLUTTER_HOME" \
    FLUTTER_RELEASES_URL="$FLUTTER_RELEASES_URL" \
    FLUTTER_SHA256="${FLUTTER_SHA256:-}" \
    PUB_CACHE="$PUB_CACHE" \
    ANDROID_HOME="$ANDROID_HOME" \
    ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" \
    NDK_VERSION="$NDK_VERSION" \
    CMAKE_VERSION="$CMAKE_VERSION" \
    BUILD_TOOLS_VERSION="$BUILD_TOOLS_VERSION" \
    PLATFORM_VERSION="$PLATFORM_VERSION" \
    CMDLINE_TOOLS_VERSION="$CMDLINE_TOOLS_VERSION" \
    GRADLE_USER_HOME="$GRADLE_USER_HOME" \
    CCACHE_DIR="$CCACHE_DIR" \
    bash "$0" "$@"
fi

# Root / sudo.
SUDO=()
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    SUDO=(sudo -n)
  else
    die "Butuh sudo tanpa password. Jalankan sebagai user vscode."
  fi
fi
run_root() { "${SUDO[@]}" "$@"; }

# Cegah postStart dan postAttach berjalan bersamaan.
LOCK_DIR="${TMPDIR:-/tmp}/dump-devcontainer-setup.lock.d"
if command -v flock >/dev/null 2>&1; then
  LOCK_FILE="${TMPDIR:-/tmp}/dump-devcontainer-setup.lock"
  exec 9>"$LOCK_FILE"
  flock -w 900 9 || die "Setup lain masih berjalan (lock: $LOCK_FILE)."
else
  lock_wait=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    lock_wait=$((lock_wait + 1))
    if [ "$lock_wait" -ge 900 ]; then
      die "Setup lain masih berjalan (lock: $LOCK_DIR)."
    fi
    sleep 1
  done
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
fi

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
export FLUTTER_HOME PUB_CACHE ANDROID_HOME ANDROID_SDK_ROOT
export PATH="$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION:${PATH:-/usr/local/bin:/usr/bin:/bin}"

. /etc/os-release
OS_ID="${ID:-unknown}"
case "$OS_ID" in
  alpine)         PLATFORM="alpine" ;;
  ubuntu|debian)  PLATFORM="debian" ;;
  *)
    warn "OS '$OS_ID' belum dikenal; mencoba jalur Debian."
    PLATFORM="debian"
    ;;
esac

ensure_owner() {
  local path="$1" real owner
  [ -e "$path" ] || return 0

  # Ikuti symlink supaya /opt/flutter -> /home/vscode/flutter tetap aman.
  if [ -L "$path" ]; then
    real="$(readlink -f "$path")"
  else
    real="$path"
  fi

  owner="$(stat -c '%U' "$real" 2>/dev/null || true)"
  if [ "$owner" != "$TARGET_USER" ]; then
    run_root chown -R "$TARGET_USER:$TARGET_GROUP" "$real"
  fi

  if [ -L "$path" ]; then
    run_root chown -h "$TARGET_USER:$TARGET_GROUP" "$path"
  fi
}

java_major() {
  local bin="${1:-java}"
  "$bin" -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -n1
}

flutter_version_of() {
  local bin="$1"
  [ -x "$bin" ] || return 1
  "$bin" --version 2>/dev/null | sed -nE '1s/^Flutter ([^ ]+).*/\1/p'
}

plugin_registration_lines() {
  grep -F 'getPlugins().add' "$1" 2>/dev/null | sed 's/^[[:space:]]*//' || true
}

add_safe_directory() {
  local path="$1"
  [ -n "$path" ] || return 0
  command -v git >/dev/null 2>&1 || return 0
  git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$path" \
    || git config --global --add safe.directory "$path" 2>/dev/null \
    || true
}

toolchain_ok() {
  local fv
  [ -x "$FLUTTER_HOME/bin/flutter" ] || return 1
  [ -x "$FLUTTER_HOME/bin/dart" ] || return 1
  fv="$(flutter_version_of "$FLUTTER_HOME/bin/flutter" || true)"
  [ "$fv" = "$FLUTTER_VERSION" ] || return 1

  command -v java >/dev/null 2>&1 || return 1
  [ "$(java_major java)" = "21" ] || return 1
  command -v node >/dev/null 2>&1 || return 1
  command -v npm >/dev/null 2>&1 || return 1
  command -v g++ >/dev/null 2>&1 || return 1
  local cmd
  for cmd in cmake ninja clang pkg-config; do
    command -v "$cmd" >/dev/null 2>&1 || return 1
  done
  pkg-config --exists gtk+-3.0 2>/dev/null || return 1

  [ -w "$PUB_CACHE" ] || return 1
  [ -w "$GRADLE_USER_HOME" ] || return 1
  [ -w "$FLUTTER_HOME/bin/cache" ] || return 1
  [ -w "$ANDROID_SDK_ROOT" ] || return 1
  [ -f "$ROOT_DIR/android/local.properties" ] || return 1

  [ -x "$ANDROID_SDK_ROOT/platform-tools/adb" ] || return 1
  [ -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ] || return 1
  [ -d "$ANDROID_SDK_ROOT/platforms/android-34" ] || return 1
  [ -d "$ANDROID_SDK_ROOT/platforms/android-35" ] || return 1
  [ -d "$ANDROID_SDK_ROOT/platforms/android-$PLATFORM_VERSION" ] || return 1
  [ -d "$ANDROID_SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION" ] || return 1
  [ -d "$ANDROID_SDK_ROOT/ndk/$NDK_VERSION" ] || return 1
  [ -d "$ANDROID_SDK_ROOT/cmake/$CMAKE_VERSION" ] || return 1

  return 0
}

if [ "$QUICK" -eq 1 ]; then
  if toolchain_ok; then
    echo "Toolchain sudah lengkap (Flutter $FLUTTER_VERSION, Android SDK $PLATFORM_VERSION)."
    exit 0
  fi
  warn "Toolchain belum lengkap. Menjalankan setup penuh."
fi

# ---------------------------------------------------------------------------
# Paket sistem
# ---------------------------------------------------------------------------
install_alpine_packages() {
  step "Alpine recovery container terdeteksi"

  run_root apk add --no-cache \
    bash curl wget git openssh-client \
    unzip zip xz tar patch \
    gcompat libstdc++ libgcc \
    openjdk21-jdk \
    nodejs npm \
    python3 py3-pip \
    cmake ninja clang g++ ccache pkgconf make gtk+3.0-dev \
    procps coreutils findutils util-linux

  # Paket opsional: jangan gagalkan setup kalau repositori tidak menyediakannya.
  local pkg
  for pkg in chromium jq ffmpeg shellcheck shfmt; do
    run_root apk add --no-cache "$pkg" >/dev/null 2>&1 || warn "Paket Alpine opsional gagal dipasang: $pkg"
  done

  # Flutter/Android butuh path JDK ala Debian.
  local java_bin jdk_home
  java_bin="$(command -v java || true)"
  if [ -n "$java_bin" ]; then
    jdk_home="$(dirname "$(dirname "$(readlink -f "$java_bin")")")"
    if [ ! -e /usr/lib/jvm/java-21-openjdk-amd64 ]; then
      run_root rm -f /usr/lib/jvm/java-21-openjdk-amd64
      run_root ln -s "$jdk_home" /usr/lib/jvm/java-21-openjdk-amd64
    fi
  fi

  # Flutter mencari google-chrome-stable.
  if [ ! -e /usr/bin/google-chrome-stable ]; then
    local chrome_bin
    chrome_bin="$(command -v chromium-browser || command -v chromium || true)"
    if [ -n "$chrome_bin" ]; then
      run_root rm -f /usr/bin/google-chrome-stable
      run_root ln -s "$(readlink -f "$chrome_bin")" /usr/bin/google-chrome-stable
    fi
  fi
}

install_debian_packages() {
  local need=0 cmd
  for cmd in git curl wget unzip zip xz java node npm python3 cmake ninja clang g++ ccache pkg-config; do
    command -v "$cmd" >/dev/null 2>&1 || need=1
  done
  if ! pkg-config --exists gtk+-3.0 2>/dev/null; then
    need=1
  fi
  [ "$need" -eq 0 ] && return 0

  step "Memasang paket Ubuntu/Debian yang hilang"
  run_root apt-get update
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git curl wget unzip zip xz-utils \
    openjdk-21-jdk clang g++ cmake ninja-build ccache pkg-config \
    libglu1-mesa libgtk-3-dev file gnupg \
    nodejs npm python3 python3-pip python3-venv \
    jq ffmpeg patch shellcheck
}

install_chrome_debian() {
  command -v google-chrome-stable >/dev/null 2>&1 && return 0
  command -v google-chrome >/dev/null 2>&1 && return 0

  step "Memasang Google Chrome (opsional, untuk flutter doctor/web)"
  local deb="/tmp/google-chrome-stable.deb"
  if curl -fL --retry 2 --connect-timeout 20 \
      "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" \
      -o "$deb" 2>/dev/null; then
    run_root apt-get update >/dev/null 2>&1 || true
    if ! run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$deb" >/dev/null 2>&1; then
      warn "Google Chrome gagal dipasang; flutter doctor mungkin memberi warning."
    fi
    rm -f "$deb"
  else
    warn "Download Google Chrome gagal; lanjut tanpa Chrome."
  fi
}

if [ "$PLATFORM" = "alpine" ]; then
  install_alpine_packages
else
  install_debian_packages
  install_chrome_debian
fi

# ---------------------------------------------------------------------------
# Java 21
# ---------------------------------------------------------------------------
step "Memeriksa Java 21"
if ! command -v java >/dev/null 2>&1; then
  if [ "$PLATFORM" = "alpine" ]; then
    run_root apk add --no-cache openjdk21-jdk
  else
    run_root apt-get update
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jdk
  fi
fi

JAVA_MAJOR="$(java_major java)"
if [ "$JAVA_MAJOR" != "21" ]; then
  step "Memasang Java 21"
  if [ "$PLATFORM" = "alpine" ]; then
    run_root apk add --no-cache openjdk21-jdk
  else
    run_root apt-get update
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jdk
  fi
  if [ -x /usr/lib/jvm/java-21-openjdk-amd64/bin/java ]; then
    export PATH="/usr/lib/jvm/java-21-openjdk-amd64/bin:$PATH"
  fi
  JAVA_MAJOR="$(java_major java)"
fi
[ "$JAVA_MAJOR" = "21" ] || die "Java 21 wajib, ditemukan Java ${JAVA_MAJOR:-tidak dikenal}."
JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
echo "Java: $("$JAVA_HOME/bin/java" -version 2>&1 | head -n1)"

# ---------------------------------------------------------------------------
# Node / pnpm
# ---------------------------------------------------------------------------
step "Memeriksa Node.js dan pnpm"
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  if [ "$PLATFORM" = "alpine" ]; then
    run_root apk add --no-cache nodejs npm
  else
    run_root apt-get update
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs npm
  fi
fi
if ! command -v pnpm >/dev/null 2>&1; then
  run_root npm install -g pnpm@10 >/dev/null 2>&1 || warn "pnpm gagal dipasang (tidak wajib untuk build Android)."
fi
echo "Node: $(node --version 2>/dev/null || echo '?')  npm: $(npm --version 2>/dev/null || echo '?')  pnpm: $(pnpm --version 2>/dev/null || echo '?')"

# ---------------------------------------------------------------------------
# Cache yang bisa saja berupa volume root-owned
# ---------------------------------------------------------------------------
step "Menyiapkan cache dan permission"
mkdir -p "$PUB_CACHE" 2>/dev/null || run_root mkdir -p "$PUB_CACHE"
ensure_owner "$PUB_CACHE"

mkdir -p "$GRADLE_USER_HOME" 2>/dev/null || run_root mkdir -p "$GRADLE_USER_HOME"
ensure_owner "$GRADLE_USER_HOME"

mkdir -p "$CCACHE_DIR" 2>/dev/null || run_root mkdir -p "$CCACHE_DIR"
ensure_owner "$CCACHE_DIR"

# ---------------------------------------------------------------------------
# Flutter
# ---------------------------------------------------------------------------
resolve_flutter_sha() {
  command -v python3 >/dev/null 2>&1 || return 0
  curl -fsSL --retry 2 --connect-timeout 20 --max-time 60 "$FLUTTER_RELEASES_URL" 2>/dev/null \
    | python3 -c '
import json, sys
version = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for release in data.get("releases", []):
    if release.get("version") == version and release.get("channel") == "stable":
        print(release.get("sha256", ""))
        break
' "$FLUTTER_VERSION" || true
}

install_flutter() {
  step "Memasang Flutter $FLUTTER_VERSION ke $FLUTTER_HOME"

  local archive="/tmp/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  local tmpdir="/tmp/flutter-extract.$$"
  local sha=""

  rm -rf "$tmpdir"
  mkdir -p "$tmpdir"

  curl -fL --retry 3 --connect-timeout 30 --progress-bar \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    -o "$archive" || die "Download Flutter $FLUTTER_VERSION gagal."

  sha="$(resolve_flutter_sha)"
  [ -n "$sha" ] || sha="${FLUTTER_SHA256:-}"
  if [ -n "$sha" ]; then
    echo "$sha  $archive" | sha256sum -c - || die "Checksum Flutter tidak cocok."
  else
    warn "Checksum Flutter tidak tersedia; verifikasi dilewati."
  fi

  tar -xJf "$archive" -C "$tmpdir"
  [ -x "$tmpdir/flutter/bin/flutter" ] || die "Arsip Flutter tidak valid."

  run_root rm -rf "$FLUTTER_HOME"
  run_root mkdir -p "$(dirname "$FLUTTER_HOME")"
  run_root mv "$tmpdir/flutter" "$FLUTTER_HOME"
  run_root chown -R "$TARGET_USER:$TARGET_GROUP" "$FLUTTER_HOME"

  rm -rf "$tmpdir" "$archive"

  add_safe_directory "$FLUTTER_HOME"
  echo "Flutter terpasang."
}

if [ -e "$FLUTTER_HOME" ]; then
  ensure_owner "$FLUTTER_HOME"
fi

CURRENT_FLUTTER_VERSION="$(flutter_version_of "$FLUTTER_HOME/bin/flutter" || true)"
if [ "$CURRENT_FLUTTER_VERSION" != "$FLUTTER_VERSION" ]; then
  # Recovery container lama mungkin punya Flutter di home user.
  if [ ! -e "$FLUTTER_HOME" ] \
     && [ -x "$TARGET_HOME/flutter/bin/flutter" ] \
     && [ "$(flutter_version_of "$TARGET_HOME/flutter/bin/flutter" || true)" = "$FLUTTER_VERSION" ]; then
    step "Menautkan Flutter dari $TARGET_HOME/flutter"
    run_root ln -s "$TARGET_HOME/flutter" "$FLUTTER_HOME"
  else
    install_flutter
  fi
fi

ensure_owner "$FLUTTER_HOME"
FLUTTER_REAL_HOME="$(readlink -f "$FLUTTER_HOME" 2>/dev/null || echo "$FLUTTER_HOME")"
add_safe_directory "$FLUTTER_HOME"
add_safe_directory "$FLUTTER_REAL_HOME"

step "Memeriksa Flutter"
"$FLUTTER_HOME/bin/flutter" config --no-analytics --no-cli-animations >/dev/null 2>&1 || true
"$FLUTTER_HOME/bin/flutter" --version

# ---------------------------------------------------------------------------
# Android SDK
# ---------------------------------------------------------------------------
step "Memeriksa Android SDK"
if [ ! -d "$ANDROID_SDK_ROOT" ]; then
  run_root mkdir -p "$ANDROID_SDK_ROOT"
  run_root chown -R "$TARGET_USER:$TARGET_GROUP" "$ANDROID_SDK_ROOT"
fi
ensure_owner "$ANDROID_SDK_ROOT"

SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
  step "Memasang Android command-line tools"
  cmdtools_zip="/tmp/android-cmdline-tools.zip"
  cmdtools_dir="/tmp/android-cmdline-tools.$$"
  rm -rf "$cmdtools_dir"
  mkdir -p "$cmdtools_dir"
  curl -fL --retry 3 --connect-timeout 30 \
    "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" \
    -o "$cmdtools_zip" || die "Download Android command-line tools gagal."
  unzip -q "$cmdtools_zip" -d "$cmdtools_dir" || die "Ekstrak Android command-line tools gagal."
  run_root mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  run_root rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  run_root mv "$cmdtools_dir/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  run_root chown -R "$TARGET_USER:$TARGET_GROUP" "$ANDROID_SDK_ROOT/cmdline-tools"
  rm -rf "$cmdtools_dir" "$cmdtools_zip"
fi

[ -x "$SDKMANAGER" ] || die "sdkmanager tidak ditemukan di $SDKMANAGER"

step "Menerima lisensi Android"
set +o pipefail
yes | "$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null 2>&1 || true
set -o pipefail

step "Memasang komponen Android yang hilang"
PACKAGES=()
[ -x "$ANDROID_SDK_ROOT/platform-tools/adb" ] || PACKAGES+=("platform-tools")
[ -d "$ANDROID_SDK_ROOT/platforms/android-34" ] || PACKAGES+=("platforms;android-34")
[ -d "$ANDROID_SDK_ROOT/platforms/android-35" ] || PACKAGES+=("platforms;android-35")
[ -d "$ANDROID_SDK_ROOT/platforms/android-$PLATFORM_VERSION" ] || PACKAGES+=("platforms;android-$PLATFORM_VERSION")
[ -d "$ANDROID_SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION" ] || PACKAGES+=("build-tools;$BUILD_TOOLS_VERSION")
[ -d "$ANDROID_SDK_ROOT/cmake/$CMAKE_VERSION" ] || PACKAGES+=("cmake;$CMAKE_VERSION")
[ -d "$ANDROID_SDK_ROOT/ndk/$NDK_VERSION" ] || PACKAGES+=("ndk;$NDK_VERSION")
if [ "${#PACKAGES[@]}" -gt 0 ]; then
  "$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" "${PACKAGES[@]}"
else
  echo "Semua komponen Android sudah ada."
fi

ensure_owner "$ANDROID_SDK_ROOT"

if [ -d "$ANDROID_SDK_ROOT/ndk/$NDK_VERSION" ]; then
  export ANDROID_NDK_HOME="$ANDROID_SDK_ROOT/ndk/$NDK_VERSION"
  export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
  export ANDROID_NDK="$ANDROID_NDK_HOME"
fi

# ---------------------------------------------------------------------------
# Konfigurasi proyek
# ---------------------------------------------------------------------------
step "Menulis android/local.properties"
mkdir -p "$ROOT_DIR/android"
cat > "$ROOT_DIR/android/local.properties" <<EOF
flutter.sdk=$FLUTTER_HOME
sdk.dir=$ANDROID_SDK_ROOT
EOF

"$FLUTTER_HOME/bin/flutter" config --android-sdk "$ANDROID_SDK_ROOT" >/dev/null 2>&1 || true
"$FLUTTER_HOME/bin/flutter" config --jdk-dir "$JAVA_HOME" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Engine artifact, package, Gradle
# ---------------------------------------------------------------------------
if [ ! -d "$FLUTTER_HOME/bin/cache/artifacts/engine/android-arm64-release" ]; then
  step "Mengunduh engine artifact Android"
  "$FLUTTER_HOME/bin/flutter" precache --android --no-web --no-ios || \
    warn "flutter precache gagal; build pertama akan mengunduhnya sendiri."
fi

step "Mengambil dependency Dart/Flutter"
REGISTRANT_FILE="$ROOT_DIR/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
REGISTRANT_BACKUP=""
if [ -f "$REGISTRANT_FILE" ]; then
  REGISTRANT_BACKUP="$(mktemp "${TMPDIR:-/tmp}/registrant.XXXXXX")"
  cp "$REGISTRANT_FILE" "$REGISTRANT_BACKUP"
fi

"$FLUTTER_HOME/bin/flutter" pub get

# Flutter selalu menulis ulang file ini dan menghapus patch NativeLogger lokal.
# Kalau daftar plugin tidak berubah, kembalikan file lama agar patch tetap ada.
if [ -n "$REGISTRANT_BACKUP" ] && [ -f "$REGISTRANT_FILE" ]; then
  if diff -q \
      <(plugin_registration_lines "$REGISTRANT_BACKUP") \
      <(plugin_registration_lines "$REGISTRANT_FILE") >/dev/null 2>&1; then
    cp "$REGISTRANT_BACKUP" "$REGISTRANT_FILE"
    echo "Patch NativeLogger di GeneratedPluginRegistrant.java dipertahankan."
  else
    warn "Daftar plugin berubah; GeneratedPluginRegistrant.java hasil generate dipertahankan."
  fi
fi
if [ -n "$REGISTRANT_BACKUP" ]; then
  rm -f "$REGISTRANT_BACKUP"
fi

if [ -f "$ROOT_DIR/native_audio_runtime/pubspec.yaml" ]; then
  step "Mengambil dependency native_audio_runtime"
  (cd "$ROOT_DIR/native_audio_runtime" && "$FLUTTER_HOME/bin/dart" pub get)
fi

step "Memeriksa Gradle wrapper"
(cd "$ROOT_DIR/android" && ./gradlew --version --no-daemon)

# ---------------------------------------------------------------------------
# Verifikasi akhir
# ---------------------------------------------------------------------------
step "Verifikasi akhir"
"$FLUTTER_HOME/bin/flutter" doctor || warn "flutter doctor melaporkan masalah opsional."
echo
echo "Flutter : $("$FLUTTER_HOME/bin/flutter" --version | head -n1)"
echo "Dart    : $("$FLUTTER_HOME/bin/dart" --version 2>&1 | head -n1)"
echo "Java    : $("$JAVA_HOME/bin/java" -version 2>&1 | head -n1)"
echo "SDK     : $ANDROID_SDK_ROOT"
echo "NDK     : ${ANDROID_NDK_HOME:-$ANDROID_SDK_ROOT/ndk/$NDK_VERSION}"
echo "Pub     : $PUB_CACHE"
echo
echo "Toolchain siap."
