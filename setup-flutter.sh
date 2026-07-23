#!/usr/bin/env bash
# setup-flutter.sh
# 1. Install Flutter 3.44.5 ke /home/runner/flutter/ kalau belum ada.
# 2. Salin Flutter ke /home/runner/workspace/flutter-ws/ agar bisa tulis ke cache
#    (/home/runner/ quota penuh — flutter tidak bisa update engine.stamp di sana).
# 3. Install JDK 17 Temurin ke /home/runner/workspace/jdk17/ kalau belum ada.
# Jalankan: bash setup-flutter.sh

set -e

# ──────────────────────────────────────────────────
# 1. Flutter — install ke /home/runner/flutter/ (source)
# ──────────────────────────────────────────────────
FLUTTER_VERSION="3.44.5"
FLUTTER_SRC="/home/runner/flutter"
FLUTTER_SRC_BIN="$FLUTTER_SRC/bin/flutter"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

if [ -f "$FLUTTER_SRC_BIN" ]; then
  echo "✓ Flutter source ada di $FLUTTER_SRC"
else
  echo "Flutter $FLUTTER_VERSION tidak ditemukan di $FLUTTER_SRC, mengunduh..."
  cd /home/runner
  curl -# -L "$FLUTTER_URL" -o flutter_setup.tar.xz
  echo "Download selesai. Extracting..."
  tar -xJf flutter_setup.tar.xz
  rm flutter_setup.tar.xz
  echo "✓ Flutter $FLUTTER_VERSION berhasil diinstall di $FLUTTER_SRC"
fi

# ──────────────────────────────────────────────────
# 2. Flutter workspace copy — /home/runner/workspace/flutter-ws/
#    Diperlukan karena /home/runner/ quota penuh:
#    flutter menulis ke bin/cache/ saat startup → "Disk quota exceeded" → exit 1
#    Salinan di workspace bisa tulis ke cache-nya sendiri.
#    Dibuat sekali (~1.5GB, cp -a, ±1 menit pertama kali).
# ──────────────────────────────────────────────────
FLUTTER_WS="/home/runner/workspace/flutter-ws/flutter"
FLUTTER_WS_BIN="$FLUTTER_WS/bin/flutter"

if [ -f "$FLUTTER_WS_BIN" ]; then
  echo "✓ Flutter workspace copy ada: $FLUTTER_WS"
else
  echo "▶ Membuat salinan Flutter di workspace (setup 1x, ~1.5GB)..."
  mkdir -p "/home/runner/workspace/flutter-ws"
  cp -a "$FLUTTER_SRC" "/home/runner/workspace/flutter-ws/flutter"
  echo "✓ Salinan Flutter berhasil dibuat di $FLUTTER_WS"
  echo "  Versi: $("$FLUTTER_WS_BIN" --version 2>/dev/null | head -1)"
fi

# ──────────────────────────────────────────────────
# 3. JDK 17 Temurin (x64 Linux) — /home/runner/workspace/jdk17/
# ──────────────────────────────────────────────────
JDK_DIR="/home/runner/workspace/jdk17"
JDK_BIN="$JDK_DIR/bin/java"
JDK_URL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.15%2B6/OpenJDK17U-jdk_x64_linux_hotspot_17.0.15_6.tar.gz"

if [ -f "$JDK_BIN" ]; then
  echo "✓ JDK 17 sudah ada: $("$JDK_BIN" -version 2>&1 | head -1)"
else
  echo "▶ Mengunduh JDK 17 Temurin ke workspace..."
  cd /home/runner/workspace
  curl -# -L "$JDK_URL" -o jdk17_temurin.tar.gz
  echo "Download selesai. Extracting..."
  tar -xzf jdk17_temurin.tar.gz
  rm jdk17_temurin.tar.gz
  JDK_EXTRACTED=$(ls -d /home/runner/workspace/jdk-17* 2>/dev/null | head -1)
  if [ -n "$JDK_EXTRACTED" ]; then
    mv "$JDK_EXTRACTED" "$JDK_DIR"
    echo "✓ JDK 17 berhasil diinstall di $JDK_DIR"
    echo "  Versi: $("$JDK_BIN" -version 2>&1 | head -1)"
  else
    echo "✗ Gagal extract JDK" && exit 1
  fi
fi

echo ""
echo "✓ setup-flutter.sh selesai"
echo "  Flutter WS : $FLUTTER_WS_BIN"
echo "  Java       : $JDK_BIN"
