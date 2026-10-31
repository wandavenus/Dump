---
name: AutoMix seam-edge features (v1.5.63)
description: Fase 0 benchmark harness + Fase 1 15 s seam-edge RMS/LUFS/onset, cache schema v21.
---

# AutoMix seam-edge features (v1.5.63)

**Tanggal:** 2026-10-31 · **Versi:** 1.5.63 · **Basis audit:** `automix_algorithm_audit_v9.md` (AM9-H01/H05/M10/M11).

## Fase 0 — benchmark harness

- `tools/automix_bench.dart` menjalankan `NativeAutomix.analyze` atas manifest
  `testdata/automix/manifest.json` (12 kasus sintetis deterministik; `kind=file`
  menerima WAV PCM16/float32 untuk korpus nyata).
- Metrik: BPM error mentah dan octave-folded, key/tonic+mode, metre, error fase
  beat/downbeat, waktu analisis, RSS. Golden `testdata/automix/golden.json`
  menyimpan 41 slot analyzer; `--check` membandingkan dengan toleransi per field
  (tempo 2%, dB 1.5, fase 25 ms, label struktur/key/metre exact).
- Baseline sintetis: 8/8 BPM dalam 2%, 8/8 metre, 10/10 key, ~93 ms/trek,
  peak RSS ~228 MB. Ini **bukan** klaim akurasi musik nyata; korpus 120 trek
  berlabel masih harus dipasok.
- Perintah: `dart run tools/automix_bench.dart [--write-golden|--check|--json]`.

## Fase 1 — edge features + keputusan seam

- ABI analyzer naik 35 → 41 (append-only). Slot baru:
  - 35/36: median RMS dBFS 15 detik pertama/terakhir.
  - 37/38: LUFS K-weighted BS.1770 (400 ms block, 100 ms hop, absolute -70 LUFS
    gate + relative -10 LU gate), dihitung pada sample rate aktual.
  - 39/40: onset rate 15 detik pertama/terakhir.
- Kotlin `AutomixAnalysisBridge` meneruskan field opsional (getOrNull), jadi
  library native lama tetap fail-open.
- `AutomixSegmentFeatures` + `AutomixTrackFeatures` menyimpan edge RMS/LUFS/onset.
  Cache schema **v21**; v20 sengaja cache miss karena `introRmsDb`/`outroRmsDb`
  berubah semantik dari median window ke median edge.
- `automixMergeSegments`: `introRmsDb`/`outroRmsDb` = edge RMS (fallback ke
  `rmsDb` untuk segmen lama/tanpa slot edge). `introEnergy`/`outroEnergy` =
  energi edge dinormalisasi terhadap peak window; sehingga planner native dan
  early-handover memakai material seam, bukan median 120 s.
- `_automixEdgeStructure`: memakai edge dB relatif terhadap `segment.rmsDb`
  (bukan ambang absolut); label low/buildup/breakdown/stable-high menjadi
  relatif. Fallback quarter-profile dipertahankan untuk segmen tanpa edge.
- `automixTransitionCue`: level trim memprioritaskan pasangan edge LUFS, lalu
  edge RMS, lalu integrated LUFS/whole-track RMS. Busy detection memakai edge
  onset (fallback onsetRate). Atenuasi mid saat vocal clash kontinu:
  `1 - 0.22 * clamp01(min((like-0.55)/0.20, (conf-0.45)/0.20))`.
- `outroSlope`/`introSlope` tetap dari quarter profile; belum ada tempo arc
  atau beat tracking baru (itu fase berikutnya).

## Verifikasi sesi

- `cd native_audio_runtime && dart test -j 1` → 65 lulus; tes baru
  `test_analyzer_edge_features` memverifikasi tail 20 dB lebih pelan terpisah.
- `flutter test test/services/automix_service/automix_engine_test.dart` → 113 lulus
  (termasuk merge edge, edge-LUFS trim, vocal kontinu).
- `flutter test .../automix_cache_test.dart` → 6 lulus (fixture v21 + edge fields).
- `dart run tools/automix_bench.dart --check` → 12 kasus lulus.
- Kotlin compile/unit test, ffmpeg regression, dan capture audio perangkat tidak
  dijalankan di sandbox ini.

## Risiko / lanjutan

- Ambang edge relatif (-16/-6/-12 dB) dan batas 15 s belum dikalibrasi pada
  musik nyata; harness siap menerima WAV berlabel.
- Edge onset pada noise broadband bisa tinggi secara arbitrer; belum dipakai
  untuk menolak track, hanya busy detection.
- Belum ada LUFS channel weighting stereo (analyzer mono) dan belum ada
  post-mix true-peak capture.
