---
name: Notification Artwork Fix
description: Two-stage artwork fallback in PlaybackNotificationManager + TTL-based no-artwork cache
---

# Notification Artwork Fix

## UPDATE 1.5.27 — jalur ini BUKAN yang merender bug zoom+pecah
`loadBitmap()` / largeIcon / BitmapLoader hanya menyentuh jalur notifikasi
collapsed + MediaSessionLegacyStub (Bluetooth). SystemUI/MIUI shade & lock
screen merender **MediaSession metadata artworkData/ART_URI langsung** (tanpa
largeIcon dan tanpa BitmapLoader app). Fix sesungguhnya ada di
[`session-artwork-metadata.md`](session-artwork-metadata.md) — publish artworkData
full-res persegi dengan replace current MediaItem (`Player.replaceMediaItems`;
`Player.setMediaMetadata` TIDAK ada di Media3). Jangan kembalikan logika
"resolveSessionArtworkUri" (commit 8a157cf) yang membiarkan SystemUI decode URI
albumart low-res.

## Rule (jalur notifikasi + Bluetooth, tetap berlaku)
`PlaybackNotificationManager.loadBitmap()` now has two stages:
1. Embedded full-res via MediaMetadataRetriever (uncommitted 1.5.27)
2. ContentResolver (artUri dari MediaStore albumart URI) / `ArtworkCacheManager.getOrExtract(songId)`

`noArtworkUris` (permanent blacklist) diganti `noArtworkTimestamps: HashMap<String, Long>` dengan TTL 30 detik.

**Why:** Sebelumnya notifikasi hanya pakai ContentResolver; jika MediaStore belum index artwork (cold start, file non-standar), notifikasi tidak pernah punya artwork. TTL fix: song yang gagal saat MediaStore belum siap bisa di-retry otomatis.

**How to apply:**
- `ArtworkCacheManager` diinject via constructor param `artworkCacheManager: ArtworkCacheManager?` (nullable, default null).
- `Media3PlaybackService` membuat `serviceArtworkCache = ArtworkCacheManager(this)` dan meneruskannya ke notificationManager.
- Disk cache di `{filesDir}/artwork/` dishare antara `MainActivity` dan `Media3PlaybackService` (path sama, dua instance terpisah, OK).
- Cache key: `artUri ?: "song:$songId"` — konsisten di `bitmapCache` (LruCache) dan `noArtworkTimestamps`.
- `FallbackBitmapLoader` tetap untuk Bluetooth/lock-screen via Media3 `BitmapLoader` — tidak diubah.

## UPDATE 1.5.28 — optimasi minor hasil audit (2 file)
1. **Cache positif per-album** (`albumArtworkCache`, LruCache 4 album) di FallbackBitmapLoader — album yang sudah resolve art tidak di-query ulang (MediaStore + MediaMetadataRetriever) saat MediaSessionLegacyStub memanggil loadBitmap lagi per metadata/queue update. Negative cache (`noArtworkCache`) tetap.
2. **Probe multi-track** (`songIdsForAlbum`, MAX_ALBUM_PROBE=3) — album kompilasi: art diambil dari lagu pertama yang punya embedded art, bukan cuma lagu pertama di query.
3. **Never-upscale** di `normalizeSquare` + `normalizeNotificationArtwork` — letterbox canvas = min(maxPx, sisi terpanjang source); art kecil tetap resolusi asli (tidak ada upscale pass sia-sia).
4. **`inPreferredConfig = ARGB_8888`** di semua decode — art yang sudah 1024×1024 persegi langsung return di fast-path, tidak di-reletterbox (hemat ~4MB alokasi per panggilan).
5. **Prewarm repost**: kalau lagu yang di-prewarm sudah jadi current track saat load selesai (user pencet next), notifikasi langsung repost — tidak menunggu refresh berikutnya.
6. **Hapus double lookup** `bitmapCache.get()` di `refresh()`.
7. **Prewarm non-crossfade + generation per-key** — di `Media3PlaybackService.onMediaItemTransition`, artwork lagu berikutnya (`p.nextMediaItemIndex` → `queueManager.queue`) ikut di-prewarm via `notificationManager.prewarmArtwork` (sebelumnya hanya CrossfadeController Phase-1 yang prewarm). `artworkLoadGeneration` global diganti `artworkLoadGenerations` per-cacheKey supaya prewarm lagu berikutnya tidak men-discard hasil async load lagu yang sedang diputar (race lintas-key).
Catatan: `SessionArtworkProvider.letterboxSquare` sengaja tetap 1024 tetap (session artwork dipakai SystemUI render BESAR, ukuran seragam 1024 lebih aman).

## UPDATE 1.5.29 — batch 2 temuan audit `Notification_Artwork_Audit_2026-08-11.md`
1. **Anti stale async post** — `refreshAsync()` completion: sebelum `postNotification`, validasi `cacheKey == currentTrackCacheKey()`; kalau bukan lagu aktif, hasil di-drop (bitmap tetap di-cache per key). Notifikasi tidak lagi dibangun dari `track`/`isPlaying` yang ditangkap saat enqueue — di-rebuild dari `getCurrentTrack()`/`getIsPlaying()` saat completion. (P1 #1)
2. **In-flight per-key** — `pendingAsyncCacheKey` (slot tunggal) diganti `inFlightLoads: HashSet<String>`; completion request A tidak bisa menghapus marker B → tidak ada load duplikat untuk key yang sama. (P2 #5)
3. **Crossfade promotion refresh** — `onCrossfadeComplete` memanggil `scheduleSessionArtworkRefresh()` setelah offload listener swap, karena READY/transition standby player ter-drop guard `isActiveEvent()` → artworkData SystemUI/MIUI tidak basi. (P1 #2)
4. **Album kompilasi cache fallback** — `FallbackBitmapLoader.tryEmbedded()` iterasi SEMUA `songIds` (bukan `songIds.first()`) untuk `artworkCache.getOrExtract()`; decode gagal di satu track lanjut ke track berikutnya. (P2 #6)
5. **Executor shutdown** — `PlaybackNotificationManager.close()`, `SessionArtworkProvider.close()`, `FallbackBitmapLoader.close()` dipanggil di `Media3PlaybackService.onDestroy()` (idempotent); `provide()`/`loadBitmap()`/`decodeBitmap()` resolve null/exception saat executor sudah shutdown, `prewarmArtwork`/`refreshAsync` di-guard `closed`. (P2 #7)
6. **Pull 78715ae sudah menutup P1 #3** (process-wide lock + unique temp file + `isUsableCacheFile` di ArtworkCacheManager) **dan P1 #4** (`artworkSource` dibawa buildSongMapFromUri → TrackMapper → MediaItemFactory untuk file eksternal).

## UPDATE 1.5.29b — ZOOM-01: zoom artwork muncul SAAT PLAYING (user repro, menunggu konfirmasi device)
Gejala user: artwork notifikasi normal saat lagu PAUSED, tapi langsung zoom/membesar saat PLAY ditekan. Mekanisme yang dicocokkan ke kode:
1. `MediaItemFactory` selalu set `artworkUri = content://media/external/audio/albumart/{albumId}` (low-res ≤512px, non-persegi); `artworkData` 1024 persegi hanya masuk asinkron via `publishSessionArtwork()` → `replaceMediaItems()`.
2. Saat PLAYING, SystemUI/MIUI shade media card beralih ke session-driven → kalau `artworkData` absen (window async, item di-rebuild `rebuildPlayerQueue`, publish ter-drop), renderer jatuh ke `artworkUri` low-res → upscale + center-crop = zoom+pecah. Saat PAUSED card tidak aktif/renders dari largeIcon → normal.
3. `onIsPlayingChanged(true)` SEBELUMNYA TIDAK memanggil `scheduleSessionArtworkRefresh()` → play tidak pernah menyembuhkan artworkData yang hilang.
Fix 3 lapis (ZOOM-01):
- **PNM**: `normalizeNotificationArtwork` dipulihkan (eksperimen hapus-letterbox di-revert — largeIcon wajib persegi agar tidak bisa di-center-crop).
- **publishSessionArtwork**: saat `bytes == null`, `artworkUri` ikut di-null-kan (jangan biarkan URI low-res jadi satu-satunya sumber art; no-art > zoomed-art; URI dead karena buildBytes cuma null kalau embedded+cache+URI semuanya gagal). Early-return dibandingkan artworkData DAN artworkUri.
- **onIsPlayingChanged(true)** → `scheduleSessionArtworkRefresh()` (cache hit = sinkron, murah).
Belum di-changelog — tunggu konfirmasi device.

## UPDATE 1.5.29c — artworkUri DIHAPUS dari metadata MediaItem (ZOOM-01 decisive)
`MediaItemFactory.from()` TIDAK lagi set `MediaMetadata.artworkUri` (sebelumnya `content://media/external/audio/albumart/{albumId}` low-res ≤512px). Konsekuensi:
- SystemUI/MIUI session-driven card hanya punya `artworkData` (1024 persegi) atau tidak ada art — **tidak mungkin lagi fallback ke thumbnail low-res** (zoom source hilang di akar).
- **App-internal track-map `artworkUri` TETAP ada** (`TrackMapper`, `LocalSong` Dart, PNM cache key + URI fallback, `refreshSessionArtwork` URI source) — itu tidak bocor ke session, tetap dipakai untuk notifikasi/overlay.
- `publishSessionArtwork` masih punya guard `setArtworkUri(null)` saat bytes==null — sekarang no-op defensif (metadata tak pernah punya URI), biarkan.
- Bluetooth/lock-screen (MediaSessionLegacyStub): art lewat `artworkData` (byte-array path BitmapLoader) — URI path hilang, tapi itu jalur low-res yang justru jadi masalah; lagu tanpa artworkData tampil tanpa art (lebih baik dari zoom).
- Semua MediaItem (restore queue, standby crossfade, insert, rebuild) lewat satu `MediaItemFactory.from()` — satu titik ubah.
- Komentar doc `SessionArtworkProvider` class + `scheduleSessionArtworkRefresh` KDoc di-update (artworkUri tidak lagi di-set).
Kalau device masih zoom, tersisa hipotesis: kartu MIUI membaca `artworkUri` dari track-map Dart/overlay (bukan session) — cek jalur overlay player.

## UPDATE 1.5.29d — Overlay player (NowPlayingOverlayActivity) ikut ZOOM-01
Overlay floating window (buka file audio dari file manager/Telegram) decode embedded art VIA `BitmapFactory.decodeByteArray(bytes, 0, bytes.size)` — FULL-SIZE tanpa cap dan tanpa normalisasi — lalu render di `ImageView` 56dp `scaleType=centerCrop` → art non-persegi di-crop, art kecil di-upscale (zoom/pecah), art raksasa berisiko OOM. Fix: helper `decodeCappedSquare(bytes)` — bounds-first decode cap `MAX_ART_PX=1024` (sisi terpanjang, ARGB_8888) + letterbox persegi never-upscale (pola sama dengan `normalizeNotificationArtwork`); `MediaMetadataRetriever.release()` dipindah ke `finally`. Catatan: jalur Flutter in-app (`SongArtwork`/`ArtworkRepository`) sudah aman — pakai `getArtworkPath(songId)` → cache WebP ≤1000px, `LocalSong.artworkUri` di Dart tidak pernah dibaca UI (dead field).
