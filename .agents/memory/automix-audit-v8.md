# AutoMix audit v8 — metrical & perceptual modelling

**Tanggal:** 2026-10-28 · **Sifat:** audit + rekomendasi (awalnya tanpa perubahan kode), lalu remediasi v1.5.55.
**Laporan lengkap:** `automix_implementation_audit_v8.md` (root repo, bagian H berisi status remediasi).
**Pendahulu:** `automix-audit-v7.md` (timing/phase). v8 mulai dari lapisan *musical intelligence* yang belum
diperiksa v7: metrical level, bar phase, key, loudness, kalibrasi skor, dan kesepakatan grid live vs offline.

## Bukti

Probe C (scratch `build/audit_tmp/`, git-ignored dan sudah dihapus) dikompilasi terhadap sumber asli
`automix_analyzer.c`/`automix_live_tracker.c`/`automix_phase_lock.c` dan dijalankan pada sinyal sintetis
dengan ground truth. Native C suite (58 test) **lulus** (`exit 0`). `flutter test` AutoMix **tidak bisa
dijalankan** di sesi ini: filesystem 99% (53 MB) → `ENOSPC` dari test compiler. Kotlin/Gradle butuh Android SDK
(tidak ada), ffmpeg regression butuh `ffmpeg` (tidak ada).

## Temuan utama

| ID | Sev | Ringkas |
|---|---|---|
| AM8-01 | Critical | BPM offline salah pada rasio integer: 2× (60–87), ½× (180–200), ⅔× (170–190), ⁴⁄₃× (syncopated), conf 0.62–0.89. `comb(P) == comb(2P)` untuk materi periodik → hanya prior Gaussian 115 BPM yang memutuskan. 12/27 tempo sweep salah. |
| AM8-02 | Critical | Live tracker: 180 → 60.00 conf **1.000**; 174 → 86.98 sedangkan offline 174.05. Tanpa prior, rescue hanya arah "×2", confidence tidak mengukur metrical level. `AutomixGridMerge` (offline weight 0.8) **membuang** grid offline saat beda >4% log → grid live menang. |
| AM8-03 | High | Downbeat butuh kontras aksen; four-on-floor datar → `downbeatConfidence = 0.000` di 12/12 tempo → `phraseAlignedStartMs` jatuh ke snap 1 beat; alignment bar/phrase tidak pernah aktif. |
| AM8-04 | High | `estimate_beat_phase_ms` = `NaN` pada pola kick + hat off-beat (2/5 pola) → beat matching hilang senyap. Akar: ODF log-flux broadband tanpa pembobotan frekuensi. |
| AM8-05 | High | Key: Am–F–C–G → C major conf 1.00; white noise → key conf 0.754; +45 cent → E minor. Dipakai untuk hard reject `keyCost ≥ 0.60` dan pitch shift ±1 st (gate conf 0.55). |
| AM8-06 | High | Energi: koefisien 0.30+0.55+0.30+0.25 (+momentum 0.30) = 1.40 lalu di-clamp 1.0 → saturasi, gradien hilang. Ada di Dart **dan** `automix_planner.c`. |
| AM8-07 | High | Tidak ada model time signature: bar live hard-code 4 beat, phrase grid 16 beat. |
| AM8-08 | Medium | Chord: triad → `maj7` conf 1.00 (lebih tinggi dari maj7 asli 0.93), gap `conf 0.00` tepat di pergantian chord; harmoni dihitung dua kali + gate keras 0.62. |
| AM8-09 | Medium | `PHRASE_SNAP_MAX_BEATS = 4` → `fadeLeadMs = dur − start` memperpanjang fade sampai 4 beat (komentar bilang "< one beat"); lolos dari cap 12 s karena cap dikenakan ke `crossMs`. |
| AM8-10 | Medium | `fade = crossfadeBeats×60/bpm` lalu ×0.75/×1.25/×1.15 → 4 beat jadi 5.75 beat; kuantisasi beat hilang. |
| AM8-11 | Medium | Artis dihitung dua kali: `variety` (0.15) + `_artistCooldownCost` aditif (0.05/0.12). |
| AM8-12 | Medium | File 241–300 s: hanya head+tail → lubang tengah sampai 60 s. Struktur hanya label per-window, bukan segmentasi track. |
| AM8-13 | Medium | L1 headroom → dip ~3 dB di tengah fade, padahal tone processor sudah punya true-peak limiter. |
| AM8-14/15 | Low | `alternateBpm` jarang terisi (jalur octave-recovery mati); `vocalPenalty` di luar normalisasi bobot. |

## Yang sudah dicek dan BUKAN bug

- Penjumlahan `ACF(k·lag)` (comb) memang benar untuk beat yang hilang; yang kurang adalah keputusan metrical.
- Fold half/double di `automixTempoCost` disengaja; 120↔60 = beat-perfect itu benar.
- `isBeatMatchedPair` menolak phase-lock lintas oktaf — benar.
- `AutomixGridMerge` men-gate downbeat pada confidence → fail-safe (masalahnya: tidak pernah tersedia).
- Cache schema v18 + `ident` + migrasi → tidak ada jalur data basi.
- Live tracker: fixed size, tanpa alokasi, seqlock, reset per-slot, LFE dikecualikan.
- `ODF_TIMESTAMP_OFFSET_SAMPLES` (fix v7) hadir dan benar.
- **Ditolak setelah diukur:** dugaan "tempo drift dilaporkan stabil" (ternyata tidak: 0.21/0.00 → varispeed diblokir
  oleh threshold 0.65) dan dugaan "analyzer alokasi di audio thread" (tidak).

## Rekomendasi (urutan)

1. Kalibrasi cost (normalisasi 1.40, satu mekanisme artis, lipat vocal term) — 2 file, parity-tested.
2. Fade integer-beat + snap dibatasi durasi fade.
3. Live: rescue simetris + confidence dari margin hipotesis + **balik default `AutomixGridMerge`** (offline menang saat beda).
4. ODF multi-band (low/mid untuk phase) → hilangkan kelas `NaN`.
5. Key: gate energi harmonik, estimasi tuning, confidence terkalibrasi; matikan pitch shift sementara.
6. **Metrical hypothesis test** `{P/2, P, 2P} × {bar 3, bar 4}` dengan skor comb + coherence + bar consistency +
   stabilitas setengah-window; publish runner-up sebagai `alternateBpm`. Ini keystone.
7. Bar phase dari **bukti perubahan** (novelty/SSM), bukan aksen loudness → menghidupkan phrase snap yang sudah ada.
8. Chord quality dengan bukti partial ke-7; satu otoritas harmoni (hapus gate 0.60/0.62).

Metrik target: BPM exact-hit ≥90% (sekarang 56% di sweep), phase error ≤15 ms & ≤1% NaN, downbeat published
≥80% four-on-floor, live/offline agreement ≥95%, |executed fade − planned| ≤1 beat, seam dip ≤1.5 dB.
**Jangan klaim peningkatan persepsi dari sinyal sintetis** — perlu field set 10–20 track berlabel.

## Remediasi (2026-10-28, v1.5.55)

Audit ditindaklanjuti tanpa AI/ML. Ringkasan status per temuan:

| ID | Status | Perubahan |
|---|---|---|
| AM8-01 | **Fixed** | `estimate_tempo` mengganti prior-first dengan uji hipotesis metrikal: kandidat `{P/2, P, 2P, ⅔P, 3⁄2P}` + peak comb, diskor dari comb, onset-grid coverage, grid fill, aksen on/off-beat, dan phase coherence; prior 120 BPM hanya tie-break 15%. Runner-up dipublikasikan sebagai `alternateBpm` (AM8-14). |
| AM8-02 | **Fixed (v1.5.58)** | Estimator live memakai uji hipotesis grid yang sama dengan offline: level `1, ½, 2, ⅔, 3⁄2, ⅓, 3` diuji coverage+fill, rescue kini simetris (90/135/160/174/180 semua benar; sweep 70–200 dalam 0.2 BPM), dan confidence diskalakan oleh margin antar-hipotesis. `AutomixGridMerge` tetap memilih offline saat beda >4% log. |
| AM8-03 | **Fixed (v1.5.58)** | Downbeat live memakai aksen low-band **plus** timbre-change; meter harus menang di dua jendela 2-bar dan didukung kenaikan low-band share. Flat 13/13 tempo → meter 0 / dbc 0.000; meter-3 120 BPM → dbc 0.77. Offline tetap memakai chroma novelty. |
| AM8-04 | **Fixed** | ODF phase dipisah per band (30–150 Hz bobot 1.0, 150–1500 Hz 0.55, 1500–8000 Hz 0.15); beat phase memakai `phase_odf`, tempo/frase tetap memakai ODF penuh. |
| AM8-05 | **Fixed** | Key: gate entropi + minimal 3 kelas, pencarian tuning ±50 sen (5 sen step), confidence = bukti absolut × margin × flatness × penalti relatif mayor/minor; gate pitch shift dinaikkan 0.55→0.70; hard reject harmoni di cue dihapus (harmoni hanya di planner). |
| AM8-06 | **Fixed** | Koefisien energi Dart + C dinormalisasi ke 1.0 (0.22/0.40/0.18/0.10, momentum cap 0.10); clamp tinggal guard. |
| AM8-07 | **Fixed (v1.5.58)** | Meter 3/4/6 diuji di analyzer (output index 32) dan live tracker; nilainya diteruskan JNI → Dart → payload target native (outgoing = exit window, incoming = head window). Grid frasa = `meter × 4`, snap fade memakai bar sesuai meter, phrase lock hanya bila kedua deck sama meter. |
| AM8-08 | **Fixed** | Kualitas 7th hanya diterima bila ada energi nyata di partial ke-7; gate keras `keyCost`/`chordCost` di cue dihapus; baris chord ber-confidence rendah di tengah perubahan diisi hangover ber-decay (bukan gap 0.00). |
| AM8-09 | **Fixed** | `AutomixTransitionPolicy.boundedFadeLeadMs` membatasi fade hasil phrase snap ke `plannedFade + ½ beat` dan tidak melewati EOF; dipakai `CrossfadeController` pada jalur non-early. |
| AM8-10 | **Fixed** | Density scaling mengalikan jumlah beat (bukan detik), lalu kuantisasi ½ beat; fade dihitung ulang setelah cap 1.5–12 s (kecuali structureAligned yang memang terikat boundary). |
| AM8-11 | **Fixed (v1.5.58)** | `variety` dihapus dari Dart dan planner native; artist cooldown satu-satunya mekanisme (base 0.09/0.03, back 1..4). Bobot 0.15 dibagi ke tempo/key/energi dengan proporsi lama. Lookahead kini tidak membaca slot plan yang belum ditulis (dulu index OOB → segfault). |
| AM8-12 | **Fixed (v1.5.58)** | File 241–300 s menambah jendela tengah bila gap >30 s; analyzer mempublikasikan boundary seksi track-level dari blok chroma 2 s (index 33/34). Boundary dengan conf ≥0.50 dan lead 30–65 s dipakai sebagai titik early handover; boundary palsu tidak muncul pada aransemen datar (diuji). |
| AM8-13 | **Open (sengaja)** | L1 headroom tidak diubah: perlu pengukuran loudness seam pada audio nyata sebelum melepas proteksi clipping. |
| AM8-14 | **Fixed** | `alternateBpm` = runner-up hipotesis metrikal, bukan tebakan <90/>140. |
| AM8-15 | **Fixed** | Vocal menjadi sub-cost berbobot 0.10 di dalam denominator yang sama. |

Cache analysis sekarang **schema v21** (2026-10-31): entri v20 masih menyimpan median window di `introRmsDb`/`outroRmsDb`, bukan statistik edge 15 s, jadi dianalisis ulang. Lihat `automix-seam-edge-v21.md`.

**Tindak lanjut 2026-10-29 (dirilis 2026-10-30, v1.5.58):** AM8-02/03/07/08/11/12 selesai. Regresi native baru:
`test_live_tracker_resolves_third_and_double_tempo` (90/135/160/174/180),
`test_live_tracker_reports_meter_and_rejects_flat_bars` (flat 120 → meter 0/dbc <0.30; waltz 120 → meter 3/dbc ≥0.30),
`test_analyzer_metre_and_section_boundary` (meter 3 + boundary 30 s, steady → tanpa boundary, frasa 12-beat dari perubahan chord).
Dart: parse/persist `meter`/`tailMeter`/`tailSectionCueMs`, payload target `meter`, dan tes cue early-handover berbasis boundary seksi.
Verifikasi sesi: native C suite exit 0; `flutter test` AutoMix 115 lulus; `dart analyze` bersih pada layanan/test AutoMix.
Kotlin belum bisa dijalankan di sandbox (Gradle gagal membuat `gradle-api-9.8.2.jar`), `ffmpeg` tidak ada — keduanya tetap untuk CI.

Verifikasi: native C suite (`automix_native_c_test.c`) **exit 0**, termasuk sweep metrikal 60–200 BPM,
beat phase dengan off-beat hat, key noise/detune, dan phrase phase dari perubahan harmoni. `dart analyze` pada
`engine.dart`, `service.dart`, dan test AutoMix: bersih. Sweep syntetik pasca-fix: four-on-floor **27/27 benar**
(sebelumnya 15/27); backbeat-only 4/27 (ambiguitas half/double tetap, `alternateBpm` membawa level lain);
syncopated 14/27 benar, hanya 12/27 dengan conf ≥0.20 (level ambigu ditahan, bukan ditebak); pad-only bukan
sinyal ritmis. Setelah cache sandbox dibersihkan, `flutter test --no-pub test/services/automix_service/`
menjalankan **131 test, semuanya lulus** (`ENOSPC` sebelumnya murni disk penuh, bukan kegagalan test).
Kotlin/Gradle tetap tidak tersedia dan `ffmpeg` tidak ada, jadi suite Kotlin dan audio nyata tetap untuk CI.

**Uji audio nyata 2026-10-30 (ffmpeg 4.4.2):** harness `build/audit_real/` (gitignored) — numpy
mensintesis 13 fixture musikal → WAV 44,1 kHz → `ffmpeg -ac 1 -ar 22050 -f f32le` →
`nar_automix_analyze_centered`/`_chords`, jalur PCM yang sama dengan `AutomixAnalysisBridge`. Hasil:
four-on-floor 120/124/174 benar (≤0,03 BPM), phase error 7,8 ms pada trek 124 yang digeser 100 ms,
MP3 192k identik dengan WAV (Δ0,3 ms, chord sama), waltz meter 3, progresi C–Am–F–G + key C mayor 0,84
benar. **Temuan:** (1) four-on-floor 120 + snare 2/4 terbaca **60,00 BPM conf 0,87** (alt 119,98) —
lock half-tempo offline, kelas yang sudah diperbaiki di live tracker (AM8-02) tapi belum di
`estimate_tempo` offline — **pre-existing**, dikonfirmasi dengan membangun ulang analyzer dari `HEAD~1`
(hasil identik 60,00/87,01); 174 breakbeat → 87,01 (alt 174); (2) trek dengan intro sparse 32 s +
chorus padat: whole/end BPM 60 padahal `start_bpm` 120; (3) 6/8 pada pulsa dotted-quarter 80 →
meter 4 (bar 3 s, 2× bar asli); (4) section cue tepat 32000 ms conf 1,00 saat harmoni statis,
tapi NaN saat ada progresi akor tiap 2 bar (novelty akor menutupi boundary). Detail tabel di
`automix_implementation_audit_v8.md` §J.

**Meter 2 (6/8 compound) 2026-10-30 (v1.5.60):** hipotesis meter di analyzer dan live tracker kini
`{4,3,6,2}`; fixture 6/8 pada 80,02 BPM → **meter 2** (bar 1,5 s) dari sebelumnya 4, sementara
120/124/174 four-on-floor tetap tanpa meter, waltz tetap 3, breakbeat 174 tetap 4. Semua konsumen
(analyzer, live, Dart models/native IO, bridge, grid merge, transition policy) memvalidasi himpunan
eksak `{2,3,4,6}` — bukan range 2..6 — sehingga meter 5 yang tidak pernah diproduksi tidak lolos.
Regresi: `test_analyzer_compound_meter_two_beats` dan kasus compound di
`test_live_tracker_reports_meter_and_rejects_flat_bars`; tes parser Dart/Kotlin diperbarui.

**Perbaikan half-tempo 2026-10-30 (v1.5.59):** `evaluate_metrical_candidate` sekarang memberi bobot
coverage 0.45 / fill 0.25 / comb 0.10 / contrast 0.08 / phase 0.12 (dulu 0.12/0.40/0.30/0.06/0.12), dan
`estimate_tempo` (wrapper baru; body lama = `estimate_tempo_window`) memakai voting 4 quarter bila ≥3
sepakat dalam 4% dan berbeda dari whole-window. Hasil harness yang sama: 120+snare 60,00→**119,98**
(conf 0,87→0,57), 124+snare conf 0,50→**0,72** (start 61,9→123,9), breakbeat 174 87,01→**173,98**,
intro sparse 60,00→**120,01** (start/end 120,01), section statis tetap 32000@1,00. Efek samping: beat
phase head pada trek intro-sparse jadi NaN (tidak ada onset level-beat di 32 s pertama). Regresi C baru:
`test_analyzer_backbeat_keeps_beat_level`, `test_analyzer_sparse_intro_keeps_chorus_tempo` (keduanya
abort di analyzer lama). **Belum diperbaiki:** meter 6/8 (pulsa dotted-quarter → meter 4) dan section cue
yang tertutup progresi akor.

**Penutupan 2026-10-30:** chord hangover (AM8-08) ditambahkan di `nar_automix_analyze_chords` — baris yang
jendelanya melintasi pergantian akor diisi akor sebelumnya dengan confidence meluruh (1 − gap/1500 ms), hanya
jika ada akor yakin dalam 1500 ms berikutnya; trailing silence tetap `-1`. Regresi baru
`test_chord_hangover_bridges_one_gap_and_not_trailing_silence`. Verifikasi akhir: native C suite exit 0,
`flutter test test/services/automix_service` **137 lulus**, `dart test` native bridge **4 lulus**,
`dart analyze` pada layanan/test AutoMix + paket native bersih. Kotlin belum terverifikasi (tanpa Android SDK).

**Tempo lagu nyata dengan ODF pita ketukan 2026-10-30 (v1.5.61):** tiga trek `.opus` komersial yang
diunggah pengguna (227/205/200 s, decode `ffmpeg -ac 1 -ar 22050 -f f32le`) membongkar bug tempo nyata:
ODF full-band menghitung hi-hat/ghost note sebagai ketukan sehingga 2 On→200,00, Baby→175,54,
Dirty Dirty→141,98 BPM (aubio 109,54/119,43/140,69). Analyzer sekarang membangun ODF pita ketukan
(`low + 0,55×mid`) khusus untuk tempo dan fallback ke envelope lebar bila confidence <0,20; hasil final
**101,02 / 117,03 / 141,97** (tail konsisten untuk trek 2–3; trek 1 masih ~8% di bawah aubio, bukan oktaf).
Beat phase tetap memakai `phase_odf` full-band. Gate frasa turun 0,45→0,35 (waltz sempat 0,44 dan
kehilangan meter 3), dan meter 2 butuh margin 0,20 (trek 4/4 nyata sempat salah dilabeli 2). Regresi baru
`test_analyzer_waltz_meter_three_beats`; native C suite exit 0, fixture four-on-floor tetap 120/124/174.
Sisa temuan §J (A harmonic downbeat, B section masking, C chord bass-root, D head phase sparse, E L1,
F streaming decode, G SSM) belum dikerjakan.

**Downbeat harmonik & section de-trend 2026-10-30 (v1.5.61):** house four-on-the-floor datar (kick tiap
ketukan, akor per bar) kini mempublikasikan downbeat bar dari novelty akor lokal: rumah 120/124 → fase
1993,2/1929,7 ms terhadap bar 2000/1935,5 ms (error −6,8/−5,8 ms), meter tetap NaN; waltz/6/8/breakbeat
tidak berubah. Deteksi section `estimate_section_boundary_ms` sekarang men-de-trend novelty 2 s terhadap
median lokal ±16 s (laju perubahan akor), bukan median global; fixture progresi akor + drum masuk 32 s →
**32000 ms conf 1,00** (sebelumnya NaN), harmoni statis tetap 32000@1,00, loop stabil tetap tanpa batas.
Regresi C baru: `test_analyzer_harmonic_bar_downbeat_on_flat_house`,
`test_analyzer_section_boundary_survives_chord_progression`. Start phase trek sparse kini terukur finite
(257 ms) sehingga temuan D tidak lagi mereproduksi. Native C suite exit 0.

**Ground truth full-band chord roots 2026-10-30 (C ditutup):** karena tiga trek Opus tidak punya label
akor, dibuat dua fixture by-construction di `build/audit_real/gen_audio.py`: `full_band_chords.wav`
(bass root) dan `full_band_chords_inverted.wav` (bass fifth: C/G, F/C, G/D, Am/E), 120 BPM C–F–G–Am
masing-masing 4 s dengan kick tiap ketukan, snare 2/4, hat off-beat, bass sine, dan pad triad. Hasil
`nar_automix_analyze_chords`: **12/12 baris stabil benar** untuk kedua varian (root 0/5/7/9), confidence
0,51–1,00; term `0.18×chroma[root]` sudah cukup, jadi gate bass-root terpisah **tidak diperlukan**.
Baris jendela 2 s yang melintasi pergantian akor (3/7/11 s) tetap ambigu — varian root: Fmaj7 0,37 /
Dm7 0,22 / Am7 0,54; varian inversi: Am7 0,75 / Dm7 0,51 / Em7 0,25 — ini keterbatasan straddle 2 s
yang sudah ada, bukan kesalahan bass-root. Regresi baru
`test_chord_full_band_mix_keeps_harmonic_root` (12 root stabil + conf ≥0,40, dua varian); native C suite
exit 0. Sisa §J: E (L1, butuh Kotlin/CI), F (streaming decode), G (SSM).

**Single-pass streaming decode 2026-10-30 (F/D10, v1.5.62):** channel `analyzeAll` pada
`AutomixAnalysisBridge.kt` men-decode file sekali dari sample 0; `onFormat` merencanakan window (head +
middle, termasuk window tengah 241–300 s), buffer head/middle ditangkap saat stream lewat dan dianalisis
begitu penuh, tail disimpan di ring buffer berukuran satu window dan di-unwrap pada EOF aktual (durasi
container basi tidak bisa menyembunyikan akhir lagu). Peak memory = satu window + ring, bukan PCM sefile.
Dart `_analyzeSegments` memanggil satu kali; fallback per-window lama hanya untuk `MissingPluginException`
(bridge native lama). **Kotlin belum dikompilasi/diuji** karena Android SDK/Gradle tidak tersedia; klaim
percepatan scan belum diukur. Dart analyze + AutoMix 137 test lulus; native C suite tidak berubah. Sisa §J:
E (L1, butuh Kotlin/CI), G (SSM), dan validasi wall-clock F di perangkat.
