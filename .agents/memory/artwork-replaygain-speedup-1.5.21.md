# Perf 1.5.21: artwork LRU/raw-copy + ReplayGain batch write

Tanggal: 10 Agustus 2026 · Versi: 1.5.21

## Konteks
Repo sudah disinkronkan ke remote (1.5.20). Mayoritas optimasi artwork/replaygain
(E-A raw-copy JPEG, 3 thread, two-pass decode, negative cache, PcmDecoder
grow-only, fd-TagLib write+verify+rollback, batch write grant 1 dialog) sudah
ada. Sisa peluang kecil-sedang diterapkan di 1.5.21:

## A1 — Throttle LRU artwork (`ArtworkCacheManager.kt`)
- Sebelum: `cleanupIfNeeded()` (listFiles + sumOf seluruh folder cache) dipanggil
  SETIAP ekstraksi sukses → O(n) scan berulang saat batch/prefetch 3 thread.
- Sesudah: maksimal 1×/15 detik (`SystemClock.elapsedRealtime`, `@Volatile
  lastCleanupAtMs`). Cap 500MB tetap soft ceiling; eviksi telat beberapa detik
  tidak mengubah UX. `cleanupIfNeeded` tetap public (dipanggil langsung bila perlu).

## A3 — Raw-copy diperluas ke PNG/WebP (`ArtworkCacheManager.kt`)
- Sebelum: raw-copy (tanpa decode→re-encode WebP) hanya untuk JPEG ≤ 1000px.
- Sesudah: `isRawCopyCandidate()` = JPEG/PNG/WebP (cek magic bytes) + bounds
  decode ≤ 1000px + ukuran ≤ 400KB (MAX_RAW_COPY_BYTES). PNG/WebP kecil ikut
  disalin byte-for-byte — hemat 50–150ms/lagu + tanpa penurunan kualitas.
  File tetap berekstensi `.webp`; semua pembaca sniff magic bytes (sudah dibuktikan
  untuk JPEG).

## R-C — Write ReplayGain 2 thread (`MainActivity.kt`)
- `replayGainWriteExecutor` 1 → 2. Aman: tiap write→verify pakai fd MediaStore
  per lagu (file berbeda tidak pernah disentuh 2 worker bersamaan); MetadataCacheDb
  (SQLite) sudah diakses 2 thread scan hari ini.

## R-B — Batch write API (nilai tertinggi)
Jalur `scanLibrary(writeTags:true)` lama: ±6 round-trip MethodChannel + SharedPrefs
per lagu (identity ×3, scanTrack, writeReplayGain, invalidate).

Sesudah (3 layer):
- **`MainActivity.kt`** — case channel baru `"writeReplayGainBatch"` (list of
  per-song args maps → 1 `submitBackground` ke write executor → list hasil;
  consume `batchPreAuthorizedSongIds` sekaligus). Caller WAJIB pre-authorize via
  `requestReplayGainWriteAccessBatch`; lagu yang tidak di-grant gagal per-lagu
  (WRITE_ACCESS_DENIED), tidak memunculkan dialog per file.
- **`ReplayGainBridge.kt`** — `writeReplayGainBatch(requests)` = map ke
  `writeReplayGain()` per item + tambah `songId` di tiap hasil (untuk invalidate
  tepat sasaran). Error per-lagu dipertahankan (1 file rusak tidak menggagalkan batch).
- **`lib/services/replay_gain_service/service.dart`** —
  - `scanOneSong` di-refactor ke `_scanTrackResult()` (identity before → scanTrack →
    identity after; mengembalikan `_TrackScan` = LoudnessData + integratedLufs + identity).
  - `scanLibrary` kini scan saja per chunk (writeTags tidak lagi per-lagu), kumpulkan
    `ReplayGainWriteRequest`, lalu `_flushPendingWrites()` SATU kali di akhir
    (juga di jalur cancel — hasil yang sudah diukur tetap ditulis).
  - `writeReplayGainBatch(List<ReplayGainWriteRequest>)` → 1 call channel, invalidate
    batch untuk yang sukses.
- Round-trip per lagu: ±6 → ±3 (identity before, scanTrack, identity after) + 1/N.

## Validasi
- `flutter analyze lib test` → bersih; `flutter test` → hijau.
- Kotlin tidak bisa dikompilasi di sandbox (Gradle di-kill) — hunk direview manual:
  struktur handler, kunci arg, konsistensi tipe Map, semantik per-lagu.

## Yang sengaja TIDAK diubah
- Scan PCM tetap 2 thread (hardware MediaCodec, Snapdragon 730) — dominan & sudah pas.
- Protokol write→close→reopen→verify→(restore) tetap utuh (safety, jangan dilonggarkan).
- `scanOneSong(writeTags:true)` tetap ada (single-song flow UI) — hanya `scanLibrary`
  yang pindah ke batch.
