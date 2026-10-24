# FFmpeg JNI hardening

## Changes applied

- Native static-library cache uses a fingerprint of the FFmpeg source revision, configure arguments, target ABI/API, pinned NDK/compiler, decoder set, and build recipe. Missing libraries or a changed fingerprint force a clean FFmpeg reconfigure/rebuild.
- Gradle task inputs include the FFmpeg tag, Android API, NDK version, ABI, build script, and JNI source.
- The build script rejects an unexpected NDK version, validates all required static archives, and records the output fingerprint only after the linked JNI library passes export, dependency, and decoder checks.
- LGPL-2.1 and Apache-2.0 license texts and third-party notices are packaged as Android assets; the repository-level license statement explicitly excludes third-party components.
- CI installs the pinned NDK, runs on pull requests, assembles a debug APK, runs unit tests, and checks that the native library and license assets are in the APK.

## Verification boundary

CI build/package checks are the source of truth for compilation and packaging. Physical-device validation remains separate: install a fresh APK on an arm64 Android device, verify FfmpegCapabilityProbe reports the expected codecs, and test ALAC, DTS, TrueHD, Vorbis, and Opus playback.

The FFmpeg source and build recipe are included/referenced in the repository, but packaging notices alone do not establish full LGPL compliance for the combined native library. Review source availability, replacement/relinking requirements, and the actual distribution method before publishing.
