# Artwork viewport pre-decode 1.5.24

Audit jalur artwork (semua item diverifikasi berbasis kode; lihat ringkasan chat untuk verdict per item).

## Gap yang ditemukan & diperbaiki

Sebelumnya: `ArtworkRepository.prefetch()` = warm-up **path saja** (getPath, tidak pernah decode). List Lagu (library detail Songs tab) hanya memakai prefetch path ini → lagu yang belum di-extract tetap flash placeholder saat pertama discroll.

### Perbaikan (murni Dart, tanpa thread/worker baru)

**`lib/services/artwork_repository.dart`** — metode baru `predecode(songIds, {targetSizePx, concurrency: 2, limit: 20})`:
- Benar-benar **decode ke Flutter ImageCache** (getProvider → `_decodeIntoImageCache`), bukan cuma path.
- Dedup: `_decoding` set mencegah decode ganda id yang sama; skip via `ImageCache.containsKey(obtainKey)` untuk yang sudah resident.
- Engine Flutter yang decode (background), tidak block UI isolate; tidak ada worker baru (sesuai constraint audit).

**`lib/widgets/pages/library_sections/detail.dart`** — hook di `_onScroll`:
- Saat first-visible row berubah (`pixels / _kRowExtent(61px)`), request window ±(ahead 10 / behind 8) ≈ 18 lagu, **visible-first** (baris di depan anchor dulu, baru di belakang).
- Latest-wins drain loop (`_pendingDecodeAnchor` + `_decodeRunning`) → fling cepat hanya memproses anchor terakhir.
- Dinonaktifkan saat `_filter` aktif (index mapping berubah); anchor di-reset saat songs di-update.
- `_smallArtworkPx = resolveTargetPx(55)` → key ResizeImage persis sama dengan request SongArtwork 55px → prewarm benar-benar hit.

## Yang diverifikasi (tidak diubah)

- Rebuild/scroll widget **tidak** re-decode: provider di-reuse (`_providers` map), `_providersEqual` guard di SongArtwork, ImageCache key stabil (FileImage value-equality + ResizeImage compare).
- 1 songId → 1 extraction in-flight (Dart `_inFlight` + lock per-song native) + 1 decode in-flight (ImageCache shared completer).
- Cache-hit: `getProviderSync` via `_diskCachedIds` O(1) tanpa statSync; `getPath` stat 1×/lagu/sesi lalu memori; native cache hit = exists()+length()+touch() saja, LRU sudah di-throttle (A1 1.5.21).
- Raw-copy JPEG/PNG/WebP tetap byte-for-byte (`saveRaw`), bounds-only decode cuma validasi.
- `targetSizePx`/WEBP_QUALITY/MAX_ARTWORK_SIZE tidak disentuh.

## Benchmark

Belum bisa diukur di sandbox (Android-only). Harus diukur di Mi 9T/K20 (target device): waktu artwork pertama muncul (cold/warm cache), scroll FPS/jank, memory. Jangan klaim lebih cepat tanpa measurement.
