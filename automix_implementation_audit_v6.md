# Audit Implementasi AutoMix — v6 (2026-10-24)

**Basis audit:** `11bc7d6058d77eb29cc79f879961b5e7c94acd98` + working tree yang hanya berisi perubahan l10n yang sudah ada sebelumnya.

**Ruang lingkup:** seluruh jalur AutoMix: analisis PCM Android/MediaCodec, downsampling dan JNI, analyzer/planner C, cache dan planner Dart, target MethodChannel, preload/early handover, `CrossfadeController`, live beat tracker, tempo/phase follow, bass/tone DSP C/NEON, lifecycle, concurrency, serta test/CI.

**Metode:** pembacaan call path Dart → MethodChannel → Kotlin → Media3/ExoPlayer → JNI/C; pembacaan test dan workflow; static analysis; suite Dart/Kotlin/native; dan regresi PCM offline FFmpeg.

## Ringkasan eksekutif

Fondasi AutoMix sudah matang: native owns playback, target transition dibatasi ke pasangan deck aktif, queue mutation memakai CAS/identity check, early handover dipisahkan dari durasi fade, state tracker memakai seqlock, DSP tone memiliki state per physical stream, dan planner Dart/native memiliki regression parity.

Namun, audit ini menemukan **tiga isu yang layak diprioritaskan sebelum menganggap implementasi benar-benar production-hard**:

1. **P1 — EOF decoder dapat dilaporkan terlalu dini.** `PcmDecoder` menandai EOF ketika EOS baru dimasukkan ke codec, bukan ketika buffer output EOS benar-benar diterima. AutoMix kemudian dapat menganggap tail window parsial sebagai `tailAnalyzed`, sehingga exit BPM/phase/cue bisa berasal dari bagian sebelum ujung file.
2. **P1 — Fail-open JNI tone belum lengkap.** Beberapa panggilan JNI AutoMix langsung dipanggil tanpa menangkap `LinkageError`, walaupun library berhasil di-load. Native library lama/mismatch yang masih memiliki simbol DSP utama tetapi tidak memiliki simbol tone baru dapat menjatuhkan thread audio atau callback utama.
3. **P2 — Jalur native fade C/NEON tidak pernah diaktifkan.** `nativeFadeAvailable` di-hard-code `false`, sehingga produksi memakai ramp `player.volume` Kotlin setiap 16 ms. Helper native dan test-nya ada, tetapi tidak menjadi jalur runtime yang diuji oleh regresi audio.

Selain itu terdapat hardening penting pada batas MethodChannel, koordinasi batch scan vs idle sweep, validasi settings dari disk, dan biaya synchronous file/cache work pada jalur replan.

## Hal yang sudah baik

- **Ownership jelas:** Media3/Kotlin tetap sumber kebenaran queue, shuffle, repeat, crossfade, dan transport; Dart hanya menyiapkan metadata/plan.
- **Target aman:** Dart hanya mengirim current + immediate incoming; same-ID, missing-ID, atau target kurang dari dua tidak mengaktifkan AutoMix-specific DSP.
- **Stale-work protection:** generation check, queue snapshot check, source identity (size + mtime), cache schema, in-flight dedup, dan bounded retry sudah diterapkan.
- **Early handover:** lead relatif terhadap EOF dipisahkan dari fade duration dan divalidasi ulang memakai durasi Media3 aktual.
- **Crossfade cancellation:** perbaikan v5 menutup dua hard-cut penting: update durasi positif tidak lagi membatalkan fade aktif dan promosi deck tidak lagi menyalin volume deck keluar.
- **DSP isolation:** tone, tracker, tempo multiplier, limiter, dan filter memakai physical stream slot terpisah; native audio path tidak melakukan allocation/logging/locking pada hot path.
- **Planner parity:** test native/reference mencakup profil DJ/harmonic/energy, tempo seam, structure, vocal conflict, local search, dan determinism.
- **Batasan terdokumentasi:** implementasi tidak mengklaim post-mix true-peak guarantee karena dua AudioTrack dijumlahkan oleh AudioFlinger tanpa shared software bus.

## Temuan prioritas

| ID | Prioritas | Area | Status | Dampak |
|---|---|---|---|---|
| AM6-01 | **P1** | EOF / tail analysis | **Fixed 2026-10-24** | Tail parsial tidak lagi ditandai selesai sebelum output EOS benar-benar didrain. |
| AM6-02 | **P1** | JNI fail-open | **Fixed 2026-10-24** | Semua entry point tone menangkap `LinkageError` dan melatch bypass process-wide. |
| AM6-03 | **P2** | Native fade path | Open | C/NEON fade dead di produksi; ramp bergantung Handler 16 ms dan belum divalidasi end-to-end. |
| AM6-04 | **P2** | Native target boundary | **Fixed 2026-10-24** | Boundary Media3 sekarang hanya menyimpan pasangan target aktif pertama. |
| AM6-05 | **P2** | Scan concurrency | **Fixed 2026-10-24** | Manual scan sekarang menunggu idle sweep selesai alih-alih overlap. |
| AM6-06 | **P2** | Settings validation | **Fixed 2026-10-24** | Nilai prefs non-finite, fractional, atau di luar batas kembali ke default sebelum planner dipanggil. |
| AM6-07 | **P2** | Replan latency | Open | `statSync`, JSON decode, dan fallback loudness serial dapat menambah jank/stall ketika AutoMix baru aktif. |
| AM6-08 | **P3** | Device/CI evidence | Open | Tidak ada capture Mi 9T/AudioFlinger; workflow AutoMix masih dispatch-only. |

## Temuan rinci

### AM6-01 — EOF decoder dilaporkan sebelum output EOS (P1)

**Lokasi:**

- `android/app/src/main/kotlin/dev/wndavenz/music/replaygain/PcmDecoder.kt:163-174`
- `android/app/src/main/kotlin/dev/wndavenz/music/replaygain/PcmDecoder.kt:242-254`
- `android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixAnalysisBridge.kt:127, 182-185`
- `lib/services/automix_service/service.dart:1886-1905`

**Masalah:** ketika `MediaExtractor.readSampleData()` mengembalikan `<= 0`, kode memasukkan input buffer EOS dan langsung mengeset `reachedEnd = true`. Loop kemudian dapat berhenti sebelum seluruh delayed output dari `MediaCodec` dikuras. `onEos` akhirnya dipanggil berdasarkan flag tersebut, walaupun output buffer dengan `BUFFER_FLAG_END_OF_STREAM` belum terlihat.

AutoMix memakai `onEos` sebagai bukti bahwa tail benar-benar mencapai EOF. Jika window tail hanya menghasilkan PCM parsial tetapi sudah melewati batas minimum satu detik, parser dapat menerima window itu sebagai `tailAnalyzed`. Akibatnya `automixMergeSegments()` dapat mempublikasikan BPM/phase/structure yang bukan berasal dari bagian terakhir lagu.

**Perbaikan terkecil:** pisahkan dua state:

```text
inputEosQueued  — EOS sudah dikirim ke decoder
outputEosSeen   — buffer output EOS benar-benar diterima
```

Teruskan drain sampai `outputEosSeen`, atau sampai feed sengaja abort karena cap. Hanya panggil `onEos` bila output EOS terlihat. Tambahkan test seam untuk loop decoder yang membedakan input EOS dan output EOS, lalu tambahkan regression untuk tail parsial/stale duration.

**Status per 24 Oktober 2026:** diperbaiki di `PcmDecoder` dengan state terpisah untuk input-EOS dan output-EOS. Loop sekarang tetap mendrain output setelah EOS input diantrekan, dan `onEos` hanya dipanggil setelah buffer output berflag EOS terlihat. Regression test state machine ditambahkan di `PcmDecoderTrimTest`.

### AM6-02 — JNI tone belum sepenuhnya fail-open (P1)

**Lokasi:** `android/app/src/main/kotlin/dev/wndavenz/music/effects/AutomixToneManager.kt:73-112, 127-226`.

Wrapper statis `setNativeFadeGain`, `setNativeTruePeakLimit`, dan `setNativeCrossfadeGains` sudah menangkap `LinkageError`. Namun jalur berikut masih memanggil external JNI secara langsung:

- `nativeSetBassGain`, `nativeSetMidGain`, `nativeSetHighGain`
- `nativeSetTruePeakLimit`
- `nativeConfigureTone`
- `nativeProcessTone`
- `nativeResetTone`

`NativeDspAudioProcessor.isLibraryAvailable` hanya membuktikan library dapat di-load; itu tidak membuktikan semua simbol AutoMix tone tersedia. Skenario native `.so` lama/mismatch masih mungkin: simbol pipeline DSP utama tersedia, tetapi simbol tone baru hilang. Dalam kondisi itu `nativeProcessTone()` dapat melempar pada audio rendering thread, bukan mengembalikan `0` untuk bypass.

**Perbaikan terkecil:** buat satu facade JNI safe yang:

1. menangkap `LinkageError` pada setiap entry point;
2. melatch status `toneNativeUnavailable` per process;
3. mengembalikan `false`/`NOT_SET` dan membuat processor transparan ketika simbol tidak ada;
4. tidak mencatat log pada audio thread;
5. diuji dengan fake native facade atau test harness yang mensimulasikan symbol failure.

Jalur normal saat library lengkap sudah tercover oleh test native, tetapi skenario ABI mismatch belum dikunci.

**Status per 24 Oktober 2026:** diperbaiki di `AutomixToneManager.kt`. Seluruh panggilan tone JNI kini berada di guard `LinkageError`; satu kegagalan melatch `AutomixToneNativeAvailability` ke unavailable, mengembalikan processor ke jalur transparan, dan mencegah panggilan simbol berikutnya. Test latch ditambahkan di `AutomixToneNativeAvailabilityTest`.

### AM6-03 — Native fade C/NEON dead di runtime (P2)

**Lokasi:** `android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt:540-548, 1157-1187`.

`nativeFadeAvailable` selalu bernilai `false`. Akibatnya `setAutoMixCrossfadeGains()` tidak pernah dipakai untuk envelope fade produksi; runtime selalu memakai `AutomixGainEnvelope` Kotlin dan menulis `oldPlayer.volume`/`newPlayer.volume` setiap 16 ms.

Dampaknya:

- native per-sample fade C/NEON dan helper JNI tidak tervalidasi end-to-end;
- kualitas timing bergantung pada Handler/main looper dan jitter scheduling;
- lebih banyak write volume dari Kotlin;
- dokumentasi `docs/automix-production-wiring.md:81,102` menggambarkan jalur native sebagai jalur yang tersedia saat overlap, tetapi kode produksi saat ini sengaja tidak mengaktifkannya;
- regresi FFmpeg saat ini hanya menguji fallback Kotlin, sesuai catatan `automix_implementation_audit_v5.md:146`.

**Pilihan desain:**

- **Direkomendasikan:** aktifkan native fade setelah menambahkan shared fade epoch/sequence sehingga dua physical stream membaca pasangan gain yang konsisten, lalu verifikasi capture PCM/device.
- **Alternatif:** hapus jalur native fade yang tidak dipakai dan koreksi dokumentasi agar tidak menyiratkan bahwa C/NEON envelope digunakan di produksi.

Jangan mengaktifkan hanya dengan mengganti `false` menjadi `true` tanpa menguji desynchronization antar-audio-thread; komentar pada source sendiri menyebut risiko pair gain out-of-phase.

### AM6-04 — Native menyimpan seluruh target, bukan hanya dua target aktif (P2)

**Lokasi:** `android/app/src/main/kotlin/dev/wndavenz/music/Media3PlaybackService.kt:2415-2449`.

`usableTargets` divalidasi memakai `targets.take(2)`, tetapi loop penyimpanan memakai `for (target in targets)`. Dart saat ini memotong payload melalui `automixImmediateTransitionTargets()`, sehingga bug belum terpicu oleh caller resmi. Namun boundary native tidak konsisten dengan kontraknya: caller lama atau payload malformed dengan target ke-3 yang memakai ID berulang dapat menimpa map tempo/phase/cue untuk pasangan aktif.

**Perbaikan:** gunakan `for (target in targets.take(2))` dan tambahkan test Kotlin yang mengirim tiga target dengan ID berulang, lalu pastikan hanya pasangan pertama yang tersimpan.

**Status per 24 Oktober 2026:** diperbaiki dengan helper `automixTargetsForActiveDecks()`. Validasi ID dan penyimpanan map kini memakai list dua target yang sama, sehingga target ke-3 tidak dapat menimpa metadata pasangan aktif. Regression test ditambahkan di `Media3PlaybackServiceAutomixBoundaryTest`.

### AM6-05 — Manual scan dan idle sweep belum memakai coordinator bersama (P2)

**Lokasi:** `lib/services/automix_service/service.dart:2090-2160, 2231-2319`.

`analyzeLibrary()` hanya menolak ketika `_analysisFuture != null`. Idle sweep memiliki guard sendiri (`_sweepRunning`), tetapi tidak dicek oleh `analyzeLibrary()`. Dengan demikian user dapat memulai batch scan ketika sweep sedang decode. Kedua jalur berbagi `analyzeOne()`, executor native yang sama, dan `analysisProgress` yang sama.

Konsekuensinya adalah kompetisi queue, `scan_busy` yang tidak perlu, progress UI yang dapat saling menimpa, dan retry/backoff yang sulit diprediksi.

**Perbaikan:** buat satu coordinator eksplisit dengan state `idle / automatic-near / manual-library / idle-sweep`, atau minimal:

- manual scan meng-cancel/menunggu sweep;
- sweep tidak memulai jika manual scan aktif;
- hanya owner coordinator yang boleh menulis `analysisProgress`;
- `analyzeOne()` tetap menjadi dedup level bawah.

Tambahkan test race: mulai sweep, mulai manual scan, cancel manual scan, lalu pastikan hanya satu producer yang mengubah progress.

**Status per 24 Oktober 2026:** guard `analyzeLibrary()` sekarang juga menolak start ketika `_sweepRunning` aktif, sehingga manual scan dan idle sweep tidak dapat memakai decoder/progress secara bersamaan. Race test end-to-end tetap terbuka karena perlu harness untuk mengendalikan timer dan power-state sweep.

### AM6-06 — Settings dari SharedPreferences tidak divalidasi (P2)

**Lokasi:** `lib/services/automix_service/models.dart:677-686`.

`AutomixSettings.fromMap()` menerima angka yang tidak finite, `bpmTolerance` nol/negatif, dan `beats` nol/negatif. Native planner menolak `bpm_tolerance <= 0` atau `crossfade_beats <= 0`, sedangkan service kemudian masuk jalur retry/replan tanpa memperbaiki nilai settings.

**Perbaikan:** validasi saat hydration dan `copyWith`/constructor:

- angka harus finite;
- tolerance harus berada pada rentang produk yang disepakati;
- beat count harus integer positif dan dibatasi agar fade tetap masuk akal;
- invalid data kembali ke default, bukan dipropagasikan ke native.

Tambahkan test untuk prefs corrupt, NaN/Infinity, zero, dan angka ekstrem.

**Status per 24 Oktober 2026:** diperbaiki di `AutomixSettings`. Hydration dan `copyWith` sekarang menolak nilai non-finite, fractional beats, tipe malformed, serta nilai di luar batas aman; constructor juga memberi assertion pada batas produk. Coverage ditambahkan di `automix_settings_test.dart`.

### AM6-07 — Jalur replan masih melakukan kerja synchronous/serial yang mahal (P2)

**Lokasi:**

- `lib/services/automix_service/service.dart:1076-1085`
- `lib/services/automix_service/service.dart:1253-1307`
- `lib/services/automix_service/service.dart:1341-1412`

`_featuresForPlan()` memproses window secara serial. Untuk track dekat, `featuresFor()` melakukan `statSync`, baca/parse cache, lalu dapat memanggil fallback `ReplayGainService.resolve()`. Untuk track jauh, `_cachedOrNeutral()` tetap melakukan `statSync` dan baca cache per track. Window planner dibatasi 250, tetapi semua ini tetap berjalan di isolate UI Dart sebelum target transition dikirim.

**Dampak:** saat AutoMix baru diaktifkan atau queue besar berubah, frame UI dan respons planning dapat tertahan, terutama pada storage lambat.

**Perbaikan:**

1. baca cache AutoMix secara batch sekali;
2. gunakan identity dari metadata/cache yang sudah tersedia sebelum `statSync`;
3. parallel-kan hanya near-feature window dengan bounded concurrency kecil;
4. pindahkan stat/JSON parse besar ke isolate atau worker;
5. ukur `time-to-first-target` dan `time-to-replan` pada Mi 9T.

### AM6-08 — Bukti device-level dan CI gate masih kurang (P3)

**Lokasi:** `docs/automix-production-wiring.md:96-108`, `.github/workflows/run-noisegraph-tests.yml:3-17`.

Suite offline/native/Kotlin sudah kuat, tetapi:

- belum ada capture output AudioFlinger dari Xiaomi Mi 9T/Redmi K20;
- native C/NEON tone envelope belum dirender oleh harness produksi karena native fade dinonaktifkan;
- belum ada test audio untuk MediaCodec tail drain;
- workflow AutoMix adalah `workflow_dispatch`, bukan gate otomatis pada perubahan AutoMix.

**Perbaikan:** buat fixture audio nyata (kick-heavy, vocal clash, silence intro/outro, tempo drift, 44.1/48/96 kHz), jalankan cold install pada target device, simpan timeline log + PCM/loopback capture, lalu jadikan suite focused AutoMix sebagai required check untuk perubahan `automix/**`, `crossfade/**`, `Media3PlaybackService.kt`, `native_audio_runtime/src/automix_*`, dan `PcmDecoder.kt`.

## Peningkatan kualitas yang direkomendasikan

### Audio quality

1. Pertahankan L1 headroom sebagai mode aman, tetapi ukur persepsi drop ~3 dB di tengah fade; pertimbangkan adaptive L2 + per-deck limiter hanya bila hasil device capture aman.
2. Jika ingin true-peak end-to-end, desain shared software mix bus; jangan memperluas klaim limiter per-deck menjadi klaim post-mix.
3. Tambahkan golden fixtures musik nyata untuk memvalidasi drop/breakdown, vocal proxy, chord estimator, dan early handover. Sine fixture hanya membuktikan kontinuitas/peak.

### Planner dan metadata

1. Simpan alasan fallback per transition: `no_tail_grid`, `unstable_tempo`, `no_drop`, `same_id`, `native_disarmed`, dan `decoder_partial`.
2. Tambahkan metrik kualitas plan sebelum/sesudah replan supaya peningkatan cache tidak mengubah sequence secara mengejutkan.
3. Pertimbangkan 64-bit queue fingerprint atau snapshot token native bila ingin mengurangi risiko collision pada queue identity.

### Product/API

1. Data model dan l10n memiliki profile/tolerance/crossfade-beats/library-scan, tetapi UI AutoMix saat ini hanya menampilkan satu toggle (`lib/pages/settings_page/audio/automix_section.dart:3-20`). Pilih salah satu: hapus kontrak yang sengaja internal, atau tambahkan Advanced AutoMix settings yang benar-benar memanggil `saveSettings()`.
2. Tampilkan status analisis yang lebih jelas: cache warm, tail belum valid, retry/backoff, dan alasan AutoMix memakai ordinary crossfade.
3. Sediakan tombol “re-analyze this track” untuk kasus file berubah/metadata stale tanpa memaksa full-library scan.

## Verifikasi yang dijalankan

| Pemeriksaan | Hasil |
|---|---|
| `flutter test test/services/automix_service` | **127 test lulus** |
| `flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos lib test` | **No issues found** |
| `dart test` di `native_audio_runtime` | **Semua test lulus**; termasuk AutoMix native analyzer/planner dan DSP suite |
| `./gradlew :app:testDebugUnitTest` | **BUILD SUCCESSFUL** |
| Focused Kotlin tests: `PcmDecoderTrimTest` + `AutomixToneNativeAvailabilityTest` + `Media3PlaybackServiceAutomixBoundaryTest` | **BUILD SUCCESSFUL** |
| `flutter test test/services/automix_service/automix_settings_test.dart` | **3 test lulus** |
| `tools/automix_ffmpeg_regression.sh` | **RESULT: PASS**; envelope current kontinu dan dua fault model terdeteksi |
| `git diff --check` | Lulus |

Test yang lulus sekarang menutup regression state untuk AM6-01, latch fail-open untuk AM6-02, target boundary AM6-04, settings boundary AM6-06, serta compile/runtime guard untuk AM6-05. Validasi device/listening tetap diperlukan, dan AM6-03 masih terbuka karena jalur native fade belum diaktifkan.

## Urutan pengerjaan yang disarankan

1. **Selesai:** perbaiki output-EOS drain, lengkapi fail-open wrapper JNI tone, batasi native target ke dua item, dan validasi settings.
2. **Berikutnya:** putuskan nasib native fade; jika diaktifkan, tambahkan shared envelope synchronization dan device PCM capture.
3. **Hardening berikutnya:** race harness coordinator scan dan optimasi replan cache/stat.
4. **Performance:** batch cache read/stat dan ukur time-to-first-target pada device target.
5. **Quality/product:** fixture musik nyata, transition reason diagnostics, dan konsistensi UI/settings contract.

## Kesimpulan

AutoMix saat ini sudah **kuat secara arsitektur dan lulus seluruh pemeriksaan lokal yang tersedia**. AM6-01, AM6-02, AM6-04, AM6-05, dan AM6-06 sudah diperbaiki; AM6-01/02/04/06 memiliki regression coverage, sementara AM6-05 masih membutuhkan race harness end-to-end. Batas berikutnya tetap AM6-03, yaitu kesesuaian jalur native fade dengan runtime sebenarnya, dan AM6-07 untuk biaya replan.
