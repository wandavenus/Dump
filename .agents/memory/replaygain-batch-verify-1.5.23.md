# Verifikasi + hardening batch write ReplayGain — 1.5.23

Tanggal: 10 Agustus 2026 · Versi: 1.5.23

## Konteks
Verifikasi menyeluruh atas `_flushPendingWrites()` paralel (1.5.22). Hasil per item
ada di chat; catatan penting untuk masa depan:

## Verdict kunci (bukti kode)
- **Executor benar paralel**: `boundedExecutor` = ThreadPoolExecutor(2,2, AbortPolicy,
  queue 16); `writeReplayGainBatch` handler = 1 task per call → 2 calls = 2 worker.
  Write path native (tag_writer.cpp) TIDAK punya mutex/global state (hanya
  `g_registry_mutex` di replaygain_jni untuk ANALYZER scan, bukan write).
- **SQLite aman**: MetadataCacheDb = SQLiteOpenHelper singleton + WAL +
  synchronous=NORMAL (onOpen), semua method try/catch (gagal = cache-miss,
  bukan korupsi). Sudah diakses 2 thread scan sejak lama.
- **batchPreAuthorizedSongIds**: hanya disentuh di main thread (MethodChannel
  callbacks + handler) → tidak ada race; `removeAll` per batch idempotent.
- **Ordering**: bridge `requests.map { … }` → hasil 1:1 urut; invalidate pakai
  songId DARI hasil native (bukan indeks) — aman walau urutan berubah (tidak akan).

## Perubahan 1.5.23 (Dart, `lib/services/replay_gain_service/service.dart`)
1. **Dedup `toScan` di scanLibrary** oleh `song.id` — duplikat tidak pernah
   di-scan 2× / di-antri 2× untuk tulis.
2. **`_flushPendingWrites`**: dedup `pending` oleh song.id (defense-in-depth) +
   chunk tetap 250 (`_writeChunkSize`) + pool 2 worker (loop berbagi `next`;
   Dart single-thread → aman) → payload per pesan ~40–50KB & kedua worker
   tersaturasi (bukan 50/50 yang idle di ekor + 1 pesan raksasa utk ribuan lagu).
3. **`writeReplayGainBatch`**: catch diperluas `on Object` (setelah
   PlatformException) → Future tidak pernah reject → `Future.wait` tidak bisa
   membatalkan hasil batch satunya; `_flushPendingWrites` juga try/catch.
4. Protokol write→close→reopen→verify→(rollback) TIDAK disentuh.

## Catatan
- Library 1.000–10.000 lagu: pendingWrites di memori ±2–3MB (OK); payload channel
  kini ≤250 req/call. Kalau mau throughput lebih tinggi, naikkan worker native +
  jumlah worker pool Dart secara bersama.
