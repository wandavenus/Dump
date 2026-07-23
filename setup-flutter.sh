#!/usr/bin/env bash
# setup-flutter.sh
# 1. Install Flutter 3.44.5 ke /home/runner/flutter/ kalau belum ada.
# 2. Salin Flutter ke /home/runner/workspace/flutter-ws/ agar bisa tulis ke cache
#    (/home/runner/ quota penuh — flutter tidak bisa update engine.stamp di sana).
# 3. Install JDK 17 Temurin ke /home/runner/workspace/jdk17/ kalau belum ada.
# Jalankan: bash setup-flutter.sh

set -e

SETUP_LOCK="/tmp/musicplayer-flutter-setup.lock"
exec 9>"$SETUP_LOCK"
flock 9

# ──────────────────────────────────────────────────
# 1. Flutter — install ke /home/runner/flutter/ (source)
# ──────────────────────────────────────────────────
FLUTTER_VERSION="3.44.5"
FLUTTER_SRC="/home/runner/flutter"
FLUTTER_SRC_BIN="$FLUTTER_SRC/bin/flutter"
FLUTTER_WS="/home/runner/workspace/flutter-ws/flutter"
FLUTTER_WS_BIN="$FLUTTER_WS/bin/flutter"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

if [ -x "$FLUTTER_SRC_BIN" ] && [ -f "$FLUTTER_SRC/bin/internal/shared.sh" ]; then
  echo "✓ Flutter source ada di $FLUTTER_SRC"
  FLUTTER_SOURCE_READY=true
elif [ -x "$FLUTTER_WS_BIN" ] && [ -f "$FLUTTER_WS/bin/internal/shared.sh" ]; then
  echo "✓ Flutter workspace copy valid; download source dilewati"
  FLUTTER_SOURCE_READY=false
else
  echo "Flutter $FLUTTER_VERSION tidak ditemukan/invalid di $FLUTTER_SRC, mengunduh..."
  cd /home/runner
  FLUTTER_ARCHIVE="/home/runner/flutter_setup.tar.xz"
  FLUTTER_TMP="/home/runner/flutter.extract.$$"
  rm -rf "$FLUTTER_TMP" "$FLUTTER_ARCHIVE"
  mkdir -p "$FLUTTER_TMP"
  curl -# -L "$FLUTTER_URL" -o "$FLUTTER_ARCHIVE"
  echo "Download selesai. Extracting..."
  tar -xJf "$FLUTTER_ARCHIVE" -C "$FLUTTER_TMP"
  rm "$FLUTTER_ARCHIVE"
  rm -rf "$FLUTTER_SRC"
  mv "$FLUTTER_TMP/flutter" "$FLUTTER_SRC"
  rmdir "$FLUTTER_TMP" 2>/dev/null || true
  test -x "$FLUTTER_SRC_BIN"
  test -f "$FLUTTER_SRC/bin/internal/shared.sh"
  echo "✓ Flutter $FLUTTER_VERSION berhasil diinstall di $FLUTTER_SRC"
  FLUTTER_SOURCE_READY=true
fi

# ──────────────────────────────────────────────────
# 2. Flutter workspace copy — /home/runner/workspace/flutter-ws/
#    Diperlukan karena /home/runner/ quota penuh:
#    flutter menulis ke bin/cache/ saat startup → "Disk quota exceeded" → exit 1
#    Salinan di workspace bisa tulis ke cache-nya sendiri.
#    Dibuat sekali (~1.5GB, cp -a, ±1 menit pertama kali).
# ──────────────────────────────────────────────────
if [ -x "$FLUTTER_WS_BIN" ] && [ -f "$FLUTTER_WS/bin/internal/shared.sh" ]; then
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
# 3. JDK 17 Temurin (x64 Linux) — /home/runner/workspace/jdk17/
# ──────────────────────────────────────────────────
JDK_DIR="/home/runner/workspace/jdk17"
JDK_BIN="$JDK_DIR/bin/java"

if [ -x "$JDK_BIN" ] && [ -f "$JDK_DIR/lib/jli/libjli.so" ] && "$JDK_BIN" -version >/dev/null 2>&1; then
  echo "✓ JDK 17 sudah ada: $("$JDK_BIN" -version 2>&1 | head -1)"
else
  JDK_CANDIDATE="/nix/store/bk2hgshkd3a9v4hrs9gjmxfkzvflgydx-openjdk-17.0.15+6"
  if [ -z "$JDK_CANDIDATE" ]; then
    echo "✗ JDK 17 tervalidasi tidak ditemukan."
    exit 1
  fi
  if [ ! -x "$JDK_CANDIDATE/bin/java" ] || ! "$JDK_CANDIDATE/bin/java" -version >/dev/null 2>&1; then
    echo "✗ JDK fallback tidak bisa dijalankan: $JDK_CANDIDATE"
    exit 1
  fi
  echo "⚠ JDK lokal tidak lengkap; build akan memakai JDK tervalidasi: $JDK_CANDIDATE"
fi

echo ""
echo "✓ setup-flutter.sh selesai"
echo "  Flutter WS : $FLUTTER_WS_BIN"
echo "  Java       : $JDK_BIN"
