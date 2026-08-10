---
name: Session artwork metadata (artworkData)
description: Root cause + fix of the zoom/pecah notification artwork bug — SystemUI/MIUI renders MediaSession artworkData, NOT setLargeIcon
---

# Session artwork metadata (artworkData) — fix zoom + pecah notifikasi

## Akar masalah (kenapa 5 fix sebelumnya gagal)
SystemUI / MIUI media surfaces (shade notification card, lock screen media
controls) **tidak** merender `Notification.Builder.setLargeIcon()`. Mereka
connect ke MediaSession dan decode `METADATA_KEY_ART` (artworkData) atau
`ART_URI` sendiri. `MediaItemFactory` hanya set `artworkUri =
content://media/external/audio/albumart/{albumId}` — thumbnail MediaStore
low-res (≤512px, non-square). SystemUI upscale + center-crop → **zoom + pecah**.
LargeIcon letterboxing di `PlaybackNotificationManager` dan BitmapLoader
(`FallbackBitmapLoader`) tidak menyentuh jalur ini sama sekali.

## Fix (1.5.27)
Publish `MediaMetadata.artworkData` = artwork full-res (embedded-first via
MediaMetadataRetriever), letterbox persegi 1024px, encode JPEG 90, ke metadata
**player-level** session via `ExoPlayer.setMediaMetadata()` (aman saat play,
tidak reset stream). Consumer yang prefer ART bytes (MediaStyleNotificationHelper,
SystemUI, MIUI, MediaSessionLegacyStub/Bluetooth) langsung render tajam.

- `SessionArtworkProvider.kt` (baru): produce square bytes; fast-path raw
  passthrough kalau source sudah persegi & ≤1024 (tanpa decode/re-encode);
  cache LruCache 12 lagu; single daemon thread; callback selalu terpanggil.
- `Media3PlaybackService.refreshSessionArtwork()`: ambil id + artworkUri dari
  `transportState.currentTrackMap()`, panggil provider, post ke main handler,
  `activePlayerProxy.setMediaMetadata(...)` (ForwardingPlayer → ExoPlayer).
  Kalau lagu tanpa art / gagal load → set metadata kosong (clear stale art
  lagu sebelumnya).
- Hook: `onMediaItemTransition`, `onPlaybackStateChanged(STATE_READY)`,
  setelah `restoreQueueFromPrefs()` di onCreate.
- Merge semantics: field item-level menang atas player-level per-field. Item
  punya artworkUri (low-res) tapi artworkData null → merged punya artworkData
  high-res dari player → consumer pakai bytes. Tidak perlu ubah MediaItemFactory.

## Catatan
- `setDisableArtworkMetadata(true)` di extractors tetap (item artworkData tak
  dipakai); kita set player-level, bukan item-level.
- `Player.setMediaMetadata` ada sejak Media3 1.1; proyek pakai 1.11.0.
- LargeIcon + FallbackBitmapLoader (uncommitted 1.5.27) tetap berguna untuk
  jalur notifikasi collapsed + Bluetooth fallback URI — saling melengkapi.
