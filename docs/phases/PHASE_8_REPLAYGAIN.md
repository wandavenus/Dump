# Phase 8 — ReplayGain Engine

## Objective

Production-quality ReplayGain playback engine integrated into the native DSP
pipeline. Metadata-driven gain stage — audio files are never modified.

---

## Architecture

```
Media3 (ExoPlayer)
  ↓
NativeDspAudioProcessor  (JNI — float PCM in-place)
  ↓  slot 0 — dsp.gain          (manual volume trim)
  ↓  slot 1 — dsp.replaygain    (Phase 8 — this processor)
  ↓  slot 2 — dsp.peq           (Parametric EQ)
  ↓  slot 3 — dsp.compressor    (Soft-knee compressor)
  ↓  slot 4 — dsp.crossfeed     (Headphone crossfeed)
  ↓  slot 5 — dsp.limiter       (Look-ahead brickwall)
  ↓  slot 6 — dsp.soft_clipper  (Tanh waveshaper)
  ↓
StereoWideningAudioProcessor
  ↓
SilenceSkippingAudioProcessor
  ↓
SonicAudioProcessor
  ↓
Audio Output
```

---

## 1. ReplayGain Processor (`dsp.replaygain`)

**File:** `native_audio_runtime/src/replaygain_processor.c/h`

A transparent, zero-latency scalar-multiply gain stage at pipeline slot 1.
- Zero algorithmic latency (no IIR, no look-ahead).
- Lock-free atomic parameter updates (IEEE 754 bit-pattern trick, same as
  `gain_processor.c`).
- Starts **bypassed** — engaged only after Dart resolves metadata.
- Stateless — `reset()` is a no-op.

### Audio-thread hot path

```
atomic_load(_bypass)  →  if 1, return early (zero-copy bypass)
atomic_load(_gain_bits)  →  memcpy bits→float
for each sample: data[i] *= g   (auto-vectorized by NEON on arm64)
```

No transcendentals, no branches, no heap allocation on the audio thread.

---

## 2. Metadata Support

**Formats supported (in priority order):**

| Tag | Format | Notes |
|-----|--------|-------|
| `REPLAYGAIN_TRACK_GAIN` / `REPLAYGAIN_ALBUM_GAIN` | ReplayGain v1/v2 | Primary standard |
| `R128_TRACK_GAIN` / `R128_ALBUM_GAIN` | EBU R128 | Offset-adjusted to RG reference |
| `iTunNORM` | Apple SoundCheck | Parsed from iTunNORM comment tag |

**Peak fields:**
- `REPLAYGAIN_TRACK_PEAK` / `REPLAYGAIN_ALBUM_PEAK` — linear (e.g. 1.0532)

**Service:** `lib/services/replay_gain_service/service.dart`  
→ Reads via `musicplayer/media_store` MethodChannel (Kotlin `ReplayGainScanner`)  
→ Caches in SharedPreferences (`rg_<songId>`) — avoids repeated file scans.

**Model:** `lib/models/loudness_data.dart`  
→ `LoudnessData(gainDb, peakLinear?, source)`

---

## 3. Playback Modes

**Enum:** `lib/models/replay_gain_mode.dart` — `ReplayGainMode`

| Mode | Behaviour |
|------|-----------|
| `off` | Processor bypassed — audio at recorded level |
| `track` | `REPLAYGAIN_TRACK_GAIN` (or R128/iTunNORM equivalent) |
| `album` | `REPLAYGAIN_ALBUM_GAIN`, fallback to track |
| `auto` | Album gain for consecutive same-album tracks; track gain otherwise |

**Resolver:** `lib/services/loudness_source_resolver.dart`  
→ Selects the appropriate `LoudnessData` given `ReplayGainMode` + song context.

---

## 4. Clipping Protection

Optional; controlled by **Clipping Protection** toggle in Settings → Audio Normalize.

**Mechanism (native C, `_compute_effective_gain`):**

```c
float g = powf(10.0f, gain_db / 20.0f);        // dB → linear
if (use_clipping && peak > 0 && g * peak > 1.0f)
    g = 1.0f / peak;                            // cap so g × peak ≤ 1.0
g = clamp(g, kMinGain, kMaxGain);               // ±24 dB safety rail
atomic_store(&_gain_bits, float_to_bits(g));
```

- Computed on the **control thread** (Dart call via FFI) — `powf` is off the
  audio hot path.
- When `peakLinear = 0.0` (no peak tag) the protection step is skipped and
  dynamics are fully preserved.

---

## 5. PlaybackManager Public API

**File:** `lib/services/audio/playback_manager.dart`

```dart
// Apply gain to the native DSP processor.
PlaybackManager.setNativeReplayGain(
  gainDb: gainDb,              // metadata gain + user preamp
  peakLinear: peakLinear,      // 0.0 if no peak tag
  useClippingProtection: true,
);

// Bypass / un-bypass.
PlaybackManager.setNativeReplayGainBypass(bool bypass);

// Status queries.
PlaybackManager.nativeReplayGainBypassed;   // bool
PlaybackManager.nativeReplayGainAvailable;  // bool (pipeline initialized)
```

**`PlaybackManager` remains the only public caller of `NativeReplayGain`.**
UI and service code use `AudioEffectsService` → `AudioService._applyReplayGain`.

---

## 6. AudioEffectsService State

**File:** `lib/services/audio/audio_effects_service/service.dart`

| ValueNotifier | Key | Default |
|---------------|-----|---------|
| `replayGainMode` | `replayGainMode` | `ReplayGainMode.off` |
| `replayGainPreamp` | `replayGainPreamp` | `0.0 dB` |
| `clippingProtection` | `rgClipProtect` | `true` |

All three trigger `AudioService._applyReplayGain()` on change.

---

## 7. Gain Application Flow

```
Track change / setting change
  ↓
AudioService._applyReplayGain(song)
  ↓
LoudnessSourceResolver.resolve(song, mode, previousSong)
  → ReplayGainService.resolveBoth(song)   [SharedPrefs cache → MethodChannel]
  ↓
PlaybackManager.setNativeReplayGain(gainDb, peakLinear, useClip)
  → NativeReplayGain.instance.setGain(...)
    → nar_replaygain_set_gain(gain_db, peak_linear, use_clipping)
      → _compute_effective_gain() [powf + clip cap + clamp]
      → atomic_store(&_gain_bits, bits)
  ↓  (next audio thread render)
  → atomic_load(&_gain_bits)
  → for each sample: data[i] *= g
```

---

## 8. Thread Safety

| Thread | Guarantee |
|--------|-----------|
| Audio (ExoPlayer) | Zero locks, zero heap, deterministic: single `atomic_load` + scalar multiply |
| Control (Dart/JNI) | `atomic_store` of pre-computed linear gain — no locking needed |

---

## 9. Files Added

| File | Description |
|------|-------------|
| `native_audio_runtime/src/replaygain_processor.c` | C processor implementation |
| `native_audio_runtime/src/replaygain_processor.h` | C header / public API |
| `docs/PHASE_8_REPLAYGAIN.md` | This document |

## 10. Files Modified

| File | Change |
|------|--------|
| `native_audio_runtime/lib/native_audio_runtime_bindings_generated.dart` | FFI bindings added |
| `native_audio_runtime/lib/src/dsp_pipeline_io.dart` | Registration (slot 1) + `NativeReplayGain` facade |
| `native_audio_runtime/lib/src/dsp_pipeline_unsupported.dart` | `NativeReplayGain` web stub |
| `lib/services/audio/playback_manager.dart` | `setNativeReplayGain`, `setNativeReplayGainBypass`, `nativeReplayGainBypassed` |
| `lib/services/audio/audio_effects_service/service.dart` | `clippingProtection` VN + `setClippingProtection` |
| `lib/services/audio_service/service.dart` | `_applyReplayGain` → native DSP (was LoudnessEnhancer) |
| `lib/pages/settings_page/audio.dart` | Clipping Protection toggle in Audio Normalize section |

---

## 11. Remaining Work Before Loudness Normalization

1. **True integrated loudness scanning** (EBU R128 LUFS) — `ReplayGainScanner.kt`
   exists but its results are stored separately from the tag-based path; the two
   systems should be unified into a single `LoudnessData` source with a preference
   order: tags → scanner fallback.

2. **Metadata via Media3 extractors** — investigate whether ExoPlayer's
   `MetadataRetriever` can surface `REPLAYGAIN_*` frames directly (avoiding the
   separate MethodChannel scan for most files).

3. **Crossfeed UI** — the crossfeed processor (`dsp.crossfeed`) has no settings
   page yet (preset selector, amount/cutoff/width sliders). Needed before any
   further DSP phase work.

4. **Sample-rate tracking** — when ExoPlayer reports a sample-rate change between
   tracks, `setNativeCrossfeedParams` (and eventually any rate-dependent filter)
   must be re-called with the updated rate.

5. **Loudness Normalization (Phase 9)** — LUFS-based target loudness using the
   `ReplayGainScanner.kt` R128 engine; separate from ReplayGain metadata mode.
