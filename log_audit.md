# Audit Log Aplikasi Dump

- **Tanggal:** 23 Oktober 2026
- **Scope:** seluruh call site logging Dart, Kotlin, C/native, pipeline LogService, LogPage, dan konfigurasi native logger.
- **Versi saat audit:** 1.5.41
- **Status:** seluruh rekomendasi P0/P1/P2 diterapkan; verifikasi runtime penuh tertunda karena Flutter SDK tidak tersedia di workspace Termux ini.

## Ringkasan Eksekutif

Logging di Dump sudah terpusat dan di-gate dengan baik, tetapi audit menemukan tiga masalah besar:

1. **Live tail berhenti setelah buffer penuh.** `LogService.logCount` mentok di 5000 dan dipakai sebagai sinyal “ada log baru”, sehingga LogPage tidak pernah refresh lagi setelah buffer penuh.
2. **Error framework hilang saat logging dimatikan.** `FlutterError.presentError` hanya dipanggil ketika toggle logging ON, dan `PlatformDispatcher.onError` tidak pernah melaporkan ke console release.
3. **PII dan noise.** Banyak jalur mencatat judul/artis lagu, path file, URI, path lirik, serta log per-item/per-slider dengan level INFO. Buffer 5000 juga membuang entri tertua tanpa memprioritaskan error/warning.

Semua masalah di atas sudah diperbaiki. Log C/native yang tersisa hanya diagnostik init berlevel DEBUG dan sudah mengikuti gate logging; tidak ada perubahan C yang diperlukan.

## Statistik Awal

| Area | Jumlah | Catatan |
|---|---:|---|
| Dart call site | 288 | 46 file; 105 info, 92 verbose, 50 warn, 33 error, 8 `debugPrintIfEnabled` |
| Kotlin call site | 184 | 129 `emit`, 34 `warnLog`, 14 `debugLog`, 5 `infoLog`, 2 `errorLog` |
| Crossfade timeline | 71 | stamp diagnostik per operasi crossfade |
| C/native log | 26 | seluruhnya DEBUG dan di-gate `native_runtime_is_logging_enabled()` |
| Buffer LogService | 5000 | FIFO; tidak memprioritaskan warning/error |
| Stack trace per entri | 3000 karakter | sudah dibatasi |

## Temuan dan Status

### P0 — Rusak / kehilangan diagnostik

| # | Temuan | Lokasi | Dampak | Status |
|---|---|---|---|---|
| P0-1 | `logCount` berhenti berubah setelah 5000 entri sehingga listener live tail tidak terpicu | `lib/services/log_service/service.dart:109` (sebelum fix), `lib/pages/log_page.dart:41,48` | Log viewer membeku saat buffer penuh | **Fixed** — `logRevision` monotonik; LogPage listen ke revision |
| P0-2 | `FlutterError.presentError` hanya dipanggil jika logging ON | `lib/main/main.dart:101` | Error framework hilang dari console release saat toggle OFF | **Fixed** — selalu `presentError` |
| P0-3 | `PlatformDispatcher.onError` hanya menulis ke LogService, tidak pernah `presentError` | `lib/main/main.dart:108` | Unhandled Dart error tidak terlihat di release console | **Fixed** — `FlutterError.presentError` + stack |
| P0-4 | Fallback zone pra-init memakai `debugPrintIfEnabled` yang ikut OFF | `lib/main/main.dart` | Error sebelum `LogService.init()` hilang total | **Fixed** — `debugPrint` tanpa gate |

### P1 — Privasi dan kualitas diagnostik

| # | Temuan | Lokasi | Dampak | Status |
|---|---|---|---|---|
| P1-1 | Judul/artis lagu masuk log | `audio_service/service.dart` (Native track, Now Playing, Queue jump, Queued next/end), `replay_gain_service/service.dart`, `replay_gain_applicator.dart`, `loudness_source_resolver.dart` | Judul koleksi pribadi tersimpan di buffer/logcat | **Fixed** — diganti `songId` |
| P1-2 | Path/URI file masuk log | `fetch_manager.dart`, `local_file_provider.dart`, `open_file_service.dart`, `automix_service/service.dart`, `audio_effects_service` (lyrics path) | Struktur folder pengguna bocor | **Fixed** — dihapus di sumber + redaksi terpusat |
| P1-3 | Tidak ada redaksi terpusat | Dart + Kotlin | Satu call site baru bisa membocorkan path | **Fixed** — `LogRedaction` Dart dan `NativeLogger.redact` Kotlin |
| P1-4 | Error Flutter tidak punya stack konsisten | beberapa widget card | Sulit dilacak | **Fixed** — stack ditambahkan di card/play button dan media store timeout |
| P1-5 | `debugPrintIfEnabled` menjadi jalur log kedua | `native_palette_service.dart`, `artwork.dart` | Log tidak muncul di viewer | **Fixed** — semua call site pindah ke `LogService`; method tinggal sebagai fallback API |
| P1-6 | `NativeLogger` tidak meneruskan warning/error ke viewer | `EventEmitter.kt` | Warning Kotlin hanya terlihat di logcat | **Fixed** — `infoLog`/`warnLog`/`errorLog` di-emit; `debugLog` tetap logcat-only |
| P1-7 | Duplikasi `warnLog` + `emit` | `SignalsmithStretchAudioProcessor.kt`, `ReplayGainBridge.kt` | Dua entri untuk satu kejadian | **Fixed** — emit eksplisit dihapus, forwarding terpusat |

### P2 — Noise, level, dan duplikasi

| # | Temuan | Lokasi | Tindakan | Status |
|---|---|---|---|---|
| P2-1 | Buffer membuang entri tertua tanpa prioritas | `LogService` | Eviction verbose/info tertua lebih dulu; warning/error dipertahankan | **Fixed** |
| P2-2 | Setter/slider audio mencatat INFO setiap perubahan | `audio_effects_service/service.dart:357-925`, `media_capabilities_service/service.dart:189-281` | Turun ke VERBOSE; path lirik tidak dicetak | **Fixed** |
| P2-3 | Log QRIS 10 langkah | `settings_page/about.dart:109-179` | Ringkas menjadi start/success/warning/error | **Fixed** |
| P2-4 | “Not found” lirik memakai WARN | `fetch_manager.dart:175` | Turun ke VERBOSE; kegagalan jaringan tetap terlihat | **Fixed** |
| P2-5 | Scan ReplayGain per-track WARN | `replay_gain_service/service.dart:445-467` | Turun ke VERBOSE dengan `songId` | **Fixed** |
| P2-6 | Warning Media3 release/decoder per track | `Media3PlaybackService.kt:2040,2144,2197` | Turun ke VERBOSE | **Fixed** |
| P2-7 | Crossfade timeline INFO | `CrossfadeTimelineLogger.kt:48,71,102,122` | Turun ke VERBOSE | **Fixed** |
| P2-8 | Catatan offload per crossfade | `AudioOffloadManager.kt:110-209` | Turun ke VERBOSE; teks no-op dipertahankan | **Fixed** |
| P2-9 | Duplikasi end-of-queue | `audio_service/service.dart` | Satu log INFO dihapus; satu VERBOSE dipertahankan | **Fixed** |
| P2-10 | Command shuffle/repeat dicatat dua kali | `audio_service/service.dart` | Log command dihapus; stream tetap menjadi sumber log | **Fixed** |
| P2-11 | PII path di native Kotlin | `MetadataCacheDb`, `ExoMetadataReader`, `MetadataPrescanner`, `ReplayGainBridge`, dll. | Redaksi terpusat sebelum logcat + emit | **Fixed** |
| P2-12 | `queue mutation failed` memakai `log(level: warning)` | `audio_service/service.dart` | Diganti `warn` + stack | **Fixed** |
| P2-13 | DSP unavailable hanya INFO | `playback_manager.dart` | Diganti WARN | **Fixed** |
| P2-14 | `getInitialUri` gagal memakai ERROR | `open_file_service.dart` | Diganti WARN; URI dihapus dari pesan | **Fixed** |

## Kebijakan Level yang Diterapkan

- **ERROR:** kegagalan nyata, kehilangan data, kegagalan playback/IO yang tidak fail-open.
- **WARN:** fallback/degradasi yang perlu diketahui (DSP unavailable, media store gagal non-kritis, permission ditolak, metadata gagal).
- **INFO:** aksi pengguna/lifecycle penting (play, save QRIS, mode Pure Playback, sleep timer).
- **VERBOSE:** per-item/per-track/per-slider/per-request (cache lirik, scan ReplayGain, timeline crossfade, setter audio, palette retry).

## Normalisasi Kategori

Alias berikut dipetakan di `LogService` agar filter UI tetap ringkas:

- `AudioEffects`, `AudioFocus`, `AudioSession`, `DeviceDsp`, `MediaCap`, `NativeDspBridge`, `PlaybackManager` → **Audio**
- `Media3Bridge` → **Media3**
- `FetchManager`, `LocalFileProvider`, `EmbeddedProvider` → **Lyrics**
- `ReplayGainApplicator`, `LoudnessResolver` → **ReplayGain**
- `SongMetadata` → **Metadata**
- `NativeModuleRegistry` → **Native**
- `LocalSongCard`, `NewMusicCell`, `AlbumsSection`, `SmartPlaylistCard`, `PlayShuffleButtons` → **UI**
- `AppState` → **App**
- `DeviceState` → **Device**

## Redaksi PII

`LogRedaction` (Dart) dan `NativeLogger.redact` (Kotlin) mengubah:

- `content://`, `file://`, `http://`, `https://`, `rtsp://`, `ftp://` → `<uri>`
- path absolut (`/storage/...`, `/sdcard/...`, `/data/...`, `/mnt/...`, `/proc/...`, `/system/...`, `/tmp/...`, `/home/...`, dll.) → `<path>`

Redaksi diterapkan pada message dan stack trace sebelum masuk buffer. Call site tetap diminta tidak mengirim judul/artis/path sejak awal; redaksi adalah lapisan pertahanan terakhir.

## Perubahan Kode

### LogService

- `lib/services/log_service.dart`: menambah part `redaction.dart`.
- `lib/services/log_service/redaction.dart`: regex redaksi URI/path.
- `lib/services/log_service/service.dart`:
  - `logRevision` monotonik,
  - eviction berprioritas,
  - redaksi message/stack,
  - alias kategori,
  - `exportText()`,
  - `redact()` publik,
  - `clear()` menaikkan revision.
- `lib/pages/log_page.dart`: listener live tail pindah ke `logRevision`.
- `test/services/log_service_test.dart`: test redaksi, alias kategori, revision saat buffer penuh, dan retensi error.

### Dart call site

- `lib/main/main.dart`: error framework selalu dilaporkan; fallback zone pra-init tidak lagi di-gate.
- `lib/pages/settings_page/about.dart`: log QRIS diringkas.
- `lib/services/audio_service/service.dart`: PII judul diganti `songId`; duplikasi end-of-queue dan command shuffle/repeat dihapus; queue mutation WARN + stack.
- `lib/services/audio/audio_effects_service/service.dart`: setter/slider VERBOSE; path lirik tidak dicetak.
- `lib/services/media_capabilities_service/service.dart`: setter VERBOSE; init INFO ringkas.
- `lib/services/lyrics_service/fetch_manager.dart`: tanpa judul/artis; cache/not-found VERBOSE.
- `lib/services/lyrics_service/providers/local_file_provider.dart`: path lirik dihapus.
- `lib/services/replay_gain_service/service.dart`: `songId`, scan per-track VERBOSE, tanpa judul.
- `lib/services/audio_service/replay_gain_applicator.dart`: fail-open WARN, `songId`.
- `lib/services/loudness_source_resolver.dart`: `songId`.
- `lib/services/media_store_service.dart`: timeout/error dengan stack; operasi cache non-kritis WARN.
- `lib/services/open_file_service.dart`: URI dihapus; initial URI WARN.
- `lib/services/song_metadata_service/service.dart`: `LogService.warn` + `songId`.
- `lib/services/native/native_module_registry.dart`: init sukses VERBOSE; error WARN + stack.
- `lib/services/native_palette_service.dart`: `debugPrintIfEnabled` → `LogService`; gagal ekstraksi VERBOSE; persist WARN.
- `lib/services/audio/playback_manager.dart`: DSP unavailable WARN.
- `lib/services/automix_service/service.dart`: path di pesan “analysis channel busy” dihapus.
- `lib/widgets/local_song_card/card.dart`, `new_music_grid.dart`, `stations.dart`, `play_shuffle_buttons.dart`: stack trace pada error.
- `lib/widgets/player/player_background/artwork.dart`: shader gagal dimuat → WARN.

### Kotlin

- `android/app/src/main/kotlin/dev/wndavenz/music/events/EventEmitter.kt`:
  - `NativeLogger.redact`,
  - `infoLog`/`warnLog`/`errorLog` meneruskan ke viewer,
  - `emit` selalu meredaksi,
  - `debugLog` tetap logcat-only.
- `Media3PlaybackService.kt`: release/decoder warning → VERBOSE; wording “audio output disconnected”.
- `CrossfadeTimelineLogger.kt`: seluruh stamp → VERBOSE.
- `AudioOffloadManager.kt`: catatan eligibility/no-op → VERBOSE.
- `SignalsmithStretchAudioProcessor.kt`: hapus emit duplikat; warning init membawa format/sample rate.
- `ReplayGainBridge.kt`: hapus emit duplikat pada `logError`.

### Native C/C++

Tidak ada perubahan. Seluruh `*_LOG` di `native_audio_runtime/src` sudah:

- hanya aktif ketika `native_runtime_is_logging_enabled()`,
- berlevel DEBUG,
- hanya di jalur init/register/update, bukan audio thread per-sample.

`stretch_jni.cpp` dan `tag_writer.cpp` juga sudah di-gate oleh preferensi yang sama.

## Verifikasi

- `dart format` pada file yang diubah: **berhasil** (hanya peringatan resolusi `flutter_lints` karena paket belum di-`pub get`).
- `dart analyze`: **tidak dapat dijalankan penuh** karena workspace Termux ini tidak memiliki Flutter SDK/paket (`package:flutter`, `package:shared_preferences`, `flutter_test` tidak dapat di-resolve).
- Test Flutter/Kotlin belum dijalankan di workspace ini.
- Test baru ditambahkan: redaksi/revision/alias/overflow di `test/services/log_service_test.dart`, serta redaksi URI/path di `EventEmitterTest` (D05–D06).
- Verifikasi wajib berikutnya di CI/devcontainer:
  - `flutter pub get`
  - `dart analyze lib test`
  - `flutter test test/services/log_service_test.dart`
  - `cd android && ./gradlew :app:testDebugUnitTest`
  - build APK dan uji toggle logging ON/OFF di Mi 9T.

## Risiko Residual

1. Buffer 5000 tetap bisa penuh oleh warning berulang (mis. artwork gagal untuk banyak lagu). Eviction berprioritas hanya memastikan error tidak langsung terdorong oleh verbose/info.
2. Redaksi berbasis regex tidak menggantikan disiplin call site. Path relatif atau nama file tanpa prefix absolut tidak terdeteksi.
3. `NativeLogger.infoLog` sekarang masuk viewer; jika ada library yang memanggilnya sangat sering, volume viewer bisa naik. Saat ini call site `infoLog` hanya 5.
4. Export log masih berupa helper teks; belum ada tombol share/export file karena repo belum memakai dependency share.
5. Audit ini tidak mengubah level logcat Media3 global; `Log.setLogLevel` tetap mengikuti toggle aplikasi.

## Temuan Positif

- Gate logging sudah berlapis: Dart, Kotlin, Media3, JNI, dan C.
- Stack trace sudah dibatasi 3000 karakter sejak sebelumnya.
- NativeLogger sudah thread-safe untuk emit dari audio/JNI thread.
- Sebagian besar log C sudah tidak berjalan di audio callback.
- `errorsOnly` dan `verbose` sudah menjadi filter yang jelas; audit ini mempertegas pemakaiannya.
