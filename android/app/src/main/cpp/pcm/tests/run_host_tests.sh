#!/usr/bin/env bash
#
# Host tests for the single-AudioTrack native PCM bus.
#
# The production library is built as part of the Android Gradle NDK build.
# These tests compile pcm_native.cpp for the host (scalar fallbacks) or for
# aarch64 (NEON paths) and exercise the public C API.
#
# Examples:
#   ./run_host_tests.sh
#   CXX=clang++ ./run_host_tests.sh
#   CXX=aarch64-linux-gnu-g++ \
#     RUNNER="qemu-aarch64-static -L /usr/aarch64-linux-gnu" \
#     ./run_host_tests.sh
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$here/.." && pwd)"
work_dir="${TMPDIR:-/tmp}/pcm_native_host_tests"
mkdir -p "$work_dir"

CXX="${CXX:-c++}"
CXXFLAGS="${CXXFLAGS:--std=c++17 -O2 -Wall -Wextra}"
RUNNER="${RUNNER:-}"

run_binary() {
    if [[ -n "$RUNNER" ]]; then
        # RUNNER is intentionally word-split so callers can pass qemu flags.
        # shellcheck disable=SC2086
        $RUNNER "$@"
    else
        "$@"
    fi
}

build_and_run() {
    local name="$1"
    echo "==> building $name with $CXX"
    # shellcheck disable=SC2086
    "$CXX" $CXXFLAGS -I "$source_dir" "$here/$name.cpp" \
        "$source_dir/pcm_native.cpp" -o "$work_dir/$name"
    run_binary "$work_dir/$name"
}

build_and_run pcm_native_test
build_and_run pcm_native_fuzz
