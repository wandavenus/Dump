# AutoMix Fase 3–6 (v1.5.66, cache schema v23)

Lanjutan `automix-fase2-contract-v22.md`. Semua perubahan Fase 3–6 di bawah sudah
di-commit sebagai `d27de4c` (v1.5.66).

## Fase 3 — drop/early handover

- Analyzer menyimpan hingga **tiga kandidat drop per window**, dedupe jarak onset 1,5 s.
  ABI analyzer naik **41 → 45**; slot 41/42 dan 43/44 adalah offset/confidence kandidat
  kedua dan ketiga. Header, FFI, map Kotlin, dan parser Dart harus tetap sinkron.
- `automixMergeSegments` mengubah kandidat ke waktu absolut file dan memilih **drop paling
  awal yang confident** di envelope **8.000–150.000 ms**. Gate 90 s yang lama dihapus dari
  engine, service, dan `Media3PlaybackService`.
- Early handover boleh phrase-snap sampai **satu frasa penuh (`metre × 4` beat)** lewat
  `phraseAlignedStartMs(..., maxShiftBeats)`; fallback near-EOF tetap 4 beat.
- Alasan early handover tidak tersedia diekspos sebagai
  `earlyHandoverUnavailableReason` dan dicatat verbose sekali per perubahan.
- Tes: `test_analyzer_multiple_drop_candidates`, parser tiga kandidat, merge earliest,
  gate Kotlin, dan phrase snap Kotlin (tes Kotlin belum dijalankan di sandbox).

## Fase 4 — cache dan perencanaan

- Cache pindah dari SharedPreferences ke **satu file per lagu**:
  `${appSupport}/automix_cache/automix_<id>.json`. Tulis atomic (temp + rename), decode
  `jsonDecode` di `Isolate.run`. Metadata MediaStore tidak disimpan di cache.
- Migrasi sekali dari key legacy `automix_<id>`, lalu `prefs.remove`. Prune sekali per
  service menghapus `*.tmp` dan ID yang sudah tidak ada di MediaStore.
- Perencanaan hanya prefix **20 lagu**, minimal **4 decoded**. Reorder hanya diterapkan
  bila biaya membaik **≥5%** atau tiga posisi teratas berubah (`scoreOrder` hysteresis).
- Cache schema **v22 → v23**. Fixture dan test memakai `version: 23`.

## Fase 5 — beat/downbeat/phrase (parsial)

- Ditambahkan `track_beats_dp`: DP gaya Ellis, kandidat periode ±35%, penalti log-ratio,
  gate confidence. `estimate_phrase_grid` menerima `beat_indices` dan memakai timestamp
  beat aktual untuk bar/frasa.
- **Gate penting:** DP hanya dipakai bila `output[23] (tempo stability) < 0.85`. Material
  fixed-tempo tetap memakai histogram phase lama. Tanpa gate ini, downbeat click 120 BPM
  bergeser ~58 ms dan golden gagal; penyebabnya perbedaan pusat frame vs timestamp onset.
- `output[3] (phase)` sengaja tidak diubah agar playback/tes lama tidak regresi.
- BPM gabungan antar-window sekarang **weighted median**, bukan rata-rata. Bila agreement
  < 70%, confidence dipotong setengah agar planner memperlakukan tempo sebagai netral
  (kasus 120/120/90 tidak lagi menjadi 110).
- Belum dikerjakan: key per section dan chord-quality HMM; butuh corpus berlabel.

## Fase 6 — planner/transisi (parsial)

- Beam search **width 8, depth 2** di C (`NAR_PLAN_BEAM_WIDTH/DEPTH`) dan mirror Dart.
  Cost dua langkah: `cost1 + 0.35·min(cost2 + 0.35·cost3)`.
- Polish swap/insert/reverse dan cooldown artis tetap; budget tidak berubah di fase ini.
- Belum dikerjakan: tempo arc per posisi, crossover LR4, short-term loudness tambahan,
  dan post-mix limiter. Limiter pasca-mix tidak mungkin tanpa perubahan arsitektur dua
  AudioTrack; jangan klaim sudah ada.

## Verifikasi yang benar-benar dijalankan

- `native_audio_runtime` C suite: lulus (warning lama `nanosleep`).
- `cd native_audio_runtime && dart test -j 1`: **65 lulus**.
- `flutter test test/services/automix_service`: **149 lulus**.
- `dart analyze lib test`: bersih.
- `dart run tools/automix_bench.dart --check`: **12 kasus lulus, golden tidak berubah**;
  8/8 BPM ≤2%, 8/8 metre, 10/10 key, rata-rata ~99 ms.
- Belum dijalankan: Kotlin/Gradle (percobaan `:app:testDebugUnitTest --tests ...AutomixTransitionPolicyTest`
  gagal saat wrapper mengunduh Gradle: `No space left on device`, root hanya ~36 KB),
  `tools/automix_ffmpeg_regression.sh`, capture perangkat, APK (dilarang di environment ini).

## Blueprint sisa temuan

Rencana eksekusi lengkap untuk semua temuan yang masih terbuka ada di
`docs/superpowers/plans/2026-10-31-automix-open-findings-blueprint.md`. Isinya memetakan
workstream, urutan PR, file, ABI/cache checklist, tes, kriteria lulus P01–P10, dan aturan
status (Open / Implemented, unvalidated / Validated). Gunakan dokumen itu sebagai titik
mulai; jangan mengulang implementasi dasar yang sudah ada, dan kerjakan residual parsial
sesuai matriksnya.

## Jebakan

- Jangan menaikkan `output[3]` ke phase DP tanpa memperbarui golden dan memeriksa
  pergeseran timestamp frame.
- Jangan memakai DP phrase untuk semua track; gate stability adalah bagian dari kontrak
  agar fixed-tempo tidak regresi.
- File cache harus atomic; jangan menulis JSON langsung ke path final.
- ABI 45 harus diperbarui di empat tempat: C header/analyzer, JNI, FFI Dart, dan map Kotlin.
