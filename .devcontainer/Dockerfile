FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_VERSION=3.47.7
ENV FLUTTER_SHA256=af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_NDK_HOME=/opt/android-sdk/ndk/28.2.13676358
ENV ANDROID_NDK_ROOT=/opt/android-sdk/ndk/28.2.13676358
ENV ANDROID_NDK=/opt/android-sdk/ndk/28.2.13676358
ENV FLUTTER_HOME=/opt/flutter
ENV PUB_CACHE=/opt/pub-cache
ENV GRADLE_USER_HOME=/home/vscode/.gradle
ENV CCACHE_DIR=/home/vscode/.ccache
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/build-tools/36.0.0:${JAVA_HOME}/bin:/usr/lib/ccache:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget unzip zip xz-utils \
    openjdk-21-jdk clang g++ cmake ninja-build ccache pkg-config libglu1-mesa libgtk-3-dev file gnupg \
    nodejs npm python3 python3-pip python3-venv jq ffmpeg \
    && npm install -g pnpm@10 \
    && rm -rf /var/lib/apt/lists/*

RUN java -version 2>&1 | grep -q 21

RUN mkdir -p /opt/pub-cache /opt/ccache && chmod -R 777 /opt/pub-cache /opt/ccache

# Flutter resmi: versi dipin + checksum diverifikasi.
RUN curl -fsSL --retry 3 --connect-timeout 30 "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        -o /tmp/flutter.tar.xz \
    && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --system --add safe.directory /opt/flutter

RUN flutter config --no-analytics --no-cli-animations
RUN flutter --version

RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools && \
    curl -fsSL --retry 3 --connect-timeout 30 "https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip" -o /tmp/cmdline.zip && \
    unzip -q /tmp/cmdline.zip -d /tmp/cmdline && \
    mv /tmp/cmdline/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest && \
    rm -rf /tmp/cmdline.zip /tmp/cmdline

RUN yes | sdkmanager --sdk_root="${ANDROID_SDK_ROOT}" --licenses >/dev/null 2>&1 || true && \
    sdkmanager --sdk_root="${ANDROID_SDK_ROOT}" \
    "platform-tools" \
    "platforms;android-34" \
    "platforms;android-35" \
    "platforms;android-36" \
    "build-tools;36.0.0" \
    "cmake;3.22.1" \
    "ndk;28.2.13676358"

# postCreate/postStart berjalan sebagai vscode, bukan root. Tanpa chown ini
# Flutter dan sdkmanager tidak bisa menulis cache/SDK saat rebuild.
RUN chown -R vscode:vscode /opt/flutter /opt/android-sdk \
    && mkdir -p /opt/pub-cache /opt/ccache /home/vscode/.gradle /home/vscode/.ccache \
    && chmod -R 777 /opt/pub-cache /opt/ccache \
    && chown -R vscode:vscode /home/vscode/.gradle /home/vscode/.ccache
