# Audit Implementasi AutoMix — 2026-10-17

**Status:** Selesai — audit statis lintas layer, tanpa perubahan kode produksi.  
**Repository:** `wandavenus/Dump`  
**Branch:** `main`  
**Revisi kode yang diaudit:** [`f841a4a7c68d0c4bc1d37efcf9828b7712697e4b`](https://github.com/wandavenus/Dump/commit/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b)  
**Cakupan:** Dart planning/cache/settings, bridge MethodChannel, PCM decode/downsample, JNI, native analyzer/planner/live beat tracker/tone DSP, Kotlin dual-player preload/crossfade, ARM64 NEON, tests, dan CI.

> Laporan ini menilai source pada SHA di atas. Hasil CI yang disebutkan di bawah memvalidasi revisi source tersebut; audit ini tidak melakukan pengukuran audio hasil render di perangkat fisik.

## Ringkasan eksekutif

Ditemukan **5 item**: 2 masalah perilaku/analisis yang terkonfirmasi, 1 trade-off kualitas fade yang perlu diputuskan secara produk, 1 celah gating pekerjaan latar, dan 1 celah cakupan pengujian runtime. Tidak ditemukan masalah kritis/tinggi yang dapat dikonfirmasi dari inspeksi statis ini.

| ID | Severity | Topik | Confidence |
|---|---|---|---|
| AM-01 | Sedang | Arah kurva fade `gamma` terbalik dari makna strategi | Tinggi |
| AM-02 | Sedang | Analisis PCM multichannel hanya memakai kanal L/R | Tinggi |
| AM-03 | Sedang — trade-off desain | Fader L1 dapat menurunkan RMS sekitar 3 dB di tengah fade | Tinggi |
| AM-04 | Rendah | Library sweep tetap berjalan ketika Bit-Perfect aktif | Tinggi |
| AM-05 | Sedang — celah validasi | Runnable crossfade dan jalur ARM64 NEON belum diuji end-to-end di runtime | Tinggi |

---

## AM-01 — Arah kurva `gamma` terbalik dari makna strategi

**Severity:** Sedang (P2)  
**Confidence:** Tinggi  
**Jenis:** Bug perilaku terkonfirmasi

**Lokasi:**
- [`AutomixGainEnvelope.kt:31-40`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixGainEnvelope.kt#L31-L40)
- [`engine.dart:627-629`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/lib/services/automix_service/engine.dart#L627-L629)
- [`AutomixTransitionPolicy.kt:97-105`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixTransitionPolicy.kt#L97-L105)
- [`CrossfadeController.kt:943-951`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt#L943-L951)

**Bukti / root cause:** progress dibentuk sebagai `t.pow(gamma)`. Untuk progress di antara 0 dan 1, `gamma > 1` menghasilkan nilai yang lebih kecil daripada `t`; ini mempertahankan gain outgoing lebih lama dan menahan kenaikan incoming. Namun planner dan policy menyatakan `gamma > 1` mempercepat handover; strategi quick/short handover justru mengatur gamma lebih tinggi. Gamma di bawah 1 melakukan kebalikannya. Ini adalah jalur Kotlin yang dipakai produksi; `CrossfadeController.kt:490` saat ini mematikan native fade envelope. Helper fade di native C memakai eksponen yang sama sehingga punya semantik yang sama bila jalur itu digunakan di masa depan.

**Dampak:** fade yang dipilih sebagai cepat/short tetap memakai kurva yang lebih lambat di dalam durasi fade-nya, sedangkan long blend mendapat kurva yang lebih cepat. Panjang fade tetap dibatasi terpisah, jadi dampaknya khususnya pada bentuk perpindahan volume, bukan penjadwalan waktu fade.

**Rekomendasi:** sepakati satu definisi gamma lalu selaraskan komentar, Kotlin, policy, dan native C. Jika gamma lebih tinggi memang bermakna handover lebih cepat, bentuk seperti `t.pow(1 / gamma)` konsisten dengan makna tersebut. Tambahkan regresi yang membandingkan incoming gain pada progress 0.25/0.5/0.75 untuk gamma di atas dan di bawah 1; tes saat ini menguji endpoint dan batas jumlah gain, tetapi tidak menguji arah kurva.

## AM-02 — Analisis multichannel mengabaikan kanal selain L/R

**Severity:** Sedang (P2)  
**Confidence:** Tinggi  
**Jenis:** Masalah cakupan format terkonfirmasi

**Lokasi:**
- [`AutomixPcmDownsampler.kt:40-57`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixPcmDownsampler.kt#L40-L57)
- [`PcmDecoder.kt`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/android/app/src/main/kotlin/dev/wndavenz/music/replaygain/PcmDecoder.kt)

**Bukti / root cause:** decoder menerima format dengan 1–8 kanal, tetapi downsampler membentuk mono hanya dari kanal pertama dan kedua. Kanal center, LFE, dan surround diabaikan untuk input multichannel.

**Dampak:** file 5.1/7.1 dengan informasi musik penting di kanal center/surround dapat dianalisis sebagai energi yang rendah atau salah, sehingga estimasi BPM, key, energi, dan cue transisi berisiko salah. Jalur stereo anti-phase sudah ditangani; itu tidak menyelesaikan kasus multichannel.

**Rekomendasi:** downmix seluruh kanal dengan bobot yang sesuai sebelum filter anti-alias, atau paksa decoder menghasilkan stereo secara eksplisit. Pertahankan proteksi anti-phase pada jalur stereo dan tambahkan tes untuk sinyal center-only serta surround-only.

## AM-03 — Headroom L1 menyebabkan penurunan RMS di tengah fade

**Severity:** Sedang (P2, trade-off kualitas suara; bukan crash/correctness defect)  
**Confidence:** Tinggi

**Lokasi:**
- [`AutomixGainEnvelope.kt:31-44`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixGainEnvelope.kt#L31-L44)
- [`automix_tone_processor.c:113-141`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/native_audio_runtime/src/automix_tone_processor.c#L113-L141)
- [`automix-production-wiring.md:60-68`](https://github.com/wndavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/docs/automix-production-wiring.md#L60-L68)

**Bukti / root cause:** envelope memakai koefisien cos/sin lalu menormalkan jumlah absolut dua gain agar tidak melebihi 1. Pada titik tengah fade standar (`t = 0.5`, gamma 1, trim 1), koefisien menjadi sekitar 0.5 + 0.5. Untuk dua sinyal dengan loudness sebanding dan tidak berkorelasi, RMS gabungan secara teoritis menjadi sekitar `sqrt(0.5² + 0.5²) = 0.707`, atau turun kira-kira **3.0 dB** dari envelope equal-power standar.

**Dampak:** gain budget yang konservatif membantu membatasi clipping dari penjumlahan sumber yang berkorelasi, tetapi dapat membuat fade terasa turun volumenya di bagian tengah saat dua lagu berbeda overlap.

**Rekomendasi:** putuskan trade-off ini berdasarkan target loudness dan hasil listening test. Bila ingin mempertahankan loudness tanpa kehilangan proteksi headroom, evaluasi limiter true-peak di bus bersama atau kontrol headroom/correlation yang sesuai, bukan sekadar menghapus pembatas L1. Tambahkan tes trajectory RMS selain tes bahwa jumlah koefisien tidak melewati target.

## AM-04 — Library sweep tidak berhenti saat Bit-Perfect aktif

**Severity:** Rendah (P3)  
**Confidence:** Tinggi  
**Jenis:** Ketidakkonsistenan gating pekerjaan latar

**Lokasi:**
- [`service.dart:1868-1888`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/lib/services/automix_service/service.dart#L1868-L1888)
- [`service.dart:1908-1958`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/lib/services/automix_service/service.dart#L1908-L1958)
- Sebagai pembanding, [`service.dart:699-704`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/lib/services/automix_service/service.dart#L699-L704) dan [`service.dart:777-778`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/lib/services/automix_service/service.dart#L777-L778) mengecek Bit-Perfect untuk pipeline analisis lainnya.

**Bukti / root cause:** ketika AutoMix tetap dalam keadaan enabled, `_runLibrarySweepPass()` hanya mengecek platform dan `automixEnabled`, lalu memproses batch sampai 40 track dengan jeda dan pemeriksaan baterai/thermal. Fungsi ini tidak mengecek `bitPerfectMode` di awal maupun di antara decode. Pipeline analisis track yang dipakai untuk transisi aktif justru berhenti saat Bit-Perfect aktif.

**Dampak:** pemindaian DSP latar dapat terus menggunakan CPU, disk, dan MediaCodec saat pengguna memakai Bit-Perfect. Ini tidak mengubah sampel audio secara langsung, tetapi menambah beban kerja dan risiko gangguan playback pada perangkat terbatas.

**Rekomendasi:** hentikan atau tunda sweep ketika Bit-Perfect aktif, cek kembali sebelum setiap analisis, lalu jadwalkan ulang ketika mode itu dimatikan. Tambahkan tes bahwa sweep yang sedang berjalan menyerah setelah mode diubah.

## AM-05 — Tes controller tidak menjalankan fade runtime; ARM64 NEON belum diuji lewat eksekusi perangkat

**Severity:** Sedang (P2 — risiko regresi yang belum terukur)  
**Confidence:** Tinggi  
**Jenis:** Celah validasi

**Lokasi:**
- [`CrossfadeControllerTest.kt:22-29`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/android/app/src/test/kotlin/dev/wndavenz/music/crossfade/CrossfadeControllerTest.kt#L22-L29)
- [`CrossfadeController.kt:641-979`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt#L641-L979)
- [`automix_tone_neon.S`](https://github.com/wandavenus/Dump/blob/f841a4a7c68d0c4bc1d37efcf9828b7712697e4b/native_audio_runtime/src/automix_tone_neon.S)

**Bukti / root cause:** test controller sendiri mendokumentasikan bahwa Android JVM stubs tidak menyediakan message queue, sehingga badan `Handler.post/postDelayed` tidak dieksekusi. Test mencakup guard dan perubahan state sinkron, bukan progres fade penuh, perubahan speed/buffering, penyelesaian/cancel di setiap titik, atau output audio. Di Android ARM64, jalur stereo menggunakan assembly NEON; CI saat ini membangun APK ARM64 tetapi tes native dengan sanitizer tidak mengeksekusi jalur assembly pada perangkat ARM64.

**Dampak:** build/unit test dapat hijau walaupun timing real-time atau hasil PCM ARM64 memiliki regresi yang baru muncul pada playback sungguhan.

**Rekomendasi:** injeksikan scheduler/clock yang bisa dimajukan deterministik untuk tes progres/cancel/pause-resume dan early handover. Tambahkan tes parity scalar-vs-NEON yang benar-benar berjalan pada ARM64, serta smoke/instrumentation test dengan dua player dan PCM capture untuk pergantian tempo dan crossfade. Ini tidak berarti runtime terbukti rusak; artinya validasi saat ini belum menguji jalur penuh tersebut.

---

## Batasan implementasi yang memang sudah didokumentasikan

- **True-peak limiter bersama belum diimplementasikan.** Dokumentasi menyatakan jaminan yang ada hanya sample-peak clamp per stream dan batas koefisien fader. Itu bukan jaminan true peak setelah kedua deck dijumlahkan; potensi inter-sample peak masih merupakan risiko residual. Ini dicatat sebagai fitur yang ditunda, bukan temuan baru yang tidak diketahui.
- Live beat tracker merupakan heuristik onset/autocorrelation dengan confidence gate, bukan transkripsi beat/downbeat yang dijamin benar. Estimasi chord berbasis spectral template, bukan model transkripsi chord penuh.
- AutoMix memulai perencanaan tanpa memaksa decode panjang di jalur play; fitur yang belum tersedia di cache dapat dinilai netral dahulu dan disempurnakan setelah analisis latar. Ini merupakan trade-off latensi startup yang dijelaskan dalam komentar implementasi.

## Matriks prioritas

| Prioritas | Pekerjaan | Alasan |
|---|---|---|
| P2 | Betulkan definisi dan pemakaian gamma; tambahkan tes arah kurva | Membuat quick/short vs long blend cocok dengan strategi yang diminta engine |
| P2 | Downmix semua kanal audio sebelum analisis | Mencegah fitur palsu pada file multichannel |
| P2 | Putuskan kebijakan loudness di tengah fade dan verifikasi lewat PCM/listening test | Menghindari penurunan loudness yang tidak diinginkan saat overlap |
| P2 | Tingkatkan uji fade runtime dan jalur ARM64 NEON | Menutup celah yang tidak ditangkap test JVM/host |
| P3 | Gate library sweep saat Bit-Perfect aktif | Mengurangi kerja latar yang tidak diperlukan dan risiko beban tambahan |

## Temuan positif

- Pipeline analisis menggunakan jendela head/tail dan, untuk file sangat panjang, middle; kegagalan tail tidak disamarkan sebagai analisis outro lengkap.
- PCM ditapis sebelum decimation dan tes mencakup supresi alias frekuensi tinggi serta proteksi audio stereo anti-phase.
- Cache DSP berversi (schema 12) dan dipasangkan dengan identitas file berbasis path/size/mtime.
- Parser cue/native target memvalidasi finite values, confidence, rentang BPM, durasi fade, dan offset cue. Early handover dibatasi oleh validasi lead, durasi, drop cue dan beat-grid confidence.
- Planning menjaga urutan queue sebagai data otoritatif, memvalidasi snapshot sebelum reorder, dan menangani pasangan ID lagu berulang dengan fallback ke crossfade biasa.
- Gain filter/native DSP memisahkan state per physical player slot; target gain lintas thread memakai atomics, dan callback DSP tidak perlu mengambil lock Kotlin.
- Phase-lock nudge dibatasi, memakai offline beat grid dengan confidence gate, dan memiliki fallback jika native helper tidak tersedia.

## Validasi CI

Untuk source SHA `f841a4a7c68d0c4bc1d37efcf9828b7712697e4b`, workflow tes yang dipicu dan benar-benar berjalan di [Noisegraph — Test Noisegraph run 39029415905](https://github.com/wandavenus/Noisegraph/actions/runs/39029415905) selesai dengan seluruh lima job sukses:

- `automix-dart`: engine, cache, dan plan-signature tests
- `native-c`: C AutoMix tests dengan sanitizer
- `flutter`: analyzer dan full Flutter test suite
- `kotlin`: Kotlin unit tests
- `android-arm64`: kompilasi debug APK untuk ARM64

Build APK release terkait juga sukses di [Noisegraph — Build Android APK run 39029852100](https://github.com/wandavenus/Noisegraph/actions/runs/39029852100). Job ARM64 tersebut adalah bukti build/kompilasi, bukan bukti bahwa fade dan NEON sudah diuji pada perangkat fisik.

## Batas audit

Audit source dan alur CI dilakukan terhadap revisi yang dicantumkan. Tidak ada perubahan pada kode produksi, tidak ada pengujian playback langsung di perangkat fisik, dan tidak ada pengukuran/capture PCM end-to-end. Temuan AM-01, AM-02, dan AM-04 berasal dari alur kode yang dapat ditunjuk; AM-03 adalah konsekuensi matematis dari envelope saat ini; AM-05 adalah batas cakupan test yang terverifikasi, bukan klaim bahwa runtime pasti gagal.
