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
