# Audit Implementasi AutoMix — v2 (2026-10-18)

**Status:** Audit v1 (statis) selesai; audit lanjutan v2 menemukan 6 temuan baru dan seluruh rekomendasi P1/P2/P3 telah **diterapkan sebagai perubahan working tree** di atas SHA audit.  
**Repository:** `wandavenus/Dump`  
**Branch:** `main`  
**Revisi kode audit v1:** [`f841a4a`](https://github.com/wandavenus/Dump/commit/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b)  
**Revisi kode audit v2 (HEAD):** [`fadb0bd`](https://github.com/wandavenus/Dump/commit/fadb0bddc40eb7287b0197262d72b5423a5a1d66) — "Bound AutoMix startup feature loading to near tracks"  
**Perbaikan v2:** diterapkan pada working tree setelah `fadb0bd` (belum di-commit saat laporan ini ditulis; 12 file berubah).  
**Cakupan:** Dart planning/cache/settings/gating, bridge MethodChannel, PCM decode/downsample, JNI, native analyzer/planner/live beat tracker/tone DSP, Kotlin dual-player preload/crossfade, ARM64 NEON, tests, dan CI.

> Laporan ini menilai source pada SHA di atas ditambah patch working tree yang menyertainya. Verifikasi eksekusi (Flutter/Kotlin/C) harus dilakukan lewat dispatch workflow; laporan ini tidak melakukan pengukuran audio hasil render di perangkat fisik.

## Ringkasan eksekutif

Audit v1: 5 temuan (2 bug perilaku, 1 trade-off desain, 1 celah gating, 1 celah validasi). Status setelah 10 commit lanjutan dan patch v2 ini:

| ID | Severity | Topik | Status |
|---|---|---|---|
| AM-01 | Sedang | Arah kurva fade `gamma` terbalik dari makna strategi | ✅ Fixed (`t^(1/gamma)`) + tes arah kurva |
| AM-02 | Sedang | Analisis PCM multichannel hanya memakai kanal L/R | ✅ Fixed (downmix berbobot semua kanal) + tes center/surround |
| AM-03 | Sedang — trade-off | Fader L1 menurunkan RMS ~3 dB di tengah fade | ⚠️ Terbuka (keputusan produk) — kini didokumentasikan eksplisit |
| AM-04 | Rendah | Library sweep berjalan saat Bit-Perfect aktif | ✅ Fixed (entry, antar-lagu, re-arm) + tes |
| AM-05 | Sedang — validasi | Runnable crossfade & ARM64 NEON belum dieksekusi di runtime | ◐ Sebagian besar tertutup (C11/C12, qemu ARM64 di CI); capture perangkat tetap deferred |

Temuan baru v2 (dari audit lanjutan HEAD → patch):

| ID | Severity | Topik | Status |
|---|---|---|---|
| NEW-1 | Sedang | Tick posisi 200 ms mem-bypass pacing resume analisis | ✅ Fixed |
| NEW-2 | Sedang | `analyzeLibrary` tidak di-gate Bit-Perfect | ✅ Fixed + tes |
| NEW-3 | **Tinggi** | Abort mid-fade Kotlin melewati seluruh cleanup cancel | ✅ Fixed + tes C11 |
| NEW-4 | Sedang | Suite C AutoMix tidak dikompilasi di CI repo; tes disable vacuous | ✅ Fixed (CI + tes baru) |
| NEW-5 | Rendah | `nativeFadeAvailable = false` — jalur fade native dead code | ⚠️ Keputusan: dipertahankan (terdokumentasi) |
| NEW-6 | Rendah | `startAutomix` dead code (caller UI dihapus) | ✅ Hardened (bukan dihapus) + docs |

---

## 1. Status temuan v1

### AM-01 — Arah kurva `gamma` ✅ Fixed

`AutomixGainEnvelope.kt:27-33` kini membentuk progress sebagai `t^(1/gamma)` dengan clamp `[0.6, 1.6]`: `gamma > 1` mempercepat handover (incoming naik lebih cepat), konsisten dengan makna strategi quick/short vs long blend. Helper native C memakai definisi yang sama. Regresi arah kurva ada di `AutomixIntegrationTest.kt:89` (membandingkan gain incoming 0.25/0.5/0.75 untuk gamma di atas dan di bawah 1). Semantik ini kini juga dicatat di `docs/automix-production-wiring.md` §4.

### AM-02 — Downmix multichannel ✅ Fixed

`AutomixPcmDownsampler.kt:62-102` melakukan downmix berbobot semua kanal (1–8) sebelum low-pass: bobot berbasis RMS halus per kanal, kanal nyaris senyap diabaikan tanpa menipiskan materi L/R-only, lalu fallback anti-phase ke kanal dominan. Tes `AutomixPcmDownsamplerTest.kt:86-98` memastikan konten center-only dan surround-only pada 5.1 tidak mengalami atenuasi (ambang 80% dari baseline mono).

### AM-03 — Headroom L1 (~3 dB di tengah fade) ⚠️ Terbuka, terdokumentasi

Perilaku tidak diubah (masih keputusan produk). Yang berubah: `docs/automix-production-wiring.md` §4 kini menyatakan eksplisit bahwa untuk materi tidak berkorelasi, L1 budget menurunkan level hingga ~3 dB di tengah fade, dan alasan mempertahankannya (dua deck bisa berkorelasi fase; downstream AudioFlinger mix tanpa limiter post-mix bersama). Rekomendasi tetap: putuskan lewat listening test / evaluasi limiter bus bersama, bukan menghapus pembatas L1.

### AM-04 — Gating Bit-Perfect pada sweep & analisis ✅ Fixed

Tiga lapis kini ada di `service.dart`:
- `analyzeLibrary` menolak sejak entry saat Bit-Perfect aktif (`service.dart:1842-1850`) dan berhenti antar-lagu (`service.dart:1865`);
- `_runLibrarySweepPass` memeriksa mode di entry, antar-decode (`service.dart:2024`, `2028`) dan re-arm tidak menimpa timer yang lebih pendek (`service.dart:2074`);
- `_onBitPerfectModeChanged` membatalkan pipeline berjalan (bump generasi), membersihkan timer, dan menyetel `automixActive = false` (`service.dart:187-218`).

Tes `automix_integration_test.dart` mencakup siklus sweep stop/resume dan penolakan batch eksplisit sebelum decode.

### AM-05 — Validasi runtime crossfade & NEON ◐ Sebagian besar tertutup

Sudah ada sejak sebelum patch: test deterministik dengan clock/scheduler terinjeksi (`CrossfadeControllerTest.kt`, grup C/F sampai C10 termasuk budget headroom L1 dan auto-cancel tick). Patch v2 menambah:
- tes abort dan completion penuh (C11/C12, lihat NEW-3);
- eksekusi jalur NEON ARM64 di CI lewat cross-compile + `qemu-aarch64-static` (lihat NEW-4);
- tes live tracker dengan click train non-nol (lihat NEW-4).

Yang tetap deferred: smoke/instrumentation test dual-player dengan PCM capture di perangkat fisik dan listening test. Build ARM64 APK tetap hanya bukti kompilasi.

## 2. Temuan baru v2

### NEW-3 (Tinggi) — Abort mid-fade melewati cleanup cancel ✅ Fixed

**Lokasi:** `CrossfadeController.kt:678-699` (sebelum) → `:696-704` (sesudah).

**Bukti / root cause:** ketika player aktif berubah di tengah fade (mis. pengguna memilih lagu lain — takeover eksternal), runnable fade masuk ke cabang abort. Cabang itu me-reset flag dan gain AutoMix, tetapi **tidak** memulihkan volume deck pengganti, tidak melepas indeks preload milik promosi yang dibatalkan, tidak memperbaiki timeline satu-item hasil promosi, dan tidak memberi tahu service — berbeda dari `cancel()` (`:394-402`). Akibatnya deck pengganti bisa tertinggal pada volume duck, `preloadManager` menunjuk track yang salah, navigasi next/prev terkunci pada timeline satu item, dan update target AutoMix yang ditunda tidak pernah dikuras.

**Dampak:** bug audible/UX pada takeover eksternal saat fade berjalan; sebelumnya tidak tertangkap karena test hanya mencakup `cancel()`.

**Perbaikan:** cabang abort kini melakukan cleanup setara cancel: `getActivePlayer()?.volume = getVolumeBeforeDuck().coerceIn(0f, 1f)`, `preloadManager.resetPreloadedIndex()`, `rebuildPromotedQueue()`, `onCrossfadeCancelled()` (drain update tertunda di service). Tes `C11 abort mid-fade is a full cancel (volume, preload, queue, callback)` memverifikasi keempat efek; `C12 fade completion lands on full volume without cancellation` mengunci sisi sebaliknya (completion normal tetap penuh tanpa cancel).

### NEW-1 (Sedang) — Tick posisi 200 ms mem-bypass pacing resume analisis ✅ Fixed

**Lokasi:** `service.dart:294-309`.

**Bukti / root cause:** `_checkPlaybackStateForAutoMix` dipanggil pada setiap perubahan state termasuk tick posisi 200 ms. Sebelum patch, panggilan itu selalu menjalankan `_autoAnalyzeUpcomingTracks(...)`, sehingga timer resume ter-paced (`_analyzeTimer`) dapat di-bypass oleh tick berikutnya — pekerjaan analisis berjalan lebih cepat dari pacing yang disengaja (boros decode/disk saat playback normal).

**Perbaikan:** saat `_analyzeTimer` aktif, hanya perubahan queue nyata (`queueChanged`) yang boleh memicu analisis langsung; selain itu pass berikutnya diserahkan ke timer (`resumePending && !queueChanged ? false : await _autoAnalyzeUpcomingTracks(...)`).

### NEW-2 (Sedang) — `analyzeLibrary` tidak di-gate Bit-Perfect ✅ Fixed

**Lokasi:** `service.dart:1840-1850` (entry), `:1865` (antar-lagu).

**Bukti / root cause:** scan perpustakaan yang dipicu pengguna tetap berjalan saat Bit-Perfect aktif — kelas masalah yang sama dengan AM-04, tetapi jalur eksplisit ini tidak ikut digating. Decode massal bersaing dengan decoder Bit-Perfect.

**Perbaikan:** penolakan sejak entry sebelum progress diumumkan, plus berhenti antar-lagu (progress `cancelled: true`) bila mode menyala di tengah scan. Tes baru: `Bit-Perfect mode rejects explicit library analysis before decoding` (memastikan readout progress tidak tersentuh sama sekali).

### NEW-4 (Sedang) — Suite C tidak dikompilasi di CI repo; tes disable vacuous ✅ Fixed

**Lokasi saat audit awal:** `.github/workflows/native-tests.yml`, `native_audio_runtime/test/automix_native_c_test.c`. Workflow kemudian dipindahkan ke `wandavenus/Noisegraph/.github/workflows/test-suite.yml` (job `native-c`).

**Bukti / root cause:** workflow native hanya menjalankan `flutter test` (yang memuat library build eksternal/Noisegraph) — suite C in-repo (`automix_native_c_test.c` + sumber `automix_*`) tidak pernah dikompilasi langsung oleh repo ini. Selain itu, tes disable tracker lama hanya mengirim audio senyap, sehingga "state nol setelah disable" juga benar bila tracker memang tidak pernah menghasilkan apa pun — asersinya vacuous.

**Perbaikan:** workflow kini membangun dan menjalankan suite C in-repo:
- x86_64 + `-fsanitize=address,undefined`;
- ARM64 via `aarch64-linux-gnu-gcc` (dengan `automix_neon.S` + `automix_tone_neon.S`) dieksekusi dengan `qemu-aarch64-static`, sehingga jalur NEON benar-benar dijalankan.

Tes `test_live_tracker_disable_clears_live_state` kini mengirim click train 120 BPM 8 detik, menegaskan tuple hidup non-nol (BPM 100–140, confidence > 0), lalu menegaskan disable (termasuk disable idempoten) mengosongkan tuple dan re-enable tidak membangkitkan fase lama.

### NEW-6 (Rendah) — `startAutomix` dead code ✅ Hardened

**Lokasi:** `service.dart:1338-1460`; klaim dokumen lama di `docs/automix-production-wiring.md` §2.

**Bukti / root cause:** caller UI dihapus di commit `4083ddf`, tetapi `startAutomix` tetap publik dan diklaim dokumen sebagai "production planning path". Fungsi ini juga tanpa guard pass bersamaan, tanpa penanganan error (exception lolos ke pemanggil), dan tidak mencatat signature native sehingga pass otomatis berikutnya bisa membangun ulang decoder standby untuk plan yang identik.

**Keputusan:** pertahankan sebagai entry one-shot eksplisit (bukan hapus), dengan hardening: menolak saat `_autoMixPreparing || _autoMixCheckRunning`, membungkus seluruh eksekusi `try/catch` → `-1`, mencatat `_lastNativeSignature` via `_nativePlanSignature(...)` setelah `setAutomixTransition` sukses, dan me-reset `_replanRetryCount`. Dokumen §2 kini menyebut pipeline otomatis sebagai jalur produksi dan status `startAutomix` yang sebenarnya.

### NEW-5 (Rendah) — `nativeFadeAvailable = false` ⚠️ Keputusan: dipertahankan

`CrossfadeController.kt:490` tetap mematikan envelope native per-sample; produksi memakai ramp Kotlin dengan skala headroom bersama per tick (komentar `:481-489` menjelaskan alasan konsistensi headroom dua deck). Jalur native dipertahankan untuk masa depan dan kini generasi target-nya ikut di-reset (`setAutoMixFadeGain(current/standby, 1f)` sebelum fade). Tidak ada perubahan perilaku.

## 3. Temuan minor (M-xx) — semuanya diperbaiki

| ID | Temuan | Perbaikan |
|---|---|---|
| M-01 | `nar_automix_live_tracker_get` bisa membaca tuple BPM/fase/confidence campuran antar-estimasi (torn read) | Seqlock + writer try-lock non-blocking (`automix_live_tracker.c:45-84, 123-141, 386-414`); audio callback tidak pernah memblokir |
| M-02 | `set_enabled` disable non-atomik (dua thread bisa double-bump generasi) | CAS `1→0`; yang kalah tetap mengembalikan sukses (`:96-116`) |
| M-03 | `nar_automix_live_tracker_reset` tidak menaikkan epoch; hasil callback in-flight bisa republish fase pra-reset | Bump generasi + clear ber-lock (`:420-429`) |
| M-04 | Re-arm sweep di `finally` bisa menimpa timer lebih pendek yang baru dipasang | Hanya re-arm bila `_sweepTimer` tidak aktif (`service.dart:2072-2076`) |
| M-05 | `_autoAnalyzeUpcomingTracks`/`_scheduleAnalysisResume` menelusuri seluruh tail antrian | Kandidat dibatasi ke jendela plan (shuffle-aware next + `automixPlanWindow`) |
| M-06 | `_checkPlaybackStateForAutoMix` tanpa penanganan error (berjalan `unawaited`) | `on Object catch` + logging, flag tetap dibersihkan di `finally` |
| M-07 | `resetInMemoryState` tidak me-reset flag pass berjalan (`_autoMixCheckRunning`, `_autoMixPreparing`, `_autoAnalyzeRunning`, `_sweepRunning`) | Semua flag di-reset (sengaja bukan `_analysisFuture`) |
| M-08 | Live tracker tetap aktif saat durasi crossfade 0 (tidak ada fade yang mungkin) | Gate `trackerActive = transitionActive && crossfadeDurationSec > 0` di `applyAutomixTransitionNow` |
| M-09 | `AutomixAnalysisBridge` meneruskan NaN `startSeconds`/`maxSeconds` ke decoder & stempel chord | Sanitasi di entry; decode dan stempel chord memakai nilai yang sama (`AutomixAnalysisBridge.kt:60-73, 159`) |
| M-10 | NEON tone: `cbz` hanya menangkap 0; frames negatif spin ~4 miliar iterasi | `cmp w1, #0; b.le` (`automix_tone_neon.S:42-46`) |
| M-11 | Bit-Perfect ON tidak meng-invalidasi pass AutoMix in-flight yang bisa republish target setelah switch engine | Bump generasi + `automixActive = false` + reset retry (`service.dart:187-204`) |

## 4. Perubahan pengujian & CI (ringkas)

- **Kotlin:** `CrossfadeControllerTest` — harness dapat mensimulasikan takeover eksternal (`activePlayerState`), menghitung `onCrossfadeCancelled`; tes baru **C11** (abort = cancel penuh) dan **C12** (completion penuh tanpa cancel).
- **C native:** tes baru `test_live_tracker_disable_clears_live_state` (click train 120 BPM, tuple hidup → disable → nol, re-enable bersih).
- **Dart:** tes integrasi baru untuk gate Bit-Perfect `analyzeLibrary`.
- **CI (setelah migrasi):** `wandavenus/Noisegraph/.github/workflows/test-suite.yml` job `native-c` menjalankan suite C in-repo (x86_64 ASan/UBSan), build ARM64 + `qemu-aarch64-static`, native runtime tests, dan benchmark. `run-noisegraph-tests.yml` men-dispatch `native-c` pada perubahan native source/test/pubspec.

## 5. Temuan positif (tidak berubah dari v1)

- Pipeline analisis memakai jendela head/tail (dan middle untuk file panjang); kegagalan tail tidak disamarkan.
- PCM ditapis sebelum decimation; proteksi anti-phase stereo dan kini downmix multichannel teruji.
- Cache DSP berversi (schema 12) dengan identitas file path/size/mtime.
- Parser cue/native target memvalidasi finite, confidence, rentang BPM, durasi fade, dan offset cue; early handover dibatasi validasi lead/durasi/drop/beat-grid.
- Planning menjaga urutan queue sebagai otoritatif, memvalidasi snapshot sebelum reorder, dan menangani ID duplikat dengan fallback crossfade.
- DSP native per-slot tanpa lock Kotlin; kontrol lintas thread memakai atomics (kini termasuk seqlock untuk tuple live-beat).
- Phase-lock nudge dibatasi dan bergantung pada beat grid offline dengan confidence gate.

## 6. Matriks prioritas (status)

| Prioritas | Pekerjaan | Status |
|---|---|---|
| P1 | Abort mid-fade = cancel penuh (NEW-3) | ✅ |
| P1 | Gate Bit-Perfect untuk `analyzeLibrary` (NEW-2) | ✅ |
| P2 | Pacing resume analisis tidak di-bypass tick 200 ms (NEW-1) | ✅ |
| P2 | Suite C di CI repo + tes disable yang valid (NEW-4) | ✅ |
| P2 | Hardening `startAutomix` (NEW-6) | ✅ |
| P2 | Tes abort/completion controller (C11/C12, AM-05) | ✅ |
| P3 | Minor M-01…M-11 | ✅ |
| P3 | Dokumentasi (jalur produksi, L1 ~3 dB, gamma, seqlock, sanitizer) | ✅ |
| Tetap terbuka | AM-03 (keputusan loudness mid-fade), NEW-5 (envelope native nonaktif), true-peak limiter bersama, capture PCM perangkat | ⚠️ |

## 7. Batas audit & validasi

Perubahan v2 ditulis di lingkungan tanpa toolchain (tidak ada `dart`/`flutter`/`clang`), sehingga **belum ada kompilasi/tes lokal** yang dijalankan untuk patch ini; verifikasi sintaks dilakukan lewat inspeksi dan pencocokan kontrak. Langkah verifikasi yang wajib dijalankan sebelum merge:

1. `flutter analyze` + `flutter test test/services/automix_service`.
2. Workflow Noisegraph `test-suite.yml`, job `native-c` — mencakup suite C sanitizer dan run ARM64 QEMU; perubahan native pada Dump otomatis men-dispatch job tersebut.
3. Kotlin unit tests (task Gradle) untuk `CrossfadeControllerTest` baru.

Untuk source SHA `f841a4a` (audit v1), bukti CI historis ada di [Noisegraph run 39029415905](https://github.com/wandavenus/Noisegraph/actions/runs/39029415905) (lima job sukses: dart, native-c, flutter, kotlin, android-arm64) dan build release di [run 39029852100](https://github.com/wandavenus/Noisegraph/actions/runs/39029852100). Patch v2 memerlukan run baru pada SHA hasil commit; status "hijau" run lama tidak berlaku untuk patch ini. Tidak ada pengujian playback langsung di perangkat fisik dan tidak ada pengukuran/capture PCM end-to-end dalam audit ini.

## 8. Follow-up migrasi CI (18 Oktober 2026)

- Suite yang sebelumnya ada di Dump `.github/workflows/native-tests.yml` telah digabung ke job `native-c` di [Noisegraph test-suite](https://github.com/wandavenus/Noisegraph/blob/main/.github/workflows/test-suite.yml).
- Dump `run-noisegraph-tests.yml` kini men-dispatch suite `native-c` saat file di `native_audio_runtime/src/**`, `native_audio_runtime/test/**`, atau `native_audio_runtime/pubspec.yaml` berubah pada `main`. Workflow lama `native-tests.yml` dihapus agar tidak ada dua jalur yang tumpang tindih.
- Kegagalan assembler ARM64 diperbaiki dengan mengganti `FCMLE` yang salah memakai register sebagai operand ketiga menjadi `FCMGE` dengan operand dibalik: `fcmge v6.2s, v31.2s, v3.2s` dan `fcmge v7.2s, v31.2s, v7.2s`. Ini mempertahankan pemeriksaan nilai absolut `<= FLT_MAX`, dan membuat instruksi valid untuk assembler AArch64.
- Status validasi sesudah perubahan harus dibaca dari [Noisegraph Actions](https://github.com/wandavenus/Noisegraph/actions/workflows/test-suite.yml); temuan perbaikan sumber tidak dianggap lulus CI sebelum job ARM64 build dan QEMU benar-benar selesai.
