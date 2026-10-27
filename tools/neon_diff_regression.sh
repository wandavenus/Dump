#!/usr/bin/env bash
#
# AArch64 NEON differential regression for the hand-written kernels in
# native_audio_runtime/src/*.S.
#
# Why this exists
#   NEON is selected at compile time (#if defined(__aarch64__)) and the .S files
#   carry the same guard, so on an x86_64 host they become empty translation
#   units. `dart test` and `flutter test` therefore never execute a single NEON
#   instruction, and an assembly bug would only show up on-device.
#
# What it does
#   1. Compiles native_audio_runtime/tool/neon_diff_test.c together with the
#      three .S kernel files.
#   2. Runs it and fails if any kernel output differs from its reference by even
#      one bit. The harness is freestanding (no libc/libm) so it links the same
#      way on a native AArch64 host and under qemu.
#
# Toolchain selection
#   * arm64 host  -> plain cc, executed natively.
#   * other host  -> clang cross-compiles to aarch64-linux-gnu, links with lld
#                    (or aarch64-linux-gnu-ld), and qemu-aarch64 runs the result.
#
# Run from anywhere:
#   tools/neon_diff_regression.sh
#
# Requirements: bash, clang (or cc on arm64), and on x86_64 additionally a
# cross-capable linker (lld) plus qemu-user (qemu-aarch64-static). On Debian and
# Ubuntu: apt-get install -y clang lld qemu-user-static.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/native_audio_runtime/src"
HARNESS="$ROOT/native_audio_runtime/tool/neon_diff_test.c"
OUT="$ROOT/build/neon-diff"
BIN="$OUT/neon_diff_test"

SOURCES=(
  "$HARNESS"
  "$SRC/neon_kernels.S"
  "$SRC/automix_neon.S"
  "$SRC/automix_tone_neon.S"
)

for f in "${SOURCES[@]}"; do
  [ -f "$f" ] || { echo "missing source: $f" >&2; exit 2; }
done

mkdir -p "$OUT"

HOST_ARCH="$(uname -m)"

if [ "$HOST_ARCH" = "aarch64" ] || [ "$HOST_ARCH" = "arm64" ]; then
  # Native AArch64: the .S files are live, no cross toolchain or emulator.
  CC="${CC:-cc}"
  command -v "$CC" >/dev/null 2>&1 || { echo "$CC is required on arm64" >&2; exit 2; }

  echo "==> host is $HOST_ARCH: building natively with $CC"
  "$CC" -std=c17 -O2 -ffp-contract=off -ffreestanding -nostdlib -static \
    -march=armv8-a+simd -Wall -Wextra \
    -o "$BIN" "${SOURCES[@]}"
  RUNNER=()
else
  # Cross path: everything is verified against the real AArch64 encodings, but
  # executed under emulation, so timing-sensitive results are out of scope.
  command -v clang >/dev/null 2>&1 || { echo "clang is required to cross-build for AArch64" >&2; exit 2; }

  # lld is often only installed under a versioned name (ld.lld-14, ld.lld-18,
  # /usr/lib/llvm-*/bin/ld.lld), so search instead of assuming `ld.lld` exists.
  # --ld-path takes the exact binary and does not depend on clang's own lookup.
  LD_PATH=""
  for candidate in \
    "$(command -v ld.lld 2>/dev/null || true)" \
    "$(ls -1 /usr/bin/ld.lld-* /usr/lib/llvm-*/bin/ld.lld 2>/dev/null | sort -r | head -1 || true)" \
    "$(command -v aarch64-linux-gnu-ld 2>/dev/null || true)"
  do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then LD_PATH="$candidate"; break; fi
  done

  if [ -z "$LD_PATH" ]; then
    echo "no AArch64-capable linker found: install lld (or binutils-aarch64-linux-gnu)" >&2
    exit 2
  fi
  LD_FLAG="--ld-path=$LD_PATH"

  if command -v qemu-aarch64-static >/dev/null 2>&1; then
    QEMU="qemu-aarch64-static"
  elif command -v qemu-aarch64 >/dev/null 2>&1; then
    QEMU="qemu-aarch64"
  else
    echo "qemu-aarch64 not found: install qemu-user-static to run the AArch64 binary" >&2
    exit 2
  fi

  echo "==> host is $HOST_ARCH: cross-compiling for aarch64-linux-gnu with $LD_PATH, running under $QEMU"
  clang --target=aarch64-linux-gnu -march=armv8-a+simd \
    -std=c17 -O2 -ffp-contract=off -ffreestanding -nostdlib -static "$LD_FLAG" \
    -Wall -Wextra \
    -o "$BIN" "${SOURCES[@]}"
  RUNNER=("$QEMU")
fi

echo "==> running $BIN"
echo
"${RUNNER[@]}" "$BIN"
