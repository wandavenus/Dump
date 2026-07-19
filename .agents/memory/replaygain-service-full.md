---
name: ReplayGain Service Full
description: ReplayGainService Dart API, LoudnessSourceResolver logic, LoudnessData model, ReplayGain Kotlin/JNI layer.
---

# ReplayGain Service — Full Map

## ReplayGainService (`lib/services/replay_gain_service/service.dart`)

**Scan flow:**
1. Receives `LocalSong` list
2. Reads existing tags via `ExoMetadataReader` (MetadataCacheDb SQLite lookup by mtime)
3. Songs without valid tags → JNI → `ReplayGainScanner.kt` → `libebur128` offline EBU R128 analysis
4. Scan result → `MetadataCacheDb` (SQLite, mtime-keyed)
5. Write tags → `ReplayGainTagger.kt` → TagLib (temp-file + atomic-rename)

**Public API:**
- `scanSongs(List<LocalSong>)` → writes tags + updates cache
- `getGainForSong(LocalSong)` → returns `LoudnessData?` from cache

**Notes:**
- M4A tag write unsupported (TagLib limitation) — by design
- Crash-safe: TagLib write = temp-file + atomic-rename

## LoudnessSourceResolver (`lib/services/loudness_source_resolver.dart`)

Picks best loudness source per song:

**Priority order:**
1. Native ReplayGain tags (track or album, per `ReplayGainMode`)
2. Loudness Normalization (EBU R128 native, real-time)
3. None (bypass)

**Mutual exclusion:** ReplayGain and Loudness Normalization cannot be active simultaneously.

## LoudnessData (`lib/models/loudness_data.dart`)

```dart
class LoudnessData {
  final double? trackGain;    // dB, e.g. -7.3
  final double? albumGain;    // dB
  final double? trackPeak;    // linear, for clipping protection
  final double? albumPeak;    // linear
  final LoudnessSource source; // enum: replayGain / loudnessNorm / none
}

enum LoudnessSource { replayGain, loudnessNorm, none }
```

## Kotlin ReplayGain Layer (`android/app/src/main/kotlin/.../replaygain/`)

### ReplayGainScanner.kt
- Calls JNI `Java_dev_wndavenz_music_replaygain_ReplayGainNative_scan*`
- Passes PCM data from ExoPlayer decode to libebur128
- Returns integrated loudness LUFS + true-peak linear

### ReplayGainTagger.kt
- Calls JNI `Java_dev_wndavenz_music_replaygain_ReplayGainNative_write*`
- TagLib writes: FLAC (VORBIS_COMMENT), MP3 (ID3v2), OGG (VORBIS_COMMENT), OPUS
- M4A write → not supported, silently skipped
- Atomic write: write to `.tmp` file → `rename()` → original path

## libebur128 vs loudness_processor.c

| | libebur128 (offline scanner) | loudness_processor.c (real-time DSP) |
|---|---|---|
| Use | Offline tag scanning | Real-time pipeline normalization |
| Algorithm | Exact ITU-R BS.1770-4 | Causal IIR approximation |
| Location | `android/app/src/main/cpp/libebur128/` | `native_audio_runtime/src/` |
| Output | LUFS measurement for tag writing | Gain smoothing for live playback |

## ReplayGain DSP (native_audio_runtime slot 1)

- `nar_replaygain_set_gain(gain_db, peak_linear)`
- Applied FIRST in pipeline (slot 1) — before all other processors
- Effective linear gain pre-computed on control thread
- Clipping protection: `min(gain_linear, 1.0 / peak_linear)`
- NaN/Inf sanitization on all inputs
