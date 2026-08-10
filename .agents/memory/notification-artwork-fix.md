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
full-res persegi via `Player.setMediaMetadata()`. Jangan kembalikan logika
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
