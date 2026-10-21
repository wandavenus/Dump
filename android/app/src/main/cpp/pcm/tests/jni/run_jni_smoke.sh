#!/usr/bin/env bash
#
# JNI smoke test for pcm_native_jni.cpp on a desktop JVM.
#
# Builds a host libpcm_mixer_native.so, then validates direct-buffer offsets,
# array marshalling, handle lifetimes and error handling through the same JNI
# entry points the Kotlin NativePcmBridge uses.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pcm_dir="$(cd "$here/../.." && pwd)"
work_dir="${TMPDIR:-/tmp}/pcm_native_jni_smoke"
rm -rf "$work_dir"
mkdir -p "$work_dir/classes"

CXX="${CXX:-c++}"
CXXFLAGS="${CXXFLAGS:--std=c++17 -O2 -Wall -Wextra}"

javac -d "$work_dir/classes" \
    "$here/JniSmoke.java" \
    "$here/dev/wndavenz/music/audio/mixer/NativePcmBridge.java"

java_home="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")}"
case "$(uname -s)" in
    Darwin) jni_platform=darwin ;;
    *) jni_platform=linux ;;
esac

# shellcheck disable=SC2086
"$CXX" $CXXFLAGS -fPIC -shared \
    -I "$pcm_dir" \
    -I "$java_home/include" \
    -I "$java_home/include/$jni_platform" \
    "$pcm_dir/pcm_native.cpp" \
    "$pcm_dir/pcm_native_jni.cpp" \
    -o "$work_dir/libpcm_mixer_native.so"

java -Djava.library.path="$work_dir" -cp "$work_dir/classes" JniSmoke
