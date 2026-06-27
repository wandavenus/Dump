# Rencana Migrasi: Native Media3 → media_kit

> **Target device:** Xiaomi Mi 9T / K20 — Snapdragon 730 — Android 11 — MIUI 12  
> **Scope:** Offline music player (tanpa fitur video/streaming)  
> **Dibuat:** 26 Juni 2026  
> **Status:** DRAFT — Perlu review sebelum eksekusi

---

## Daftar Isi

1. [Ringkasan Eksekutif](#1-ringkasan-eksekutif)
2. [Inventaris Arsitektur Saat Ini](#2-inventaris-arsitektur-saat-ini)
3. [Analisis Kompatibilitas media_kit](#3-analisis-kompatibilitas-media_kit)
4. [Matriks Fitur: Media3 → media_kit](#4-matriks-fitur-media3--media_kit)
5. [Isu Kritis: Android 11 + MIUI 12 + Snapdragon 730](#5-isu-kritis-android-11--miui-12--snapdragon-730)
6. [Strategi Migrasi per Fase](#6-strategi-migrasi-per-fase)
7. [Detail Implementasi per Fitur](#7-detail-implementasi-per-fitur)
8. [Arsitektur Target (Post-Migration)](#8-arsitektur-target-post-migration)
9. [Channel & Event Contract Baru](#9-channel--event-contract-baru)
10. [Estimasi Effort & Risiko](#10-estimasi-effort--risiko)
11. [Testing Checklist](#11-testing-checklist)
12. [Go / No-Go Criteria](#12-go--no-go-criteria)

---

## 1. Ringkasan Eksekutif

### Mengapa media_kit?

| Aspek | Media3 (saat ini) | media_kit |
|---|---|---|
| Engine | ExoPlayer (Java/Kotlin) | libmpv (C + FFmpeg) |
| Pendekatan | Kotlin-native, deep Android integration | Cross-platform, Dart-first |
| Format support | Bergantung pada codec Android | FFmpeg — hampir semua format |
| Maintenance | Google (aktif) | Komunitas (aktif, ~1.x) |
| Kompleksitas kode | ~27 file Kotlin, ~2100 baris | Potensi ~5 file Kotlin + Dart |
| Audio effects | Android AudioEffect API (system-level) | libmpv lavfi / FFmpeg filters |
| Crossfade | Custom Kotlin (CrossfadeController) | Custom Dart (dua Player instance) |

### Peringatan Utama

> ⚠️ **RISIKO TINGGI: Audio Effects**  
> Implementasi saat ini menggunakan `Android AudioEffect API` (Equalizer, BassBoost, Virtualizer, PresetReverb, LoudnessEnhancer) yang bergantung pada **Audio Session ID** dari ExoPlayer. media_kit menggunakan libmpv dengan `ao=audiotrack` dan **tidak mengekspos Audio Session ID** secara langsung. Seluruh pipeline audio effects harus didesain ulang menggunakan **FFmpeg lavfi filters** (di libmpv) atau audio processing murni Dart.

> ⚠️ **RISIKO TINGGI: MediaSession / Notifikasi**  
> media_kit tidak menyertakan background service atau MediaSession. Diperlukan integrasi manual dengan paket `audio_service` atau membuat foreground service Kotlin sendiri.

> ⚠️ **RISIKO MENENGAH: MIUI 12 Background Kill**  
> MIUI 12 pada Mi 9T sangat agresif dalam mematikan background process. Implementasi foreground service baru harus mengikuti pola yang sudah diketahui bekerja di MIUI 12 (sama seperti yang sudah ada di implementasi Media3 saat ini).

---

## 2. Inventaris Arsitektur Saat Ini

### File Kotlin (27 file)

```
Media3PlaybackService.kt       ← Orkestrator utama (MediaSessionService)
ActivePlayerProxy.kt           ← Proxy player untuk MediaSession
MainActivity.kt                ← MethodChannel & EventChannel registration
ArtworkCacheManager.kt         ← LruCache artwork async loader
audio_focus/
  AudioFocusManager.kt         ← AudioFocus request/abandon + ducking
audio_offload/
  AudioOffloadManager.kt       ← Hardware offload state observer
crossfade/
  CrossfadeController.kt       ← Equal-power fade (sin/cos curve)
  PreloadManager.kt            ← Standby player preload + prewarm
  CrossfadeTimelineLogger.kt   ← Diagnostics
diagnostics/
  SessionAuditLogger.kt        ← Per-session playback audit
effects/
  AudioEffectsManager.kt       ← EQ, BassBoost, Virtualizer, Reverb, Loudness
  StereoWideningAudioProcessor.kt  ← Custom BaseAudioProcessor (PCM16 + Float)
  StereoWidthManager.kt        ← Atomic stereo-width untuk multi-player
events/
  EventEmitter.kt              ← Semua EventChannel outbound
  SessionAuditLogger.kt
metadata/
  ExoMetadataReader.kt         ← ExoPlayer MetadataRetriever (embedded tags)
  MetadataCacheDb.kt           ← SQLite cache (mtime-keyed)
  MetadataPrescanner.kt        ← Background scan coordinator
  TagBuilder.kt                ← FLAC/OGG/M4A tag parser
notification/
  PlaybackNotificationManager.kt  ← MediaStyle notification + artwork cache
queue/
  QueueManager.kt              ← Queue state + incremental rebuild (addMediaItems)
  QueueSync.kt                 ← SharedPreferences persistence
replay_gain/
  ReplayGainScanner.kt         ← EBU R128 scanner via MediaCodec + K-weighting
sleep_timer/
  SleepTimerManager.kt         ← Duration fade-out + end-of-song mode
transport/
  TransportCommands.kt         ← MethodChannel inbound dispatcher
  TransportState.kt            ← State emit + position ticker
utils/
  MediaItemFactory.kt          ← Flutter map → MediaItem converter
  TrackMapper.kt               ← MediaItem → Flutter map converter
```

### MethodChannels (inbound dari Dart)

| Channel | Jumlah Methods |
|---|---|
| `musicplayer/media3_playback` | 38 metode |
| `musicplayer/audio_effects` | 5 metode |
| `musicplayer/media_store` | 14 metode |
| `musicplayer/native_commands` | Debug/diagnostic |

### EventChannels (outbound ke Dart)

```
musicplayer/media3_playbackState   playing, processingState
musicplayer/media3_position        posisi ms
musicplayer/media3_duration        durasi ms
musicplayer/media3_currentTrack    metadata lagu aktif
musicplayer/media3_queue           queue list
musicplayer/media3_bufferingState  buffering bool
musicplayer/media3_audioSessionId  session ID
musicplayer/media3_shuffleMode     bool
musicplayer/media3_repeatMode      off/one/all
musicplayer/media3_sleepTimer      active, remainingMs, endOfSong
musicplayer/media3_offloadState    osGranted bool
musicplayer/media3_audioFormat     sample rate, bitrate, mime, dll
musicplayer/media3_skipSilence     bool
musicplayer/media3_stereoWidening  enabled, strength
musicplayer/native_logs            debug logs
```

### SharedPreferences (Persistence)

File: `media3_queue_prefs`  
Keys: `queue_json`, `queue_index`, `position_ms`, `repeat_mode`, `shuffle_enabled`

---

## 3. Analisis Kompatibilitas media_kit

### Engine: libmpv via media_kit_libs_android_audio

media_kit pada Android menggunakan `libmpv` yang dikompilasi dengan FFmpeg.  
Audio output menggunakan `ao=audiotrack` (Android AudioTrack API langsung).

### Paket yang Diperlukan

```yaml
# pubspec.yaml
dependencies:
  media_kit: ^1.x
  media_kit_audio: ^1.x                  # Audio-only build (tanpa video)
  media_kit_libs_android_audio: ^1.x     # libmpv Android binary (audio only, ~15 MB)
  audio_service: ^0.18.x                 # Background service + MediaSession
  audio_session: ^0.2.x                  # Audio focus management (sudah ada)
  just_audio_background: null            # TIDAK dipakai (konflik dengan audio_service)
```

### Kemampuan media_kit (Verified)

| Fitur | Status |
|---|---|
| Playback file lokal (MP3/FLAC/OGG/M4A/WAV/OPUS/APE) | ✅ Native libmpv |
| Gapless playback | ✅ `gapless-audio=yes` option |
| Playlist (sequential) | ✅ Native |
| Shuffle | ✅ Native |
| Repeat (none/one/all) | ✅ `PlaylistMode` |
| Seek | ✅ `player.seek()` |
| Volume | ✅ `player.setVolume()` 0–100 |
| Playback speed (rate) | ✅ `player.setRate()` |
| Pitch | ✅ via `af=rubberband` atau `scaletempo2` |
| Multiple Player instances | ✅ (untuk crossfade dual-player) |
| Streams reaktif | ✅ `player.stream.*` |
| State persistence | ❌ Manual (Dart) |
| Background service | ❌ Perlu `audio_service` |
| MediaSession | ❌ Perlu `audio_service` |
| Notification artwork | ❌ Manual via `audio_service` |
| Audio focus | ❌ Perlu `audio_session` |
| Android AudioEffect API (EQ dll) | ❌ Audio Session ID tidak diekspos |
| ReplayGain tagging | ❌ Manual scanner + libmpv `replaygain` option |
| Crossfade | ❌ Custom Dart (2 Player instances) |
| Sleep timer | ❌ Custom Dart |
| Skip silence | ⚠️ `af=silenceremove` (FFmpeg filter, tidak identik) |
| Hi-res audio | ⚠️ Bergantung libmpv output format |
| Stereo widening | ⚠️ `af=extrastereo` (FFmpeg filter, beda karakteristik) |

---

## 4. Matriks Fitur: Media3 → media_kit

### Legenda
- 🟢 **LANGSUNG** — Didukung media_kit secara native
- 🟡 **ULANG DART** — Perlu reimplementasi di Dart di atas media_kit
- 🟠 **ULANG LIBMPV** — Pakai FFmpeg filter via libmpv (karakteristik bisa beda)
- 🔴 **BLOKIR** — Tidak dapat diimplementasi dengan media_kit, perlu solusi alternatif
- ⚫ **BAWAAN** — Tetap sebagai Kotlin native terpisah (bukan bagian media_kit)

---

| Fitur | Saat ini | Target | Catatan |
|---|---|---|---|
| **Playback dasar** | ExoPlayer | 🟢 media_kit | `player.open()`, `play()`, `pause()` |
| **Format audio** | ExoPlayer codecs | 🟢 libmpv/FFmpeg | MP3/FLAC/OGG/M4A/WAV/OPUS/APE/WV |
| **Seek** | ExoPlayer | 🟢 media_kit | `player.seek()` |
| **Volume** | ExoPlayer | 🟢 media_kit | `setVolume(0-100)` |
| **Speed (rate)** | ExoPlayer | 🟢 media_kit | `setRate()` |
| **Pitch** | ExoPlayer | 🟡 ULANG DART | `af=rubberband` via `setProperty` |
| **Shuffle** | ExoPlayer native | 🟢 media_kit | `PlaylistMode` + Dart Fisher-Yates |
| **Repeat** | ExoPlayer | 🟢 media_kit | `PlaylistMode.none/single/loop` |
| **Gapless** | ExoPlayer gapless | 🟢 media_kit | `gapless-audio=yes` |
| **Queue management** | QueueManager.kt | 🟡 ULANG DART | `Playlist` + Dart state |
| **Queue persistence** | QueueSync.kt (SharedPrefs) | 🟡 ULANG DART | `shared_preferences` di Dart |
| **Skip next/prev** | ExoPlayer | 🟢 media_kit | `player.next()` / `player.previous()` |
| **Insert next / append** | QueueManager | 🟡 ULANG DART | Manipulasi `Playlist` Dart |
| **Remove from queue** | QueueManager | 🟡 ULANG DART | |
| **Reorder queue** | QueueManager | 🟡 ULANG DART | |
| **Crossfade** | CrossfadeController.kt | 🟡 ULANG DART | Dua `Player` instance + Dart timer |
| **Preload / prewarm** | PreloadManager.kt | 🟡 ULANG DART | `gapless-audio=yes` sebagian menggantikan |
| **Sleep timer (durasi)** | SleepTimerManager.kt | 🟡 ULANG DART | Dart `Timer` + volume fade |
| **Sleep timer (end-of-song)** | SleepTimerManager.kt | 🟡 ULANG DART | `player.stream.completed` |
| **Background service** | MediaSessionService | ⚫ `audio_service` | Handler + BaseAudioHandler |
| **Notification** | PlaybackNotificationManager | ⚫ `audio_service` | MediaItem + artwork |
| **Lock screen controls** | MediaSession | ⚫ `audio_service` | |
| **AVRCP / Bluetooth** | MediaSession | ⚫ `audio_service` | |
| **Audio focus** | AudioFocusManager.kt | ⚫ `audio_session` | Sudah ada di pubspec |
| **Ducking saat telepon** | AudioFocusManager | ⚫ `audio_session` | |
| **Equalizer (5-band)** | Android AudioEffect API | 🔴 BLOKIR / 🟠 LIBMPV | lihat §7.1 |
| **BassBoost** | Android AudioEffect API | 🔴 BLOKIR / 🟠 LIBMPV | lihat §7.1 |
| **Virtualizer (spatial)** | Android AudioEffect API | 🔴 BLOKIR / 🟠 LIBMPV | lihat §7.1 |
| **PresetReverb** | Android AudioEffect API | 🔴 BLOKIR / 🟠 LIBMPV | lihat §7.1 |
| **LoudnessEnhancer** | Android AudioEffect API | 🟡 ULANG DART | `af=volume` atau gain di libmpv |
| **Stereo widening** | StereoWideningAudioProcessor | 🟠 LIBMPV | `af=extrastereo=...` |
| **Skip silence** | ExoPlayer skipSilence | 🟠 LIBMPV | `af=silenceremove` |
| **ReplayGain scan** | ReplayGainScanner.kt (MediaCodec + EBU R128) | ⚫ TETAP KOTLIN | Terlalu kompleks untuk Dart |
| **ReplayGain apply** | LoudnessEnhancer setTargetGain | 🟠 LIBMPV | `replaygain=track/album` option |
| **Metadata (embedded tags)** | ExoMetadataReader.kt | ⚫ TETAP KOTLIN | MetadataCacheDb SQLite tetap |
| **Lyrics (embedded)** | ExoMetadataReader + MetadataCacheDb | ⚫ TETAP KOTLIN | |
| **Lyrics (LRC file / internet)** | LyricsService.dart | 🟢 DART EXISTING | Tidak berubah |
| **MediaStore (getSongs)** | MediaStoreService.kt | ⚫ TETAP KOTLIN | Scoped storage, tidak berubah |
| **Audio output mode** | AudioOutputMode.kt (AAudio/OpenSL ES/Hi-Res) | 🔴 BLOKIR | libmpv `ao=` tidak granular |
| **Audio offload** | AudioOffloadManager.kt | 🔴 DROPPED | Tidak relevan untuk libmpv |
| **Hi-res audio (24-bit)** | Custom AudioProcessor + pcmEncoding | ⚠️ PARSIAL | libmpv bisa decode, output tergantung OS |
| **Audio format info** | onTracksChanged | 🟡 ULANG DART | `player.stream.tracks` |
| **Playback stats** | PlaybackStatsListener | 🔴 DROPPED | Tidak ada equivalent |
| **Session audit log** | SessionAuditLogger.kt | ⚫ TETAP KOTLIN / 🟡 DART | Opsional |
| **Debug native logs** | NativeLogger.kt | ⚫ TETAP KOTLIN | |
| **MIUI foreground service** | Media3PlaybackService | ⚫ BARU KOTLIN | Service baru berbasis `audio_service` |

---

## 5. Isu Kritis: Android 11 + MIUI 12 + Snapdragon 730

### 5.1 MIUI 12 — Background Process Killer

**Masalah:** MIUI 12 pada Mi 9T menggunakan MACE (Memory Activity Control Engine) yang dapat mematikan background audio service bahkan saat lagu sedang diputar, kecuali ada konfigurasi khusus.

**Solusi yang Wajib:**
```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.WAKE_LOCK" />

<service
    android:name=".MusicPlayerService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="true"
    android:stopWithTask="false">
    <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
    </intent-filter>
</service>
```

**Pola startForeground yang Terbukti Bekerja di MIUI 12:**
- Panggil `startForeground()` SEKALI saja saat `onCreate()` atau `onStartCommand()` pertama — pattern yang sama seperti yang sudah diterapkan di `PlaybackNotificationManager` saat ini.
- Semua update notifikasi berikutnya via `NotificationManager.notify()` bukan `startForeground()` ulang.
- Guard `isForeground: Boolean` wajib ada untuk mencegah double-call.

### 5.2 MIUI 12 — Autostart Permission

**Masalah:** Tanpa izin autostart di MIUI 12, service tidak bisa restart otomatis setelah dibunuh.

**Solusi:** Arahkan user ke pengaturan izin autostart MIUI saat instalasi pertama. Deteksi MIUI dengan:
```kotlin
val isMiui = Build.MANUFACTURER.equals("Xiaomi", ignoreCase = true)
    && !SystemProperties.get("ro.miui.ui.version.name").isNullOrEmpty()
```

### 5.3 Android 11 (API 30) — Scoped Storage

**Dampak pada media_kit:** Sama seperti Media3. Akses file audio tetap via `content://` URI dari MediaStore atau `file://` path.

**media_kit siap:** libmpv dapat memutar dari `content://` URI langsung. Tidak ada perubahan pada MediaStoreService.

### 5.4 Snapdragon 730 — Audio Hardware

**Kualitas output:** Snapdragon 730 mendukung AAudio (Android 8.1+) dan OpenSL ES. media_kit via libmpv menggunakan `ao=audiotrack` secara default pada Android.

**Hi-res audio:** Snapdragon 730 memiliki Qualcomm Aqstic WCD9340 audio codec yang mendukung 32-bit/384kHz secara hardware. Namun libmpv dengan `ao=audiotrack` dibatasi oleh Android AudioTrack API — output maksimum tergantung konfigurasi OS.

**Perhatian:** `ao=audiotrack` pada Android 11 mendukung output PCM float (32-bit) jika device mendukung. Tidak ada jaminan bit-perfect untuk Hi-res audio di MIUI 12 tanpa root.

### 5.5 Audio Effects — Masalah Fundamental dengan media_kit

**Masalah Utama:**
Android AudioEffect API (`android.media.audiofx.*`) bekerja dengan cara meng-hook ke dalam **AudioTrack session** menggunakan `audioSessionId`. Saat ini, ExoPlayer mengekspos `player.audioSessionId` yang kemudian dipakai oleh `AudioEffectsManager`.

libmpv membuat AudioTrack-nya sendiri secara internal melalui JNI/C++. AudioSession ID dari AudioTrack ini **tidak diekspos** ke Dart atau Kotlin oleh media_kit API.

**Dua Opsi Solusi:**

**Opsi A — FFmpeg lavfi Filters (Direkomendasikan):**
Gunakan libmpv `af=` (audio filter) dengan FFmpeg lavfi. Implementasi via `player.setProperty("af", filterChain)`.

```
Equalizer    → af=equalizer=f=32:width_type=o:width=2:g=0,equalizer=f=64:...
BassBoost    → af=bass=g=10:f=110:t=q:w=0.5
Virtualizer  → af=sofalizer=... atau af=haas=...
Reverb       → af=aecho=0.8:0.88:60:0.4
Volume/Gain  → af=volume=3dB
Stereo wide  → af=extrastereo=m=2.5
```

**Kelebihan:** Berjalan dalam libmpv pipeline, tidak perlu AudioSession ID, cross-platform.
**Kekurangan:** Filter FFmpeg tidak identik dengan Android AudioEffect hardware processing. Karakteristik suara bisa berbeda. Snapdragon 730 hardware acceleration untuk audio effects tidak dapat dipakai.

**Opsi B — AudioSession ID via Reflection (TIDAK Direkomendasikan):**
Upaya mengambil AudioSession ID dari libmpv internal AudioTrack via Java reflection dari Kotlin.
- Sangat rapuh dan bisa break di versi libmpv/media_kit berikutnya
- Tidak ada API public untuk ini
- Risiko crash di MIUI 12 (Xiaomi memodifikasi AudioTrack internals)
- **Jangan digunakan**

**Keputusan:** Gunakan **Opsi A** (FFmpeg lavfi filters) untuk semua audio effects.

---

## 6. Strategi Migrasi per Fase

### Fase 0 — Persiapan (Estimasi: 3-5 hari)
**Tujuan:** Setup environment, validasi media_kit, prototipe dasar.

- [ ] Tambah `media_kit`, `media_kit_audio`, `media_kit_libs_android_audio` ke `pubspec.yaml`
- [ ] Buat project Flutter terpisah (sandbox) untuk validasi media_kit di Mi 9T
- [ ] Validasi: putar MP3/FLAC/OGG/M4A/APE dari `content://` URI
- [ ] Validasi: gapless playback 3 lagu berturut-turut tanpa gap
- [ ] Validasi: background playback dengan `audio_service` tetap berjalan di MIUI 12 setelah 5 menit
- [ ] Validasi: `af=equalizer` FFmpeg filter bekerja tanpa crash di Snapdragon 730
- [ ] Validasi: dua `Player` instance simultan (untuk crossfade) tidak crash di MIUI 12
- [ ] **Go/No-Go checkpoint** — jika salah satu validasi gagal, evaluasi ulang

### Fase 1 — Core Playback Engine (Estimasi: 7-10 hari)
**Tujuan:** Ganti ExoPlayer dengan media_kit untuk playback dasar. Tidak ada audio effects dulu.

Deliverables:
- [ ] `MediaKitPlayer` — wrapper Dart di atas `Player` dari media_kit
- [ ] `MusicPlayerHandler extends BaseAudioHandler` — integrasi `audio_service`
- [ ] `MediaKitService` (Kotlin) — foreground service launcher + MIUI 12 fixes
- [ ] `MediaKitTransportState` — EventChannel state emitter (menggantikan TransportState.kt)
- [ ] `MediaKitTransportCommands` — MethodChannel dispatcher (menggantikan TransportCommands.kt)
- [ ] Playback: play, pause, stop, seek, next, previous
- [ ] Queue: setQueue, setTrack, insertNext, appendToQueue, removeFromQueue, reorderQueue
- [ ] Shuffle / Repeat
- [ ] Queue persistence via `shared_preferences` di Dart
- [ ] Notifikasi: artwork + controls via `audio_service`
- [ ] Audio focus via `audio_session` (sudah ada)

Feature parity check Fase 1:
- ✅ Semua fungsi transport dasar
- ❌ Crossfade (Fase 2)
- ❌ Audio effects (Fase 3)
- ❌ ReplayGain (Fase 4)
- ❌ Sleep timer (Fase 2)

### Fase 2 — Crossfade + Sleep Timer (Estimasi: 5-7 hari)
**Tujuan:** Reimplementasi crossfade engine di Dart.

Deliverables:
- [ ] `DartCrossfadeController` — mengelola dua `Player` instance
- [ ] Equal-power fade curve (sin/cos) di Dart menggunakan `Timer.periodic`
- [ ] Prewarm: standby player mulai vol=0 sebelum fade
- [ ] `DartPreloadManager` — prediksi next track + preload di standby player
- [ ] Crossfade cancel saat audio focus loss
- [ ] `SleepTimerController` (Dart) — duration mode + end-of-song mode
- [ ] Volume fade-out 20s sebelum stop (sleep timer)
- [ ] `player.stream.completed` → end-of-song trigger

### Fase 3 — Audio Effects via FFmpeg lavfi (Estimasi: 7-10 hari)
**Tujuan:** Ganti Android AudioEffect API dengan libmpv lavfi filters.

Deliverables:
- [ ] `LibmpvEffectsController` — manages `af=` filter chain di libmpv
- [ ] `EqualizerFilter` — 5-band via `af=equalizer` (parameter per-band)
- [ ] `BassBoostFilter` — `af=bass=g=N:f=110:t=q:w=0.5`
- [ ] `VirtualizerFilter` — `af=haas` atau `af=sofalizer` (lebih sederhana dari Android Virtualizer)
- [ ] `ReverbFilter` — `af=aecho` dengan preset (None/SmallRoom/LargeRoom/Hall/Cathedral)
- [ ] `StereoWideningFilter` — `af=extrastereo=m=N`
- [ ] `VolumeGainFilter` — `af=volume=NdB` untuk LoudnessEnhancer replacement
- [ ] UI MethodChannel wiring baru untuk semua effects
- [ ] Preset saving ke `shared_preferences`

**Catatan penting:** Filter chain FFmpeg di libmpv diset sebagai satu string `af=filter1,filter2,...`. Setiap perubahan parameter membutuhkan rebuild seluruh filter chain dan call `setProperty("af", newChain)`. Ada potensi brief audio dropout saat rekonfigurasi filter.

### Fase 4 — ReplayGain + Metadata (Estimasi: 3-5 hari)
**Tujuan:** Integrasikan ReplayGain dengan libmpv, pertahankan scanner Kotlin.

Deliverables:
- [ ] `ReplayGainScanner.kt` — **TETAP** (scanner EBU R128 via MediaCodec tidak berubah)
- [ ] `MetadataCacheDb.kt` — **TETAP**
- [ ] Ganti `LoudnessEnhancer.setTargetGain()` dengan `player.setProperty("replaygain", "track")` + `player.setProperty("replaygain-preamp", "NdB")`
- [ ] `ExoMetadataReader.kt` — Perlu adaptasi: tidak lagi menggunakan ExoPlayer MetadataRetriever. Ganti dengan `MediaMetadataRetriever` (Android API) atau tetap gunakan ExoPlayer khusus untuk metadata reading saja (detached, tidak untuk playback)
- [ ] `LyricsService.dart` — **TIDAK BERUBAH**

**Catatan:** Jika `ExoMetadataReader` bergantung pada ExoPlayer `MetadataRetriever`, ada dua opsi:
- Tetap sertakan `androidx.media3.exoplayer` (ExoPlayer library) hanya untuk metadata reading, tanpa MediaSessionService
- Migrasikan ke `MediaMetadataRetriever` (Android built-in API, lebih terbatas untuk tag support)

### Fase 5 — Polish, Diagnostics, MIUI Hardening (Estimasi: 3-5 hari)
**Tujuan:** Stabilisasi, penanganan edge case MIUI 12.

Deliverables:
- [ ] Audio format info dari `player.stream.tracks` → emit ke Dart
- [ ] `skipSilence` via `af=silenceremove` 
- [ ] MIUI 12: uji battery saver mode, RAM ≤ 2GB scenario
- [ ] MIUI 12: uji resume setelah telepon masuk
- [ ] Hapus semua file Kotlin yang tidak lagi digunakan
- [ ] Update AndroidManifest untuk media_kit + audio_service

---

## 7. Detail Implementasi per Fitur

### 7.1 Audio Effects — FFmpeg lavfi Filter Chain

**Struktur Filter Chain:**

```dart
class LibmpvEffectsController {
  // State internal
  bool _eqEnabled = false;
  final List<double> _eqBands = [0, 0, 0, 0, 0]; // gain per band (dB)
  bool _bassEnabled = false;
  double _bassStrength = 0;     // 0–1000 (mapped ke gain dB)
  bool _virtualizerEnabled = false;
  double _virtualizerStrength = 0;
  int _reverbPreset = 0;        // 0=None, 1=SmallRoom, …5=Cathedral
  bool _stereoEnabled = false;
  double _stereoStrength = 1.5;
  double _gainDb = 0.0;

  // Frekuensi 5-band default (Hz): 60, 250, 1000, 4000, 14000
  static const _eqFreqs = [60, 250, 1000, 4000, 14000];

  String _buildFilterChain() {
    final filters = <String>[];

    // Gain / Loudness
    if (_gainDb.abs() > 0.1) {
      filters.add('volume=${_gainDb}dB');
    }

    // Equalizer (5 band)
    if (_eqEnabled) {
      for (int i = 0; i < 5; i++) {
        if (_eqBands[i].abs() > 0.1) {
          // width_type=o = oktaf, width=1.0 = 1 octave bandwidth
          filters.add('equalizer=f=${_eqFreqs[i]}:width_type=o:width=1:g=${_eqBands[i]}');
        }
      }
    }

    // Bass boost
    if (_bassEnabled && _bassStrength > 0) {
      final g = (_bassStrength / 1000.0 * 15).clamp(0.0, 15.0);
      filters.add('bass=g=$g:f=110:t=q:w=0.5');
    }

    // Virtualizer (Haas effect / pseudo-surround)
    if (_virtualizerEnabled && _virtualizerStrength > 0) {
      final d = (_virtualizerStrength / 1000.0 * 40).clamp(0.0, 40.0);
      filters.add('haas=level_in=1:level_out=1:side_gain=1:middle_source=left:middle_phase=true:left_delay=${d}ms:left_balance=-1:right_delay=${d * 0.8}ms:right_balance=1');
    }

    // Reverb presets
    final echo = _reverbForPreset(_reverbPreset);
    if (echo != null) filters.add(echo);

    // Stereo widening
    if (_stereoEnabled && _stereoStrength > 1.0) {
      filters.add('extrastereo=m=${_stereoStrength}');
    }

    return filters.isEmpty ? '' : filters.join(',');
  }

  static String? _reverbForPreset(int preset) => switch (preset) {
    0 => null,              // None
    1 => 'aecho=0.6:0.5:50:0.35',         // Small Room
    2 => 'aecho=0.6:0.6:100:0.45',        // Medium Room
    3 => 'aecho=0.7:0.7:200:0.55',        // Large Room
    4 => 'aecho=0.8:0.75:400:0.6',        // Hall
    5 => 'aecho=0.9:0.9:700:0.7',         // Cathedral
    _ => null,
  };

  Future<void> applyToPlayer(Player player) async {
    final chain = _buildFilterChain();
    await player.setProperty('af', chain);
  }
}
```

**Peringatan FFmpeg lavfi:**
- `equalizer` filter di libmpv memerlukan libavfilter dengan support penuh. Versi `media_kit_libs_android_audio` harus dikompilasi dengan FFmpeg yang menyertakan filter ini. **Verifikasi di Fase 0.**
- Perubahan filter chain dapat menyebabkan reset audio buffer yang terdengar sebagai brief glitch. Untuk EQ band adjustment yang sering dilakukan user (saat drag slider), gunakan **debounce 150ms** sebelum apply.

### 7.2 Crossfade — Dual Player Dart Implementation

```dart
class DartCrossfadeController {
  late Player _primary;
  late Player _standby;
  Player get activePlayer => _activePlayer;
  Player _activePlayer;
  
  double crossfadeDurationSec = 5.0;
  static const int _tickMs = 16; // ~60fps
  
  // Equal-power crossfade
  // primary volume: cos(t * π/2) * targetVol  (fade-out)
  // standby volume: sin(t * π/2) * targetVol  (fade-in)
  
  Timer? _fadeTimer;
  int _step = 0;
  int _steps = 0;

  void maybeTriggerCrossfade() {
    final dur = _activePlayer.state.duration;
    final pos = _activePlayer.state.position;
    if (dur == Duration.zero) return;
    
    final remaining = dur - pos;
    final crossMs = (crossfadeDurationSec * 1000).round();
    
    if (remaining.inMilliseconds <= crossMs + 250 && 
        remaining.inMilliseconds > 0 && 
        !_crossfadeInProgress) {
      _beginCrossfade(remaining.inMilliseconds);
    }
  }

  void _beginCrossfade(int remainingMs) {
    _crossfadeInProgress = true;
    final actualFadeMs = min(remainingMs, (crossfadeDurationSec * 1000).round());
    _steps = max(1, actualFadeMs ~/ _tickMs);
    _step = 0;
    
    // Isolate old player (reset its repeat mode, keep only current item)
    _activePlayer.setPlaylistMode(PlaylistMode.none);
    
    // Prewarm standby (sudah dipreload sebelumnya)
    _standby.setVolume(0);
    _standby.play();
    
    final double targetVol = 100.0;
    
    _fadeTimer = Timer.periodic(Duration(milliseconds: _tickMs), (t) {
      _step++;
      if (_step >= _steps) {
        t.cancel();
        _activePlayer.setVolume(0);
        _standby.setVolume(targetVol);
        _activePlayer.pause();
        _activePlayer.stop();
        _onCrossfadeComplete();
        return;
      }
      final progress = _step / _steps;
      final angle = progress * pi / 2;
      _activePlayer.setVolume(targetVol * cos(angle));
      _standby.setVolume(targetVol * sin(angle));
    });
  }
}
```

**Catatan MIUI 12:** Dua Player instance media_kit berjalan di isolate yang sama. Pastikan keduanya mendapatkan wakelock lewat foreground service. Di MIUI 12, CPU clock throttling dapat menyebabkan `Timer.periodic` drift — gunakan `Stopwatch` untuk corrected timing jika drift terdeteksi.

### 7.3 Background Service — audio_service Integration

```dart
// lib/services/audio/music_player_handler.dart
class MusicPlayerHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final DartCrossfadeController _crossfade;
  final LibmpvEffectsController _effects;
  
  @override
  Future<void> play() => _crossfade.activePlayer.play();
  
  @override
  Future<void> pause() => _crossfade.activePlayer.pause();
  
  @override
  Future<void> seek(Duration position) => _crossfade.activePlayer.seek(position);
  
  @override
  Future<void> skipToNext() => _crossfade.skipToNext();
  
  @override
  Future<void> skipToPrevious() => _crossfade.skipToPrevious();
  
  // Update MediaItem untuk notifikasi
  void _updateMediaItem(LocalSong song) {
    mediaItem.add(MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: _crossfade.activePlayer.state.duration,
      artUri: Uri.parse('content://media/external/audio/albumart/${song.albumId}'),
    ));
  }
}
```

**Registrasi di main.dart:**
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();  // ← WAJIB pertama
  
  await AudioService.init(
    builder: () => MusicPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.musicplayer.audio',
      androidNotificationChannelName: 'Music Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,  // ← PENTING untuk MIUI 12
      notificationColor: Color(0xFF000000),
    ),
  );
  // ...
}
```

### 7.4 MIUI 12 Foreground Service Kotlin Wrapper

`audio_service` membuat foreground service-nya sendiri, tetapi di MIUI 12 perlu tambahan:

```kotlin
// android/app/src/main/kotlin/com/example/musicplayer/MiuiServiceCompat.kt
object MiuiServiceCompat {
    fun ensureAutostart(context: Context) {
        if (!isMiui()) return
        // Cek apakah sudah ada izin autostart via MIUI API
        // Jika tidak, tampilkan dialog untuk arahan ke pengaturan
        val intent = Intent().apply {
            component = ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            )
        }
        if (intent.resolveActivity(context.packageManager) != null) {
            // Tampilkan snackbar / dialog untuk arahkan user
        }
    }
    
    fun isMiui(): Boolean = !android.os.Build.VERSION.RELEASE.isNullOrEmpty() &&
        !android.os.SystemProperties.get("ro.miui.ui.version.name").isNullOrEmpty()
}
```

### 7.5 ReplayGain — Integrasi dengan libmpv

**Scanner tetap di Kotlin** (`ReplayGainScanner.kt` tidak berubah).

**Aplikasi gain ke media_kit player:**
```dart
// Saat track dimuat
Future<void> applyReplayGain(Player player, ReplayGainData? data) async {
  if (data == null || !replayGainEnabled) {
    await player.setProperty('replaygain', 'no');
    return;
  }
  
  // libmpv dapat membaca tag replaygain dari file secara otomatis
  await player.setProperty('replaygain', 'track'); // atau 'album'
  await player.setProperty('replaygain-preamp', '${data.preampDb}');
  await player.setProperty('replaygain-clip', 'yes');
}
```

**Catatan:** libmpv dapat membaca tag ReplayGain (REPLAYGAIN_TRACK_GAIN, dll.) secara otomatis dari file audio. Jika tag sudah ada di file, cukup set `replaygain=track`. Jika gain disimpan di database lokal (MetadataCacheDb), perlu apply via `af=volume=NdB` sebagai gantinya.

### 7.6 Metadata Reader — Adaptasi tanpa ExoPlayer

`ExoMetadataReader.kt` saat ini menggunakan `androidx.media3.exoplayer.MetadataRetriever`. Setelah migrasi:

**Opsi A — Android MediaMetadataRetriever:**
```kotlin
val retriever = MediaMetadataRetriever()
retriever.setDataSource(context, uri)
val title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
val artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
// Embedded lyrics: tidak semua format didukung
```
⚠️ `MediaMetadataRetriever` tidak mendukung semua format audio atau semua tag custom (misalnya lyrics di FLAC Vorbis comment).

**Opsi B — Tetap gunakan ExoPlayer khusus untuk metadata:**
Sertakan dependency `media3-exoplayer` hanya untuk `MetadataRetriever`, tanpa `MediaSessionService`. Ini memungkinkan metadata reading tetap lengkap tanpa menjalankan ExoPlayer untuk playback.
```gradle
// build.gradle — hanya untuk metadata
implementation "androidx.media3:media3-exoplayer:1.10.1"
// Tidak perlu: media3-session, media3-ui
```
Ini adalah opsi yang direkomendasikan untuk mempertahankan semua kemampuan metadata (termasuk embedded lyrics FLAC/OGG/M4A).

---

## 8. Arsitektur Target (Post-Migration)

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter / Dart Layer                    │
├─────────────────────┬───────────────────┬───────────────────┤
│  MusicPlayerHandler │   DartCrossfade   │  LibmpvEffects    │
│  (audio_service)    │   Controller      │  Controller       │
│  BaseAudioHandler   │  (2x Player)      │  (af= chain)      │
├─────────────────────┴───────────────────┴───────────────────┤
│              media_kit Player (libmpv)                      │
│              media_kit_libs_android_audio                   │
├────────────────────────────────────────────────────────────-┤
│              audio_session (AudioFocus)                     │
└─────────────────────────────────────────────────────────────┘
         ↕ MethodChannel / EventChannel ↕
┌─────────────────────────────────────────────────────────────┐
│                  Kotlin / Android Layer                     │
├──────────────┬──────────────┬──────────────┬────────────────┤
│ MediaStore   │  Metadata    │  ReplayGain  │  MIUI Service  │
│ Service.kt   │  CacheDb.kt  │  Scanner.kt  │  Compat.kt     │
│ (tidak ubah) │ (tidak ubah) │ (tidak ubah) │  (baru)        │
└──────────────┴──────────────┴──────────────┴────────────────┘
```

### File Kotlin yang Dihapus Setelah Migrasi
```
Media3PlaybackService.kt       ← Diganti MusicPlayerHandler (Dart)
ActivePlayerProxy.kt           ← Tidak diperlukan
audio_focus/AudioFocusManager.kt ← Diganti audio_session (Dart)
audio_offload/AudioOffloadManager.kt ← Dropped
crossfade/CrossfadeController.kt ← Diganti DartCrossfadeController
crossfade/PreloadManager.kt    ← Diganti DartPreloadManager
crossfade/CrossfadeTimelineLogger.kt ← Opsional (Dart log)
effects/AudioEffectsManager.kt ← Diganti LibmpvEffectsController
effects/StereoWideningAudioProcessor.kt ← Diganti af=extrastereo
effects/StereoWidthManager.kt  ← Tidak diperlukan
notification/PlaybackNotificationManager.kt ← Diganti audio_service
queue/QueueManager.kt          ← Diganti Dart queue management
queue/QueueSync.kt             ← Diganti Dart SharedPreferences
sleep_timer/SleepTimerManager.kt ← Diganti SleepTimerController (Dart)
transport/TransportCommands.kt ← Diganti (MethodChannel Dart-side)
transport/TransportState.kt    ← Diganti (EventChannel Dart-side)
utils/MediaItemFactory.kt      ← Tidak diperlukan
utils/TrackMapper.kt           ← Tidak diperlukan
```

### File Kotlin yang Tetap
```
MainActivity.kt                ← Update channel names, hapus Media3 init
ArtworkCacheManager.kt         ← Tetap untuk artwork cache
metadata/ExoMetadataReader.kt  ← Tetap (pakai ExoPlayer untuk metadata saja)
metadata/MetadataCacheDb.kt    ← Tetap
metadata/MetadataPrescanner.kt ← Tetap
metadata/TagBuilder.kt         ← Tetap
replay_gain/ReplayGainScanner.kt ← Tetap
events/EventEmitter.kt         ← Tetap (atau migrasi ke Dart)
events/SessionAuditLogger.kt   ← Opsional
diagnostics/CrossfadeTimelineLogger.kt ← Hapus atau port ke Dart
```

---

## 9. Channel & Event Contract Baru

### MethodChannel Names (Berubah atau Tetap)

| Channel | Status | Catatan |
|---|---|---|
| `musicplayer/media_store` | ✅ TETAP | getSongs, metadata, ReplayGain scan |
| `musicplayer/audio_effects` | 🔄 DEPRECATED | Diganti Dart-side effects |
| `musicplayer/media3_playback` | 🔄 RENAME ke `musicplayer/playback` | Semua transport commands |
| `musicplayer/native_commands` | ❌ HAPUS | Tidak diperlukan |

### EventChannel Names (Berubah atau Tetap)

Semua EventChannel yang saat ini ada di Kotlin dapat di-port ke Dart `StreamController`. Pertahankan nama channel yang sama untuk menghindari perubahan UI layer:

```
musicplayer/media3_playbackState  → Dart StreamController → EventChannel
musicplayer/media3_position       → Dart StreamController → EventChannel
musicplayer/media3_duration       → Dart StreamController → EventChannel
musicplayer/media3_currentTrack   → Dart StreamController → EventChannel
musicplayer/media3_queue          → Dart StreamController → EventChannel
musicplayer/media3_bufferingState → Dart StreamController → EventChannel
musicplayer/media3_audioSessionId → ❌ HAPUS (tidak tersedia)
musicplayer/media3_shuffleMode    → Dart StreamController → EventChannel
musicplayer/media3_repeatMode     → Dart StreamController → EventChannel
musicplayer/media3_sleepTimer     → Dart StreamController → EventChannel
musicplayer/media3_offloadState   → ❌ HAPUS (tidak relevan)
musicplayer/media3_audioFormat    → Dart (dari player.stream.tracks)
musicplayer/media3_skipSilence    → Dart state
musicplayer/media3_stereoWidening → Dart state
musicplayer/native_logs           → Opsional tetap Kotlin atau Dart
```

---

## 10. Estimasi Effort & Risiko

### Estimasi Waktu Total

| Fase | Durasi Estimasi |
|---|---|
| Fase 0 — Persiapan & Validasi | 3–5 hari |
| Fase 1 — Core Playback Engine | 7–10 hari |
| Fase 2 — Crossfade + Sleep Timer | 5–7 hari |
| Fase 3 — Audio Effects (lavfi) | 7–10 hari |
| Fase 4 — ReplayGain + Metadata | 3–5 hari |
| Fase 5 — Polish + MIUI Hardening | 3–5 hari |
| **Total** | **~28–42 hari** |

### Register Risiko

| # | Risiko | Probabilitas | Dampak | Mitigasi |
|---|---|---|---|---|
| R-01 | FFmpeg lavfi EQ filter tidak tersedia di `media_kit_libs_android_audio` binary | Menengah | Tinggi | Validasi di Fase 0; jika gagal, gunakan custom libmpv build |
| R-02 | Dua Player instances media_kit menyebabkan audio glitch di MIUI 12 | Menengah | Tinggi | Uji intensif di Fase 0; alternatif: satu player + gapless |
| R-03 | `audio_service` tidak reliable di MIUI 12 (service dibunuh) | Menengah | Kritis | Terapkan pola startForeground yang sudah terbukti (§5.1) |
| R-04 | libmpv tidak dapat memutar format tertentu (APE, WavPack) | Rendah | Menengah | Validasi semua format di Fase 0 |
| R-05 | FFmpeg filter chain rekonfigurasi menyebabkan audio glitch | Tinggi | Menengah | Debounce 150ms, crossfade filter apply |
| R-06 | Audio format info tidak selengkap ExoPlayer (`onTracksChanged`) | Rendah | Rendah | `player.stream.tracks` cukup untuk info dasar |
| R-07 | `MediaMetadataRetriever` tidak mendukung embedded lyrics FLAC | Tinggi | Menengah | Gunakan ExoPlayer hanya untuk metadata (§7.6 Opsi B) |
| R-08 | Ukuran APK bertambah (libmpv ~15 MB) | Pasti | Rendah | Acceptable untuk offline music player |
| R-09 | Dart `Timer.periodic` drift menyebabkan crossfade tidak smooth | Menengah | Menengah | Gunakan Stopwatch-corrected timing |
| R-10 | `audio_session` + `audio_service` interop conflict | Rendah | Tinggi | Gunakan versi yang kompatibel, uji early |

### Fitur yang Tidak Dapat Direplikasi Sempurna

| Fitur | Status di media_kit | Catatan |
|---|---|---|
| Android hardware EQ (AudioEffect API) | ❌ Tidak tersedia | FFmpeg lavfi sebagai pengganti, karakteristik beda |
| Audio output mode (AAudio/OpenSL ES/Hi-Res switching) | ❌ Tidak tersedia | libmpv `ao=audiotrack` fixed |
| Audio offload (hardware offload) | ❌ Tidak tersedia | Tidak relevan tanpa ExoPlayer |
| `audioSessionId` EventChannel | ❌ Tidak tersedia | Tidak ada API dari libmpv |
| Playback stats (totalPlayTimeMs, rebufferCount) | ❌ Tidak tersedia | Perlu implementasi manual Dart |
| Bit-perfect Hi-res audio | ⚠️ Terbatas | Bergantung Android AudioTrack + OS |

---

## 11. Testing Checklist

### Playback Core
- [ ] MP3 (CBR, VBR) — play, pause, seek, resume
- [ ] FLAC (16-bit, 24-bit)
- [ ] OGG Vorbis
- [ ] M4A / AAC
- [ ] WAV
- [ ] OPUS
- [ ] APE (Monkey's Audio)
- [ ] WavPack
- [ ] File dengan path mengandung spasi/karakter Unicode
- [ ] File dari `content://` URI (scoped storage Android 11)

### Queue & Transport
- [ ] setQueue → play → skip next → skip prev
- [ ] Shuffle on/off mid-queue
- [ ] Repeat none / one / all
- [ ] insertNext, appendToQueue
- [ ] removeFromQueue (item yang sedang diputar)
- [ ] reorderQueue
- [ ] Persistence setelah app kill dan restart
- [ ] Resume position yang tersimpan

### Crossfade
- [ ] Fade A→B tidak ada click/pop
- [ ] Equal-power curve — tidak ada loudness dip
- [ ] Crossfade dengan berbagai durasi (2s, 5s, 10s)
- [ ] Crossfade pada lagu terakhir di queue (repeat all)
- [ ] Crossfade dibatalkan saat audio focus loss
- [ ] Crossfade saat charging (MIUI 12 tidak throttle)
- [ ] Crossfade saat layar mati (MIUI 12 + battery saver)

### Audio Effects
- [ ] EQ enable/disable — tidak ada click
- [ ] EQ band adjustment — debounce bekerja
- [ ] BassBoost on/off
- [ ] Virtualizer on/off
- [ ] Reverb preset change
- [ ] Stereo widening on/off
- [ ] Efek tetap aktif setelah skip/crossfade
- [ ] Efek tersimpan dan di-restore setelah restart

### Background & MIUI 12
- [ ] Notifikasi muncul dengan artwork yang benar
- [ ] Lock screen controls bekerja
- [ ] Bluetooth AVRCP (play/pause/skip dari headset)
- [ ] Telepon masuk → audio duck/pause → audio resume
- [ ] App di background 30 menit — masih berjalan
- [ ] Battery saver mode — masih berjalan
- [ ] RAM rendah (MIUI kill) → service restart → resume
- [ ] Autostart permission dialog muncul untuk user baru

### ReplayGain
- [ ] Scan ReplayGain tetap bekerja
- [ ] Gain applied ke player (track mode)
- [ ] Gain applied ke player (album mode)
- [ ] Clipping prevention bekerja

### Sleep Timer
- [ ] Timer durasi — berhenti tepat waktu
- [ ] Volume fade 20s sebelum stop
- [ ] End-of-song mode — berhenti di akhir lagu
- [ ] Timer cancel bekerja

---

## 12. Go / No-Go Criteria

### Go (Lanjut Migrasi)
Semua kondisi berikut harus terpenuhi di akhir **Fase 0**:

1. ✅ media_kit dapat memutar MP3/FLAC/OGG di Mi 9T Android 11 dari `content://` URI tanpa crash
2. ✅ Dua `Player` instance simultan berjalan tanpa audio glitch
3. ✅ Background playback via `audio_service` bertahan > 5 menit di MIUI 12 tanpa auto-start permission
4. ✅ `af=equalizer` FFmpeg filter bisa di-set dan terdengar efeknya
5. ✅ Gapless playback antara dua file lokal bekerja

### No-Go (Hentikan / Evaluasi Ulang)
Jika salah satu kondisi berikut ditemukan di Fase 0:

1. ❌ `media_kit_libs_android_audio` crash di Snapdragon 730 / Android 11
2. ❌ FFmpeg lavfi filter tidak tersedia di binary (tidak ada `equalizer` filter)
3. ❌ Dua Player instance menyebabkan ANR atau audio corruption di MIUI 12
4. ❌ `audio_service` tidak dapat mempertahankan foreground service di MIUI 12 bahkan dengan pola startForeground yang benar

**Jika No-Go:** Evaluasi alternatif:
- Tetap dengan Media3 + tambahkan fitur yang kurang
- Gunakan `just_audio` (berbasis ExoPlayer) sebagai middle ground
- Custom compile libmpv dengan konfigurasi khusus untuk audio effects

---

## Catatan Tambahan

### Dependensi Versi yang Direkomendasikan

```yaml
media_kit: ^1.1.11
media_kit_audio: ^1.3.5
media_kit_libs_android_audio: ^1.3.8
audio_service: ^0.18.15
audio_session: ^0.2.3  # sudah ada
shared_preferences: ^2.5.3  # sudah ada
```

> Selalu cek `pub.dev` untuk versi terbaru saat mulai eksekusi. Versi di atas adalah referensi per Juni 2026.

### Ukuran APK

| Komponen | Ukuran tambahan |
|---|---|
| `media_kit_libs_android_audio` (libmpv) | ~15 MB |
| `audio_service` | ~200 KB |
| Pengurangan (hapus Media3) | ~2 MB |
| **Net tambahan** | **~13 MB** |

### Kompatibilitas Format Audio (libmpv + FFmpeg)

libmpv dengan FFmpeg mendukung lebih banyak format daripada ExoPlayer default:

| Format | ExoPlayer | libmpv/FFmpeg |
|---|---|---|
| MP3 | ✅ | ✅ |
| FLAC | ✅ | ✅ |
| OGG Vorbis | ✅ | ✅ |
| M4A/AAC | ✅ | ✅ |
| WAV | ✅ | ✅ |
| OPUS | ✅ | ✅ |
| APE (Monkey's Audio) | ❌ | ✅ |
| WavPack | ❌ | ✅ |
| AIFF | ❌ | ✅ |
| TrueAudio (TTA) | ❌ | ✅ |
| Musepack (MPC) | ❌ | ✅ |

Ini adalah salah satu kelebihan signifikan media_kit untuk offline music player.

---

*Dokumen ini dibuat berdasarkan audit lengkap kode sumber (27 file Kotlin, arsitektur Media3 native) dan spesifikasi device target (Xiaomi Mi 9T / K20, Snapdragon 730, Android 11, MIUI 12). Rencana ini bersifat draft dan memerlukan validasi di Fase 0 sebelum eksekusi penuh.*
