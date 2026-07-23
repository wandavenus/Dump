---
name: Notification Artwork Fix
description: Two-stage artwork fallback in PlaybackNotificationManager + TTL-based no-artwork cache
---

# Notification Artwork Fix

## Rule
`PlaybackNotificationManager.loadBitmap()` now has two stages:
1. ContentResolver (artUri dari MediaStore albumart URI)
2. `ArtworkCacheManager.getOrExtract(songId)` — same pipeline as Full Player

`noArtworkUris` (permanent blacklist) diganti `noArtworkTimestamps: HashMap<String, Long>` dengan TTL 30 detik.

**Why:** Sebelumnya notifikasi hanya pakai ContentResolver; jika MediaStore belum index artwork (cold start, file non-standar), notifikasi tidak pernah punya artwork. TTL fix: song yang gagal saat MediaStore belum siap bisa di-retry otomatis.

**How to apply:**
- `ArtworkCacheManager` diinject via constructor param `artworkCacheManager: ArtworkCacheManager?` (nullable, default null).
- `Media3PlaybackService` membuat `serviceArtworkCache = ArtworkCacheManager(this)` dan meneruskannya ke notificationManager.
- Disk cache di `{filesDir}/artwork/` dishare antara `MainActivity` dan `Media3PlaybackService` (path sama, dua instance terpisah, OK).
- Cache key: `artUri ?: "song:$songId"` — konsisten di `bitmapCache` (LruCache) dan `noArtworkTimestamps`.
- `FallbackBitmapLoader` tetap untuk Bluetooth/lock-screen via Media3 `BitmapLoader` — tidak diubah.
