#!/usr/bin/env bash
# setup-flutter.sh
# Install Flutter 3.44.4 ke /home/runner/flutter/ kalau belum ada.
# Jalankan: bash setup-flutter.sh

set -e

FLUTTER_VERSION="3.44.4"
FLUTTER_DIR="/home/runner/flutter"
FLUTTER_BIN="$FLUTTER_DIR/bin/flutter"
ARCHIVE_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

if [ -f "$FLUTTER_BIN" ]; then
  INSTALLED=$("$FLUTTER_BIN" --version 2>/dev/null | head -1)
  echo "✓ Flutter sudah terinstall: $INSTALLED"
  exit 0
fi

echo "Flutter $FLUTTER_VERSION tidak ditemukan, mengunduh..."
cd /home/runner

curl -# -L "$ARCHIVE_URL" -o flutter_setup.tar.xz
echo "Download selesai. Extracting..."
tar -xJf flutter_setup.tar.xz
rm flutter_setup.tar.xz

echo ""
echo "✓ Flutter $FLUTTER_VERSION berhasil diinstall di $FLUTTER_DIR"
echo "  Versi: $("$FLUTTER_BIN" --version 2>/dev/null | head -1)"
