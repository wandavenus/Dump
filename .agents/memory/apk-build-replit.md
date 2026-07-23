---
name: Replit APK build environment
description: Environment requirements and failure modes for building the Android APK on Replit.
---

# Replit APK build environment

The APK build requires a writable Flutter workspace copy, a runnable JDK 17, Android SDK/NDK/CMake, and Ninja. `build-apk.sh` validates each tool and links Ninja into the configured CMake directory because Android Gradle may not discover a PATH-only Ninja binary.

**Why:** The first imported-project build could report success for partial Flutter/JDK installations, then fail during native CMake configuration because Ninja was absent. Concurrent setup workflows also produced incomplete Flutter copies.

**How to apply:**
- Run `bash setup-flutter.sh && bash build-apk.sh` from the project root.
- Keep setup serialized and copy Flutter atomically.
- Keep `ninja` in the Replit system dependencies.
- Treat `build/app/outputs/flutter-apk/app-debug.apk` as the successful debug artifact.