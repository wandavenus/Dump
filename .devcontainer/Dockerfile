# ─────────────────────────────────────────────────────────────────────────────
# Dev Container — Flutter Android (GitHub Codespaces)
# Base: Ubuntu 24.04
# Flutter: 3.44.5 stable
# Java: OpenJDK 21 (Temurin-compatible)
# Android SDK: platform-tools + platforms;android-35 + build-tools;36.0.0
#              + cmake;3.22.1 + ndk;28.2.13676358
# ─────────────────────────────────────────────────────────────────────────────

FROM ubuntu:24.04

# ── Non-interactive apt ───────────────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ── Version pins ──────────────────────────────────────────────────────────────
ENV FLUTTER_VERSION=3.44.5
ENV ANDROID_CMDLINE_TOOLS_BUILD=11076708

# ── Install paths (fixed; never change without updating devcontainer.json) ────
ENV FLUTTER_HOME=/opt/flutter
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk
ENV PUB_CACHE=/opt/pub-cache

# ── Java home (openjdk-21-jdk on amd64) ──────────────────────────────────────
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64

# ── PATH (all toolchains available in every shell / RUN step) ─────────────────
ENV PATH="\
${FLUTTER_HOME}/bin:\
${FLUTTER_HOME}/bin/cache/dart-sdk/bin:\
${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:\
${ANDROID_SDK_ROOT}/platform-tools:\
${ANDROID_SDK_ROOT}/build-tools/36.0.0:\
${JAVA_HOME}/bin:\
/usr/lib/ccache:\
${PATH}"

# ─────────────────────────────────────────────────────────────────────────────
# 1. System packages
#    Layer is cached as long as this list doesn't change.
# ─────────────────────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        # VCS / download
        git \
        curl \
        wget \
        unzip \
        zip \
        xz-utils \
        # Java 21
        openjdk-21-jdk \
        # Native toolchain
        clang \
        cmake \
        ninja-build \
        ccache \
        pkg-config \
        # Flutter web rendering deps (required even for Android-only builds)
        libglu1-mesa \
        # Misc utils needed by sdkmanager / gradle wrappers
        file \
        gnupg \
    && rm -rf /var/lib/apt/lists/*

# Verify Java 21 is the active JDK
RUN java -version 2>&1 | grep -q "21" && echo "✓ Java 21 confirmed"

# ─────────────────────────────────────────────────────────────────────────────
# 2. Flutter SDK
#    Extracted to /opt/flutter; precache runs here so the ~650 MB artifact
#    bundle is baked into the image layer — no download on first Codespace start.
# ─────────────────────────────────────────────────────────────────────────────
RUN echo "▶ Downloading Flutter ${FLUTTER_VERSION}..." && \
    curl -fsSL \
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        -o /tmp/flutter.tar.xz && \
    echo "▶ Extracting Flutter..." && \
    tar -xJf /tmp/flutter.tar.xz -C /opt && \
    rm /tmp/flutter.tar.xz && \
    chmod -R a+rx /opt/flutter

# Disable telemetry / analytics in the image
RUN flutter config --no-analytics --no-cli-animations 2>/dev/null || true

# Precache Android artifacts (downloads engine, Dart SDK, gradle wrapper, etc.)
# This is the main startup-time optimization — nothing to download on first run.
RUN flutter precache --android --no-web --no-ios 2>/dev/null

# Verify flutter binary works
RUN flutter --version

# ─────────────────────────────────────────────────────────────────────────────
# 3. Android SDK — command-line tools
# ─────────────────────────────────────────────────────────────────────────────
RUN echo "▶ Downloading Android command-line tools (build ${ANDROID_CMDLINE_TOOLS_BUILD})..." && \
    mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools && \
    curl -fsSL \
        "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_BUILD}_latest.zip" \
        -o /tmp/cmdline-tools.zip && \
    unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-extract && \
    # Google bundles it as "cmdline-tools/"; rename to "latest" per SDK convention
    mv /tmp/cmdline-tools-extract/cmdline-tools \
       ${ANDROID_SDK_ROOT}/cmdline-tools/latest && \
    rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools-extract

# ─────────────────────────────────────────────────────────────────────────────
# 4. Android SDK packages
#    Accept licenses non-interactively, then install the exact versions the
#    project requires.  NDK and cmake are large; they're baked in so Gradle
#    never has to download them inside a Codespace.
# ─────────────────────────────────────────────────────────────────────────────
RUN yes | sdkmanager --licenses > /dev/null 2>&1 || true

RUN sdkmanager --verbose \
        "platform-tools" \
        "platforms;android-35" \
        "build-tools;36.0.0" \
        "cmake;3.22.1" \
        "ndk;28.2.13676358"

# Accept any newly generated licenses after package install
RUN yes | sdkmanager --licenses > /dev/null 2>&1 || true

# Verify critical SDK components exist
RUN test -d "${ANDROID_SDK_ROOT}/ndk/28.2.13676358" \
    && echo "✓ NDK 28.2.13676358 confirmed" \
    || (echo "✗ NDK missing" && exit 1)

RUN test -d "${ANDROID_SDK_ROOT}/cmake/3.22.1" \
    && echo "✓ CMake 3.22.1 confirmed" \
    || (echo "✗ CMake 3.22.1 missing" && exit 1)

# ─────────────────────────────────────────────────────────────────────────────
# 5. Shared cache directories
#    /opt/pub-cache   — Dart pub package cache (PUB_CACHE env points here)
#    /opt/gradle-home — Gradle dist/dependency cache (mounted as volume)
#    /opt/ccache      — ccache data dir
#    All created world-writable so the Codespace "vscode" user can write to them.
# ─────────────────────────────────────────────────────────────────────────────
RUN mkdir -p /opt/pub-cache /opt/gradle-home /opt/ccache && \
    chmod -R 777 /opt/pub-cache /opt/gradle-home /opt/ccache

# ─────────────────────────────────────────────────────────────────────────────
# 6. Permissions
#    Make the entire SDK and Flutter tree readable + executable by any user
#    (Codespaces runs as "vscode" — UID 1000 — not root).
# ─────────────────────────────────────────────────────────────────────────────
RUN chmod -R a+rX /opt/flutter && \
    chmod -R a+rX ${ANDROID_SDK_ROOT} && \
    # SDK dirs that sdkmanager/Gradle need to write into at runtime
    chmod -R a+rwX \
        ${ANDROID_SDK_ROOT}/.temp \
        ${ANDROID_SDK_ROOT}/.knownPackages 2>/dev/null || true && \
    chmod a+w ${ANDROID_SDK_ROOT} && \
    find ${ANDROID_SDK_ROOT} -maxdepth 2 -type d -exec chmod a+w {} + 2>/dev/null || true

# Ensure ccache shims are executable
RUN update-ccache-symlinks 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# Default shell for postCreate and interactive use
# ─────────────────────────────────────────────────────────────────────────────
SHELL ["/bin/bash", "-c"]
