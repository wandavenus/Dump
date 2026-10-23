# Audit Implementasi AutoMix — v4 final (2026-10-21)

**Status:** Audit akhir atas basis `c36eaf2` ditambah patch working tree. Dokumen v3 (`automix_implementation_audit_v3.md`) tetap disimpan sebagai riwayat; status di v4 ini menggantikan status v3.
**Tindak lanjut:** Dua regresi jalur early handover yang ditemukan setelah v4 dicatat dan diperbaiki di `automix_implementation_audit_v5.md` (2026-10-23).
**Repository:** `wandavenus/Dump`
**Basis kode:** `c36eaf2` — "Fix AutoMix 145 BPM downbeat estimation"
**Perubahan working tree:** 10 berkas, +269/−28 (tanpa churn format)
**Metode:** pembacaan kode, penelusuran call-site, pembandingan Dart/Kotlin/native, dan eksekusi suite C lokal.
**Batasan:** Flutter, Gradle, dan Java tidak tersedia di lingkungan ini. Test Flutter/Kotlin tidak dapat dijalankan; capture PCM perangkat dan listening test tetap deferred.

## Ringkasan eksekutif

Tidak ditemukan bug **Tinggi** atau **Sedang** yang masih terbuka pada jalur AutoMix yang diaudit. Seluruh temuan v3 yang berupa bug sudah ditutup atau diklasifikasikan ulang sebagai batasan desain yang eksplisit. Putaran akhir menemukan dan memperbaiki satu bug fase edge: fase beat lokal yang diukur pada tempo dua kali lebih cepat tidak boleh dipakai setelah BPM dilipat ke oktaf track.

| ID | Severity | Topik | Status akhir |
|---|---|---|---|
| AM3-01 | Tinggi | Exit grid bisa berasal dari window middle/head | Fixed |
| AM3-02 | Tinggi | Target kosong/same-ID tetap mengaktifkan AutoMix | Fixed |
| AM3-03 | Tinggi | Abort mid-fade tidak melakukan cleanup penuh | Fixed |
| AM3-04 | Sedang | Kegagalan arm native ditelan, native tetap aktif | Fixed |
| AM3-05 | Sedang | Klaim true-peak melebihi kemampuan DSP | Ditutup sebagai batasan desain + dokumentasi dikoreksi |
| AM3-06 | Sedang | Path filter CI tidak mencakup jalur AutoMix | Fixed |
| AM3-07 | Sedang | Dokumentasi tidak sesuai implementasi | Fixed |
| AM3-08 | Rendah | `tailAnalyzed` tanpa bukti EOF | Fixed (`reachedEof`) |
| AM3-09 | Rendah | LFE ikut downmix dan pembulatan window | Fixed |
| AM3-10 | Rendah | `removeProcessor` menyisakan target tone | Fixed |
| AM3-11 | Rendah | Durasi berubah setelah decode head | Residual rendah, dibatasi retry |

### Perbaikan pasca-v3 yang ikut diverifikasi

| ID | Area | Perbaikan | Bukti |
|---|---|---|---|
| A4-01 | Dart merge | Fase beat outgoing tidak lagi memakai grid head saat hanya grid whole-track yang tersedia | `service.dart:397-417`, tes `automix_start_test.dart:55` |
| A4-02 | Dart merge | Fase edge yang diukur pada tempo lebih cepat di-drop sebelum fold oktaf | `engine.dart:438-453`, `:462`, `:576`, `:593`, tes `automix_engine_test.dart:1396`, `:1430` |
| A4-03 | Native live tracker | Skoring grid dan proyeksi fase memakai BPM tracker yang sama | `automix_live_tracker.c:413-422` |
| A4-04 | Native live tracker | Multichannel memakai hanya L/R; LFE/surround tidak mengatenuasi musik | `automix_live_tracker.c:555-566`, tes native `:1687` |
| A4-05 | Kotlin early handover | Snap frasa yang keluar dari envelope early-handover kembali ke `idealStart` | `CrossfadeController.kt:279-305` |
| A4-06 | Kotlin phase lock | Grid live/offline yang tidak beat-match mereset `lastPhaseNudge` | `CrossfadeController.kt:1072-1136` |
| A4-07 | Kotlin queueInput | Tail PCM yang tidak frame-aligned dibuang dan seluruh buffer dikonsumsi | `AutomixToneManager.kt:178-208` |
| A4-08 | Dart arm rollback | Kegagalan `setAutomixTransition` melepas native dan menjadwalkan retry | `service.dart:770-787` |
| A4-09 | Dokumentasi | Klaim true-peak dikoreksi menjadi estimator/limiter kausal, bukan lookahead guarantee | `docs/automix-production-wiring.md:79`, `:89`, `:102` |

## Temuan rinci

### AM3-01 — Exit grid hanya dari window tail (Fixed)

`automixMergeSegments` sekarang hanya memakai `segments.last` sebagai `exitWindow` ketika `tailSegmentAnalyzed` benar (`engine.dart:567-570`). Tidak ada lagi iterasi ke middle/head. Jika tail tidak punya BPM layak, `tailBpm`/`tailBeatOffsetMs`/`tailDownbeatOffsetMs` tidak dipublikasikan; BPM head hanya boleh dipakai untuk sequencing tanpa fase.

**Dampak penutupan:** planner dan phase lock tidak dapat lagi menerima fase dari tengah lagu sebagai exit grid. Regresi lama untuk tail gagal decode tetap berlaku.

### AM3-02 — Target kosong/same-ID tidak mengaktifkan AutoMix (Fixed)

`automixImmediateTransitionTargets` mengosongkan payload untuk pasangan same-ID dan memotong target ke dua deck aktif (`plan_signature.dart:9-24`). `automixHasUsableTransitionTargets` menolak list kosong, target tunggal, ID hilang, dan ID sama (`plan_signature.dart:26-40`). Service memeriksa hasil ini sebelum arm native; bila tidak layak, ia memanggil `_clearAutoMixTransition` dan memulihkan durasi crossfade pengguna (`service.dart:725-743`).

**Dampak penutupan:** limiter, tracker, dan durasi fade AutoMix tidak lagi aktif untuk plan yang tidak dapat direpresentasikan oleh map berbasis song ID.

### AM3-03 — Abort mid-fade adalah cancel penuh (Fixed)

Jalur abort di `CrossfadeController` memulihkan volume deck aktif, mereset preload, membangun ulang queue hasil promosi, dan memanggil callback pembatalan (`CrossfadeController.kt:830-836`). Ini menyamakan efek abort dengan `cancel()` dan mencegah deck tertinggal pada volume duck atau timeline satu-item. Test Kotlin C11/C12 mengunci kedua arah (abort dan completion).

### AM3-04 — Kegagalan arm native di-rollback (Fixed)

`setAutomixTransition` sekarang dibungkus `try/catch` (`service.dart:770-787`). Jika arm gagal setelah crossfade override aktif, service mencatat warning, memanggil `_clearAutoMixTransition(generation)`, memeriksa generation, lalu menjadwalkan retry terbatas. Tidak ada lagi sesi Dart yang menganggap AutoMix aktif sementara native tidak memegang transisi.

### AM3-05 — True-peak: batasan desain, bukan bug tersembunyi (Closed)

Limiter per-deck berjalan setelah `SignalsmithStretch`, memakai interpolator Lagrange 4x kausal, attack instan, dan release sekitar 50 ms. Karena tidak ada lookahead, peak yang baru terlihat pada sampel berikutnya dapat meninggalkan overshoot inter-sample singkat; clamp per-sampel tetap menjaga sample peak di bawah ceiling. Dua deck juga tetap disumkan downstream oleh AudioFlinger tanpa limiter bus bersama.

Dokumentasi telah dikoreksi agar tidak menjanjikan true-peak end-to-end (`docs/automix-production-wiring.md:79`, `:89`, `:102`). Ini keputusan arsitektur yang terdokumentasi, bukan cacat implementasi yang dapat ditutup tanpa mix bus bersama.

### AM3-06 — Cakupan CI (Fixed)

Workflow memicu `pull_request` dan mencakup jalur `crossfade/**`, `Media3PlaybackService.kt`, serta `effects/AutomixToneManager.kt`. Suite native C in-repo dibangun dan dijalankan terpisah dari `flutter test`, termasuk jalur ARM64/NEON.

### AM3-07 — Dokumentasi diselaraskan (Fixed)

Dokumentasi kini mencerminkan skema cache saat ini, jumlah fitur planner, nilai analyzer, status gating tracker, alur PR, dan batas true-peak. Versi skema analisis di kode adalah 17 (`service.dart:1060`) dan test cache memakai versi 17 (`automix_cache_test.dart:69`).

### AM3-08 — `tailAnalyzed` memerlukan EOF (Fixed)

`_analyzeWindow` hanya menyatakan `reachedEof` bila callback `onEos` benar-benar terpanggil (`AutomixAnalysisBridge.kt:80`, `:127`, `:276`). Service memakai nilai itu untuk `tailAnalyzed` (`service.dart:1862-1876`). Bridge lama yang tidak mengirim field ini diperlakukan sebagai unknown dan tidak mempublikasikan exit grid. Ini lebih aman daripada menganggap buffer penuh sebagai bukti EOF.

### AM3-09 — LFE dan pembulatan window (Fixed)

Downsampler offline mengecualikan LFE berdasarkan channel mask, dan live tracker hanya memakai L/R musical bed (`automix_live_tracker.c:555-566`). `windowSeconds` mengikuti durasi yang dilaporkan decoder dan dihitung ulang sebelum tail dipilih (`service.dart:1815-1850`).

### AM3-10 — `removeProcessor` membersihkan target (Fixed)

`AutomixToneManager.removeProcessor` menghapus target bass, mid, high, dan true-peak untuk slot yang dilepas (`AutomixToneManager.kt:261-273`). Tidak ada lagi target lama yang dapat diterapkan ke processor baru pada slot yang sama.

### AM3-11 — Stabilitas window (Residual rendah)

Decoder yang melaporkan durasi berbeda pada setiap pembukaan dibatasi oleh retry maksimal tiga kali (`service.dart:1835-1846`). Pada kasus patologis, head dan tail masih dapat memakai ukuran window yang berbeda. Dampaknya terbatas pada analisis fitur, bukan crash atau kebocoran state. Tidak diubah pada putaran ini karena memerlukan kebijakan tambahan untuk decoder yang tidak stabil.

## Temuan putaran final: fase edge setelah fold oktaf (Fixed)

**Lokasi:** `engine.dart:438-453`, `:462`, `:576`, `:593`.

**Akar masalah:** fase beat edge diukur modulo periode tempo edge. Ketika estimator edge memberi tempo dua kali lebih cepat (misalnya 240 BPM) lalu BPM dilipat ke oktaf track (120 BPM), periode beat berubah dari 250 ms menjadi 500 ms. Fase 250 ms dapat berarti beat utama atau offbeat pada grid hasil fold. Memakai fase itu sebagai `introBeatOffsetMs` atau `tailBeatOffsetMs` dapat membuat phase lock mengunci offbeat.

**Perbaikan:** `edgePhaseSurvivesFold(measuredBpm, publishedBpm)` hanya meloloskan fase bila tempo terukur tidak lebih cepat dari sekitar 3% di atas tempo yang dipublikasikan. Tempo yang lebih lambat tetap aman karena periodenya merupakan kelipatan periode track. Guard diterapkan pada fase intro, fase tail lokal, dan fallback beat/downbeat tail.

**Regresi:** `automix_engine_test.dart:1396` memastikan edge 240 BPM → 120 BPM membuang offset tetapi mempertahankan confidence tempo; `:1430` memastikan edge 60 BPM → 120 BPM mempertahankan offset.

## Verifikasi

| Pemeriksaan | Hasil |
|---|---|
| `git diff --check` | Lulus; tidak ada whitespace error |
| Suite native C (`automix_build/automix_native_c_test`) | Exit 0 |
| Test native LFE/surround | Terdaftar dan dijalankan (`automix_native_c_test.c:1687`, `:2239`) |
| Test native disable tracker | Terdaftar dan dijalankan (`:1756`) |
| `dart analyze lib/services/automix_service/engine.dart` | Hanya 4 unresolved name karena `part`/Flutter tidak tersedia; tidak ada error sintaks dari perubahan |
| `dart analyze service.dart` | Error yang tersisa adalah simbol Flutter/platform yang tidak dapat di-resolve di luar proyek Flutter |
| `flutter test` | Tidak dapat dijalankan: Flutter tidak tersedia |
| Test Kotlin | Tidak dapat dijalankan: Gradle/Java tidak tersedia |
| Capture PCM perangkat / listening test | Belum dilakukan |

**Kesimpulan verifikasi:** perubahan Dart lolos pemeriksaan sintaks dan logika statis; suite native lulus. Test regresi Dart/Kotlin yang baru belum dieksekusi di lingkungan ini dan harus dijalankan melalui CI Flutter/Kotlin sebelum rilis.

## Risiko residual

1. **True peak end-to-end (AM3-05):** dua deck disumkan downstream tanpa limiter bus bersama; overshoot inter-sample singkat mungkin terjadi. Perlu shared software mix bus bila ingin jaminan penuh.
2. **Stabilitas durasi decoder (AM3-11):** decoder yang terus mengubah durasi dapat menyisakan mismatch ukuran window head/tail. Dampak rendah dan sudah dibatasi.
3. **Bass swap / overlap lanjutan:** analisis cue dan energy berbasis heuristik, bukan transkripsi model; keputusan audible tetap perlu validasi perangkat.
4. **CI dan perangkat:** hasil CI Noisegraph dan capture PCM perangkat tidak tersedia pada audit ini.

## Berkas yang berubah

- `lib/services/automix_service/engine.dart`
- `lib/services/automix_service/service.dart`
- `test/services/automix_service/automix_cache_test.dart`
- `test/services/automix_service/automix_engine_test.dart`
- `test/services/automix_service/automix_start_test.dart`
- `android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt`
- `android/app/src/main/kotlin/dev/wndavenz/music/effects/AutomixToneManager.kt`
- `native_audio_runtime/src/automix_live_tracker.c`
- `native_audio_runtime/test/automix_native_c_test.c`
- `docs/automix-production-wiring.md`
