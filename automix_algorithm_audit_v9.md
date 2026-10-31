# AutoMix — Audit Algoritma Menyeluruh (v9)

| Field | Nilai |
| --- | --- |
| Tanggal audit | 31 Oktober 2026 |
| Versi app | 1.5.62 (`pubspec.yaml`) |
| Commit basis | `38fdf31` |
| Target perangkat | Xiaomi Mi 9T / Redmi K20 (arm64-v8a, Android 11 / MIUI 12) |
| Cakupan | Seluruh pipeline AutoMix: analisis Dart/MethodChannel, Kotlin/Media3, JNI, C/NEON, planner, cue, eksekusi crossfade, cache, konkurensi |
| Status | Laporan saja. **Tidak ada perubahan kode, refactor, commit, atau PR.** Menunggu persetujuan sebelum implementasi. |
| Audit sebelumnya | `automix_implementation_audit_v8.md` (2026-10-28) + pembaruan real-audio 2026-10-30 |

Dokumen ini menjawab permintaan audit penuh: peta arsitektur, inventaris algoritma dan evaluasinya, temuan berprioritas dengan 8 elemen analisis (lokasi, algoritma saat ini, masalah, root cause, alternatif, perbandingan, trade-off, prioritas), pemisahan **terbukti vs hipotesis**, perbandingan pendekatan, rencana bertahap, serta strategi benchmark/regression.

---

## 0. Cara membaca laporan ini

- **Terbukti (T)** = ditemukan langsung dari kode: kontradiksi semantik, dua pemilik sinyal dengan skala berbeda, gate yang saling bertentangan, jalur mati, atau batas numerik yang tidak konsisten. Tidak butuh perangkat untuk memverifikasi keberadaannya.
- **Terbukti-sebagian (T-S)** = mekanismenya ada dan berjalan, tetapi semantiknya tidak sesuai dengan yang diasumsikan konsumennya.
- **Hipotesis (H)** = dampak audible/performa/kualitas yang **harus** diukur dengan audio nyata atau profiling. Semua hipotesis punya metode uji yang disarankan di §6.
- Prioritas **HIGH / MEDIUM / LOW** menilai dampak pada kualitas mixing dan risiko regresi, bukan besarnya usaha.
- Referensi baris memakai format `file:baris` dari commit di atas; nomor bisa bergeser beberapa baris setelah perubahan berikutnya, jadi setiap temuan juga menyebut nama fungsi.

---

## 1. Ringkasan eksekutif

Pipeline AutoMix saat ini jauh lebih matang daripada sistem rekomendasi lagu biasa: ada analisis offline multi-window (head/tail/middle), estimasi tempo berbasis hipotesis metrikal, grid beat/downbeat, metre 2/3/4/6, cue drop/breakdown, section boundary, chord progression dengan Viterbi akar, cache beridentitas file, planner global dengan local-search, beat-grid scheduling saat fade, bass swap terkuantitasi beat, EQ tiga band per-deck di native C/NEON, true-peak limiter per-deck, phase lock berbasis JNI, live beat tracker dengan seqlock, dan tempo-follow live. Ini bukan prototipe.

Namun audit penuh menemukan tiga kelas masalah struktural yang membatasi kualitas menuju standar DJ profesional:

1. **Semantik fitur seam tidak sesuai dengan pemakaiannya.** Fitur "intro/outro energy", "intro/outro RMS", dan "section region" dihitung dari **median seluruh window 120 detik**, lalu dipakai untuk memutuskan fade 3–12 detik pada seam akhir/awal lagu (durasi fade, strategi, level trim, EQ, early handover). Lagu dengan chorus keras lalu outro sunyi terbaca "outro padat" (AM9-H01/H05).
2. **Beberapa sinyal dimiliki dua algoritma dengan skala berbeda.** Artist cooldown sudah "dipindahkan" agar hanya punya satu pemilik, tetapi optimizer lokal memakainya 0,05× sementara greedy 1,0× dan `path_cost` mengabaikannya — jadi polish bisa mengembalikan pengulangan artis yang baru saja dihindari (AM9-H03). Rangkaian gate tempo juga tidak konsisten antar layer (60–200 vs 50–220 vs 50–250, AM9-M18).
3. **Cache dan pemrosesan analisis tidak skalabel.** Hasil analisis (termasuk chord progression ratusan baris) disimpan sebagai satu string JSON per lagu di SharedPreferences, lalu seluruh window rencana (hingga 250 lagu) di-decode di isolate UI saat replan; tidak ada pruning, dan migrasi versi menulis ulang semuanya (AM9-H02/M16). Library sweep 40 lagu per sesi bisa menjadi puluhan MB XML dan puluhan MB alokasi sementara.

Yang sudah kuat dan **tidak** perlu diganti secara fundamental: arsitektur dual-deck + equal-power fader + per-deck limiter, bass swap berbasis posisi source, confidence-gated fallback (fail-open), live tracker dengan seqlock bebas lock di audio thread, dan kontrak sidecar native yang ketat. Rekomendasi utama bukan "tambah ML", melainkan **memperbaiki semantik fitur seam, menyeragamkan kepemilikan sinyal, dan memberi dataset/metrik** agar perubahan algoritma bisa divalidasi.

**Lima temuan prioritas tertinggi:**

| ID | Temuan | Prioritas |
| --- | --- | --- |
| AM9-H01 | Fitur seam (intro/outro energy, RMS) adalah median window 120 s, bukan profil 8–16 s terakhir/pertama | HIGH |
| AM9-H02 | Cache analisis di SharedPreferences + decode JSON 250 lagu di isolate UI | HIGH |
| AM9-H03 | Artist cooldown 1,0× di greedy vs 0,05× di polish; `path_cost` mengabaikannya | HIGH |
| AM9-H04 | Drop cue hanya dari window head dan hanya 8–90 s → early handover diam-diam tidak tersedia untuk lagu ber-intro panjang | HIGH |
| AM9-H05 | Label struktur memakai ambang dB absolut → hampir semua master modern = STABLE_HIGH; term structure-seam jadi nyaris konstan | HIGH |

---

## 2. Metodologi, bukti, dan verifikasi yang dijalankan

### 2.1 Yang dibaca (bukan hanya nama fungsi)

| Layer | Berkas utama |
| --- | --- |
| Dart pipeline | `lib/services/automix_service/service.dart` (2525 baris), `engine.dart` (2731), `models.dart` (875), `plan_signature.dart` (71), `lib/services/automix_service.dart` |
| Kotlin analisis | `automix/AutomixAnalysisBridge.kt` (594), `AutomixPcmDownsampler.kt` (200) |
| Kotlin keputusan | `AutomixTransitionPolicy.kt` (292), `AutomixGridMerge.kt` (175), `AutomixBassSwap.kt` (103), `AutomixGainEnvelope.kt` (45), `AutomixTempoFollow.kt` (109), `AutomixPhaseLock.kt` (138), `AutomixNative.kt` |
| Kotlin DSP/eksekusi | `effects/AutomixToneManager.kt` (436), `effects/NativeDspAudioProcessor.kt`, `crossfade/CrossfadeController.kt` (1235), `Media3PlaybackService.kt` (2762, bagian target/seek/nudge) |
| Native C | `automix_analyzer.c` (2629), `automix_planner.c` (1105), `automix_live_tracker.c` (1018), `automix_phase_lock.c` (103), `automix_tone_processor.c` (449), header ABI `automix_native.h` |
| JNI | `android/app/src/main/cpp/replaygain/automix_jni.cpp` (108) |
| SIMD | `automix_neon.S`, `automix_tone_neon.S` |
| ABI Dart | `native_audio_runtime/lib/src/automix_native_io.dart`, `automix_native_types.dart` |
| Docs | `docs/automix-production-wiring.md`, `.agents/memory/automix-automatic-controls.md`, changelog v1.5.55–1.5.62 |

### 2.2 Yang dijalankan

| Perintah | Hasil |
| --- | --- |
| `flutter test test/services/automix_service` | **137 tes lulus** |
| `cd native_audio_runtime && dart test -j 1` | **65 tes lulus** |
| `cd native_audio_runtime && dart test` (paralel default) | **64 gagal** — berkas yang diuji sendiri (automix + satu suite runtime) lulus. Penyebab: tes berbagi state global native (stream slot, pipeline, tone) dalam satu proses; suite tidak parallel-safe. Lihat AM9-M17. |
| `tools/automix_ffmpeg_regression.sh` | Tidak dijalankan (butuh `ffmpeg`, `ffprobe`, Java; di luar anggaran audit). |
| `testDebugUnitTest` (Kotlin) | Tidak dijalankan pada sesi ini. |
| APK / perangkat / capture PCM | Tidak dijalankan — sesuai instruksi repo, build APK hanya di CI. |

### 2.3 Batasan pembuktian

- Tidak ada **capture PCM perangkat** dan tidak ada **dataset audio berlabel** di repo. Semua klaim akurasi nyata (BPM, beat, downbeat, key, seam) berstatus hipotesis kecuali disebut sebagai hasil pengukuran v8 sebelumnya.
- Angka FLOP/CPU di laporan ini adalah **estimasi aritmetika** dari loop dan ukuran window, bukan hasil profiling.
- Pengukuran real-audio v8 (ffmpeg, 3 lagu) dikutip sebagai bukti sebelumnya: ODF pita ketukan menghasilkan 101/117/142 BPM vs pembanding aubio 109,5/119,4/140,7 (changelog v1.5.61). Itu berarti 2 dari 3 lagu masih **di luar toleransi 4%** pada pengukuran terakhir yang terdokumentasi.

---

## 3. Peta arsitektur pipeline AutoMix

### 3.1 Alur end-to-end

```
[Playback]  AudioService.playbackState (ValueNotifier)
     │
     ▼
AutomixService._checkPlaybackStateForAutoMix                service.dart:261
     │  (listener 200 ms tick + queue-change identity)
     ▼
_autoAnalyzeUpcomingTracks                                  service.dart:852
     │  window: playback tail + plan window (max 4) + current (terakhir)
     ▼
analyzeOne → _analyzeOneUncached                            service.dart:2079
     │  dedup in-flight per (songId, path, identity)
     ▼
MethodChannel 'musicplayer/automix' → analyzeAll            AutomixAnalysisBridge.kt:160
     │  SATU sesi decode MediaExtractor/MediaCodec (PCM16)
     │  ring buffer untuk tail nyata; head/middle dianalisis saat buffer penuh
     ▼
AutomixPcmDownsampler                                       AutomixPcmDownsampler.kt
     │  22050 Hz (factor = round(src/22050)), mono, 2-pole LP fc=0.45·fs_out
     │  stereo: mid, fallback kanal lebih kuat bila |mid| < 25% (per-sample)
     ▼
nativeAnalyzeCentered + nativeAnalyzeChords                 automix_jni.cpp
     ▼
nar_automix_analyze_centered  (35 nilai)                    automix_analyzer.c:1613
nar_automix_analyze_chords    (2 s window, hop 1 s)         automix_analyzer.c:2289
     │  STFT 2048/Hann/hop 512, ODF full + band, HPCP, RMS, centroid, onset
     │  tempo (autokorelasi + hipotesis metrikal + phase coherence + konsensus kuartal)
     │  beat phase, phrase grid (metre 2/3/4/6), section boundary, drop/breakdown,
     │  structure region, vocal proxy, chord progression (Viterbi akar)
     ▼
Kotlin memetakan 35 slot → map MethodChannel                AutomixAnalysisBridge.kt:418
     ▼
automixSegmentFeaturesFromAnalysisMap (validasi ketat)      models.dart:250+
     ▼
automixMergeSegments                                         engine.dart:384
     │  tempo vote (fold oktaf) · key vote · energi duration-weighted
     │  head/tail grid · intro/outro slope · metre · section cue · chord merge
     ▼
SharedPreferences (schema v20)                              service.dart:1118
     ▼
_prepareUpcomingTracks                                      service.dart:519
     │  _featuresForPlan (_nearFeatureCount=6 penuh, sisanya cache-only)
     ▼
AutomixEngine.planSet → NativeAutomix.planSet               engine.dart:2665
     ▼
nar_automix_plan_set                                        automix_planner.c:880
     │  greedy + 1-step lookahead (n>24) + polish swap/Or-opt/reversal
     ▼
reorderUpcomingByIds (CAS: tail harus permutasi)             service.dart:700+
     ▼
_buildNativeTargets (maks 2 deck: outgoing + incoming)      service.dart:374
     ▼
automixTransitionCue (per pasangan)                         engine.dart:1093
     │  fade detik/gamma/trim/EQ/pitch/strategy/transitionStartMs
     ▼
Media3PlaybackService: simpan per songId, seek standby ke drop−fade
     ▼
CrossfadeController                                          CrossfadeController.kt:223
     │  prewarm 1500 ms → beat/phrase-aligned start → equal-power 16 ms tick
     │  bass swap, mid/high EQ, tempo nudge, phase lock 64 ms, limiter, pitch shift
     ▼
AutomixToneManager → nar_automix_tone_process (NEON stereo)  AutomixToneManager.kt
```

### 3.2 Kontrak data yang mengikat seluruh pipeline

- **ABI analyzer: 35 `double`** (`NAR_AUTOMIX_ANALYSIS_VALUE_COUNT`). Slot 0–34 mencakup BPM, confidence, alternate, beat offset, key, RMS, centroid, onset rate, durasi, phrase/drop/breakdown cue + confidence, region, vocal, tail BPM + confidence, start/end BPM + confidence, start/end beat phase, stability, 4 RMS kuartal, section cue + confidence, metre.
- **ABI planner: 27 fitur + 2 field key per track** (`NAR_AUTOMIX_FEATURE_COUNT`, `NAR_AUTOMIX_KEY_FIELD_COUNT`), plus array `song_ids` dan `artist_groups`.
- **Live tracker: 7 nilai** (BPM, phase elapsed, confidence, downbeat elapsed, downbeat confidence, activity trend, metre) dipublikasikan lewat seqlock per slot (2 slot).
- **Target MethodChannel:** hanya 2 deck (outgoing + incoming) untuk menghindari tabrakan ID pada map Kotlin.
- **Cache:** `automix_<songId>` → `{version: 20, ident: <path_size_mtime>, data: {...}}`.

### 3.3 Titik kontrol konkurensi

| Mekanisme | Lokasi | Catatan |
| --- | --- | --- |
| `_autoMixCheckRunning` + `_replanRequested` | service.dart:220-228 | Satu pass pemeriksaan; perubahan antrean selama pass menandai recheck |
| `_autoMixPreparing` | service.dart:519 | Satu perencana; permintaan berikutnya menunggu |
| `_autoAnalyzeRunning` + `_analysisFuture` | service.dart:852, 1780 | Satu decode serial seluruh aplikasi |
| `_inFlight` per flight-key | service.dart:2079 | Dedup analysis lagu yang sama |
| `_automixGeneration` | service.dart:158 | Membatalkan hasil pass lama setelah toggle/queue change |
| Seqlock + `atomic_flag` | automix_live_tracker.c:86-110 | Publish state bebas lock dari audio thread (try-lock, skip bila sibuk) |
| Atomic target gain per slot | automix_tone_processor.c:51-57 | Kontrol lintas-thread, audio thread tidak mengunci |
| CAS reorder antrean | service.dart:700+ | Reorder ditolak bila tail berubah |

---

## 4. Inventaris algoritma dan evaluasinya

### 4.1 Analisis audio & feature extraction

| Aspek | Implementasi saat ini | Penilaian |
| --- | --- | --- |
| Transformasi | STFT 2048 Hann, hop 512, radix-2 float, twiddle/bit-reverse precomputed (`automix_analyzer.c:115`), pada 22,05–24 kHz | Tepat untuk analisis offline. FFT kompleks meski input riil → ~2× biaya yang tidak perlu; kandidat rFFT |
| ODF | Log-flux positif; ODF full-band untuk onset rate, ODF pita (low 30–150, mid ≤1,5 k bobot 0,55, high ≤8 k bobot 0,15) untuk beat/phrase | Desain dua ODF sudah benar; band weighting mengatasi hi-hat vs kick |
| Timestamp | `(FFT+HOP)/2` samples untuk ODF turunan flux; RMS tetap frame-start | Terdokumentasi dan diuji; residual < 1 hop |
| Chroma/HPCP | Puncak spektral + parabolic refinement, 2 harmonik, toleransi 0,6 semitone | **Hanya 2 harmonik = oktaf (pitch class sama)**, jadi tidak menambah informasi harmonik; harmonik ke-3 (kuint) dan ke-4 yang biasanya memperkuat akar tidak dipakai (AM9-M03) |
| Energi | Median RMS frame aktif, profil 4 kuartal, slope kuartal | Median kuartal dipakai untuk slope; **tetap berbasis window 120 s** (AM9-H01) |
| Spectral centroid | Median frame aktif | Dipakai untuk brightness low-pass filter; wajar |
| Vocal | Proxy: rasio pita 300–3500, stabilitas centroid, CPP (cepstrum FFT tambahan), richness, center-channel ratio | Jujur didokumentasikan sebagai proxy; plafon keyakinan 0,65 (mono) / 0,75 (stereo) |
| Chord | Template 12 akar × 12 kualitas, 2 s window hop 1 s, Viterbi hanya untuk akar (circle of fifths), hangover 1,5 s | Kualitas dipilih greedy per akar; penalti transisi 0,004–0,012 sangat kecil dibanding emission (AM9-M09) |
| Section boundary | Novelty chroma blok 2 s, de-trend terhadap median lokal ±16 s, gate z≥3 & separation≥0,20 | Pendekatan change-point yang baik; hanya satu kandidat terkuat per window |
| Struktur | Drop/breakdown dari RMS before/after 0,75 s/0,5 s + flux; region enum | Region memakai ambang dB absolut (AM9-H05); drop/breakdown dipakai sebagai cue |
| Metre | Hipotesis 4, 3, 6, 2; accent margin + prior 4/4; corroboration low-band di live | Baik; gate 2-ketukan 0,20 mencegah 4/4 salah jadi 2 |

### 4.2 Tempo, beat, downbeat, phrase

| Tahap | Algoritma | Keterbatasan utama |
| --- | --- | --- |
| Tempo kandidat | Autokorelasi bias-corrected + comb (1, ½, ¼ harm) pada `beat_odf`; fallback `phase_odf` bila confidence <0,20 | Rentang 60–200 BPM; lag maksimum = count/2 → window pendek kehilangan tempo lambat |
| Arbitrase metrikal | 40 kandidat lag → `evaluate_metrical_candidate`: comb 0,10 + coverage 0,45 + fill 0,25 + contrast 0,08 + phase coherence 0,12, × prior Gaussian lemah | Coverage/fill memakai ambang relatif puncak (0,45·max) dan toleransi 0,12·period; hasil masih heuristik, bukan probabilistic (AM9-M08) |
| Refinement | Parabolic lag + phase-coherence search ±1 frame | Menghilangkan kuantisasi sub-frame; baik |
| Konsensus kuartal | 3+ kuartal setuju dalam 4% → median menggantikan whole-window | Kuartal yang tidak setuju **tetap dirata-ratakan** di `automixMergeSegments` (AM9-M02) |
| Beat phase | Histogram fasa modulo period fraksional, smoothing 3-bin, parabolic refinement, offset timestamp | Diuji; stabil pada kick/hat |
| Phrase | Hipotesis 16/12/24/8 beat per metre, bukti power + novelty, gate 0,35 confidence, tolak bar-period novelty | Fase global satu window; tidak ada tempo map/beat tracking DP (AM9-M04) |
| Live beat | Autokorelasi ternormalisasi pada envelope 100 Hz, 6 s history, 7 hipotesis level, margin metrikal, bar scan 2/3/4/6 dengan corroboration low-band + konsistensi dua halfwindow | Heuristik tetapi confidence-gated; berjalan di audio thread (AM9-M17 terkait WCET); hanya aktif saat transisi |
| Downbeat offline | Phrase grid + snappable cue | Snapping cue memakai 16 beat tetap, bukan `metre×4` (AM9-M01) |

### 4.3 Harmonic & key

- Key: profil Krumhansl-Schmuckler mayor/minor, pencarian tuning ±50 sen (5 sen/step), korelasi Pearson, gate entropy ≤0,95 & ≥3 kelas kaya, confidence = absolut × margin × flatness × faktor relative-major/minor.
- Penilaian: kalibrasi margin & gate entropy adalah perbaikan besar dibanding versi lama. Keterbatasan: chroma **global per window 120 s** (bukan per seksi), tanpa bobot bass, dan harmonik HPCP hanya oktaf.
- Kompatibilitas: roda Camelot dengan biaya 0 / 0,15 (relatif) / 0,2 / 0,3 / 0,45 / 0,6 / 1,0; pitch shift keluar-masuk hanya untuk jarak folded 5 pada mode sama dengan key confidence ≥0,70.
- Chord: biaya progresi tail→head (`automixChordProgressionCost`) memakai jarak kelas akar + penalti kualitas 0,08, dikembalikan ke netral oleh confidence.

### 4.4 Energi & progresi

- Energi per lagu = rescale persentil 10–90 dari campuran 0,5·RMS + 0,25·centroid + 0,25·onset (fallback LUFS ReplayGain 0,75 + onset 0,25).
- Target per profil: `dj` naik 0,25→0,75; `energy` tent puncak 0,55; `harmonic` datar 0,60; arc adaptif memproyeksikan target ke p20–p80 set (blend 50/50).
- Biaya transisi energi = 0,22·|Δ| + 0,40·|E_b − target| + 0,18·seam + 0,10·structure + momentum (≤0,10).
- Keterbatasan: `seam` memakai `outroEnergy`/`introEnergy` window (AM9-H01); tidak ada loudness jangka pendek, tidak ada LRA/crest, tidak ada tempo arc (AM9-M02).

### 4.5 Track matching & ranking

- Pool kandidat: ±12 slot pada urutan tempo + anchor exit/½/2×/alternate + kandidat seam cocok (biaya ≤0,25) + kuota 2 lagu tanpa BPM + kandidat key (profil harmonic) / level (profil energy) + lantai 8 kandidat terdekat.
- Pemilihan: greedy biaya terendah + lookahead 1 langkah (top-3, γ=0,35) untuk set >24; polish swap (maks 6000 eval, ≤6 langkah), Or-opt insertion (3000), reversal (1800) untuk ≥12 lagu, ≤8 pass.
- Penilaian: arsitektur dua tahap (greedy+polish) itu wajar, tetapi bukan optimasi global; tidak ada beam search/DP, dan biaya polish tidak memasukkan artist cooldown dengan skala yang sama (AM9-H03).

### 4.6 Transition planning & eksekusi

- Cue: fade = `crossfadeBeats` (default 16) × 60/BPM exit, diskalakan 0,75× (outro padat) / 1,25× (outro sunyi) / 1,15× (intro sunyi), kuantisasi setengah beat, cap 1,5–12 s; strategi crossfade / structureAligned / shortHandover / longBlend / quickHandover; gamma 0,6–1,6; trim level ≤1.
- Early handover: syarat durasi ≥120 s, drop masuk 8–90 s conf ≥0,55, kedua grid beat conf ≥0,35 dan tempo match; lead 35–60 s dari breakdown/section cue terdekat bila ada,否则 formula density; `transitionLeadMs` dikirim agar native menghitung ulang terhadap durasi nyata.
- Eksekusi: prewarm 1500 ms, start di-snap ke grid downbeat `metre×4 / ×2 / ×1` dalam ±4 beat, fade equal-power cos/sin dengan gamma, bass swap pada beat pertama ≥35% fade (lebar ≤1 beat, ≤35% fade), mid/high attenuation berbentuk `sin(πt)`, tail filter high -0…-12 dB, phase lock 64 ms (beat atau phrase bila metre sama), tempo follow live ±2%, true-peak limit 0,95 per-deck, pitch shift keluar ≤1 semitone.
- Keterbatasan besar: **limiter post-mix bersama tidak ada** (dua AudioTrack di-sum AudioFlinger) — sudah didokumentasikan sebagai deferred, bukan temuan baru.

### 4.7 Native/DSP/NEON/JNI

| Komponen | Implementasi | Catatan |
| --- | --- | --- |
| NEON window+RMS | `nar_automix_window_rms_neon` (automix_neon.S) | Hot loop per frame; benar |
| NEON tone stereo | `nar_automix_tone_process_stereo_neon` | 3 band komplementer (LP150, LP1200−LP150, x−LP1200) + smoothing 20 ms + clamp ±1; sum band = input → rekonstruksi unity saat gain 1 |
| Crossfade per-sample native | `nar_automix_tone_set_crossfade_gains` | **Tidak dipakai produksi**: `nativeFadeAvailable = false` (CrossfadeController.kt:560) |
| True-peak | 4× Lagrange (koefisien 3 titik), attack instan, release ~50 ms, disable berjenjang | Tidak ada lookahead; overshoot antar-sampel terbatas |
| JNI analyzer | Salin array, 35 double, `ReleaseFloatArrayElements(..., JNI_ABORT)` | Aman; alokasi `calloc` untuk chord dibatasi 4096 segmen |
| JNI phase lock | Dua entri (beat, phrase) dengan validasi input | Return NAN → Kotlin mematikan koreksi saja (fail-open) |
| Live tracker | Dipanggil dari `native_dsp_jni.c` sebelum DSP bila enabled; publish seqlock | Tidak ada alokasi di audio thread; WCET tidak diuji |

---

## 5. Temuan terbukti

### 5.1 HIGH

---

#### AM9-H01 — Fitur seam adalah median window 120 detik, bukan profil 8–16 detik terakhir/pertama

1. **Lokasi**
   - `lib/services/automix_service/engine.dart:536-580` (`automixMergeSegments`, blok `segmentEnergy`, `introEnergy`, `outroEnergy`)
   - `engine.dart:816-817` (`introRmsDb`, `outroRmsDb`)
   - `native_audio_runtime/src/automix_analyzer.c:1975-2005` (output 7 = median RMS frame aktif; output 24–27 = median RMS per kuartal)
   - Konsumen: `engine.dart:1093+` (`automixTransitionCue`: `denseTail`, `sparseTail`, `sparseIntro`, `longBlend`, `quickHandover`, `automixEarlyHandoverLeadSeconds`, trim level) dan `automix_planner.c:308+` (`NAR_AUTOMIX_INTRO_ENERGY`, `NAR_AUTOMIX_OUTRO_ENERGY`, `seam`, `momentum`).
2. **Algoritma saat ini** — Analisis membagi file menjadi window 120 s (head/tail/middle). Untuk setiap window dihitung median RMS seluruh window. `automixMergeSegments` menormalkan RMS window pertama/terakhir terhadap puncak antar-window dan menyimpannya sebagai `introEnergy`/`outroEnergy`; RMS window yang sama juga menjadi `introRmsDb`/`outroRmsDb`.
3. **Masalah** — Fade AutoMix hanya 1,5–12 detik pada seam akhir/awal. Data yang dipakai untuk memutuskan sifat seam adalah **rata-rata 60–120 detik**, bukan 8–16 detik yang benar-benar tumpang tindih. Contoh: lagu dengan chorus padat 110 detik lalu outro ambient 10 detik → `outroEnergy` ≈ 0,9 (padat) sehingga cue memilih quickHandover 3 detik, tanpa trim, dan bass swap agresif, padahal seam sebenarnya sunyi. Kebalikannya: tail window mayoritas sunyi dengan 8 detik terakhir penuh → terbaca sparse → longBlend ke seam yang padat.
4. **Root cause (bukti)** — Native sudah menyediakan profil kuartal (`output[24..27]`), tetapi merge hanya memakainya untuk `introSlope`/`outroSlope` (`engine.dart:637-650`) dan `_automixEdgeStructure` (`engine.dart:330-372`). `outroEnergy`/`outroRmsDb` tetap `segmentEnergy.last` / `lastSegment.rmsDb`, yaitu statistik **seluruh window**. Tidak ada fitur edge-RMS di ABI maupun model.
5. **Rekomendasi** — Tambahkan fitur seam eksplisit: `introEdgeRmsDb` dan `outroEdgeRmsDb` (10–15 detik pertama/terakhir, atau gabungan kuartal 3–4 untuk tail dan 1–2 untuk head) plus `edgeOnsetRate` dan `edgeLowBandShare`. Pakai untuk strategi fade, trim level, EQ, bass swap, dan early handover lead. Pertahankan `introEnergy/outroEnergy` untuk level set/track.
6. **Perbandingan** — Biaya tambahan nol (frame RMS sudah ada di array yang sama; cukup median slice akhir). Akurasi keputusan seam meningkat besar pada lagu dinamis; pada lagu datar hasil tidak berubah. Alternatif "hitung ulang RMS di Dart dari PCM" jauh lebih mahal dan tidak perlu.
7. **Trade-off/risiko** — Menambah slot ABI (append, bukan mengubah indeks) + bump schema cache → analisis ulang sekali. Risiko: ambang strategi (`0,70`/`0,35`) perlu dikalibrasi ulang terhadap fitur baru; lakukan di belakang flag/gate confidence agar tidak regresi pada lagu yang analisisnya parsial.
8. **Prioritas: HIGH.**

---

#### AM9-H02 — Cache analisis di SharedPreferences dan decode JSON seluruh window rencana di isolate UI

1. **Lokasi** — `service.dart:1118-1140` (`_analysisSchemaVersion = 20`, `_cacheKey`), `service.dart:2126-2145` (`prefs.setString(jsonEncode(...))`), `service.dart:1401-1416` (`_featuresForPlan`), `service.dart:1418-1470` (`_cachedOrNeutral`), `models.dart:570-625` (`toMap`, termasuk `'chords'`).
2. **Algoritma saat ini** — Satu entri SharedPreferences per lagu berisi JSON: seluruh fitur track + **chord progression** (hingga ~600 baris untuk file 10 menit). Rencana seluruh sisa antrean (hingga 250 lagu) membaca dan `jsonDecode` setiap entri; 6 lagu terdekat memakai jalur penuh (`featuresFor`), sisanya `_cachedOrNeutral`.
3. **Masalah** —
   - **Ukuran**: chord event JSON ≈ 80–120 byte; 300–600 event per lagu → 25–70 KB per lagu; 1000 lagu → kemungkinan 25–70 MB XML. SharedPreferences memuat seluruh file ke memori dan **menulis ulang seluruh file pada setiap commit**; library sweep menulis satu entri setiap ~350 ms → I/O kuadratik selama sweep.
   - **Jank**: `_cachedOrNeutral` melakukan `jsonDecode` di isolate utama. Rencana 250 lagu = decoding puluhan MB di UI isolate dalam satu pass `_prepareUpcomingTracks`, berulang setiap replan (setiap 3 detik saat analisis masih mengisi).
   - **Duplikasi metadata**: `title`/`artist` disimpan di cache padahal selalu ditimpa `_withSongMetadata`.
4. **Root cause (bukti)** — Keputusan lama "cache sederhana tanpa dependensi DB" tidak diperbarui ketika chord progression (v19/v20) menambah payload besar dan ketika `_planHorizonCap` naik ke 250. Tidak ada pruning (tidak ada `prefs.remove` selain restore crossfade) dan tidak ada isolasi kerja CPU.
5. **Rekomendasi** — (a) Pindahkan cache ke penyimpanan baris/kolom: SQLite (mis. `sqlite3`/`drift`) atau satu file biner per lagu (`File` + buffer, bukan `jsonEncode`); simpan chord sebagai array numerik (`Float32List`/CSV), bukan objek JSON. (b) Jalankan decode/serialisasi di `Isolate.run`/`compute`. (c) Prune entri lagu yang hilang dan batasi histori. (d) Jangan sertakan `title`/`artist` di cache.
6. **Perbandingan** — SQLite: query per ID O(1) dengan index, tidak menulis ulang seluruh library, mendukung pruning dan migrasi versi per baris. File biner: tanpa dependensi baru, tapi butuh manajemen file sendiri. Isolate: menghilangkan jank tanpa mengubah format. Estimasi perbaikan: waktu buka rencana dari ratusan ms (hipotesis) menjadi puluhan ms; memori puncak turun karena tidak ada string JSON per lagu.
7. **Trade-off/risiko** — Menambah dependensi (jika SQLite) dan pekerjaan migrasi cache sekali; `Isolate` untuk FFI-free JSON aman (tanpa handle native). Risiko rendah, dampak luas; lakukan bersamaan dengan bump schema agar tidak ada dua migrasi.
8. **Prioritas: HIGH.**

---

#### AM9-H03 — Artist cooldown punya dua skala: greedy 1,0×, polish 0,05×, dan tidak masuk metrik

1. **Lokasi** — `automix_planner.c:660-700` (`artist_cooldown_cost`), `automix_planner.c:681-760` (`pick_next`: `transition_cost + artist_cooldown_cost`), `automix_planner.c:776-796` (`link_cost`: `... + 0.05 * artist_cooldown_cost`), `automix_planner.c:760-775` (`path_cost`: tanpa cooldown). Mirror Dart: `engine.dart:2173-2196`, `2533-2618`.
2. **Algoritma saat ini** — Greedy menambahkan penalti cooldown penuh (0,03 atau 0,09 × decay jarak) ke biaya transisi. Polish (swap/insert/reversal) menilai setiap link dengan `0.05 ×` penalti yang sama. `path_cost` yang dilaporkan sebagai `averageCost` tidak memasukkan cooldown sama sekali.
3. **Masalah** — Setelah greedily menghindari pengulangan artis, local search dapat mengembalikannya karena hanya melihat 5% dari penalti. Pada set ≥12 lagu, polish selalu berjalan dan bisa membatalkan kebijakan `avoidArtistRepeat` tanpa jejak di metrik. Efeknya: dua lagu artis sama berdekatan meskipun opsi pengguna aktif.
4. **Root cause (bukti)** — Komentar "single owner artist spread" di `kProfileWeights` (planner.c:43-47) menyatakan cooldown adalah satu-satunya pemilik sinyal itu, tetapi `link_cost` menambahkan faktor 0,05 untuk menghindari penalti mendominasi polish. Skala 0,05 tidak punya dasar kalibrasi dan tidak ada tes yang membandingkan path sebelum/sesudah polish terhadap pengulangan artis.
5. **Rekomendasi** — Samakan skala: masukkan cooldown ke dalam `transition_cost` (satu fungsi biaya untuk greedy, polish, dan `path_cost`), atau pakai bobot yang sama di `link_cost` dan tambahkan ke `path_cost`/`averageCost`. Tambahkan constraint keras opsional (larangan absolut jarak 1–2 bila `avoidArtistRepeat`).
6. **Perbandingan** — Menyatukan biaya: konsisten, mudah diuji, biaya CPU tidak berubah. Alternatif tabu-search/constraint: lebih kuat tetapi menambah kompleksitas; tidak diperlukan untuk memperbaiki inkonsistensi ini.
7. **Trade-off/risiko** — Perubahan bobot dapat mengubah urutan yang sudah "enak" pada beberapa set; mitigasi dengan tes regresi urutan dan benchmark `averageCost` sebelum/sesudah.
8. **Prioritas: HIGH.**

---

#### AM9-H04 — Drop cue hanya berasal dari window head dan hanya diterima pada 8–90 detik → early handover diam-diam tidak tersedia

1. **Lokasi** — `automix_analyzer.c:2045-2160` (deteksi drop/breakdown satu terkuat per window), `engine.dart:693-705` (`dropCueMs` hanya dari `firstSegment`), `engine.dart:1190-1196` (`hasConfidentIncomingDrop`: `>= 8000 && <= 90000`), `service.dart:437-444` (`_buildNativeTargets` juga membatasi 8–90 s), `Media3PlaybackService.kt:2339-2380` (seek standby `dropCue − fade`).
2. **Algoritma saat ini** — Analyzer mencari satu drop terkuat di dalam window yang dianalisis. Merge hanya mengambil `dropCueMs` dari window **pertama** (head). Konsumen early handover hanya menerimanya bila 8–90 s.
3. **Masalah** — Untuk lagu dengan intro panjang (drop di 100–140 s), atau file panjang yang head window-nya 0–120 s sementara drop sesungguhnya ada di window tengah, `dropCueMs` **tidak pernah terbit**. Seluruh jalur early handover (seek standby ke drop, `transitionLeadMs`, phrase-aligned handover) tidak aktif tanpa peringatan apa pun; sistem jatuh ke crossfade akhir lagu standar. Fitur "DJ-style early handover" jadi hanya berlaku untuk subset lagu pop dengan drop dini.
4. **Root cause (bukti)** — Keputusan desain lama (head window = bagian lagu yang memuat drop pertama) tidak diperbarui ketika analisis menjadi multi-window dan analisis streaming menambahkan window tengah/tail. `automixMergeSegments` memilih `firstSegment.dropCueMs` secara harfiah, dan gate 8–90 s di tiga tempat (Dart cue, native targets, Media3) mengunci batas atas.
5. **Rekomendasi** — (a) Publikasikan **beberapa** cue drop dengan timestamp + confidence per window (mis. 3 teratas per file), atau khususkan pass "first drop in first 3 minutes" dengan window awal 180 s. (b) Naikkan batas atas ke durasi yang masuk akal (mis. ≤150 s) atau jadikan parameter. (c) Tambahkan telemetri/log eksplisit saat early handover tidak tersedia beserta alasannya.
6. **Perbandingan** — Menyimpan top-3 drop menambah sedikit kompleksitas di analyzer (array kandidat) tetapi membuka fitur secara luas; biaya nol tambahan karena loop sudah ada. Alternatif ML onset/drop detector tidak perlu untuk masalah ini.
7. **Trade-off/risiko** — ABI bertambah; perlu definisi "drop" yang konsisten agar tidak memilih drop palsu dari build-up. Gate confidence tetap dipertahankan.
8. **Prioritas: HIGH.**

---

#### AM9-H05 — Label struktur memakai ambang dB absolut → hampir semua master modern menjadi STABLE_HIGH, term structure-seam hampir konstan

1. **Lokasi** — `automix_analyzer.c:2168-2260` (region: `< -45`, `< -30`, `> -20`), `engine.dart:330-372` (`_automixEdgeStructure`: mean kuartal `< -32`, `> -18`, `> -22`), `automix_planner.c:72-99` (`structure_seam_cost`).
2. **Algoritma saat ini** — Region struktural adalah enum {LOW_ACTIVITY, BUILDUP, DROP, BREAKDOWN, STABLE_HIGH} yang ditentukan dari median RMS window dan keberadaan cue drop/breakdown. Planner memberi biaya 0/0,2/0,35/0,5 berdasarkan pasangan region.
3. **Masalah** — RMS median active-frame master modern umumnya −14…−20 dBFS. Window mix penuh hampir selalu memenuhi `rms_median > -20` (native) atau `mean > -18` / `> -22` (Dart), sehingga label default adalah STABLE_HIGH. Akibatnya:
   - Seam DROP→DROP / STABLE_HIGH→STABLE_HIGH selalu kena 0,35–0,5 meskipun secara musikal halus.
   - Seam yang benar-benar "tenang" hanya muncul untuk ekstrem (ambient, silence), bukan untuk outro yang lebih lembut 3–6 dB dari chorus.
   - Term structure kehilangan daya diskriminatifnya: ia menjadi konstanta hampir untuk semua pasangan, sehingga bobot 0,10 hanya menambah bias seragam.
4. **Root cause (bukti)** — Ambang ditetapkan sebagai dBFS absolut tanpa normalisasi per-track (mis. terhadap p70/p90 track) dan tanpa fitur densitas (onset rate lokal, low-band share) yang lebih tahan terhadap loudness mastering. Label dihitung pada window, bukan pada seam.
5. **Rekomendasi** — Normalisasi fitur per track (median keseluruhan atau persentil), lalu klasifikasi berbasis **kontras relatif + densitas**: (a) region low bila edge RMS < p25 track selama ≥4 bar; (b) buildup bila slope > +1 dB/bar dan densitas naik; (c) drop/peak bila densitas tertinggi & low-band kuat; (d) breakdown bila densitas turun tajam. Hitung pada 8–16 bar terakhir/pertama, bukan 120 s. Pertahankan confidence gate.
6. **Perbandingan** — Tanpa ML: perbaikan besar dengan biaya O(frame) dan tanpa ABI baru bila memakai kuartal yang ada + onset rate edge. Dengan model kecil (CNN on log-mel): potensi lebih akurat tetapi menambah dependensi, ukuran model, dan risiko; belum layak sebagai langkah pertama.
7. **Trade-off/risiko** — Ambang relatif lebih sensitif pada lagu dengan dinamika rata (mis. techno loop); mitigasi dengan gate "kontras minimum" dan fallback ke label sebelumnya bila kontras rendah.
8. **Prioritas: HIGH.**

### 5.2 MEDIUM

---

#### AM9-M01 — Snapping cue drop/breakdown memakai 16 beat tetap, sedangkan phrase grid memakai `metre × 4`

1. **Lokasi** — `automix_analyzer.c:2119` dan `2149` (`const double phrase_ms = beat_ms * 16.0`), vs `automix_analyzer.c:1350-1610` (`estimate_phrase_grid`, `phrase_beats = meter * 4` untuk metre 2/3/4/6).
2. **Algoritma saat ini** — Cue drop/breakdown disnap ke grid phrase 16 beat dengan toleransi `min(600 ms, 0,8 beat)`; phrase phase yang diterbitkan untuk lagu yang sama dihitung pada `meter × 4` beat.
3. **Masalah** — Untuk metre 3 (12 beat), 6 (24), atau 2 (8), grid snapping berbeda dari grid phrase yang dipakai phrase lock dan `phraseAlignedStartMs`. Pada 3/4, cue bisa tergeser 4 beat dari boundary musikal yang sebenarnya; pada 6/8 bisa 8 beat. Snap hanya diterima bila selisih ≤600 ms, sehingga kadang tidak terjadi — hasilnya tidak deterministik secara musikal.
4. **Root cause** — Angka 16 di-hard-code sebelum deteksi metre ditambahkan; saat `estimate_phrase_grid` diperluas ke metre 2/3/6, jalur snapping tidak ikut diubah.
5. **Rekomendasi** — Gunakan `phrase_beats = meter * 4` pada kedua jalur snapping (drop dan breakdown), dan teruskan metre ke fungsi snapping. Bila metre tidak yakin, fallback ke 4/4 seperti sekarang.
6. **Perbandingan** — Perubahan 2 baris, tanpa biaya; akurasi cue pada lagu non-4/4 meningkat langsung. Tidak ada alternatif yang lebih sederhana.
7. **Trade-off/risiko** — Perlu tes regresi cue 3/4 dan 6/8; lagu 4/4 tidak berubah. Risiko rendah.
8. **Prioritas: MEDIUM.**

---

#### AM9-M02 — Tidak ada tempo arc; biaya tempo menganggap oktaf (½/2×) gratis dan merge merata-ratakan window yang tidak setuju

1. **Lokasi** — `automix_planner.c:118-158` (`append_variant`, `tempo_cost`), `engine.dart:271-282` (`automixFoldToOctave`), `engine.dart:400-430` (tempo vote), `automix_planner.c:515-630` (`candidate_pool`).
2. **Algoritma saat ini** — Setiap pasangan dibandingkan melalui varian `{bpm, 2bpm, bpm/2, alternate}`; jarak relatif terkecil menentukan biaya. Varian oktaf selalu tersedia sebagai anchor kandidat. Tidak ada target tempo per posisi set.
3. **Masalah** — Set dapat berjalan 128 → 64 → 128 → 64 dengan biaya tempo 0, padahal perubahan pulse 2× adalah keputusan artistik yang biasanya disengaja. Tidak ada hukuman untuk lompatan oktaf, tidak ada kurva tempo (build 120→128), dan tidak ada preferensi genre/range. Selain itu, `automixMergeSegments` merata-ratakan BPM window yang **tidak** setuju (mis. 120, 120, 90 → 110) dengan confidence 0,6, menghasilkan tempo yang bukan milik window mana pun.
4. **Root cause** — Fold oktaf dimaksudkan untuk mengatasi ambiguitas detektor, lalu dipakai juga sebagai kebebasan penuh di cost. Merge memakai weighted mean, bukan median/vote dengan gate.
5. **Rekomendasi** — (a) Tambahkan biaya oktaf eksplisit (mis. 0,08–0,12) kecuali profil `openFormat`; (b) tambahkan tempo target per posisi (mis. interpolasi 118→128 untuk house) dan biaya |log2(BPM/target)|; (c) di merge, pakai median berbobot + tolak rata-rata bila agreement <70%, atau pilih anchor dan turunkan confidence secara tajam.
6. **Perbandingan** — Biaya O(1) per pasangan; peningkatan koherensi set. Alternatif ML untuk “energy/tempo curve” tidak perlu; kurva parametrik sudah cukup.
7. **Trade-off/risiko** — Biaya oktaf dapat menolak transisi 60↔120 yang sah; beri pengecualian untuk rasio 2× pada lagu ber-tempo <100 atau profil tertentu. Perlu kalibrasi pada corpus.
8. **Prioritas: MEDIUM.**

---

#### AM9-M03 — Key diestimasi global per window 120 s, bukan pada seam; HPCP hanya 2 harmonik

1. **Lokasi** — `automix_analyzer.c:294-396` (`estimate_key`), `automix_analyzer.c:407-451` (`hpcp_add_frame`, `HPCP_HARMONICS 2`), `engine.dart:480-520` (key vote).
2. **Algoritma saat ini** — Chroma diakumulasi seluruh window (120 s), dicocokkan dengan profil Krumhansl mayor/minor, tuning search ±50 sen, gate entropy. Key track = vote berbobot confidence antar-window.
3. **Masalah** — (a) Lagu pop sering modulasi atau verse/chorus berbeda mode; key global memberi satu jawaban yang mungkin bukan key pada seam. (b) HPCP 2 harmonik hanya menambahkan oktaf (pitch class sama) sehingga tidak memperkuat akar/kuint seperti HPCP 3–5 harmonik. (c) Tidak ada bobot bass; akar sering ada di bass, tetapi energi mid/high vokal/gitar bisa menenggelamkannya.
4. **Root cause** — Desain awal key berbasis seluruh file; seam-aware key belum ada. `HPCP_HARMONICS` dipilih untuk biaya, tetapi 2 harmonik praktis redundan.
5. **Rekomendasi** — Hitung chroma per 8–16 bar pada edge (30 s terakhir/pertama), lalu key seam = key window edge dengan confidence; gunakan HPCP 4 harmonik dan chroma bass (LP 250 Hz) sebagai fitur terpisah; pertimbangkan profil Temperley atau bobot akar/kuint. Untuk harmoni, gabungkan dengan chord progression yang sudah ada.
6. **Perbandingan** — Biaya tambahan kecil (akumulasi chroma tambahan per frame). Akurasi key seam umumnya lebih relevan untuk mixing daripada key global. ML key detection (mis. CNN chroma) bisa lebih akurat tetapi menambah model; belum perlu sebelum corpus tersedia.
7. **Trade-off/risiko** — Key edge pada intro/outro yang sparse bisa tidak stabil; gate confidence dan fallback ke key global. Perubahan ini memengaruhi pitch shift (saat ini butuh confidence ≥0,70), jadi harus diuji hati-hati.
8. **Prioritas: MEDIUM.**

---

#### AM9-M04 — Tidak ada tempo map/beat tracking; satu periode per window 120 s

1. **Lokasi** — `automix_analyzer.c:1051-1103` (`estimate_tempo`), `automix_analyzer.c:1350-1610` (`estimate_phrase_grid` memakai satu `beat_ms`), `automix_analyzer.c:1104-1206` (`estimate_beat_phase_ms`).
2. **Algoritma saat ini** — Satu BPM dan satu fase per window; kuartal menghasilkan BPM lokal hanya untuk kurva/stability, bukan grid per bar. Fase global dihitung dari histogram seluruh window.
3. **Masalah** — Pada rekaman live, ritardando, atau editing tempo, grid 120 s dapat melenceng >1 beat pada akhir window; phrase grid ikut melenceng. Deteksi downbeat juga mengasumsikan grid tetap. Live tracker hanya aktif saat transisi dan punya histori 6 s, jadi tidak bisa memperbaiki drift jangka panjang.
4. **Root cause** — Tidak ada dynamic programming beat tracker (mis. Ellis 2007) atau tempo map per bar; keputusan desain mengandalkan autocorrelation global + phase coherence.
5. **Rekomendasi** — Implementasikan beat tracking DP pada ODF (cost onset + transition penalty) yang menghasilkan beat times, lalu fit tempo map per 8 bar; turunkan downbeat/phrase dari beat times tersebut. Alternatif ringan: interpolasi BPM kuartal menjadi tempo curve dan hitung fase per kuartal (sudah ada slot kuartal) untuk grid bertahap.
6. **Perbandingan** — DP beat tracking O(N·lag) dengan N≈5.600 frame dan lag≤43 masih murah (<0,5 MFLOP), jauh di bawah FFT. Akurasi pada material live meningkat signifikan; material EDM hampir tidak berubah.
7. **Trade-off/risiko** — Implementasi C lebih kompleks, perlu tes sintetis (click train dengan drift) dan corpus live. Risiko regresi pada lagu ber-tempo tetap rendah bila DP di-gate oleh confidence.
8. **Prioritas: MEDIUM.**

---

#### AM9-M05 — Downsampler stereo: fallback anti-fase berganti per sampel; filter anti-alias 2-pole terlalu landai

1. **Lokasi** — `AutomixPcmDownsampler.kt:100-165` (`channels == 2` branch), `AutomixPcmDownsampler.kt:178-200` (`ButterworthLowPass`).
2. **Algoritma saat ini** — Stereo mono = `(L+R)/2`, tetapi bila `|mid| < 0.25·max(|L|,|R|)` per sampel, dipilih kanal yang lebih kuat. Filter low-pass 2-pole (12 dB/okt) pada `0,45·fs_out` sebelum decimasi; decimasi = boxcar rata-rata `factor` sampel.
3. **Masalah** — Pada materi wide/anti-fase (synth pad, stereo widening), keputusan per sampel dapat membalik tanda dan kanal dari sampel ke sampel, menambahkan distorsi broadband ke sinyal analisis. Filter 12 dB/okt pada 0,45·fs_out hanya meredam ~1–2 dB di Nyquist, sehingga aliasing dari 12–24 kHz masuk ke pita chroma/onset. Keduanya menurunkan kualitas BPM/key/onset pada sebagian materi.
4. **Root cause** — Fallback anti-fase dibuat untuk mencegah near-cancellation, tetapi tanpa smoothing; desain filter dipilih untuk biaya minimum.
5. **Rekomendasi** — Gunakan keputusan mid/side berbasis energi tersmooth ≥20 ms (seperti jalur multichannel), atau mid + side mono terpisah; naikkan filter ke 4th-order Butterworth (24 dB/okt) pada 0,40·fs_out, atau FIR linear-phase 63-tap. Pertimbangkan decimasi polyphase.
6. **Perbandingan** — Biaya tambahan kecil (beberapa operasi per sampel; masih offline). Akurasi analisis pada materi anti-fase meningkat; aliasing turun drastis. Tidak memengaruhi playback real-time.
7. **Trade-off/risiko** — Perlu tes sinyal anti-fase sintetis dan perbandingan BPM/key sebelum/sesudah; perubahan ini mengubah cache, jadi bump schema.
8. **Prioritas: MEDIUM.**

---

#### AM9-M06 — Biaya analisis: STFT kedua untuk chord + 5 window per track, tanpa anggaran/WCET

1. **Lokasi** — `AutomixAnalysisBridge.kt:160-330` (`analyzeAll`, `planWindowStarts`), `automix_analyzer.c:1613+` (STFT utama), `automix_analyzer.c:2289+` (`nar_automix_analyze_chords`, STFT terpisah 1024 hop).
2. **Algoritma saat ini** — Satu sesi decode, tetapi setiap window 120 s menjalankan STFT 2048/hop 512 untuk fitur utama, lalu pass kedua STFT 2048/hop 1024 untuk chord. File 10 menit memakai 5 window (600 s audio) → ±10 pass STFT ekuivalen.
3. **Masalah** — Estimasi aritmetika: ~112 k operasi per FFT kompleks 2048; ~5.600 frame per 120 s → ~630 M operasi untuk pass utama + ~315 M untuk cepstrum (setengah frame) + ~575 M untuk chord = ~1,5 GFLOP per window; 5 window ≈ 7,5 GFLOP per track 10 menit. Di luar biaya autocorrelation. Ini bisa berarti beberapa detik CPU per track dan sweep 40 track menghabiskan menit CPU/baterai. Belum ada pengukuran di Mi 9T.
4. **Root cause** — Chord classifier ditulis sebagai fungsi mandiri yang menghitung ulang STFT/HPCP; analisis per-window tidak berbagi frame HPCP. Tidak ada anggaran waktu atau metrik performa di CI.
5. **Rekomendasi** — (a) Simpan HPCP per frame (12 float × ~5.600 = 270 KB) dari pass utama dan pakai untuk chord 1 s/2 s, hilangkan STFT kedua; (b) gunakan real-FFT (packing) → ~2× lebih cepat; (c) turunkan sample rate analisis ke 16 kHz (cukup untuk chroma ≤5 kHz) atau 11.025 kHz untuk tempo, dengan filter yang sesuai; (d) instrumentasi waktu per tahap dan target p95.
6. **Perbandingan** — (a) menghemat ~35–40% total; (b) ~30–40% dari FFT; (c) ~30% dari semuanya dengan risiko akurasi chroma (perlu uji). Semua lebih murah daripada menambah core/parallelisme.
7. **Trade-off/risiko** — Perubahan sample rate mengubah semua fitur → bump schema dan validasi corpus. Real-FFT mengubah numerik sedikit; toleransi tes perlu disesuaikan.
8. **Prioritas: MEDIUM.**

---

#### AM9-M07 — Replan/reorder berulang saat analisis mengisi cache; lagu jauh masih netral

1. **Lokasi** — `service.dart:519-850` (`_prepareUpcomingTracks`), `service.dart:1401-1416` (`_featuresForPlan`, `_nearFeatureCount = 6`), `service.dart:947-1012` (`_scheduleAnalysisResume`, delay 3 s), `service.dart:595-612` (`_planBasisStale`).
2. **Algoritma saat ini** — Setiap kali 1–2 lagu selesai dianalisis, `_planBasisStale` memaksa rencana ulang seluruh window (hingga 250 lagu). Hanya 6 lagu terdekat yang memakai fitur penuh; sisanya `_cachedOrNeutral` (sering netral). Rencana baru langsung memanggil `reorderUpcomingByIds` pada tail.
3. **Masalah** — Urutan 244 lagu jauh ditentukan oleh fitur netral (BPM 0,35, key 0,5, energi 0,5), lalu di-reorder; ketika analisis menyusul, urutan berubah lagi. Pengguna melihat antrean “melompat” setiap beberapa detik selama fase pemanasan; native menerima banyak reorder yang tidak menghasilkan keputusan musikal bermakna. Beban decode cache JSON juga berulang (lihat AM9-H02).
4. **Root cause** — Keputusan untuk merencanakan seluruh tail dan langsung menerapkannya tidak dibatasi oleh kesiapan analisis; `_planBasisStale` tidak membedakan “fitur baru untuk 4 lagu dekat” dari “seluruh window berubah”.
5. **Rekomendasi** — (a) Rencanakan dan reorder hanya prefix yang sudah teranalisis (mis. 12–20 lagu); tail yang belum siap dipertahankan urutannya. (b) Terapkan reorder dengan histeresis: hanya bila perbaikan `averageCost` melebihi ambang (mis. 5%) atau posisi lagu dekat berubah. (c) Tunda reorder saat fade sedang berlangsung (sudah ada pengaman, tetapi churn tetap terjadi sebelum fade).
6. **Perbandingan** — Mengurangi reorder dan jank tanpa mengubah kualitas 6 lagu terdekat; rencana jauh menjadi lebih stabil. Alternatif: tetap merencanakan semua tetapi jangan terapkan sampai 80% window teranalisis — lebih sederhana, tetapi menunda manfaat.
7. **Trade-off/risiko** — Prefix yang lebih pendek berarti horizon optimasi lebih kecil; dapat diimbangi dengan analisis latar yang lebih agresif saat idle. Perlu tes UX (antrean tidak berubah-ubah).
8. **Prioritas: MEDIUM.**

---

#### AM9-M08 — Confidence tidak terkalibrasi; ambang 0,35/0,55/0,65 adalah angka tangan yang dipakai lintas sinyal

1. **Lokasi** — `automix_analyzer.c:985-1015` (BPM confidence = 0,55·prominence + 0,45·periodicity × margin), `automix_analyzer.c:380-395` (key confidence), `automix_analyzer.c:2100-2140` (drop confidence = score/12), `automix_analyzer.c:2225-2260` (vocal confidence), `automix_planner.c:62-70` (`confidence_blend`), gate di `engine.dart:900-970`, `AutomixTransitionPolicy.kt`, `CrossfadeController.kt:150-160`.
2. **Algoritma saat ini** — Setiap estimator menghasilkan skor 0–1 dengan formula linear ad hoc; konsumen memakai ambang yang sama (0,35 untuk tempo, 0,55 untuk key/harmonic filter, 0,65 untuk struktur) tanpa kalibrasi probabilistik.
3. **Masalah** — Confidence 0,5 dari BPM, key, struktur, dan vocal tidak berarti hal yang sama. Ambang yang dikalibrasi untuk satu estimator bisa terlalu longgar/ketat untuk yang lain. Tidak ada pengukuran ECE/reliability; keputusan “percaya atau tidak” tidak dapat diaudit terhadap data.
4. **Root cause** — Tidak ada corpus berlabel; confidence dirancang sebagai “margin score” agar gate aman, bukan sebagai probabilitas. Nilai ambang tersebar di banyak file tanpa satu tabel kontrak.
5. **Rekomendasi** — Kumpulkan skor + label pada corpus, lalu kalibrasi isotonic/logistic per estimator (BPM, downbeat, key, drop, vocal); simpan tabel kalibrasi kecil di C/Dart. Sementara itu, satukan ambang dalam satu konstanta/dokumen dan tambahkan tes yang memastikan semua layer memakai nilai sama.
6. **Perbandingan** — Kalibrasi tidak mengubah fitur, hanya pemetaan skor→probabilitas; peningkatan utama adalah keputusan gate yang bisa dipertanggungjawabkan dan ECE yang terukur. Alternatif ML end-to-end berlebihan untuk masalah ini.
7. **Trade-off/risiko** — Butuh data berlabel (lihat §10); kalibrasi yang salah dapat menurunkan recall. Lakukan per estimator dan simpan fallback ke formula lama.
8. **Prioritas: MEDIUM.**

---

#### AM9-M09 — Viterbi chord hanya memodelkan akar; penalti transisi terlalu kecil dan kualitas dipilih greedy

1. **Lokasi** — `automix_analyzer.c:2289-2629` (`nar_automix_analyze_chords`), khususnya `root_scores`, `kChordIntervals`, `transition[12][12]` (0,004–0,012), dan loop Viterbi.
2. **Algoritma saat ini** — Untuk setiap segmen 2 s, 12 akar × 12 kualitas dievaluasi dengan `0,82·in_chord + 0,18·share(root)`; kualitas terbaik per akar disimpan. Viterbi kemudian memilih jalur akar dengan penalti jarak circle-of-fifths; kualitas mengikuti akar terpilih.
3. **Masalah** — Penalti transisi (≤0,012) jauh lebih kecil dari perbedaan emission (≈0,3–1,0), sehingga Viterbi praktis tidak mengubah argmax per segmen; transisi akar yang tidak musikal tidak dicegah. Kualitas tidak ikut Viterbi, sehingga pergantian kualitas pada akar yang sama (mis. C→Cm) hanya ditentukan emission. Tidak ada bukti bass/inversi; akor dengan bass berbeda dianggap identik. Template juga tidak memberi penalti untuk nada non-chord yang kuat.
4. **Root cause** — Model dirancang sebagai “root smoother” ringan, bukan model harmonik; penalti dipilih agar tidak menimpa emission, tetapi tidak dikalibrasi terhadap skala emission.
5. **Rekomendasi** — (a) Skalakan penalti transisi terhadap emission (mis. 0,1–0,3) atau gunakan HMM dengan probabilitas; (b) perluas state ke (root, quality) 12×12 atau 24 state diatonis; (c) tambahkan fitur bass chroma dan penalti nada non-chord; (d) gunakan chord hanya sebagai fitur cue (sudah), jangan menambah kompleksitas tanpa corpus.
6. **Perbandingan** — HMM (root, quality) meningkatkan akurasi progresi pada lagu jazz/pop kompleks; biaya masih kecil (12×12×600). Alternatif: tetap template tetapi kalibrasi confidence dan gunakan chord change hanya untuk bar boundary (sudah dipakai).
7. **Trade-off/risiko** — State lebih besar → lebih mudah overfit template; perlu label chord untuk validasi. Karena chord hanya memengaruhi durasi fade (bukan penolakan), risiko audible rendah.
8. **Prioritas: MEDIUM.**

---

#### AM9-M10 — Level match memakai RMS window 120 s, bukan loudness jangka pendek pada seam

1. **Lokasi** — `engine.dart:1270-1315` (trim level: `outroRmsDb` vs `introRmsDb`, fallback LUFS/RMS), `engine.dart:816-817`, `automix_analyzer.c:2003-2040`.
2. **Algoritma saat ini** — Jika kedua fitur ada, `deltaDb = outroRmsDb − introRmsDb` (clamp ±6 dB), lalu trim deck yang lebih keras. `outroRmsDb`/`introRmsDb` adalah median RMS seluruh window 120 s.
3. **Masalah** — Sama seperti AM9-H01, tetapi dampaknya langsung pada gain: track dengan outro sunyi 10 s setelah chorus keras akan dianggap “sama keras” sehingga tidak di-trim; saat overlap, deck outgoing bisa 6–10 dB lebih keras dari incoming. Sebaliknya, intro sunyi 20 s pada track yang chorus-nya keras membuat incoming di-trim berlebihan. Tidak ada pengukuran LUFS jangka pendek (400 ms/3 s) yang relevan untuk overlap.
4. **Root cause** — Tidak ada fitur loudness edge; trim memakai statistik window yang sama dengan energi.
5. **Rekomendasi** — Hitung `edgeShortTermLufs` (EBU R128 momentary/short-term) untuk 10–15 s edge; pakai selisihnya untuk trim, dengan clamp ±6 dB dan gate confidence. Fallback ke RMS edge bila LUFS tidak tersedia.
6. **Perbandingan** — Biaya tambahan kecil (K-weighting filter + gating) di analyzer; hasil trim jauh lebih tepat pada lagu dinamis. Alternatif: ReplayGain track-level (sudah ada) kurang tepat untuk seam.
7. **Trade-off/risiko** — LUFS implementasi harus benar (K-weighting, gate −70 LUFS); kesalahan kalibrasi bisa menyebabkan trim salah. Uji dengan sinyal 1 kHz dan corpus.
8. **Prioritas: MEDIUM.**

---

#### AM9-M11 — Vocal proxy dan EQ vokal memakai aturan tetap, bukan estimasi yang adaptif

1. **Lokasi** — `automix_analyzer.c:2160-2260` (vocal_like/vocal_conf), `engine.dart:1360-1395` (`confidentVocalClash`, mid gain 0,78), `automix_planner.c:430-460` (vocal cost), `automix_tone_processor.c:72-100` (band split).
2. **Algoritma saat ini** — Vocal likelihood = kombinasi rasio pita 300–3500 Hz, stabilitas centroid, CPP, richness, center-channel; gate confidence ≥0,45 dan likelihood ≥0,55. Jika bentrok, kedua deck mendapat mid gain 0,78 tetap. Pemisahan band memakai one-pole 150/1200 Hz.
3. **Masalah** — Proxy ini tidak bisa membedakan vokal dari gitar/synth di pita yang sama; ketika salah deteksi, EQ 0,78 menumpulkan mid kedua deck (suara “boxy”) tanpa manfaat. Sebaliknya, vokal yang tidak terdeteksi dibiarkan bertumpuk. Mid gain tetap tidak mempertimbangkan tingkat tumpang tindih atau jarak key.
4. **Root cause** — Tidak ada source separation; keputusan dibuat biner (clash/tidak) dengan gain tetap. One-pole crossover juga membuat “mid” mencakup sebagian bass dan treble.
5. **Rekomendasi** — (a) Jadikan mid attenuation kontinu terhadap `vocalLikelihood × vocalConfidence` dan durasi tumpang tindih (mis. 1,0→0,85, bukan 0,78 tetap); (b) gunakan Linkwitz-Riley 4th-order untuk band isolation; (c) pertimbangkan sidechain ducking mid deck incoming oleh outgoing (bukan EQ statis); (d) bila kelak ada model source separation ringan, baru gunakan; jangan paksakan ML sekarang.
6. **Perbandingan** — Aturan kontinu lebih jarang merusak materi instrumental; crossover LR4 lebih bersih pada bass swap. Biaya tambahan kecil; risiko utama adalah perubahan karakter suara yang perlu listening test.
7. **Trade-off/risiko** — LR4 menambah delay/kompleksitas dan state filter; ducking membutuhkan link antar-deck yang belum ada. Lakukan bertahap.
8. **Prioritas: MEDIUM.**

---

#### AM9-M12 — Planner greedy + lookahead 1 langkah; pool kandidat heuristik, bukan beam search/optimasi global

1. **Lokasi** — `automix_planner.c:515-630` (`candidate_pool`), `681-760` (`pick_next`), `760-858` (polish), `engine.dart:1912-2660` (reference yang mirror).
2. **Algoritma saat ini** — Greedy memilih biaya terendah dari pool ±12 slot tempo + anchor; lookahead hanya untuk >24 lagu dan top-3; polish swap/insertion/reversal dengan anggaran terbatas. Tidak ada beam search, DP, atau A*/tabu.
3. **Masalah** — Pool dapat melewatkan lagu yang harmonik/energi sempurna tetapi jauh dari window tempo (kecuali profil harmonic/energy menambah kandidat). Lookahead 1 langkah tidak melihat konsekuensi 2–3 langkah; polish lokal tidak bisa keluar dari basin yang buruk. Untuk set besar, kualitas urutan sangat bergantung pada urutan awal.
4. **Root cause** — Keputusan desain untuk biaya deterministik dan cepat; kompleksitas O(n·pool) dianggap cukup. Tidak ada metrik kualitas selain averageCost.
5. **Rekomendasi** — Beam search lebar 8–16 dengan kedalaman 2–3 (biaya masih terkendali untuk n=250), atau DP per bucket (posisi × tempo × key) untuk horizon 30–50 lagu. Tambahkan diversifikasi kandidat (key/energy bucket) dan acceptance criterion berbasis averageCost + artist spread + tempo arc.
6. **Perbandingan** — Beam width 8: ~8× biaya greedy tetapi tetap <10 ms untuk 250 lagu (estimasi), dan biasanya menemukan solusi lebih baik 5–15% averageCost. DP penuh terlalu mahal karena biaya bergantung posisi.
7. **Trade-off/risiko** — Perlu tes determinisme dan waktu; beam search dapat memilih jalur yang lebih halus tetapi kurang “berani”. Simpan fallback ke greedy bila waktu melebihi budget.
8. **Prioritas: MEDIUM.**

---

#### AM9-M13 — Keputusan fade berbasis detik (bukan beat/bar) untuk quick/short handover; fade bisa berakhir di tengah bar

1. **Lokasi** — `engine.dart:1093-1260` (`automixTransitionCue`: `fadeBeats *= 0.75/1.25/1.15`, `fadeSeconds = min(fadeSeconds, 3.0)`), `AutomixTransitionPolicy.kt:193-210` (`fadeSeconds`/`curveGamma`).
2. **Algoritma saat ini** — Fade awal dihitung dalam beat dari BPM exit, lalu dikalikan faktor densitas (0,75–1,25), dikonversi ke detik, dibatasi strategi (short ≤4 s, quick ≤3 s, long ≥6 s), lalu direkuantisasi ke setengah beat dan di-clamp 1,5–12 s.
3. **Masalah** — Cap dalam detik memutus hubungan dengan bar. Pada 120 BPM, quick handover 3 s = 6 beat = 1,5 bar; pada 100 BPM = 5 beat. Start sudah phrase-aligned, tetapi akhir fade (saat outgoing dibisukan) jatuh di tengah bar, sehingga transisi terasa “terpotong” alih-alih selesai di boundary. Hal yang sama berlaku untuk short handover 4 s.
4. **Root cause** — Strategi ditambahkan sebagai cap detik agar aman, sementara kuantisasi beat dilakukan setelahnya; tidak ada aturan “durasi fade = 1/2/4 bar” untuk strategi ini.
5. **Rekomendasi** — Tentukan durasi dalam **beat/bar**: short = 2 atau 4 beat, quick = 1 bar, long = 2 bar; konversi ke detik memakai BPM exit; batasi hanya sebagai pengaman (mis. ≤2 bar). Pertahankan cap absolut 12 s.
6. **Perbandingan** — Secara musikal lebih konsisten; tidak ada biaya tambahan. Alternatif mempertahankan cap detik tetapi memilih beat terdekat ke bar — lebih sederhana, tetapi bisa memperpanjang fade pada BPM rendah.
7. **Trade-off/risiko** — Fade 1 bar pada 60 BPM = 4 s (masih wajar); pada 180 BPM = 1,33 s (di bawah minimum 1,5 s) → perlu clamp minimum. Uji lintas BPM.
8. **Prioritas: MEDIUM.**

---

#### AM9-M14 — Jalur crossfade per-sampel native tidak dipakai produksi (`nativeFadeAvailable = false`)

1. **Lokasi** — `CrossfadeController.kt:560` (`val nativeFadeAvailable = false`), `CrossfadeController.kt:1170-1195` (cabang native vs Kotlin), `Media3PlaybackService.kt:741` (wiring `setAutoMixCrossfadeGains`), `automix_tone_processor.c:190-220` (`nar_automix_tone_set_crossfade_gains`).
2. **Algoritma saat ini** — Fade produksi memakai `AutomixGainEnvelope` Kotlin yang mengatur `player.volume` setiap 16 ms. Jalur native per-sampel (C/NEON, dua deck dalam satu tick) ada, diuji, dan di-wire, tetapi sengaja dimatikan karena dua audio thread dapat tidak sinkron.
3. **Masalah** — Bukan bug audible (Kotlin path benar), tetapi: (a) kode native crossfade menjadi **dead code** yang tetap dipelihara/diuji; (b) dokumentasi/ekspektasi “native per-deck envelope” menyesatkan; (c) jika suatu saat diaktifkan, belum ada bukti sinkronisasi/headroom end-to-end.
4. **Root cause** — Keputusan desain untuk menghindari desinkronisasi dua AudioTrack; flag di-hard-code sehingga tidak ada jalur aktivasi terkontrol.
5. **Rekomendasi** — Hapus jalur native crossfade beserta tesnya, atau jadikan opsi eksperimental dengan flag + tes integrasi dua stream. Perbarui dokumen agar menyatakan Kotlin envelope adalah satu-satunya jalur produksi.
6. **Perbandingan** — Menghapus: mengurangi permukaan kode dan kebingungan; mempertahankan: opsi masa depan untuk shared-bus. Tidak ada dampak kualitas saat ini.
7. **Trade-off/risiko** — Jika nanti dibuat shared mix bus, jalur native mungkin berguna; simpan sebagai catatan desain, bukan kode aktif. Risiko rendah.
8. **Prioritas: MEDIUM.**

---

#### AM9-M15 — “Phrase alignment” dibatasi ±4 beat, sehingga biasanya hanya snap ke bar, bukan frasa 4-bar

1. **Lokasi** — `AutomixTransitionPolicy.kt:129-172` (`phraseAlignedStartMs`, `PHRASE_SNAP_MAX_BEATS = 4.0`), `CrossfadeController.kt:300-330`.
2. **Algoritma saat ini** — Start fade ideal dicoba snap ke grid 4-bar (`metre×4`), 2-bar, 1-bar, lalu 1-beat; tetapi hanya boundary dalam `maxShift = 4 beat` yang diterima. Jika tidak ada, start tidak berubah.
3. **Masalah** — Untuk grid 16 beat, hanya 25% kasus start berada dalam 4 beat setelah boundary 4-bar; 75% sisanya jatuh ke bar/beat. Jadi nama “phrase-aligned” jarang tercapai; hasilnya bar-aligned. Pada lagu EDM dengan frasa 32 beat, boundary 4-bar bahkan lebih jarang.
4. **Root cause** — Toleransi 4 beat dipilih agar fade tidak dimulai terlalu awal (mengurangi overlap). Tidak ada pemilihan mix point berbasis struktur yang independen dari durasi fade.
5. **Rekomendasi** — Pisahkan **mix point** (titik mulai, boleh 1–4 bar sebelum EOF, dipilih dari section/phrase cue) dari **fade duration**. Untuk early handover, pilih phrase boundary terdekat tanpa batas 4 beat selama masih dalam window 30–65 s. Untuk near-EOF, pertahankan batas agar tidak memotong lagu.
6. **Perbandingan** — Mix point terpisah memberi alignment musikal nyata; risiko memotong outro lebih awal, yang memang tujuan early handover. Alternatif menaikkan maxShift ke 16 beat terlalu agresif untuk near-EOF.
7. **Trade-off/risiko** — Perlu logika baru di Dart/native dan tes durasi; pastikan `boundedFadeLeadMs` tetap membatasi fade. Risiko sedang.
8. **Prioritas: MEDIUM.**

---

#### AM9-M16 — Cache tidak pernah dipangkas; migrasi versi menulis ulang seluruh entri

1. **Lokasi** — `service.dart:1222-1245` (`_migrateAnalysisSchema`), `service.dart:1118-1140`, `service.dart:2126-2145`; tidak ada `prefs.remove` untuk `automix_*` selain restore crossfade.
2. **Algoritma saat ini** — Setiap lagu yang dianalisis menulis satu key; versi schema naik → semua entri lama dianggap miss dan dianalisis ulang, tetapi key lama tetap ada sampai ditimpa. Lagu yang dihapus dari MediaStore tidak pernah menghapus key.
3. **Masalah** — SharedPreferences tumbuh monoton; pada library besar, file XML terus membesar dan waktu commit meningkat. Migrasi v18→v19→v20 menulis ulang seluruh cache tanpa membersihkan versi lama (key sama, jadi tertimpa — tetapi lagu yang tidak lagi ada tetap). Tidak ada batas ukuran/LRU.
4. **Root cause** — Cache dirancang append-only untuk kesederhanaan; belum ada lifecycle pembersihan.
5. **Rekomendasi** — Saat library sweep/COLD start, hapus key `automix_*` yang songId-nya tidak ada di MediaStore; simpan index versi kecil; atau pindah ke DB (AM9-H02) yang mendukung `DELETE WHERE`. Tambahkan batas ukuran dan logging.
6. **Perbandingan** — Pembersihan sederhana mengurangi ukuran dan waktu commit; DB lebih baik jangka panjang. Tidak ada dampak kualitas.
7. **Trade-off/risiko** — Risiko menghapus cache lagu yang sementara tidak terlihat (mis. storage unmounted); gunakan konfirmasi library lengkap sebelum prune. Risiko rendah.
8. **Prioritas: MEDIUM.**

---

#### AM9-M17 — Suite native tidak parallel-safe; `dart test` gagal 64 tes, sementara tiap berkas lulus sendiri

1. **Lokasi** — `native_audio_runtime/test/*`, state global `g_states`, `g_tracker`, `g_published`, `g_tracker_enabled` di `automix_tone_processor.c`/`automix_live_tracker.c`; perintah di `AGENTS.md` (`cd native_audio_runtime && dart test`).
2. **Algoritma/konfigurasi saat ini** — `dart test` default menjalankan beberapa berkas secara paralel dalam satu proses; semua tes berbagi slot/stream/global C yang sama.
3. **Masalah** — Pada sesi ini: `dart test` → 64 gagal; `dart test -j 1` → 65 lulus; tiap berkas sendiri → lulus. Artinya perintah verifikasi yang didokumentasikan **tidak dapat diandalkan**; kegagalan terlihat seperti regresi algoritma padahal interference. CI yang memakai perintah default akan merah atau diabaikan.
4. **Root cause** — Desain native memakai state global per proses (sesuai untuk audio), sedangkan harness tes tidak mengisolasi proses/berkas.
5. **Rekomendasi** — (a) Ubah dokumentasi/CI menjadi `dart test -j 1` atau `--concurrency=1`; (b) lebih baik, jalankan tiap berkas di proses terpisah (`dart test -j 1` masih satu proses? gunakan `--chain-stack-traces`/shard atau script per file); (c) tambahkan reset global eksplisit di `setUp` untuk tone/tracker/pipeline.
6. **Perbandingan** — `-j 1` langsung memperbaiki keandalan dengan biaya waktu kecil (suite <1 detik). Isolasi proses lebih mahal tetapi lebih benar.
7. **Trade-off/risiko** — Tidak ada dampak produksi; hanya proses verifikasi. Risiko rendah.
8. **Prioritas: MEDIUM.**

---

#### AM9-M18 — Rentang BPM tidak konsisten antar layer (60–200 vs 50–220 vs 50–250)

1. **Lokasi** — `automix_analyzer.c:17-18` (`BPM_MIN 60`, `BPM_MAX 200`), `automix_live_tracker.c:14-15` (60–200), `service.dart:339-355` (50–220), `AutomixTransitionPolicy.kt:82-95` (50–220), `AutomixPhaseLock.kt:40` (50–250), `AutomixTempoFollow.kt:20-22` (50–250), `ParsedAutomixTransitionTarget.fromMap` (50–220).
2. **Algoritma saat ini** — Analyzer hanya mencari 60–200 BPM; layer hilir menerima 50–220/250 dan menganggapnya valid.
3. **Masalah** — Lagu 55 BPM (ambient/downtempo) tidak dapat diestimasi di analyzer (autocorrelation lag maksimum = 60 BPM); lagu 205–220 BPM (hardcore/uptempo) dilipat ke ~102–110 (half-time) atau ditolak. Downstream lalu memperlakukan hasil fold sebagai tempo nyata; phase lock/tempo follow punya rentang berbeda, sehingga pasangan yang “valid” di satu layer bisa ditolak di layer lain. Ini memicu error oktaf yang tidak terdeteksi dan gate yang tidak konsisten.
4. **Root cause** — Konstanta diduplikasi di banyak bahasa; tidak ada kontrak tunggal (mis. header C + konstanta Dart/Kotlin yang diturunkan).
5. **Rekomendasi** — Tetapkan satu kontrak, mis. 50–220 BPM untuk analisis dan playback, dengan penanganan eksplisit >200 (opsi half-time) dan <60 (perpanjang lag maksimum). Ekspor konstanta dari header dan gunakan di Dart/Kotlin; tambahkan tes batas 49/50/220/221.
6. **Perbandingan** — Menyatukan rentang menghilangkan kelas bug “valid di sini, invalid di sana”; biaya nol. Alternatif membiarkan rentang berbeda tetapi memetakan hasil di boundary — lebih rapuh.
7. **Trade-off/risiko** — Memperluas rentang analisis menambah lag maksimum (biaya autocorrelation naik linear) dan dapat menambah false positive tempo lambat; gate confidence tetap.
8. **Prioritas: MEDIUM.**

---

### 5.3 LOW

| ID | Lokasi | Temuan | Dampak | Rekomendasi |
| --- | --- | --- | --- | --- |
| AM9-L01 | `automix_analyzer.c:1051-1103` + `1810-1855` | `estimate_tempo` menghitung 4 estimasi kuartal untuk konsensus; loop kurva menghitung ulang 4 kuartal yang sama; fallback ODF dapat mengulang semuanya | ~8–12 autocorrelation tambahan per window; kecil dibanding FFT, tetapi boros | Kembalikan hasil kuartal dari `estimate_tempo_window` lewat struct; hitung sekali |
| AM9-L02 | `automix_live_tracker.c:189-205`, bar scan `~590-610` | `previous_age = age + phase_lag` dapat melebihi `history_count`; `history_age` membungkus ring tanpa cek batas | Membaca sampel lama/stale satu frame di tepi window; efek kecil | Guard `age < history_count`; kembalikan 0 bila di luar |
| AM9-L03 | `automix_native.h:57-82`, `docs/automix-production-wiring.md` §1 | Komentar ABI menyebut “32 values” padahal `NAR_AUTOMIX_ANALYSIS_VALUE_COUNT=35`; docs menyebut cache v16 padahal kode v20; urutan dokumentasi slot 18/19/32/33 tidak kronologis | Miskomunikasi untuk perubahan ABI/cache berikutnya | Perbarui komentar + docs; jadikan tabel slot sebagai sumber tunggal |
| AM9-L04 | `automix_analyzer.c:93-105` | `median_float` malloc+copy+qsort setiap pemanggilan (≥10× per analisis) | Alokasi offline, bukan audio thread; masih boros | Buffer scratch yang dialokasikan sekali per analisis |
| AM9-L05 | `engine.dart:1370-1390` | LUFS fallback di-clamp −24…−6; track sangat sunyi dipetakan ke −24 | Energi fallback sedikit terlalu tinggi untuk ambient | Perluas clamp atau gunakan RMS edge |
| AM9-L06 | `AutomixAnalysisBridge.kt:335-390` | File >600 s hanya dianalisis 5 window (~60% dengan gap); komentar “full-song” menyesatkan | Drop/section di segmen yang tidak dianalisis tidak terlihat | Dokumentasikan sampling; untuk file sangat panjang tambah window adaptif atau analisis hanya head/tail dengan label `analyzedFraction` yang jelas |

---

## 6. Hipotesis yang membutuhkan pengujian runtime

| ID | Hipotesis | Mengapa belum terbukti | Metode uji | Metrik lulus |
| --- | --- | --- | --- | --- |
| AM9-P01 | BPM masih meleset >4% pada sebagian materi nyata | Angka v8/v1.5.61 (101/117/142 vs aubio 109,5/119,4/140,7) berasal dari 3 lagu dan belum diukur ulang pada kode sekarang | Corpus 120 lagu, bandingkan dengan aubio/madmom + verifikasi manual | ≤10% lagu dengan error >2%; 0 error oktaf pada 4/4 |
| AM9-P02 | Trim/EQ/strategi salah karena fitur seam 120 s (AM9-H01) | Dampak audible butuh listening test | Render 20 transisi dengan fitur lama vs fitur edge (offline), A/B buta | Preferensi ≥65% untuk versi edge; tidak ada kasus trim >3 dB salah |
| AM9-P03 | SharedPreferences menyebabkan jank/lambat pada library besar | Belum ada profiling pada 500–2000 lagu | Ukur ukuran XML, waktu `getString`/`setString`, waktu rencana 250 lagu, frame drop | Ukuran <5 MB; rencana <100 ms; tidak ada frame >32 ms |
| AM9-P04 | Analisis 1 track 10 menit >1 s CPU dan memanaskan perangkat | Estimasi aritmetika, bukan profiling | `simpleperf`/`atrace` pada Mi 9T; 5 track; ukur wall, CPU%, suhu, baterai | p95 <2 s/track; tidak ada throttling dalam sweep 40 track |
| AM9-P05 | Live tracker memperbaiki alignment pada lagu dengan grid offline lemah | Belum ada capture PCM dua deck | Rekam output fade, hitung offset beat antar-deck dengan/without tracker | Median offset <20 ms; tidak menambah artefak |
| AM9-P06 | Phase lock/tempo follow memperbaiki atau justru mengganggu | Belum ada A/B on-device | Bandingkan fade dengan phase lock on/off pada 30 pasangan | Offset akhir <1/8 beat; MOS tidak turun |
| AM9-P07 | Reorder berulang mengganggu pengguna | Belum ada UX test | Log timestamp reorder per sesi; wawancara/observasi | ≤2 reorder per 10 menit setelah 3 lagu pertama |
| AM9-P08 | Key/chord accuracy di bawah standar DJ | Tidak ada label | 30 lagu berlabel key + chord; ukur exact/relative/Camelot | Key exact ≥80% (mode), Camelot ≤1 ≥90% |
| AM9-P09 | Limiter per-deck belum menjamin true peak post-mix | Sudah didokumentasikan, tetapi belum diukur pada materi correlated | Render dua deck correlated, ukur intersample peak output | Tidak ada overshoot >0,3 dB (target; saat ini bisa lebih) |
| AM9-P10 | Cooldown artis yang tidak konsisten terdengar sebagai pengulangan | Belum ada plan diff | Bandingkan urutan sebelum/sesudah polish pada 50 library | 0 pengulangan artis jarak ≤2 saat `avoidArtistRepeat` aktif |

---

## 7. Status temuan audit v8 pada kode saat ini

Tabel ini bukan klaim bahwa masalah “selesai” secara kualitas; status menunjukkan apakah mekanisme perbaikannya ada di kode sekarang. Validasi akurasi tetap hipotesis (P01/P08).

| ID v8 | Status di v1.5.62 | Bukti kode | Catatan |
| --- | --- | --- | --- |
| AM8-01 tempo tanpa model metrikal | **Ditutup di kode** | `evaluate_metrical_candidate` (analyser:615), 7 hipotesis live | Akurasi nyata masih P01 |
| AM8-02 live tracker confidence salah level | **Ditutup di kode** | grid hypothesis + margin + sub-multiple penalty; grid merge memilih offline saat tempo beda >4% | — |
| AM8-03 bar phase flat | **Sebagian** | bar novelty path (analyser:1450-1500) + corroboration low-band live | Masih butuh kontras; H05 |
| AM8-04 NaN beat phase | **Ditutup di kode** | histogram fasa fraksional + smoothing (analyser:1104-1200) | Ada tes sintetis |
| AM8-05 key percaya diri salah | **Sebagian** | entropy gate + tuning + relative penalty | Key global, bukan seam (M03) |
| AM8-06 energy cost saturasi | **Ditutup di kode** | koefisien 0,22+0,40+0,18+0,10+momentum ≤1,0 + clamp | — |
| AM8-07 tidak ada time signature | **Ditutup di kode** | metre 2/3/4/6 di analyzer, policy, grid merge | 2-ketukan butuh margin 0,20 |
| AM8-08 chord quality | **Sebagian** | gate sevenths + margin confidence | Viterbi root-only (M09) |
| AM8-09 phrase snap memperpanjang fade | **Ditutup di kode** | `boundedFadeLeadMs` (policy:175) | — |
| AM8-10 density scaling merusak kuantisasi | **Sebagian** | rekuantisasi setelah cap | Cap detik (M13) |
| AM8-11 artist repetition bobot ganda | **Ditutup di kode** | cooldown tunggal di cost | Skala polish beda (H03) |
| AM8-12 coverage gap 241–300 s + struktur bukan track-level | **Sebagian** | centered window + section cue | Drop head-only (H04); region dB absolut (H05) |
| AM8-13 mid-fade loudness dip | **Ditutup di kode** | equal-power cos/sin + trim | — |
| AM8-14/15 (Low) | Tidak diverifikasi ulang | — | Lihat v8 §C.1 |
| Post-mix true peak | **Terbuka (deferred)** | dua AudioTrack, limiter per deck | Bukan temuan baru; tetap batas arsitektur |

---

## 8. Rekomendasi peningkatan dan perbandingan pendekatan

### 8.1 Matriks perbandingan

| Area | Pendekatan saat ini | Alternatif yang disarankan | Perkiraan peningkatan | Biaya/kompleksitas | Risiko |
| --- | --- | --- | --- | --- | --- |
| Fitur seam | Median window 120 s | Profil 10–15 s edge (RMS, onset, low-band, short-term LUFS) | Keputusan fade/trim/EQ jauh lebih tepat pada lagu dinamis | Rendah (data sudah ada) | Perlu kalibrasi ambang |
| Tempo | Autocorrelation + hipotesis metrikal + konsensus kuartal | DP beat tracking + tempo map per 8 bar | Error BPM/beat turun pada live/ritardando | Sedang (C) | Perlu corpus |
| Downbeat/phrase | Accent + chroma novelty, grid global | DP beat + HMM downbeat / SSM phrase (Foote) | F1 downbeat/phrase naik; frasa 32-beat terdeteksi | Sedang–tinggi | Overfit; butuh label |
| Key | KS global + HPCP 2 harmonik | Key per seksi + bass chroma + HPCP 4–5 harmonik | Key seam lebih relevan; error modulasi turun | Sedang | Pitch shift salah jika confidence naik tanpa kalibrasi |
| Chord | Template + Viterbi akar | HMM (root, quality) + bass/non-chord penalty | Progresi lebih stabil | Sedang | Label chord terbatas |
| Energi | RMS+centroid+onset, arc parametrik | Loudness perceptual + densitas + LRA; arc per profil | Progresi lebih halus dan sesuai genre | Rendah–sedang | Perlu kalibrasi |
| Planner | Greedy + lookahead + polish | Beam search 8–16, tempo arc, artist constraint | averageCost turun 5–15% (estimasi) | Sedang | Determinisme/waktu |
| Transisi | Equal-power + bass swap + EQ + limiter per deck | Crossover LR4, short-term loudness match, post-mix limiter | Artefak turun; headroom terjamin | Tinggi (shared bus) | Arsitektur audio berubah |
| Cache | SharedPreferences JSON | SQLite/binary + isolate + prune | Jank hilang; memori turun | Rendah–sedang | Migrasi |
| SIMD | NEON window/RMS + tone | rFFT/NEON FFT, NEON HPCP | 1,5–2,5× analisis | Sedang | Numerik/toleransi |
| ML | Tidak ada | Kecil: downbeat/section CNN (opsional) | Potensi akurasi tinggi | Tinggi (model, data, baterai) | Belum layak sebelum corpus |

### 8.2 Kapan ML masuk akal (dan kapan tidak)

- **Tidak layak sekarang** untuk BPM/key/chord: DSP + hipotesis metrikal sudah mendekati plafon yang bisa dicapai tanpa data berlabel; menambah model tanpa corpus hanya menambah risiko dan ukuran APK.
- **Layak dipertimbangkan setelah corpus ada** untuk: (a) downbeat/phrase (CNN 1D pada log-mel 2–5 MB, quantized); (b) section labeling (embedding + clustering); (c) vocal presence (small classifier) bila source separation tidak memungkinkan.
- **Kriteria go**: model harus mengalahkan baseline DSP pada F1 downbeat/phrase ≥10% relatif, latency <50 ms per 10 s audio, ukuran <5 MB, dan berjalan <5% CPU saat analysa latar. Jika tidak, pertahankan DSP.

---

## 9. Rencana implementasi bertahap

Tidak ada implementasi pada audit ini. Urutan di bawah disusun agar perbaikan berdampak besar dan berisiko rendah dilakukan lebih dulu, dan setiap fase punya gerbang validasi sendiri.

| Fase | Isi | Temuan yang ditutup | Usaha | Risiko | Kriteria keluar |
| --- | --- | --- | --- | --- | --- |
| **0. Baseline & harness** | Buat corpus 120 lagu + manifest label; harness metrik offline; instrumentasi waktu/RAM; golden JSON | M06, M17, P01–P10 | M | Rendah | Baseline terdokumentasi; suite native `-j 1` hijau; metrik BPM/beat/key/seam keluar |
| **1. Semantik seam** | Fitur edge RMS/onset/low-band/short-term LUFS; pakai untuk trim, strategi, EQ, lead; kalibrasi ambang | H01, H05, M10, M11 | M | Rendah–sedang | 20 transisi A/B: preferensi ≥65%; trim error <1,5 dB pada corpus |
| **2. Konsistensi keputusan** | Satukan skala artist cooldown; satukan rentang BPM; snapping cue pakai metre; durasi fade dalam bar; gate tabel tunggal | H03, M01, M08, M13, M18 | S–M | Rendah | 0 pengulangan artis jarak ≤2; tes batas BPM; cue 3/4 & 6/8 tepat |
| **3. Drop & early handover** | Top-3 drop cue per window; batas atas 90 s jadi parameter; log alasan fallback; seek/lead diuji pada lagu intro panjang | H04, M15 | M | Sedang | ≥80% lagu ber-drop 8–140 s memicu early handover; tidak ada seek salah |
| **4. Cache & perencanaan** | SQLite/binary + isolate + prune; rencana hanya prefix teranalisis; histeresis reorder | H02, M07, M16 | M–L | Sedang | Rencana 250 lagu <100 ms; tidak ada frame >32 ms; reorder ≤2/10 menit |
| **5. Beat/downbeat/phrase** | DP beat tracking + tempo map; downbeat HMM/bar-level; phrase SSM; key per seksi | M02, M03, M04, M09 | L | Tinggi | F1 beat ≥0,9 (subset 4/4), downbeat ≥0,75; BPM error <2% pada 90% corpus |
| **6. Planner & transisi lanjutan** | Beam search, tempo arc, crossover LR4, short-term loudness, (opsional) post-mix limiter | M12, M08, M10, M11 | L | Tinggi | averageCost turun ≥5%; MOS tidak turun; tidak ada overshoot >0,3 dB |
| **7. Opsional ML** | Downbeat/section model kecil bila Fase 5 belum cukup | — | L | Tinggi | Kriteria go §8.2 terpenuhi |

Urutan alternatif jika ingin hasil audible tercepat: Fase 0 → 1 → 2 → 4; Fase 3 dan 5 menyusul.

---

## 10. Strategi benchmark dan regression testing

### 10.1 Dataset

- **Lokasi:** `testdata/automix/` (di-luar build; hash file di manifest). Jangan commit audio berhak cipta; gunakan sampel 30–60 s yang diizinkan atau sinyal sintetis + metadata.
- **Komposisi minimum 120 track:** house/techno 120–130 BPM (25), pop 90–120 (25), hip-hop/trap 70–100 (15), DnB 170–180 (10), 3/4 waltz (5), 6/8 compound (5), live drums/ritardando (10), ambient/downtempo 50–70 (10), master padat/quiet intro-outro (15).
- **Label:** BPM (manual + aubio/madmom cross-check), metre, key (manual/Mixed In Key), beat/downbeat untuk 30 track × 60 s, phrase/section untuk 20 track, mix point pilihan DJ untuk 20 transisi.
- **Manifest JSON:** `{path, genre, bpm, meter, key, beats[], downbeats[], phrases[], sections[], mixPoints[]}`.

### 10.2 Metrik dan target

| Metrik | Formula/alat | Baseline (v1.5.62) | Target fase 5 |
| --- | --- | --- | --- |
| BPM MAE | mean(abs(est−gt)) | ukur | <1,5 BPM |
| BPM within 2% | % track | ukur | ≥90% |
| Octave error | % track | ukur | <3% |
| Beat F1 | mir_eval, ±70 ms | ukur | ≥0,90 |
| Downbeat F1 | ±70 ms | ukur | ≥0,75 |
| Phrase boundary F1 | ±1 bar | ukur | ≥0,70 |
| Section F1 | ±2 s | ukur | ≥0,75 |
| Key exact (mode) | % | ukur | ≥80% |
| Camelot ≤1 | % | ukur | ≥90% |
| Key ECE | calibration | ukur | <0,10 |
| Transition alignment | abs(fadeStart−mixPoint) | ukur | ≤1 beat pada 80% |
| Drop landing error | abs(dropStart−dropCue) | ukur | ≤1 beat |
| Artifact | max sample step, true-peak | ukur | step <0,05; TP ≤0 dBTP |
| CPU | ms/track, p95 | ukur | <2 s/track (120 s window) |
| Memori | peak RSS | ukur | <80 MB |
| Baterai/termal | %/40 track, throttling | ukur | tidak throttle |

### 10.3 Harness

1. **Offline analyzer bench** — CLI Dart (`tool/automix_bench.dart`) memanggil FFI `nar_automix_analyze_*` untuk setiap manifest, menulis CSV/JSON; hitung metrik dengan `mir_eval` (Python) atau implementasi Dart. Jalankan di host x86_64 dan cross-compile aarch64 (qemu) untuk memastikan NEON setara.
2. **Planner bench** — fixture fitur sintetis + real; ukur averageCost, waktu, artist spread, tempo arc; bandingkan greedy vs beam.
3. **Kotlin/JVM bench** — `AutomixFadeRenderTest` diperluas: render 30 pasangan, ukur envelope, phase offset, limiter, artifact; `tools/automix_ffmpeg_regression.sh` ditambah capture dua deck (bukan hanya envelope).
4. **Perangkat** — `simpleperf record` pada `nar_automix_analyze`, `atrace` untuk audio callback; ukur WCET live tracker; uji 500–2000 lagu untuk cache.
5. **Listening test** — 20 transisi, A/B buta, 5 pendengar, skala 1–5 (musikalitas, alignment, level, artefak).

### 10.4 Regression & CI

- **Golden JSON** per track: fitur + hash; toleransi absolut/relatif per field (BPM ±0,1, confidence ±0,02, fase ±2 ms). Perubahan yang melewati toleransi harus disertai penjelasan dan pembaruan golden eksplisit (tidak otomatis).
- **Smoke subset 10 track** pada setiap perubahan algoritma (cepat, <2 menit); **full corpus 120** pada dispatch/nightly.
- **Suite native** dijalankan `-j 1` (atau satu proses per file); suite Dart/Kotlin dijalankan seperti sekarang.
- **Gate merge:** tidak ada regresi BPM/beat/downbeat/key >2% relatif, tidak ada artifact baru, tidak ada kenaikan waktu >20% tanpa persetujuan.
- **Versioning:** bump schema cache setiap perubahan fitur; simpan versi di manifest benchmark.

### 10.5 Urutan validasi yang disarankan

1. Baseline semua metrik pada kode sekarang (Fase 0).
2. Untuk setiap perubahan: jalankan smoke → bandingkan metrik → listening test bila menyentuh seam/transition.
3. Jika satu algoritma naik tetapi metrik lain turun, tolak atau gate dengan confidence.

---

## 11. Batasan audit dan hal yang belum diverifikasi

- **Tidak ada perubahan kode**; semua rekomendasi belum diimplementasikan.
- **Tidak ada capture audio perangkat**, sehingga artefak (click, phase, limiter, bass swap) belum diukur secara objektif. Klaim artefak di laporan ini adalah analisis kode, bukan hasil rekaman.
- **Tidak ada dataset berlabel**; semua angka akurasi target adalah usulan, bukan hasil.
- **Kotlin unit test tidak dijalankan** pada sesi ini; suite Dart (137) dan native (65 dengan `-j 1`) lulus.
- **Tidak ada profiling** CPU/memori; estimasi FLOP di §5.1/M06 bersifat aritmetika.
- **Dokumentasi lama** (`docs/automix-production-wiring.md`, v8) sebagian sudah tidak sinkron (cache v16 vs v20; 32 vs 35 nilai); temuan L03.
- **Post-mix true-peak** tetap tidak dijamin oleh arsitektur dual-AudioTrack; ini batas yang sudah didokumentasikan dan tidak diubah oleh audit ini.

---

## Lampiran A — Peta simbol kunci

| Simbol | Berkas:baris | Peran |
| --- | --- | --- |
| `_checkPlaybackStateForAutoMix` | `service.dart:261` | Orkestrasi pass otomatis |
| `_autoAnalyzeUpcomingTracks` | `service.dart:852` | Penjadwal analisis (maks 2/pass) |
| `analyzeOne` | `service.dart:2079` | Dedup + decode + cache |
| `_featuresForPlan` / `_cachedOrNeutral` | `service.dart:1401/1418` | Fitur rencana (6 penuh, sisanya cache) |
| `_prepareUpcomingTracks` | `service.dart:519` | Rencana + reorder + target |
| `_buildNativeTargets` | `service.dart:374` | Kontrak 2 deck |
| `automixMergeSegments` | `engine.dart:384` | Agregasi multi-window |
| `automixTransitionCue` | `engine.dart:1093` | Fade/strategi/EQ/pitch/lead |
| `automixNormalizeEnergy` | `engine.dart:1573` | Energi relatif set |
| `_transitionCost` | `engine.dart:1754` | Mirror biaya native |
| `DartAutomixEngineReference` | `engine.dart:1912` | Referensi/paritas |
| `AutomixEngine.planSet` | `engine.dart:2665` | FFI planner |
| `AutomixAnalysis.analyzeAll` | `AutomixAnalysisBridge.kt:160` | Satu sesi decode |
| `AutomixPcmDownsampler` | `AutomixPcmDownsampler.kt:15` | Mono 22,05 kHz + center ratio |
| `AutomixGridMerge.mergeDeck` | `AutomixGridMerge.kt:53` | Gabung grid offline/live |
| `AutomixTransitionPolicy.phraseAlignedStartMs` | `AutomixTransitionPolicy.kt:129` | Snap start |
| `CrossfadeController.maybeCrossfadeOut` | `CrossfadeController.kt:223` | Prewarm + trigger |
| `runEqualPowerFade` | `CrossfadeController.kt:746` | Eksekusi 16 ms |
| `nar_automix_analyze_centered` | `automix_analyzer.c:1613` | Analyzer 35 slot |
| `estimate_tempo` / `evaluate_metrical_candidate` | `automix_analyzer.c:1051/615` | Tempo/hipotesis metrikal |
| `estimate_phrase_grid` | `automix_analyzer.c:1350` | Metre + phrase |
| `nar_automix_analyze_chords` | `automix_analyzer.c:2289` | Chord progression |
| `nar_automix_plan_set` | `automix_planner.c:880` | Greedy + polish |
| `estimate_live_beat` | `automix_live_tracker.c:339` | Tracker live |
| `nar_automix_tone_process` | `automix_tone_processor.c:345` | 3-band + limiter |

## Lampiran B — Matriks gate dan ambang

| Sinyal | Ambang | Lokasi |
| --- | --- | --- |
| BPM publish | confidence ≥0,20 (target grid), ≥0,35 (gate keputusan) | analyzer, service, policy |
| Key publish | confidence >0,25 (parse), ≥0,55 (harmonic filter), ≥0,70 (pitch shift) | models, planner, engine |
| Tail BPM | ≥0,35 | engine/service/planner |
| Start BPM | ≥0,35 | engine/service/planner |
| Drop | 0,55 dan 8–90 s | engine/service/Media3 |
| Breakdown | 0,45; lead 1,5–12 s | engine |
| Struktur | ≥0,50 (seam), ≥0,65/0,75 (strategi) | planner/engine |
| Vocal | likelihood ≥0,55, confidence ≥0,45 | engine; native 0,35 |
| Phase lock live | confidence ≥0,30; offset ≥6 ms; nudge ≤0,6% | controller/phase_lock |
| Tempo follow | confidence ≥0,50; koreksi ≤2%; stretch 0,92–1,08 | tempo_follow |
| True peak | ceiling 0,95 | controller/tone |

## Lampiran C — Verifikasi yang dijalankan

```
flutter test test/services/automix_service
→ 137 tests passed

cd native_audio_runtime && dart test -j 1
→ 65 tests passed

cd native_audio_runtime && dart test
→ 64 tests failed (shared native globals; each file passes alone)
```

Tidak dijalankan: `testDebugUnitTest`, `tools/automix_ffmpeg_regression.sh`, build APK, capture perangkat.

---

*Laporan ini tidak mengubah kode. Menunggu persetujuan sebelum implementasi. Usulan urutan eksekusi: Fase 0 (baseline) → Fase 1 (semantik seam) → Fase 2 (konsistensi keputusan).*

