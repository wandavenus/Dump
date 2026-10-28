# AutoMix audit v8 — metrical & perceptual modelling

**Tanggal:** 2026-10-28 · **Sifat:** audit + rekomendasi, **tanpa perubahan kode**.
**Laporan lengkap:** `automix_implementation_audit_v8.md` (root repo).
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
