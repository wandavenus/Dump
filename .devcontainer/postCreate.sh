#!/usr/bin/env bash
# postCreate.sh — runs once after the dev container is created.
set -euo pipefail

header() { printf '\n━━━ %s ━━━\n' "$*"; }

# Always run from the repository root, regardless of the caller's CWD.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export PATH="${PUB_CACHE:-/opt/pub-cache}/bin:$PATH"

FLUTTER_BIN="${FLUTTER_HOME:-/opt/flutter}/bin/flutter"
EXPECTED_FLUTTER="${FLUTTER_VERSION:-3.47.7}"

header "Environment"
echo "User      : $(whoami)"
echo "Repo      : $REPO_ROOT"
echo "Flutter   : $("$FLUTTER_BIN" --version 2>/dev/null | head -1)"
echo "Java      : $(java -version 2>&1 | head -1)"
echo "Node      : $(node --version)"
echo "pnpm      : $(pnpm --version)"

actual_flutter="$("$FLUTTER_BIN" --version 2>/dev/null | sed -nE '1s/^Flutter ([^ ]+).*/\1/p')"
if [ "$actual_flutter" != "$EXPECTED_FLUTTER" ]; then
  echo "⚠ Flutter $actual_flutter found; expected $EXPECTED_FLUTTER (rebuild the container)."
fi

header "Flutter Precache"
# Android + web (Chrome tests) + Linux desktop (headless Xvfb tests).
"$FLUTTER_BIN" precache --android --web --linux --no-ios

header "Git safe directories"
git config --global --add safe.directory "${FLUTTER_HOME:-/opt/flutter}" || true
git config --global --add safe.directory "$REPO_ROOT" || true

header "Configuring android/local.properties"
cat > android/local.properties <<EOF
flutter.sdk=${FLUTTER_HOME:-/opt/flutter}
sdk.dir=${ANDROID_SDK_ROOT:-/opt/android-sdk}
EOF

header "Android Licenses"
yes | sdkmanager --licenses >/dev/null 2>&1 || true

header "Flutter Packages"
"$FLUTTER_BIN" pub get

header "Native Runtime Packages"
(cd native_audio_runtime && dart pub get)

header "Dart Global Tools"
dart pub global activate coverage 1.16.0

header "Native Toolchain"
clang --version | head -1
clang-format --version
cmake --version | head -1
echo "ninja $(ninja --version)"
echo "ccache $(ccache --version | head -1)"

header "Node Toolchain"
node --version
npm --version
pnpm --version
prettier --version

header "CLI Utilities"
rg --version | head -1
fd --version
bat --version | head -1
jq --version
shellcheck --version | head -2 | tail -1
shfmt --version
yamllint --version
gh --version | head -1
git lfs version

header "Gradle Check"
(cd android && ./gradlew --version --no-daemon)

header "Flutter Doctor"
"$FLUTTER_BIN" doctor || true

header "Dev Container Ready"
echo "Flutter Android + Web environment ready."
echo "Try: make check   (analyze + Flutter/native/Kotlin tests)"
