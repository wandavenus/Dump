---
name: ReplayGain architecture
description: Phase 4 loudness normalization — models, services, native Kotlin, wiring into AudioService dan settings UI.
---

## Komponen utama

| File | Peran |
|---|---|
| `lib/models/loudness_data.dart` | `LoudnessData` (gainDb, peakLinear, source enum) + `LoudnessSource` enum |
| `lib/models/replay_gain_mode.dart` | `ReplayGainMode` enum: off / auto / track / album |
| `lib/services/replay_gain_service.dart` | Baca tag native via MethodChannel `musicplayer/media_store` (`getReplayGainTags`); cache di SharedPrefs key `rg_<id>_gain/peak/src` |
| `lib/services/loudness_source_resolver.dart` | Branching priority: RG track → RG album → R128 → iTunNORM → none |
| `MainActivity.kt` (`getReplayGainTags`) | Baca via jaudiotagger: REPLAYGAIN_TRACK/ALBUM_GAIN/PEAK, R128_TRACK/ALBUM_GAIN, iTunNORM |

## Priority chain (per track)
1. REPLAYGAIN_TRACK_GAIN (ID3/Vorbis/APEv2)
2. R128_TRACK_GAIN (+5 dB offset karena ref level berbeda)
3. iTunNORM (decode hex, convert ke dB)
4. LoudnessData.none → AudioEngine.applyNormalize(enabled: false)

## Wiring ke AudioService
- `_applyReplayGain(song)` dipanggil di `playSongAt`, `_playCurrentSong`, dan `_afterPromotion`.
- `_previousSong` disimpan untuk Auto mode (album gain saat lagu berurutan dari album sama).
- Gain dikirim ke `AudioEngine.applyNormalize(enabled: true, targetGainMb: gainDb * 100)`.

## AudioEngine.applyNormalize()
- Android: `AndroidLoudnessEnhancer.setTargetGain(mb)` clamp ±2400 mb (±24 dB).
- Web/non-Android: approximasi via `player.setVolume(linear_gain.clamp(0.1, 1.0))`.

## Settings UI
- Section `_ReplayGainSection` di `settings_page/audio.dart`.
- `SettingsActionRow` → bottom sheet `_ReplayGainModePicker` (4 pilihan).
- Preamp slider ±15 dB muncul hanya saat mode != off.
- SharedPrefs keys: `replayGainMode` (int), `replayGainPreamp` (double).

## Android 11 + MIUI 12
- jaudiotagger sudah ada di classpath (dari fitur embedded lyrics sebelumnya).
- `getReplayGainTags` menggunakan `org.jaudiotagger.tag.FieldKey` untuk ID3/Vorbis.
- Fallback TXXX frame lookup untuk R128 dan iTunNORM custom atoms.
- Android 11 (API 30): scoped storage tidak mempengaruhi karena path sudah didapat dari MediaStore sebelumnya.

## Known limitations
- Analisis on-demand (scan loudness real-time) belum diimplementasi — fallback ke LoudnessData.none jika tidak ada tag.
- iTunNORM hanya bisa dibaca via jaudiotagger pada M4A yang didukung.
- R128 di MP3 TXXX frame membutuhkan case-insensitive match (sudah dihandle via `equals(ignoreCase=true)`).

**Why:** `AndroidLoudnessEnhancer` menerima millibels (bukan dB langsung). Konversi: gainMb = gainDb × 100.
