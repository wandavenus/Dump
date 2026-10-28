# AutoMix audit v8 — metrical & perceptual modelling

**Tanggal:** 2026-10-28 · **Sifat:** audit + rekomendasi (awalnya tanpa perubahan kode), lalu remediasi v1.5.55.
**Laporan lengkap:** `automix_implementation_audit_v8.md` (root repo, bagian H berisi status remediasi).
**Pendahulu:** `automix-audit-v7.md` (timing/phase). v8 mulai dari lapisan *musical intelligence* yang belum
diperiksa v7: metrical level, bar phase, key, loudness, kalibrasi skor, dan kesepakatan grid live vs offline.

## Bukti

Probe C (`build/audit_tmp/`, git-ignored) dikompilasi terhadap sumber asli
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
| AM8-02 | **Partial** | `AutomixGridMerge` tidak lagi memilih live hanya karena confidence lebih tinggi: saat tempo beda >4% log, grid offline selalu menang; phase live hanya dipakai bila phase-nya setuju (≤0.25 beat). Live confidence diberi cap 0.55 (½) / 0.30 (⅓) saat ada peak sub-multiple kuat, dan flux live kini low/mid/high-weighted. Estimator live masih ACF terpisah (belum dipakai bersama dengan offline) dan rescue masih satu arah. |
| AM8-03 | **Partial (offline)** | Grid frasa offline menambah bukti chroma novelty per frame; novelty hanya dipakai bila punya periodisitas 16-beat (contrast ≥0.25). Downbeat live tetap berbasis aksen sehingga four-on-floor live masih 0.000; karena merge kini memilih offline, dampaknya berkurang. |
| AM8-04 | **Fixed** | ODF phase dipisah per band (30–150 Hz bobot 1.0, 150–1500 Hz 0.55, 1500–8000 Hz 0.15); beat phase memakai `phase_odf`, tempo/frase tetap memakai ODF penuh. |
| AM8-05 | **Fixed** | Key: gate entropi + minimal 3 kelas, pencarian tuning ±50 sen (5 sen step), confidence = bukti absolut × margin × flatness × penalti relatif mayor/minor; gate pitch shift dinaikkan 0.55→0.70; hard reject harmoni di cue dihapus (harmoni hanya di planner). |
| AM8-06 | **Fixed** | Koefisien energi Dart + C dinormalisasi ke 1.0 (0.22/0.40/0.18/0.10, momentum cap 0.10); clamp tinggal guard. |
| AM8-07 | **Open** | Belum ada hipotesis meter 3/6; bar live tetap 4 beat, frasa 16 beat. |
| AM8-08 | **Partial** | Kualitas 7th hanya diterima bila ada energi nyata di partial ke-7; gate keras `keyCost`/`chordCost` di cue dihapus. Gap confidence di titik pergantian chord belum diperbaiki. |
| AM8-09 | **Fixed** | `AutomixTransitionPolicy.boundedFadeLeadMs` membatasi fade hasil phrase snap ke `plannedFade + ½ beat` dan tidak melewati EOF; dipakai `CrossfadeController` pada jalur non-early. |
| AM8-10 | **Fixed** | Density scaling mengalikan jumlah beat (bukan detik), lalu kuantisasi ½ beat; fade dihitung ulang setelah cap 1.5–12 s (kecuali structureAligned yang memang terikat boundary). |
| AM8-11 | **Partial** | Cooldown artis diturunkan menjadi tie-breaker 0.04/0.02; `variety` tetap sebagai mekanisme utama agar parity Dart/native tidak berubah. |
| AM8-12 | **Partial** | File 241–300 s menambah satu jendela tengah bila gap >30 s. Struktur masih label per-window, belum segmentasi track. |
| AM8-13 | **Open (sengaja)** | L1 headroom tidak diubah: perlu pengukuran loudness seam pada audio nyata sebelum melepas proteksi clipping. |
| AM8-14 | **Fixed** | `alternateBpm` = runner-up hipotesis metrikal, bukan tebakan <90/>140. |
| AM8-15 | **Fixed** | Vocal menjadi sub-cost berbobot 0.10 di dalam denominator yang sama. |

Cache analysis dinaikkan ke **schema v19** karena tempo/grid/key/chord dapat berbeda dari v18.

Verifikasi: native C suite (`automix_native_c_test.c`) **exit 0**, termasuk sweep metrikal 60–200 BPM,
beat phase dengan off-beat hat, key noise/detune, dan phrase phase dari perubahan harmoni. `dart analyze` pada
`engine.dart`, `service.dart`, dan test AutoMix: bersih. Sweep syntetik pasca-fix: four-on-floor **27/27 benar**
(sebelumnya 15/27); backbeat-only 4/27 (ambiguitas half/double tetap, `alternateBpm` membawa level lain);
syncopated 14/27 benar, hanya 12/27 dengan conf ≥0.20 (level ambigu ditahan, bukan ditebak); pad-only bukan
sinyal ritmis. `flutter test` **tidak dapat dijalankan** di workspace ini (disk 100%, test compiler `ENOSPC`);
Kotlin/Gradle juga tidak tersedia. Jangan mengklaim lulus sebelum dijalankan di CI/devcontainer.
