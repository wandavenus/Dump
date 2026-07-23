#!/usr/bin/env bash
set -euo pipefail

header() { echo "\n━━━ $* ━━━"; }

header "Flutter Precache"
flutter precache --android --no-web --no-ios

header "Environment"
echo "User: $(whoami)"
flutter --version
java -version

header "Configuring android/local.properties"
cat > android/local.properties <<EOF
flutter.sdk=${FLUTTER_HOME:-/opt/flutter}
sdk.dir=${ANDROID_SDK_ROOT:-/opt/android-sdk}
EOF

header "Android Licenses"
yes | sdkmanager --licenses >/dev/null 2>&1 || true

header "Flutter Packages"
flutter pub get

header "Gradle Check"
(cd android && ./gradlew --version --no-daemon)

header "Dev Container Ready"
echo "Flutter Android environment ready."
