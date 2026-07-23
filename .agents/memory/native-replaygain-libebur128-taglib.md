---
name: Native ReplayGain (libebur128 + TagLib)
description: Android JNI/CMake module replacing the old Kotlin-only ReplayGain scanner; loudness analysis + permanent tag writing.
---

The old `dev.wndavenz.music.replay_gain.ReplayGainScanner` (hand-rolled Kotlin
K-weighting biquads, read/cache-only, never wrote tags) was replaced with a
native module at `android/app/src/main/cpp/` + Kotlin package
`dev.wndavenz.music.replaygain`:

- **libebur128** (CMake FetchContent, tag `v1.2.6`) does the actual EBU R128
  / ITU-R BS.1770-4 math (integrated LUFS, LRA, true peak). Kotlin still owns
  MediaExtractor/MediaCodec decoding (`PcmDecoder.kt`) and streams PCM across
  JNI into a per-track `ebur128_state*` (`EburTrackSession`/`ReplayGainNative`).
  Album gain uses libebur128's true multi-track album-loudness API
  (`ebur128_loudness_global_multiple`), not an average of independent track
  LUFS values.
- **TagLib** (CMake FetchContent, tag `v2.3`) does metadata-only tag writing:
  ID3v2 TXXX (MP3), Xiph/Vorbis comment (FLAC/Ogg Vorbis/Ogg Opus), plus
  R128_TRACK_GAIN/R128_ALBUM_GAIN (Q7.8 fixed point, -23 LUFS reference) for
  Opus. `WriteResult`/`ReplayGainError` ordinals are shared verbatim between
  C++ (`tag_writer.h`) and Kotlin (`ReplayGainModels.kt`) — keep them in sync
  positionally if either side changes.

**Why TagLib over jaudiotagger/other JVM libs:** pure C++, no
javax.imageio/AWT dependency (a known Android-incompatibility risk in
jaudiotagger), guaranteed metadata-only file rewrites (audio stream never
touched/re-encoded), and it's already alongside libebur128 in the same native
module so there's one dependency covering all four writable formats instead
of mixing several JVM libraries with per-format quirks.

**Deliberately out of scope:** M4A/AAC tag *writing* — MP4 atom writing via
TagLib was disabled in CMakeLists.txt (`WITH_MP4 OFF`) to shrink the binary;
M4A stays read-only via the existing `ExoMetadataReader` path.
`TagFormat.fromPath()` returns null for M4A/AAC, and callers should expect
`UNSUPPORTED_FORMAT`.

**Why:** this sandbox has no Android SDK/NDK/CMake, so the CMakeLists.txt,
JNI bridge, and Gradle `externalNativeBuild` block have never actually been
compiled here — only Dart was verified via Flutter Analyze. The exported
CMake target names (`ebur128`, `tag`) were confirmed by reading each
project's own CMakeLists.txt on GitHub at the pinned tags, but must be
re-verified against the real Gradle/CMake configure log on the first real
build (Android Studio or the `.github/workflows/android.yml` CI) since a
future upstream release could rename them.

**How to apply:** if a future task touches ReplayGain again, start from
`ReplayGainService.kt` (Kotlin orchestrator: `scanTrack`/`scanAlbum`/
`writeReplayGain`/`removeReplayGain`) rather than re-adding Kotlin-side DSP
math — the native side already owns all loudness math and tag I/O.
