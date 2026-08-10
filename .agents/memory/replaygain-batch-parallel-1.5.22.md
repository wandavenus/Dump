# ReplayGain batch write paralel — 1.5.22

Tanggal: 10 Agustus 2026 · Versi: 1.5.22

## Konteks (audit diff commit 5df2527 / 1.5.21)
Commit 1.5.21 memperkenalkan `writeReplayGainBatch` (R-B) + 2 worker tulis (R-C).
Audit ulang menemukan dua masalah:

## T-1 — Batch tulis SERIAL dalam 1 task executor (performa)
- `MainActivity` handler `writeReplayGainBatch` men-submit SATU task yang meng-loop
  semua lagu berurutan (`replayGainBridge.writeReplayGainBatch`). Artinya worker ke-2
  dari `replayGainWriteExecutor` (R-C, threads=2) TIDAK pernah dipakai untuk alur
  library write — tidak ada paralelisme write di dalam batch.
- Bonus: library ribuan lagu = 1 payload MethodChannel raksasa.

### Fix (hanya Dart, `lib/services/replay_gain_service/service.dart`)
`_flushPendingWrites()` kini memecah `pending` menjadi 2 bagian dan mengirim
**2 panggilan `writeReplayGainBatch` konkuren** (`Future.wait`). Masing-masing call
= task terpisah di native → 2 worker jalan paralel pada file berbeda (aman: fd
MediaStore per lagu). Payload per panggilan ≤ ceil(N/2).
- `pending.length == 1` → skip split (1 call).
- Keamanan 2 thread sudah terjamin: fd per lagu, SQLite sudah diakses 2 thread scan.

## T-2 — Hasil batch kosong/terpotong dianggap sukses (defensif)
- Sebelum: `results = raw ?? const []` → `ok` bisa lebih pendek dari `requests` →
  `_flushPendingWrites` menghitung 0 gagal → silent false-positive.
- Sesudah: hasil di-pad ke `requests.length` (default false); songId hanya
  di-invalidate untuk slot yang benar-benar sukses.

## Validasi
- `flutter analyze lib test` → bersih; `flutter test` → 58/58.
- Kotlin TIDAK berubah di 1.5.22 (murni perbaikan sisi Dart).

## Catatan
- Kalau mau paralelisme lebih dalam (mis. 4 arah), naikkan worker
  `replayGainWriteExecutor` + jumlah split — pola sudah terbukti.
- Protokol write→verify→(rollback) per lagu tetap utuh.
