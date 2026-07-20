FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_VERSION=3.44.5
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk
ENV FLUTTER_HOME=/opt/flutter
ENV PUB_CACHE=/opt/pub-cache
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/build-tools/36.0.0:${JAVA_HOME}/bin:/usr/lib/ccache:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget unzip zip xz-utils \
    openjdk-21-jdk clang cmake ninja-build ccache pkg-config libglu1-mesa file gnupg \
    && rm -rf /var/lib/apt/lists/*

RUN java -version 2>&1 | grep -q 21

RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    -o /tmp/flutter.tar.xz \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory /opt/flutter

RUN flutter config --no-analytics --no-cli-animations
RUN flutter --version

RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools && \
    curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o /tmp/cmdline.zip && \
    unzip -q /tmp/cmdline.zip -d /tmp/cmdline && \
    mv /tmp/cmdline/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest && \
    rm -rf /tmp/cmdline.zip /tmp/cmdline

RUN yes | sdkmanager --licenses >/dev/null 2>&1 || true && \
    sdkmanager \
    "platform-tools" \
    "platforms;android-35" \
    "build-tools;36.0.0" \
    "cmake;3.22.1" \
    "ndk;28.2.13676358"

RUN mkdir -p /opt/pub-cache /opt/ccache && chmod -R 777 /opt/pub-cache /opt/ccache /opt/flutter /opt/android-sdk
