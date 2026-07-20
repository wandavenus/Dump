#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# postCreate.sh — runs ONCE after the dev container is created.
# Called by devcontainer.json "postCreateCommand".
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

info()    { echo -e "${CYAN}▶ $*${RESET}"; }
success() { echo -e "${GREEN}✓ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $*${RESET}"; }
error()   { echo -e "${RED}✗ $*${RESET}"; }
header()  { echo -e "\n${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

# ─────────────────────────────────────────────────────────────────────────────
# 0. Environment snapshot
# ─────────────────────────────────────────────────────────────────────────────
header "Environment"
echo "  User           : $(whoami)"
echo "  Workspace      : ${PWD}"
echo "  Flutter home   : ${FLUTTER_HOME:-/opt/flutter}"
echo "  Android SDK    : ${ANDROID_SDK_ROOT:-/opt/android-sdk}"
echo "  Java home      : ${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
echo "  Pub cache      : ${PUB_CACHE:-/opt/pub-cache}"
echo "  Gradle home    : ${GRADLE_USER_HOME:-${HOME}/.gradle}"
echo "  ccache dir     : ${CCACHE_DIR:-${HOME}/.ccache}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 1. android/local.properties
#    Must point flutter.sdk at the container's Flutter installation.
#    The file is in .gitignore so rewriting it here is safe.
# ─────────────────────────────────────────────────────────────────────────────
header "Configuring android/local.properties"

FLUTTER_SDK_PATH="${FLUTTER_HOME:-/opt/flutter}"
LOCAL_PROPS="android/local.properties"

if [[ -f "${LOCAL_PROPS}" ]]; then
    # Replace existing flutter.sdk line in-place
    sed -i "s|^flutter\.sdk=.*|flutter.sdk=${FLUTTER_SDK_PATH}|" "${LOCAL_PROPS}"
    info "Updated flutter.sdk in ${LOCAL_PROPS}"
else
    # Create the file if it doesn't exist (fresh clone)
    cat > "${LOCAL_PROPS}" <<EOF
flutter.sdk=${FLUTTER_SDK_PATH}
sdk.dir=${ANDROID_SDK_ROOT:-/opt/android-sdk}
EOF
    info "Created ${LOCAL_PROPS}"
fi

# Make sure sdk.dir is also present
if ! grep -q "^sdk\.dir=" "${LOCAL_PROPS}"; then
    echo "sdk.dir=${ANDROID_SDK_ROOT:-/opt/android-sdk}" >> "${LOCAL_PROPS}"
    info "Added sdk.dir to ${LOCAL_PROPS}"
fi

cat "${LOCAL_PROPS}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 2. Flutter doctor
# ─────────────────────────────────────────────────────────────────────────────
header "Flutter Doctor"
flutter doctor -v || warn "flutter doctor reported issues — review above output"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 3. Accept any remaining Android SDK licenses
#    (sdkmanager in the Dockerfile accepted them, but Codespaces may have
#     mounted a fresh ~/.android — this is a safety net)
# ─────────────────────────────────────────────────────────────────────────────
header "Android SDK Licenses"
yes | sdkmanager --licenses > /dev/null 2>&1 \
    && success "Android SDK licenses accepted" \
    || warn "sdkmanager --licenses exited non-zero (may be fine)"

# ─────────────────────────────────────────────────────────────────────────────
# 4. Flutter pub get
# ─────────────────────────────────────────────────────────────────────────────
header "Flutter Pub Get"
info "Fetching Dart dependencies..."
flutter pub get
success "Dependencies resolved"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 5. Verify Java 21
# ─────────────────────────────────────────────────────────────────────────────
header "Java Verification"
JAVA_VERSION=$(java -version 2>&1 | head -1)
echo "  ${JAVA_VERSION}"
if echo "${JAVA_VERSION}" | grep -q "21\."; then
    success "Java 21 confirmed"
else
    error "Expected Java 21 — got: ${JAVA_VERSION}"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 6. Verify Android SDK components
# ─────────────────────────────────────────────────────────────────────────────
header "Android SDK Verification"

SDK="${ANDROID_SDK_ROOT:-/opt/android-sdk}"

check_component() {
    local label="$1"
    local path="$2"
    if [[ -e "${path}" ]]; then
        success "${label}: ${path}"
    else
        error "${label} NOT FOUND at: ${path}"
    fi
}

check_component "platform-tools"        "${SDK}/platform-tools/adb"
check_component "platforms;android-35"  "${SDK}/platforms/android-35"
check_component "build-tools;36.0.0"    "${SDK}/build-tools/36.0.0/aapt2"
check_component "cmake;3.22.1"          "${SDK}/cmake/3.22.1"
check_component "ndk;28.2.13676358"     "${SDK}/ndk/28.2.13676358"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 7. Verify NDK Clang toolchain
# ─────────────────────────────────────────────────────────────────────────────
header "NDK Clang Toolchain"
NDK_CLANG="${SDK}/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
if [[ -x "${NDK_CLANG}" ]]; then
    NDK_CLANG_VER=$("${NDK_CLANG}" --version 2>&1 | head -1)
    success "NDK clang: ${NDK_CLANG_VER}"
else
    error "NDK clang not found at expected path: ${NDK_CLANG}"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 8. Verify CMake 3.22.1 (SDK-bundled, used by externalNativeBuild)
# ─────────────────────────────────────────────────────────────────────────────
header "CMake 3.22.1 (SDK)"
SDK_CMAKE="${SDK}/cmake/3.22.1/bin/cmake"
if [[ -x "${SDK_CMAKE}" ]]; then
    success "SDK cmake: $("${SDK_CMAKE}" --version | head -1)"
else
    warn "SDK cmake not found at ${SDK_CMAKE} — will fall back to system cmake"
    CMAKE_VER=$(cmake --version 2>&1 | head -1)
    info "System cmake: ${CMAKE_VER}"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 9. Verify Gradle wrapper will use Java 21
# ─────────────────────────────────────────────────────────────────────────────
header "Gradle / Java 21 Integration"
info "Running: cd android && ./gradlew --version (no build)"
if (cd android && ./gradlew --version --no-daemon 2>&1); then
    success "Gradle wrapper works — check 'JVM' line above is Java 21"
else
    warn "Gradle --version failed; run manually: cd android && ./gradlew --version"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 10. ccache initial config
# ─────────────────────────────────────────────────────────────────────────────
header "ccache Setup"
export CCACHE_DIR="${CCACHE_DIR:-${HOME}/.ccache}"
mkdir -p "${CCACHE_DIR}"
ccache --max-size=5G
ccache --zero-stats
success "ccache configured (max 5 GB, stats reset)"
ccache --show-stats
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 11. Summary
# ─────────────────────────────────────────────────────────────────────────────
header "Dev Container Ready"
echo ""
echo -e "${GREEN}${BOLD}  Flutter Android dev environment is set up.${RESET}"
echo ""
echo "  Common commands:"
echo "    flutter pub get                      # sync Dart packages"
echo "    flutter build apk --debug            # debug APK (arm64-v8a)"
echo "    flutter build apk --release          # release APK"
echo "    flutter analyze                      # static analysis"
echo "    cd android && ./gradlew assembleDebug  # direct Gradle build"
echo ""
echo "  SDK locations:"
printf "    %-22s %s\n" "Flutter:"  "${FLUTTER_HOME:-/opt/flutter}"
printf "    %-22s %s\n" "Dart SDK:" "${FLUTTER_HOME:-/opt/flutter}/bin/cache/dart-sdk"
printf "    %-22s %s\n" "Android SDK:" "${SDK}"
printf "    %-22s %s\n" "NDK 28.2:" "${SDK}/ndk/28.2.13676358"
printf "    %-22s %s\n" "Java 21:" "${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
echo ""
