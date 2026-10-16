#!/usr/bin/env bash
# setup-flutter.sh
# 1. Install Flutter stable terbaru ke /home/runner/flutter/ kalau belum ada.
# 2. Salin Flutter ke /home/runner/workspace/flutter-ws/ agar bisa tulis ke cache
#    (/home/runner/ quota penuh — flutter tidak bisa update engine.stamp di sana).
# 3. Gunakan JDK 21 dari environment Nix.
# Jalankan: bash setup-flutter.sh

set -e

# Keep the setup lock on the workspace volume. The temporary volume can hit
# Replit's per-process quota even when the workspace still has free space.
SETUP_LOCK="/home/runner/workspace/.flutter-setup.lock"
mkdir -p "$(dirname "$SETUP_LOCK")"
exec 9>"$SETUP_LOCK"
flock 9

# ──────────────────────────────────────────────────
# 1. Flutter — install ke /home/runner/flutter/ (source)
# ──────────────────────────────────────────────────
FLUTTER_SRC="/home/runner/flutter"
FLUTTER_SRC_BIN="$FLUTTER_SRC/bin/flutter"
FLUTTER_WS="/home/runner/workspace/flutter-ws/flutter"
FLUTTER_WS_BIN="$FLUTTER_WS/bin/flutter"
FLUTTER_RELEASES_URL="https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"

flutter_version() {
  local flutter_bin="$1"
  "$flutter_bin" --version 2>/dev/null | sed -nE '1s/^Flutter ([^ ]+).*/\1/p'
}

# An SDK is reusable only when this script previously verified the official
# release archive checksum and stamped that exact stable release into it.
flutter_release_matches() {
  local root="$1"
  local stamp
  [ -x "$root/bin/flutter" ] || return 1
  [ -f "$root/bin/internal/shared.sh" ] || return 1
  [ -x "$root/bin/cache/dart-sdk/bin/dart" ] || return 1
  [ "$(flutter_version "$root/bin/flutter" || true)" = "$FLUTTER_VERSION" ] || return 1
  [ -f "$root/.flutter-release-stamp" ] || return 1
  stamp="$(cat "$root/.flutter-release-stamp" 2>/dev/null || true)"
  [ "$stamp" = "$FLUTTER_VERSION|$FLUTTER_RELEASE_HASH|$FLUTTER_RELEASE_SHA256" ]
}

# Resolve the official stable version FIRST. A usable workspace binary can
# still be stale; never let its own version or a synthetic local tag define the
# version this setup is supposed to install.
if ! FLUTTER_RELEASE="$(curl -fsSL --max-time 30 "$FLUTTER_RELEASES_URL" | node -e '
  let input = "";
  process.stdin.on("data", chunk => input += chunk);
  process.stdin.on("end", () => {
    const manifest = JSON.parse(input);
    const stableHash = manifest.current_release?.stable;
    const release = manifest.releases?.find(item =>
      item.hash === stableHash && item.channel === "stable"
    );
    if (!release?.version || !release?.archive || !release?.hash || !release?.sha256) process.exit(1);
    process.stdout.write(`${release.version}|${release.archive}|${release.hash}|${release.sha256}`);
  });
  ')"; then
  echo "✗ Gagal membaca stable release manifest Flutter."
  exit 1
fi
if [ -z "$FLUTTER_RELEASE" ] || [[ "$FLUTTER_RELEASE" != *"|"* ]]; then
  echo "✗ Manifest Flutter tidak berisi rilis stable yang valid."
  exit 1
fi
FLUTTER_VERSION="${FLUTTER_RELEASE%%|*}"
FLUTTER_RELEASE_REST="${FLUTTER_RELEASE#*|}"
FLUTTER_ARCHIVE="${FLUTTER_RELEASE_REST%%|*}"
FLUTTER_RELEASE_REST="${FLUTTER_RELEASE_REST#*|}"
FLUTTER_RELEASE_HASH="${FLUTTER_RELEASE_REST%%|*}"
FLUTTER_RELEASE_SHA256="${FLUTTER_RELEASE_REST#*|}"
if [ -z "$FLUTTER_VERSION" ] || [ -z "$FLUTTER_ARCHIVE" ] ||
   [ -z "$FLUTTER_RELEASE_HASH" ] || [ -z "$FLUTTER_RELEASE_SHA256" ]; then
  echo "✗ Metadata versi/archive/hash/checksum Flutter tidak lengkap."
  exit 1
fi
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/${FLUTTER_ARCHIVE}"

FLUTTER_WS_READY=false
if flutter_release_matches "$FLUTTER_WS"; then
  FLUTTER_WS_READY=true
  echo "✓ Flutter workspace SDK cocok dengan rilis stable terverifikasi: $FLUTTER_VERSION"
elif [ -x "$FLUTTER_WS_BIN" ]; then
  FLUTTER_WS_VERSION="$(flutter_version "$FLUTTER_WS_BIN" || true)"
  echo "⚠ Flutter workspace SDK belum terverifikasi atau stale (versi '$FLUTTER_WS_VERSION', target '$FLUTTER_VERSION'); akan diperbarui."
fi

if flutter_release_matches "$FLUTTER_SRC"; then
  echo "✓ Flutter source cocok dengan rilis stable terverifikasi: $FLUTTER_VERSION"
  FLUTTER_SOURCE_READY=true
elif [ "$FLUTTER_WS_READY" = true ]; then
  echo "✓ Flutter workspace SDK terverifikasi; download source dilewati"
  FLUTTER_SOURCE_READY=false
else
  echo "▶ Mengunduh Flutter stable $FLUTTER_VERSION..."
  cd /home/runner
  FLUTTER_ARCHIVE_FILE="/home/runner/flutter_setup.tar.xz"
  FLUTTER_TMP="/home/runner/flutter.extract.$"
  rm -rf "$FLUTTER_TMP" "$FLUTTER_ARCHIVE_FILE"
  mkdir -p "$FLUTTER_TMP"
  curl -# -fL "$FLUTTER_URL" -o "$FLUTTER_ARCHIVE_FILE"
  ACTUAL_SHA256="$(sha256sum "$FLUTTER_ARCHIVE_FILE" | awk '{print $1}')"
  if [ "$ACTUAL_SHA256" != "$FLUTTER_RELEASE_SHA256" ]; then
    echo "✗ Flutter archive checksum mismatch (expected $FLUTTER_RELEASE_SHA256, got $ACTUAL_SHA256)."
    rm -rf "$FLUTTER_TMP" "$FLUTTER_ARCHIVE_FILE"
    exit 1
  fi
  echo "✓ Flutter archive checksum cocok dengan manifest resmi."
  tar -xJf "$FLUTTER_ARCHIVE_FILE" -C "$FLUTTER_TMP"
  rm "$FLUTTER_ARCHIVE_FILE"
  rm -rf "$FLUTTER_SRC"
  mv "$FLUTTER_TMP/flutter" "$FLUTTER_SRC"
  rmdir "$FLUTTER_TMP" 2>/dev/null || true
  test -x "$FLUTTER_SRC_BIN"
  test -f "$FLUTTER_SRC/bin/internal/shared.sh"
  printf '%s|%s|%s\n' "$FLUTTER_VERSION" "$FLUTTER_RELEASE_HASH" "$FLUTTER_RELEASE_SHA256" > "$FLUTTER_SRC/.flutter-release-stamp"
  echo "✓ Flutter $FLUTTER_VERSION berhasil diinstall dan diverifikasi di $FLUTTER_SRC"
  FLUTTER_SOURCE_READY=true
fi

# ──────────────────────────────────────────────────
# 2. Flutter workspace copy — /home/runner/workspace/flutter-ws/
#    Diperlukan karena /home/runner/ quota penuh:
#    flutter menulis ke bin/cache/ saat startup → "Disk quota exceeded" → exit 1
#    Salinan di workspace bisa tulis ke cache-nya sendiri.
#    Dibuat sekali (~1.5GB, cp -a, ±1 menit pertama kali).
# ──────────────────────────────────────────────────
if [ "$FLUTTER_WS_READY" = true ]; then
  echo "✓ Flutter workspace copy ada: $FLUTTER_WS"
elif [ "$FLUTTER_SOURCE_READY" = true ]; then
  echo "▶ Membuat salinan Flutter atomik di workspace (setup 1x, ~1.5GB)..."
  rm -rf "$FLUTTER_WS"
  mkdir -p "/home/runner/workspace/flutter-ws"
  FLUTTER_WS_TMP="/home/runner/workspace/flutter-ws/flutter.tmp.$$"
  rm -rf "$FLUTTER_WS_TMP"
  cp -a "$FLUTTER_SRC" "$FLUTTER_WS_TMP"
  test -x "$FLUTTER_WS_TMP/bin/flutter"
  test -f "$FLUTTER_WS_TMP/bin/internal/shared.sh"
  mv "$FLUTTER_WS_TMP" "$FLUTTER_WS"
  echo "✓ Salinan Flutter berhasil dibuat di $FLUTTER_WS"
  echo "  Versi: $("$FLUTTER_WS_BIN" --version 2>/dev/null | head -1)"
else
  echo "✗ Flutter workspace copy tidak valid dan source Flutter tidak tersedia."
  exit 1
fi

# ──────────────────────────────────────────────────
# 2b. Flutter release metadata — archive installs have no .git directory.
#      Flutter run/devices/DevTools require Git and a matching release tag.
#      Keep this local metadata minimal so cache contents are not rebuilt.
# ──────────────────────────────────────────────────
if [ ! -d "$FLUTTER_WS/.git" ] || \
   ! git -C "$FLUTTER_WS" rev-parse --verify HEAD >/dev/null 2>&1 || \
   ! git -C "$FLUTTER_WS" describe --tags --exact-match HEAD >/dev/null 2>&1; then
  if [ ! -x "$FLUTTER_WS/bin/cache/dart-sdk/bin/dart" ]; then
    echo "✗ Flutter Dart SDK cache tidak lengkap; tidak aman membuat metadata Git."
    exit 1
  fi
  echo "▶ Menyiapkan metadata Git lokal Flutter $FLUTTER_VERSION..."
  rm -rf "$FLUTTER_WS/.git"
  git -C "$FLUTTER_WS" init -q -b stable
  git -C "$FLUTTER_WS" config user.email "flutter-sdk@localhost"
  git -C "$FLUTTER_WS" config user.name "Flutter SDK"
  git -C "$FLUTTER_WS" add -f \
    DEPS \
    bin/internal/engine.version \
    bin/internal/release-candidate-branch.version
  GIT_AUTHOR_DATE='2026-07-06T21:50:00Z' \
    GIT_COMMITTER_DATE='2026-07-06T21:50:00Z' \
    git -C "$FLUTTER_WS" commit -q -m "Flutter $FLUTTER_VERSION release metadata"
  git -C "$FLUTTER_WS" tag -f "$FLUTTER_VERSION" >/dev/null
  # Discard stale "0.0.0-unknown" metadata so Flutter regenerates it from
  # the release tag above on its next invocation.
  rm -f "$FLUTTER_WS/bin/cache/flutter.version.json" "$FLUTTER_WS/version"
  echo "✓ Metadata Git Flutter siap: $(git -C "$FLUTTER_WS" describe --tags --exact-match HEAD)"
fi

# ──────────────────────────────────────────────────
# 3. JDK 21 dari Nix — wajib untuk Android Gradle/url_launcher
# ──────────────────────────────────────────────────
JAVA_BIN="$(command -v java || true)"
if [ -z "$JAVA_BIN" ] || [ ! -x "$JAVA_BIN" ]; then
  echo "✗ JDK 21 tidak ditemukan. Pastikan pkgs.jdk21 tersedia di replit.nix."
  exit 1
fi
JAVA_MAJOR="$("$JAVA_BIN" -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -1)"
if [ "$JAVA_MAJOR" != "21" ]; then
  echo "✗ Java $JAVA_MAJOR terdeteksi; workflow wajib memakai Java 21."
  exit 1
fi
JAVA_HOME="$(cd "$(dirname "$(readlink -f "$JAVA_BIN")")/.." && pwd)"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
echo "✓ Java 21: $JAVA_HOME"

echo ""
echo "✓ setup-flutter.sh selesai"
echo "  Flutter WS : $FLUTTER_WS_BIN"
echo "  Flutter    : $FLUTTER_VERSION (stable)"
echo "  Java       : $JAVA_HOME/bin/java"
