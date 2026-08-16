# Full Re-Audit — 2026-08-16 (lib + android + native_audio_runtime)

## Scope & method

Permintaan: cek seluruh kode secara mendalam di `lib/`, `android/`, `native_audio_runtime/`.

Metode:
1. **Baca penuh** seluruh sumber C native runtime (`native_audio_runtime/src/*.c|h|S` — 5.362 baris)
   + lapisan Dart FFI (`lib/*.dart` + `lib/src/*` — 2.033 baris) — verifikasi ulang penuh,
   bukan spot-check.
2. **Trace integrasi lintas-batas** untuk jalur produksi:
   Dart `PlaybackManager`/`AudioService` → FFI → C pipeline → JNI → `NativeDspAudioProcessor` (ExoPlayer),
   khususnya ReplayGain dan Loudness Normalization.
3. **Verifikasi status** semua temuan audit sebelumnya (08-12 s/d 08-16): fixed / open / note.
4. **Scan pola bug baru** di `lib/` (Timer leak, `firstWhere` tanpa orElse, `unawaited` tanpa
   error handling, `as` cast unchecked) dan `android/` (area yang belum pernah diaudit).

Baseline: `flutter analyze` → **No issues found!**. `git diff --check` → bersih.
Working tree bersih (semua fix turn kemarin sudah ter-commit di `e82f3b4`).
Keterbatasan: tidak ada Android SDK → Kotlin/C tidak dikompilasi; verifikasi statis
(konsisten dengan audit sebelumnya). NEON assembly diverifikasi dengan membaca ulang
ABI AAPCS64 + layout struct.

---

## 1. Status temuan audit sebelumnya (verifikasi ulang terhadap code aktual)

| ID | Finding | Verdict asal | Status 16/08 |
|---|---|---|---|
| RG-1 | Cache invalidation setelah removeReplayGain | FALSE POSITIVE + residual `_inFlight` | **FIXED** — `invalidate()` juga `_inFlight.remove(songId)` (`replay_gain_service/service.dart:121`) ✓ |
| RG-2 | mtime + size identity | CONFIRMED WEAKNESS (granularity FAT32/exFAT) | **OPEN (note)** — keputusan desain, tergantung device; tidak diubah |
| RG-3 | fsync() failure handling | CONFIRMED WEAKNESS (durability) | **FIXED** — `FsyncGuard::Sync` log errno (`tag_writer.cpp`) ✓ |
| K1–K13 | Kotlin audit | 2×P2 + 11×P3 | **FIXED** — K1/K2 (13/08), K3/K4/K9/K11 (batch 13/08), K5–K8/K10/K12/K13 (16/08) ✓ |
| N1–N4 | Deep audit | 4×P3 | **FIXED** — N1/N3 (16/08), N2/N4 (14/08) ✓ |
| N5 | RG playback path melewati cache Dart prefs | Note (duplikasi cache) | **OPEN (note)** — by design: jalur playback memakai SQLite native mtime-validated, jalur song-info memakai prefs Dart |
| N6 | Loudness gain target tidak update saat blok di-gate penuh | Note (known limitation) | **OPEN (note)** — didokumentasikan di header; ≤400 ms, inaudible |
| F1–F6 | Sleep timer audit | 3×P2 + 3×P3 | **FIXED** — F1–F3 (15/08), F4–F6 (16/08) ✓ |
| BP-01..BP-08 | Bit-perfect audit | 1×P1 + 4×P2 + 3×P3 | **FIXED** (16/08) ✓ |
| BP-09 | Volume per-player tidak ditransfer antar player | Note | **OPEN (note)** — diverifikasi ulang di bawah |
| L-1..L-5 | Log system audit | 2×P3 + 2×P4 + note | **FIXED** (16/08) ✓ |
| L-6 | `countByLevel` global tidak ikut filter aktif | Note | **OPEN (note)** — `log_service/service.dart:126` |
| L-7 | Ring buffer simpan stack trace penuh per error | Note | **OPEN (note)** — `LogEntry.stackTrace` penuh per error; trade-off memory vs diagnosability |

**Verdict verifikasi: 0 temuan yang seharusnya fixed ternyata masih ada.** Semua klaim
re-audit ini di-check langsung ke source (file:line di atas), bukan dari dokumen.

---

## 2. Temuan baru (turn ini)

### NR-1 (P3) — CONFIRMED WEAKNESS — Per-stream ReplayGain gain tidak pernah dipakai dari Dart → crossfade overlap memakai gain lagu SEBELUMNYA

**File/class/line:**
- `native_audio_runtime/lib/src/dsp_pipeline_io.dart` — `NativeReplayGain.setGain` → `bindings.nar_replaygain_set_gain` (shared, kedua stream)
- `native_audio_runtime/src/replaygain_processor.c` — `nar_replaygain_set_gain_for_stream` (per-stream, sudah ada di C tapi **tidak diekspos** ke Dart)
- `lib/services/audio/playback_manager.dart:605-621` — `setNativeReplayGain` → shared API
- `lib/services/audio_service/replay_gain_applicator.dart:52` — satu-satunya pemanggil gain
- `lib/services/audio_service/service.dart:442` — `apply()` hanya di track-transition

**Exact execution path (reachable):**
1. Crossfade aktif (`crossfadeDurationSec > 0`), ReplayGain mode ON (bukan off), dua lagu
   berurutan dengan nilai gain RG berbeda (sangat umum — track gain per lagu).
2. User skip → `preloadManager.preloadNextTrack()` → standby ExoPlayer (stream slot 1)
   mulai memainkan lagu berikutnya SELAMA lagu sekarang masih fade-out di primary (slot 0).
3. Stream 1 memproses audio lewat `nar_dsp_pipeline_process_raw_stream(..., stream_slot=1)`
   → `_rg_process` membaca `_gain_bits[1]`.
4. `_gain_bits[1]` masih berisi gain **lagu sebelumnya** — `nar_replaygain_set_gain` terakhir
   dipanggil saat transisi track terakhir (shared, menulis kedua slot), dan `apply()` untuk
   lagu baru baru dijalankan saat **promotion** (event `currentTrack`), bukan saat standby start.
5. Hasil: lagu berikutnya terdengar dengan gain salah selama seluruh window preload + fade-in
   (durasi crossfade, mis. 5–8 s), lalu gain melompat (step) saat `apply()` mendarat.

**Counter-evidence:** perbedaan hanya terdengar saat nilai gain kedua lagu berbeda; dengan
LoudnessNorm aktif, RG didefer ke preamp saja (tidak terdampak). Severity P3 (audible,
window pendek, tidak merusak).

**Rekomendasi:** ekspos `nar_replaygain_set_gain_for_stream` di facade Dart; panggil
`apply()` saat standby mulai preload (bukan saat promotion) dengan stream slot yang sesuai —
native side sudah siap (NAR-4), tinggal plumbing.

### NR-2 (P3) — CONFIRMED WEAKNESS — Reset loudness analyzer stream-0 only; `nar_loudness_reset_stream` tidak diekspos

**File/class/line:**
- `native_audio_runtime/src/loudness_processor.c` — `nar_loudness_reset()` (stream 0 only), `nar_loudness_reset_stream()` (ada, tidak dipakai)
- `native_audio_runtime/lib/src/dsp_pipeline_io.dart` — `NativeLoudnessNorm.reset()` → `nar_loudness_reset` (stream 0)
- `lib/services/audio_service/service.dart:437` — `resetNativeLoudnessNorm()` saat track change

**Execution path:** crossfade aktif + Loudness Norm ON → standby (stream 1) mulai track baru
tanpa reset; state gating ring-nya bisa membawa history dari track standby sebelumnya (bila
sample rate sama, lazy-reset di `_ensure_sample_rate` tidak terpicu). Analisa tercemar
≤ 1 gating block (400 ms) → gain sementara salah, self-correcting.

**Counter-evidence:** inaudible pada praktiknya (self-correct ≤ 400 ms, alpha release 3 s
memperhalus). Keterbatasan ini sudah didokumentasikan eksplisit di file header.

**Rekomendasi:** sama dengan NR-1 — ekspos `reset_stream(slot)` dan panggil dari sisi
crossfade Dart yang tahu slot assignment.

### NR-3 (P4) — Note — Capability table tidak akurat

**File/line:** `native_audio_runtime/src/native_audio_runtime.c` `kCapabilities[]`.

- `{"dsp.equalizer", 1}` — tetapi PEQ native 32-band **sudah dihapus** (facade Dart:
  "the native 32-band Parametric EQ (Phase 5) was removed — the Band EQ feature now uses
  only the legacy Android system Equalizer"; tidak ada `peq_processor.c` di `src/`).
  Capability ini **berbohong** terhadap implementasi aktual.
- `{"scan.loudness_ebur128", 0}` — padahal `loudness_processor.c` mengimplementasikan
  pengukuran EBU R128 / BS.1770-4 penuh (real-time). Nilai 0 defensible ("scan" = offline
  scan vs real-time) tapi menyesatkan.
- Version string `"0.1.0-phase8"` sudah obsolete (fase terakhir yang diimplementasi: 8.5).

Tidak ada konsumen yang mengambil keputusan dari tabel ini (informatif untuk debug page),
jadi dampak nol — murni hygiene.

### NR-4 (P4) — Note — Doc drift slot numbering Dart vs C header

**File:** `native_audio_runtime/lib/src/dsp_pipeline_io.dart` (`initialize()` comments) vs
`comp_processor.h` / `crossfeed_processor.h` / `limiter_processor.h` / `soft_clipper_processor.h`.

Dart comment: "Compressor (slot 3)", "Crossfeed (slot 5)", "Limiter (slot 6)",
"Soft Clipper (slot 7)". Header C: compressor "after dsp.loudness", crossfeed "slot 3
(after dsp.compressor, before dsp.limiter)", limiter "slot 3", soft_clipper "slot 4
(last in the chain)". Urutan registrasi aktual di Dart: gain, replaygain, loudness, comp,
crossfeed, limiter, soft_clipper → soft_clipper adalah slot ke-6 (0-indexed), bukan 4.
Murni komentar; tidak mempengaruhi runtime (registrasi berurutan & id-based).

### NR-5 (P4) — Note — `dsp.pipeline` comment "Dart owns lifecycle" tidak sepenuhnya akurat

**File:** `native_audio_runtime/src/native_dsp_jni.c` header comment: "Dart — owns lifecycle:
... and dispose()". `dsp_pipeline_dispose()` dipanggil dari `NativeDspPipeline.dispose()`.
Namun `native_runtime_dispose()` juga di-expose — tidak ada pemanggil ganda yang ditemukan.
Tidak ada bug; catatan dokumen.

---

## 3. Open findings lama (diverifikasi ulang, tetap open, semua note-level)

| ID | Status + evidence |
|---|---|
| **BP-09** | Masih open. `TransportCommands.kt:272-276` `setVolume` hanya `p.volume = vol` (player aktif) + `audioFocusManager.setUserVolume(vol)` yang hanya merekam `volumeBeforeDuck` (`AudioFocusManager.kt:200-205`). `ActivePlayerProxy.switchTo` (baris 75-113) **tidak** menyalin volume. Setelah crossfade promotion, player hasil promotion memakai volume default-nya (1.0) — volume user < 1.0 hilang sampai user menyentuh slider lagi. Note: hanya relevan jika volume slider < 1.0 dipakai. |
| **N5** | Open (by design). `loudness_source_resolver.dart:30` → `resolveBoth` → `_readRawTags` (channel `getReplayGainTags`). Dua cache terpisah (prefs Dart vs SQLite native); jalur playback memakai SQLite (mtime-validated) — benar. |
| **N6** | Open (documented). `loudness_processor.c` gating block — gain tidak diupdate saat seluruh blok di-gate. ≤400 ms, inaudible. |
| **L-6** | Open. `log_service/service.dart:126` `countByLevel` global; badge AppBar tidak ikut filter. Kosmetik. |
| **L-7** | Open. Stack trace penuh per error di ring buffer 5000 entri. Trade-off memory. |

---

## 4. Verified strengths (setelah baca penuh native runtime)

- **C pipeline** — lock-free hot path; per-stream state (NAR-4/NAR-5) untuk envelope/delay/filter
  history; dirty-flag acquire/release per stream; NaN/Inf sanitize di SETIAP stage + fail-open;
  chain tidak berhenti saat satu processor error (limiter/clipper safety net selalu jalan).
- **NEON kernel** (`neon_kernels.S`) — ABI AAPCS64 diverifikasi ulang: argumen campuran
  pointer/float di-register-file terpisah, `ld1r`/`ins`/`fmls` benar; TDF-II 2-lane benar;
  `NarBiquadCoeffs` 5×float kontigu tanpa padding → cocok dengan `const float*` kernel.
- **JNI boundary** — `nativeProcessFloat` validasi capacity (`GetDirectBufferCapacity`) sebelum
  `GetDirectBufferAddress` (N4 fix tetap ada); fail-open NOT_INITIALIZED → passthrough.
- **Lifecycle** — `_initialized` atomic guard di init/dispose/process (NAR-2); reset defensive
  terhadap vtable null (NEW-02); pipeline fail-open saat dispose race.
- **Jalur ReplayGain/Loudness di Dart** — `_ReplayGainApplicator` fail-open total (try/catch
  mengelilingi seluruh body), mutual exclusion LoudnessNorm vs LoudnessEnhancer sistem,
  preamp + clipping protection diteruskan ke native, `catchError` untuk async errors
  (LOW-06), sample-rate sync via `audioFormatStream`.
- **Log page** — debounce 150 ms benar (Timer di-cancel di `dispose`, `mounted` guard,
  `_expanded` di-prune via `LogService.contains`).
- **Pattern scan lib/** — tidak ada Timer leak (semua file dengan `Timer(` punya `.cancel()`),
  semua `firstWhere` punya `orElse`, `unawaited` tanpa `catchError` hanya untuk channel
  calls yang tidak throw bermakna. `safe_num.dart` menutup celah `NaN.toInt()` di tick
  boundary native.

---

## 5. Test gap

- Tidak ada test untuk per-stream RG gain / loudness reset pada crossfade (NR-1/NR-2) —
  bisa di-unit-test di C dengan memanggil `nar_replaygain_set_gain_for_stream(0/1, ...)`
  dan memverifikasi `_gain_bits[0] != _gain_bits[1]`.
- `native_audio_runtime/test/` tidak bisa dijalankan dari root (dev-deps nested package
  belum ter-install); perlu `cd native_audio_runtime && flutter pub get`.
- Kotlin unit test tetap tidak bisa dijalankan tanpa Android SDK.
- Tidak ada device test untuk BP-09 (volume setelah crossfade promotion) dan RG-2 (mtime
  granularity exFAT) — dua-duanya butuh Mi 9T/MIUI 12.

---

## 6. Verification

- `flutter analyze` → **No issues found!** (3.8 s)
- `git diff --check` → bersih
- Tidak ada kode yang diubah pada audit ini (read-only, konsisten dengan konvensi audit
  sebelumnya).

---

## 7. Kesimpulan

Setelah baca penuh ketiga area, kualitas keseluruhan **tinggi dan konsisten dengan audit
sebelumnya**: semua temuan P1/P2/P3 yang dilaporkan sebelumnya sudah ter-fix dan terverifikasi
di source; tidak ditemukan bug produksi baru yang reachable.

Yang tersisa:
- **2 temuan baru P3 (CONFIRMED WEAKNESS)** — NR-1 (per-stream ReplayGain gain tidak
  dipakai → gain salah selama crossfade overlap) dan NR-2 (reset loudness stream-0 only).
  Keduanya adalah *residual yang sudah didokumentasikan* dari hardening NAR-4/NAR-5: sisi C
  sudah siap (`nar_replaygain_set_gain_for_stream`, `nar_loudness_reset_stream`), yang
  kurang hanya plumbing ekspos facade Dart + pelacakan stream slot di sisi crossfade Dart.
- **3 temuan P4/note baru** — capability table tidak akurat (NR-3), doc drift slot (NR-4/NR-5).
- **6 note open lama** (BP-09, N5, N6, L-6, L-7, RG-2) — semuanya keterbatasan yang sudah
  didokumentasikan atau by design; tidak ada yang perlu fix mendesak.

Rekomendasi prioritas jika mau lanjut: NR-1 → NR-2 (fix nyata, kecil, native side sudah
siap) → NR-3 (hygiene 5 baris). Sisanya opsional.

---

## Fix log — 2026-08-16 (NR-1 + NR-2)

Kedua temuan P3 di atas sudah diperbaiki. Ringkasan perubahan (9 file, +260/−14):

**Plumbing per-stream (facade Dart + bindings + stubs):**
- `native_audio_runtime/lib/native_audio_runtime_bindings_generated.dart` — ekspos
  `nar_replaygain_set_gain_for_stream(streamSlot, gainDb, peakLinear, useClip)` dan
  `nar_loudness_reset_stream(streamSlot)` (file hand-maintained; tetap sinkron dengan C header).
- `native_audio_runtime/lib/src/dsp_pipeline_io.dart` — `NativeReplayGain.setGainForStream(...)`
  dan `NativeLoudnessNorm.resetStream(streamSlot)`; stub web matching di
  `dsp_pipeline_unsupported.dart`.
- `lib/services/audio/playback_manager.dart` — `setNativeReplayGainForStream(...)` dan
  `resetNativeLoudnessNormForStream(slot)` (keduanya lewat `_dspGuard`, fail-open);
  `resetNativeLoudnessNorm()` kini reset **kedua** slot (dipakai hanya saat fitur dimatikan).

**Pelacakan stream slot (native → Dart):**
- `android/.../utils/TrackMapper.kt` — map `currentTrack` kini membawa `"streamSlot"`
  (slot fisik player aktif: primaryPlayer=0, secondaryPlayer=1).
- `android/.../transport/TransportState.kt` — param `getActiveStreamSlot` (default 0),
  di-wire `Media3PlaybackService.kt` dari `activePlayer === secondaryPlayer`.

**Wiring crossfade (Dart):**
- `lib/services/audio_service/service.dart` — `_syncCurrentTrackFromNative` menerima
  `activeSlot`; loudness reset + RG apply saat promotion kini menarget slot aktif
  (sebelumnya selalu stream 0). Helper baru `_preloadStandbyDsp(nextIndex, activeSlot)`:
  begitu `nextTrackIndex` diketahui (track start / next berubah), gain RG + reset loudness
  lagu berikutnya langsung di-pre-apply ke slot standby (`1 - activeSlot`, invariant native
  `setStandbyPlayer`) — window preload + fade-in tidak lagi memakai gain lagu sebelumnya.
- `lib/services/audio_service/replay_gain_applicator.dart` — `apply(..., streamSlot)` opsional:
  slot diketahui → per-stream; `null` → shared knob (setting change / single-player).

Verifikasi: `flutter analyze` (root) → No issues found; `dart analyze lib` (nested package)
→ No issues found; `git diff --check` bersih. Kotlin tidak dikompilasi (tidak ada Android
SDK di environment) — perlu `./gradlew :app:compileDebugKotlin` di mesin dengan SDK.

---

## Fix log 2 — 2026-08-16 (NR-3, NR-4, NR-5, BP-09, L-6, L-7)

Sisa temuan note-level ditutup:

- **NR-3 (capability table)** — `native_audio_runtime/src/native_audio_runtime.c`:
  `dsp.equalizer` → 0 (PEQ 32-band sudah dihapus; Band EQ memakai Equalizer sistem),
  `scan.loudness_ebur128` → 1 (loudness_processor.c mengimplementasikan EBU R128/BS.1770-4
  real-time), version string `0.1.0-phase8` → `0.1.0-phase8.5`.
- **NR-4 (doc drift slot)** — komentar slot C header + facade Dart dikoreksi ke urutan
  registrasi aktual: gain=0, replaygain=1, loudness=2, comp=3, crossfeed=4, limiter=5,
  soft_clipper=6. NR-5: komentar ownership `native_dsp_jni.c` diperjelas.
- **BP-09 (volume antar player)** — `ActivePlayerProxy.switchTo()` kini menyalin
  `_current.volume` ke player baru. Menutup gap bit-perfect: clean player (volume default
  1.0) dan restored player (volume stale) sekarang volume-transparent saat toggle mode;
  crossfade tidak terpengaruh (standby di-zero sebelum switchTo dan fade mengambil alih
  volume pada tick berikutnya).
- **L-6 (badge filter)** — `LogService.countByLevel` menerima `category`/`search`;
  LogPage melewati filter aktif → chip jumlah level + chip ALL konsisten dengan daftar.
- **L-7 (memori stack trace)** — `LogService.log` membatasi stack trace per entri
  (head 3000 char + marker truncation) → worst case ring buffer 5000 entri tidak lagi
  bisa membengkak puluhan MB.

Sisa open (by design / device-dependent, tidak diubah): RG-2 (granularitas mtime FAT32/
exFAT), N5 (dua cache), N6 (gating block ≤400 ms).
