---
name: AutoMix Fase 2 decision contract (v1.5.65)
description: Kontrak BPM/ambang bersama C-Dart-Kotlin, cue metre x4, fade berbasis bar, cooldown artis penuh, cache schema v22.
---

# AutoMix Fase 2 decision contract (v1.5.64)

**Tanggal:** 2026-10-31 · **Versi:** 1.5.65 · **Basis audit:** `automix_algorithm_audit_v9.md` (AM9-H03/M01/M08/M13/M18).

## Perubahan

- **M18 — rentang tempo tunggal 50–220 BPM.** `automix_native.h` menjadi
  sumber kontrak; `automix_analyzer.c` dan `automix_live_tracker.c` mengalias
  `BPM_MIN/MAX` ke konstanta itu, Dart `AutomixContract` dan Kotlin
  `AutomixContract.kt` mencerminkan nilai yang sama. Live tracker kini
  mengabaikan peak korelasi 3:1 selain 1:2/2:1; tanpa itu lag 3P (50 BPM)
  masuk rentang baru dan menjatuhkan confidence pada pulse 150 BPM.
- **M01 — cue memakai metre x4.** Drop/breakdown di analyzer snap ke
  `phrase_meter * 4` ketukan; `phrase_meter` dibaca dari `output[32]`, fallback
  4/4. Grid 16-ketukan tetap tidak boleh dipakai lagi untuk cue.
- **M13 — fade dalam bar.** Dart memilih short = ½ bar, quick = 1 bar, long =
  minimal 2 bar outgoing, lalu clamp 1,5–12 s dan quantise ½ ketukan. Kotlin
  `fadeSeconds` hanya memvalidasi payload + safety envelope; cap detik per
  strategi dihapus agar tidak membatalkan bar 3/4 atau 6/8.
- **H03 — cooldown artis penuh.** Biaya cooldown yang sama dipakai di greedy,
  one-step lookahead, `path_cost`, `link_cost`, local swap, dan window cost,
  baik di C maupun mirror Dart. Base 0,09 dengan `avoidArtistRepeat`, 0,03
  tanpa; decay linear empat slot. `averageCost` sekarang memuat cooldown.
- **M08 — tabel ambang tunggal.** Konstanta tempo/key/structure/drop/vocal
  confidence, vocal likelihood, dan fade min/max ada di header C; planner,
  analyzer, engine Dart, dan `service.dart` membaca mirror-nya. Tes kontrak
  Dart membaca header dan membandingkan setiap nilai; tes Kotlin mengunci
  mirror yang sama.
- **Cache schema v21 → v22.** Rentang BPM analyzer dan grid cue berubah, jadi
  entri lama dianalisis ulang. Fixture cache v21 diperbarui ke v22.

## Verifikasi sesi

- C suite manual (analyzer/planner/live/phase/tone) → lulus, termasuk tes baru
  `test_analyzer_bpm_contract_range` dan
  `test_analyzer_cue_snaps_to_measured_meter` (3/4, cue 18,5 s dari lift
  sekitar 18,1 s).
- `dart analyze lib test` dan `dart analyze tools native_audio_runtime/lib
  native_audio_runtime/test` → no issues.
- `flutter test test/services/automix_service` → 143 lulus.
- `cd native_audio_runtime && dart test -j 1` → 65 lulus.
- `dart run tools/automix_bench.dart --check` → 12 kasus lulus; 8/8 BPM ≤2%,
  8/8 metre, 10/10 key, rata-rata 96,2 ms, peak RSS 228,9 MB.
- Golden `testdata/automix/golden.json` diperbarui: 16 field bergeser karena
  kontrak tempo baru (tone-A-minor tanpa ekspektasi BPM ikut berubah 120→90;
  kasus tone memang tidak menguji tempo). Jangan revert golden ini tanpa
  menjalankan ulang benchmark.

## Batasan

- Kotlin compile/unit test (`./gradlew :app:testDebugUnitTest`) tidak
  dijalankan di sandbox ini; tes
  `AutomixTransitionPolicyTest` sudah disesuaikan tetapi belum dieksekusi.
- `tools/automix_ffmpeg_regression.sh` dan capture audio perangkat juga belum
  dijalankan.
- Ambang M08 masih heuristik sementara, bukan probabilitas terkalibrasi.
