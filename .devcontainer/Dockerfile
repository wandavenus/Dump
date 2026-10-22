FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Fail fast on any pipe error (curl | bash / curl | jq patterns below).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_VERSION=3.47.7
ENV FLUTTER_HOME=/opt/flutter
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_NDK_HOME=/opt/android-sdk/ndk/28.2.13676358
ENV PUB_CACHE=/opt/pub-cache
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV CHROME_EXECUTABLE=/usr/bin/google-chrome-stable
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PUB_CACHE}/bin:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/build-tools/36.0.0:${JAVA_HOME}/bin:/usr/lib/ccache:${PATH}"

# ─────────────────────────────────────────────────────────────────────────────
# System toolchain
#   Flutter/Android: JDK 21, clang, CMake, Ninja, ccache
#   Native DSP:      clang-format/tidy, libclang (ffigen), gdb/lldb, valgrind
#   Linux desktop:   GTK3 headers + Xvfb (headless widget/integration tests)
#   Audio/debug:     ffmpeg, sox, ImageMagick
#   Shell/CI:        ripgrep, fd, bat, jq, shellcheck, shfmt, yamllint, delta
#   FFmpeg fallback: build-essential, autotools, nasm/yasm, patchelf
# ─────────────────────────────────────────────────────────────────────────────
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget unzip zip xz-utils ca-certificates file gnupg apt-transport-https \
    openjdk-21-jdk clang clang-format-18 clang-tidy-18 libclang-18-dev \
    cmake ninja-build ccache build-essential pkg-config libglu1-mesa \
    libgtk-3-dev liblzma-dev libstdc++-13-dev \
    gdb lldb cppcheck valgrind strace \
    ripgrep fd-find tree jq bat git-lfs git-delta \
    shellcheck shfmt yamllint xmlstarlet \
    python3 python3-pip python3-venv \
    nasm yasm autoconf automake libtool patchelf \
    ffmpeg sox libsox-fmt-all xvfb imagemagick lcov \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat \
    && ln -sf /usr/bin/clang-format-18 /usr/local/bin/clang-format \
    && ln -sf /usr/bin/clang-tidy-18 /usr/local/bin/clang-tidy \
    && rm -rf /var/lib/apt/lists/*

RUN java -version 2>&1 | grep -q 21

# ── Google Chrome (Flutter web tests + `flutter run -d chrome`) ───────────────
# Download, install, and cleanup in the same layer to avoid retaining the .deb.
# hadolint ignore=DL3008,DL3015
RUN curl -fsSL "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" \
        -o /tmp/google-chrome.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/google-chrome.deb \
    && rm -f /tmp/google-chrome.deb \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 22 + JS/Markdown tooling ─────────────────────────────────────────
# NodeSource tracks the latest 22.x patch; npm package versions are pinned.
# hadolint ignore=DL3008
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install --global \
        pnpm@12.15.0 \
        prettier@3.9.10 \
        markdownlint-cli2@0.24.0 \
        serve@14.2.6 \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/*

# ── Flutter SDK (verified against the official release manifest) ──────────────
RUN ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${ARCHIVE}" \
    && EXPECTED_SHA="$(curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json" \
        | jq -r --arg archive "$ARCHIVE" \
            'first(.releases[] | select(.archive | endswith($archive)) | .sha256) // empty')" \
    && test -n "$EXPECTED_SHA" \
    && curl -fsSL "$URL" -o /tmp/flutter.tar.xz \
    && echo "${EXPECTED_SHA}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory /opt/flutter

RUN flutter config --no-analytics --no-cli-animations \
    && dart --disable-analytics \
    && flutter --version

# ── Android SDK / NDK ────────────────────────────────────────────────────────
RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools && \
    curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip" -o /tmp/cmdline.zip && \
    unzip -q /tmp/cmdline.zip -d /tmp/cmdline && \
    mv /tmp/cmdline/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest && \
    rm -rf /tmp/cmdline.zip /tmp/cmdline

RUN yes | sdkmanager --licenses >/dev/null 2>&1 || true && \
    sdkmanager \
    "platform-tools" \
    "platforms;android-35" \
    "platforms;android-36" \
    "build-tools;36.0.0" \
    "cmake;3.22.1" \
    "ndk;28.2.13676358"

# ── Writable caches for the non-root `vscode` user ───────────────────────────
# postCreate runs as vscode and must be able to update Flutter's cache, install
# SDK packages, and write Dart/Gradle/ccache data. The named volumes declared in
# devcontainer.json inherit these permissions when first initialised.
# Keep compatibility with stale VS Code Flutter SDK selections from older containers.
# The canonical SDK remains /opt/flutter; both paths point to the exact same installation.
RUN if [ -e /home/vscode/flutter ] && [ ! -L /home/vscode/flutter ]; then \
        mv /home/vscode/flutter "/home/vscode/flutter.legacy.$(date +%s)"; \
    fi \
    && ln -sfn /opt/flutter /home/vscode/flutter \
    && chown -h vscode:vscode /home/vscode/flutter \
    && mkdir -p /opt/pub-cache /opt/ccache /home/vscode/.gradle /home/vscode/.ccache \
    && chown -R vscode:vscode \
        /opt/flutter \
        /opt/android-sdk \
        /opt/pub-cache \
        /opt/ccache \
        /home/vscode/.gradle \
        /home/vscode/.ccache
