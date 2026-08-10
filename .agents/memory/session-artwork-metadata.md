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
session via **replace MediaItem saat ini dengan salinan ber-artworkData**
(`Player.replaceMediaItems(index, index+1, [updatedItem])`). Media3 TIDAK punya
`Player.setMediaMetadata` / `MediaSession.setMediaMetadata` (percobaan pertama
pakai API itu gagal build: "Unresolved reference 'setMediaMetadata'"). Replace
item ber-source identik (buildUpon, uid sama) → period UID tetap → posisi
terjaga, playback seamless, tidak memicu `onMediaItemTransition`, hanya
broadcast `onMediaMetadataChanged`. Consumer yang prefer ART bytes
(MediaStyleNotificationHelper, SystemUI, MIUI, MediaSessionLegacyStub/
Bluetooth) langsung render tajam.

- `SessionArtworkProvider.kt` (baru): produce square bytes; fast-path raw
  passthrough kalau source sudah persegi & ≤1024 (tanpa decode/re-encode);
  cache LruCache 12 lagu; single daemon thread; callback selalu terpanggil.
- `Media3PlaybackService.refreshSessionArtwork()` → `publishSessionArtwork()`:
  ambil id + artworkUri dari `transportState.currentTrackMap()`, panggil
  provider, post ke main handler, lalu `player.replaceMediaItems(index,
  index+1, [item.buildUpon().setMediaMetadata(meta-artworkData).build()])`.
  Guard mediaId untuk hasil stale; lagu tanpa art / gagal load → replace
  dengan salinan tanpa artworkData (clear stale art lagu sebelumnya).
- Hook: `onMediaItemTransition`, `onPlaybackStateChanged(STATE_READY)`,
  setelah `restoreQueueFromPrefs()` di onCreate.
- artworkData diisi LANGSUNG di current item saat replace (bukan merge
  player-level), jadi konsumen session melihat artworkUri low-res + artworkData
  high-res; yang prefer bytes memakai artworkData. Tidak perlu ubah
  MediaItemFactory.

## Catatan
- `setDisableArtworkMetadata(true)` di extractors tetap (extractor tak perlu
  baca artwork file); kita isi artworkData langsung di item saat replace.
- `Player.setMediaMetadata` / `MediaSession.setMediaMetadata` TIDAK ada di
  Media3 1.11.0 — jangan dipakai lagi; pakai `Player.replaceMediaItems`.
- LargeIcon + FallbackBitmapLoader (uncommitted 1.5.27) tetap berguna untuk
  jalur notifikasi collapsed + Bluetooth fallback URI — saling melengkapi.
