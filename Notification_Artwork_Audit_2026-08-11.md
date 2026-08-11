# Notification Artwork Audit — 2026-08-11

## Scope

Audit read-only terhadap jalur artwork Android:

- `PlaybackNotificationManager` — custom foreground notification, `largeIcon`, async loading, prewarm, dan cache.
- `SessionArtworkProvider` — high-resolution `MediaMetadata.artworkData`.
- `FallbackBitmapLoader` — Media3 legacy/Bluetooth/lock-screen bitmap loading.
- `ArtworkCacheManager` — persistent disk cache dan concurrency.
- `Media3PlaybackService` / `ActivePlayerProxy` — lifecycle, transition, crossfade, dan publikasi metadata.

Tidak ada kode produksi yang diubah sebagai bagian dari audit ini.

## Executive summary

Pendekatan `MediaSession.artworkData` sudah benar dan mengatasi akar masalah MIUI/SystemUI yang melakukan upscale/crop pada `artworkUri` MediaStore beresolusi rendah. Jalur embedded-artwork-first, bounds decode, letterboxing, TTL negative cache, dan in-flight dedup pada `SessionArtworkProvider` juga sudah ada.

Masih ada tiga risiko utama: hasil async notifikasi dapat menimpa lagu aktif dengan artwork/title lama, refresh artwork Session tidak dipanggil eksplisit saat promosi crossfade, dan dua instance `ArtworkCacheManager` berbagi file disk tetapi tidak berbagi lock proses. Ada gap tambahan untuk file yang dibuka dari aplikasi eksternal dan lifecycle executor.

## Findings

### P1 — Hasil async notifikasi dapat menampilkan lagu sebelumnya

**Evidence**

- `android/app/src/main/kotlin/dev/wndavenz/music/notification/PlaybackNotificationManager.kt:190-217`
- `refreshAsync()` menangkap `track` dan `isPlaying` saat enqueue.
- Saat selesai, callback hanya memvalidasi generation untuk `cacheKey`; callback normal tidak memvalidasi `cacheKey == currentTrackCacheKey()`.

**Failure sequence**

1. Artwork track A mulai dimuat.
2. User skip ke track B; notifikasi B diposting.
3. Worker A selesai.
4. Callback memanggil `buildNotification(sess, track, isPlaying, bmp)` memakai map A yang sudah stale.

**Impact**

Notification title/artist/large icon dapat kembali sebentar ke track A. Per-key generation tidak mencegah cross-track stale result karena generation A masih valid.

**Recommendation**

Pada completion, validasi identitas track aktif dengan cache key dan ID/media identity yang stabil. Jangan post captured `track`; rebuild dari `getCurrentTrack()` dan `getIsPlaying()` pada saat completion. Jika stale, drop result atau trigger refresh untuk current track.

---

### P1 — Promosi crossfade tidak menjadwalkan refresh artwork Session secara eksplisit

**Evidence**

- `android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt:307-335`
- `android/app/src/main/kotlin/dev/wndavenz/music/Media3PlaybackService.kt:678-703`
- Refresh Session dipanggil saat queue restore, `STATE_READY`, dan regular `onMediaItemTransition` (`Media3PlaybackService.kt:1308, 1388`).

Saat crossfade mempromosikan standby, service memanggil `switchSessionPlayer()`, `emitAll()`, dan `refreshNotification()`, tetapi tidak memanggil `scheduleSessionArtworkRefresh()` tepat setelah identity active player berubah. Callback READY/transition dari standby dapat sudah terjadi ketika standby masih dianggap inactive.

**Impact**

MIUI/SystemUI dapat menerima title track baru lebih dulu tetapi mempertahankan `artworkData` track lama sampai callback lain memicu refresh.

**Recommendation**

Jadikan setiap active-player promotion memicu `scheduleSessionArtworkRefresh()` setelah `ActivePlayerProxy.switchTo()` selesai. Pertahankan guard player/mediaId pada hasil async.

---

### P1 — Persistent cache antar-Activity/service tidak memakai lock proses yang sama

**Evidence**

- `MainActivity` membuat `ArtworkCacheManager` di `MainActivity.kt:130`.
- `Media3PlaybackService` membuat instance lain di `Media3PlaybackService.kt:269`.
- `songLocks` dan `globalLock` adalah field instance di `ArtworkCacheManager.kt:74-77`.
- Kedua instance menulis `{filesDir}/artwork/{songId}.webp` dan temp path `{songId}.webp.tmp`.

Lock saat ini aman untuk concurrency di dalam satu instance, tetapi tidak mengoordinasikan Activity dan service yang mengakses file sama secara bersamaan.

**Impact**

Dua ekstraksi lagu yang sama dapat berjalan paralel dan berbagi nama temp file. Salah satu writer dapat rename/delete temp file writer lain, menghasilkan cache miss berulang atau file cache yang tidak valid.

**Recommendation**

Gunakan process-wide lock/in-flight registry keyed by song ID atau satu shared cache owner. Tambahkan temp filename unik per writer dan validasi decode pada final cache hit.

---

### P1 — Playback dari file eksternal tidak membawa sumber artwork ke service

**Evidence**

- `Media3PlaybackService.buildSongMapFromUri()` mengembalikan `id=0` dan `albumId=0` (`Media3PlaybackService.kt:838-846`).
- `TrackMapper` hanya membuat `artworkUri` dari positive `albumId` (`utils/TrackMapper.kt:31-33`).
- `PlaybackNotificationManager` dan `SessionArtworkProvider` hanya mencoba embedded artwork jika memiliki `songId > 0`.

Overlay Activity memang membaca embedded artwork sendiri, tetapi track map yang dipakai service tidak menyimpan source URI/path artwork.

**Impact**

File MP3/FLAC yang dibuka dari Telegram/file manager dapat menampilkan artwork di overlay tetapi tidak di notification, lock screen, atau MediaSession.

**Recommendation**

Simpan source URI/path pada external-playback track map dan tambahkan source-based cache key serta embedded extraction dari URI tersebut ketika tidak ada MediaStore song ID.

---

### P2 — `pendingAsyncCacheKey` global masih memungkinkan duplicate load antar-key

**Evidence**

- `PlaybackNotificationManager.kt:69-70, 153-179, 190-217`
- Hanya ada satu slot `pendingAsyncCacheKey`.
- Completion setiap request mengosongkan slot tanpa memastikan slot tersebut masih milik request yang selesai.

Jika A dan B berada di queue berbeda, completion A dapat menghapus penanda B sehingga refresh B berikutnya enqueue duplicate load. Generation per-key mencegah cache insertion stale, tetapi tidak mencegah I/O duplikat.

**Recommendation**

Ganti slot tunggal dengan set/map in-flight per cache key dan hapus hanya token request yang cocok.

---

### P2 — Fallback cache pada compilation album hanya mencoba track pertama

**Evidence**

- `FallbackBitmapLoader.tryEmbedded()` memprobe hingga tiga song ID (`FallbackBitmapLoader.kt:213-219`).
- Persistent cache fallback hanya memanggil `getOrExtract(songIds.first())` (`FallbackBitmapLoader.kt:221-229`).

**Impact**

Jika hanya track kedua/ketiga memiliki artwork cache yang valid, loader tetap mengembalikan no-artwork.

**Recommendation**

Iterasikan semua ID yang sudah diprobe untuk persistent cache fallback, tetap dengan batas `MAX_ALBUM_PROBE`.

---

### P2 — Artwork executor tidak memiliki lifecycle shutdown eksplisit

**Evidence**

- Executor dibuat di `PlaybackNotificationManager.kt:71-73`.
- Executor lain dibuat di `FallbackBitmapLoader.kt:100-102` dan `SessionArtworkProvider.kt:61-63`.
- `Media3PlaybackService.onDestroy()` men-shutdown `ioExecutor`, tetapi tidak menutup executor artwork.

Thread daemon tidak menahan proses tetap hidup, tetapi queued work dan callback dapat bertahan melewati service teardown atau service restart.

**Recommendation**

Tambahkan `close()` idempotent pada komponen artwork untuk membatalkan/menolak callback setelah close dan shutdown executor saat teardown service.

## Verified strengths

- Notification path memprioritaskan embedded artwork, lalu persistent cache, lalu MediaStore URI sebagai fallback terakhir.
- Notification, fallback, dan session path menggunakan bounds-first decode dengan batas dimensi.
- Non-square artwork di-letterbox dan current `SessionArtworkProvider.letterboxSquare()` tidak meng-upscale source kecil.
- `SessionArtworkProvider` saat ini sudah memakai lock untuk `LruCache` dan in-flight dedup per request key.
- Negative cache `FallbackBitmapLoader` dan notification path memiliki TTL 30 detik.
- Session result memvalidasi active player dan `mediaId` sebelum `replaceMediaItems()`.
- `artworkData` di-clear untuk track tanpa source artwork.
- `FallbackBitmapLoader` me-release `MediaMetadataRetriever` di `finally`.
- Crossfade dan non-crossfade transition sama-sama melakukan prewarm artwork notifikasi.

## Test gap

Belum ada focused test untuk state machine artwork async. Regression test bernilai tinggi:

1. Load A selesai setelah transisi A→B dan tidak boleh mem-post A.
2. Dua request Session artwork untuk key sama saat in-flight harus satu extraction.
3. Promosi crossfade wajib memicu Session artwork refresh.
4. Dua `ArtworkCacheManager` pada song ID sama tidak boleh merusak temp/final cache.
5. External URI dengan embedded art harus sampai ke notification dan MediaSession.

## Verification

- `git diff --check`: passed.
- `./gradlew :app:testDebugUnitTest`: blocked by Android SDK environment.
- `./gradlew :app:compileDebugKotlin`: reached Gradle configuration but failed with `SDK location not found`; `android/local.properties` tidak menunjuk SDK yang tersedia.
- Tidak ada runtime Mi 9T/MIUI 12 validation di environment ini.

## Audit conclusion

High-resolution MediaSession metadata sudah menjadi fondasi yang tepat untuk mengatasi zoom/pixelation. Temuan paling urgent adalah stale async notification result dan refresh artwork yang hilang pada crossfade promotion. Setelah dua hal itu, process-wide cache coordination dan external-file artwork source perlu diperbaiki agar jalur notifikasi konsisten pada rapid skip, crossfade, dan playback dari file manager.