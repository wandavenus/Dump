---
name: ReplayGain Write Tag — Fix Pass
description: Fd leak fix, dead code removal, batch auth optimization, logging hardening applied to ReplayGain write-tag path.
---

## Rule
Path-based write API (WriteReplayGainTags, RemoveReplayGainTags) sudah dihapus sepenuhnya.
Satu-satunya jalur write aktif adalah fd-based (WriteReplayGainTagsFd, dll.).

**Why:** Path-based API adalah dead code — tidak pernah dipanggil dari ReplayGainBridge.
Menghapusnya menghilangkan risiko maintainer keliru menggunakannya (bypass Scoped Storage).

## Fd Leak Fix Pattern
Setiap fungsi fd-based yang membuat `TagLib::FileStream(fd, ...)` HARUS menutup fd secara manual
jika `!stream.isOpen()` (fdopen gagal — TagLib tidak mengambil ownership).
FsyncGuard memegang `dup(fd)`, bukan fd asli, jadi `::close(fd)` aman tanpa double-close.

Fungsi yang sudah diperbaiki (2026-07-20):
- WriteReplayGainTagsFd
- RemoveReplayGainTagsFd
- RestoreMetadataRegionFd
- ReadBackFd

## Batch Authorization Optimization
`batchPreAuthorizedSongIds: MutableSet<Int>` di MainActivity menampung song IDs yang
sudah di-pre-authorize via `requestReplayGainWriteAccessBatch`. Setiap `writeReplayGain` /
`removeReplayGain` handler mengkonsumsi ID dari set ini dengan `remove()` — jika ada,
skip `requestReplayGainWriteAccess` (hemat 1 openFileDescriptor round-trip per lagu).

**How to apply:** Jika ada fitur batch write baru, pastikan selalu isi `batchPreAuthorizedSongIds`
di callback `requestReplayGainWriteAccessBatch` sebelum individual write calls dilakukan.

## openReplayGainWriteFd Logging
Sekarang memisahkan SecurityException / FileNotFoundException / IOException / Exception
ke Log.w terpisah dengan tag "MainActivity" — exception tidak di-swallow silent lagi.
