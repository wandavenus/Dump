# Blueprint: Dual-Player dengan Satu AudioTrack

**Project:** Noisegraph / Dump  
**Status:** Implementasi dual-player/Single-AudioTrack aktif secara default untuk validasi perangkat nyata; sample-domain bus (konversi format, resampling, gain ramp, summing, limiter) memakai C++/NEON dengan fallback Kotlin. Set `SingleAudioTrackEngine.enabled = false` untuk kembali ke jalur legacy bila ditemukan regresi.
**Baseline:** `Media3PlaybackService`, `CrossfadeController`, `SignalsmithStretchAudioProcessor`, `AutomixToneManager`, Media3 `1.11.1`

## 0. Status implementasi

Jalur dual-player sekarang memakai dua ExoPlayer + dua `DeckAudioSink` virtual + satu
`SingleAudioTrackEngine` + satu output `DefaultAudioSink`/`AudioTrack`.

| File | Isi |
|---|---|
| `audio/mixer/SingleAudioTrackEngine.kt` | Pemilik satu output, thread mixing, bus clock, play/pause global, gain per deck, metrik |
| `audio/mixer/DeckAudioSink.kt` | Implementasi kontrak `AudioSink` per deck (tanpa AudioTrack) |
| `audio/mixer/DeckAudioPipeline.kt` | Processor chain per deck (`ToFloat → NativeDsp → StereoWiden → Reverb → Stretch → AutoMixTone`) + normalisasi bus |
| `audio/mixer/DeckTimelineMap.kt` | Mapping frame output deck ↔ posisi media sumber |
| `audio/mixer/PcmRingBuffer.kt` | Ring SPSC bounded 500 ms per deck, backpressure tanpa drop |
| `audio/mixer/SincResampler.kt` | Referensi Kotlin konversi sample-rate stereo 32-tap windowed sinc (anti-alias saat downsampling) |
| `audio/mixer/MixDsp.kt` | Referensi Kotlin bus limiter pasca-summing + smoothing gain per deck |
| `audio/mixer/NativePcmBridge.kt` | Wrapper JNI `libpcm_mixer_native.so`; gagal-terbuka ke implementasi Kotlin |
| `src/main/cpp/pcm/pcm_native.cpp` | C++/NEON: konversi PCM, resampling sinc, gain ramp, summing dua deck, limiter bus |
| `src/main/cpp/pcm/pcm_native_jni.cpp` | Validasi handle/buffer/array JNI tanpa exception ke audio thread |
| `src/main/cpp/CMakeLists.txt` | Target `pcm_mixer_native` (arm64, `-O3`, NEON intrinsics) |
| `audio/mixer/Media3SharedAudioOutput.kt` | Adapter `DefaultAudioSink` tunggal + forward event/audio session |
| `Media3PlaybackService.kt` | Membuat engine sebelum player pertama, memilih deck sink vs legacy sink, release saat teardown |

Keputusan implementasi yang menyimpang dari proposal:

- **Bus rate is authoritative end-to-end**: the engine configures the physical sink at its
  selected `busSampleRate`, and ring/mix-block sizes scale with that rate.
- **Audible timeline mapping is per deck**: consumed deck ranges are mapped to absolute bus
  frames and retained until the shared output playhead passes them. This avoids advancing
  positions from decoder/mixer consumption while PCM remains inside the hardware buffer.
- **JNI processors receive direct input buffers**: the deck pipeline copies decoder bytes into
  a reusable direct ByteBuffer before processing so Signalsmith can access samples through
  `GetDirectBufferAddress()`.
- **EOS backpressure is lossless**: a timed-out ring drain keeps pending PCM and retries
  during Media3 `hasPendingData()/isEnded()` polling instead of dropping it.
- **Bit-Perfect is exclusive**: the shared sink is reset before its clean player starts and
  the mixer reconfigures when normal dual-player playback resumes.
- **Sample math lives in C++/NEON, state stays in Kotlin**: `libpcm_mixer_native.so` owns
  byte→stereo-float conversion, windowed-sinc resampling, per-frame gain ramps, two-deck
  summing and the post-sum limiter. Kotlin still owns ring buffers, source-timeline maps,
  the Media3 `AudioSink` contract, EOS/position state and the single hardware sink. No native
  code creates an `AudioTrack`.
- **Native is optional and fail-open**: if the library is missing, an ABI/symbol mismatches,
  or a native call rejects a block, the affected deck/bus falls back to the existing Kotlin
  `PcmConversions`/`SincResampler`/`BusLimiter` implementations. `SingleAudioTrackEngine.enabled`
  remains the independent kill switch for the whole shared-output path.
- **Parity is intentional**: native constants match the Kotlin reference (32 taps, 256 phases,
  12 ms gain smoothing, 0.98 ceiling, 50 ms limiter release, stereo float bus), so enabling
  the native path does not change gain, limiting or resampling semantics.

- **Bus rate dipilih sekali per sesi dari sample rate output native perangkat**
  (`AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE`, fallback 48 kHz), stereo float. Ini
  menjamin satu AudioTrack, menghindari rekonfigurasi di tengah transisi, dan tidak
  melakukan resampling ganda pada perangkat 44.1 kHz. Setiap deck yang rate-nya berbeda
  dikonversi dengan `SincResampler`.
- **Bit-Perfect Mode tetap memakai player/sink bersihnya sendiri** dan tidak berjalan
  bersamaan dengan AutoMix/crossfade, sesuai batas di bagian 4.
- **`flushBusForSeek`** hanya mem-flush output hardware bila deck yang di-seek sendirian dan
  tidak ada frame lain yang belum diputar; selama overlap, flush per deck tidak menyentuh
  output bersama.
- **Kill switch**: `SingleAudioTrackEngine.enabled = false` sebelum player dibuat akan
  mengembalikan jalur legacy dua AudioTrack tanpa perubahan lain.

Gate Phase 0 (bukti jumlah `AudioTrack` saat runtime) dilayani oleh log engine
`AudioTrack initialized/released ... activeAudioTrackCount=...`; gate Phase 5
(capture PCM, listening test, stress test perangkat) tetap wajib dijalankan di perangkat
nyata sebelum flag dianggap final.

## 1. Tujuan

Pertahankan dua deck yang bisa decode dan preload secara independen, tetapi jumlah output device `AudioTrack` aktif harus **tepat satu**, termasuk selama crossfade.

Target alur:

- Deck A tetap memainkan lagu outgoing.
- Deck B tetap decode/preload lagu incoming secara paralel.
- PCM dari kedua deck diproses secara terpisah, lalu di-align dan dijumlahkan di software mixer.
- Hanya satu output sink yang menulis hasil mix ke satu `AudioTrack`.
- AutoMix tetap dapat mengatur tempo, pitch, beat phase, gain envelope, bass swap, transition cue, dan limiter.

Scope awal adalah mode playback biasa dan AutoMix. Bit-Perfect Mode tetap eksklusif dan tidak berjalan bersamaan dengan crossfade, karena software mixing mensyaratkan PCM decode, pemrosesan, dan kemungkinan resampling.

## 2. Baseline saat ini

`Media3PlaybackService.createConfiguredPlayer()` membuat `DefaultAudioSink` melalui `DefaultRenderersFactory.buildAudioSink()` untuk setiap ExoPlayer. Active player dan standby player memiliki processor chain masing-masing. Standby sengaja diprewarm agar siap saat fade dimulai; konsekuensinya, kedua jalur bisa membuka output audio mereka sendiri.

Jangan menyelesaikan masalah dengan mengembalikan **instance `AudioSink` yang sama** langsung dari factory untuk dua ExoPlayer. Kontrak `AudioSink` meliputi `configure`, `flush`, `play/pause`, `handleBuffer`, EOS, dan posisi playback. Dua pemilik dapat mengubah konfigurasi atau flush satu sink, sedangkan position/EOS sink hanya punya satu timeline. Itu bukan desain multi-deck yang aman.

Rujukan kode:
- `android/app/src/main/kotlin/dev/wndavenz/music/Media3PlaybackService.kt`
- `android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt`
- `android/app/src/main/kotlin/dev/wndavenz/music/effects/StretchAwareAudioProcessorChain.kt`

Media3 menyediakan extension point resmi untuk mengganti `AudioSink` dari `DefaultRenderersFactory`. `AudioSink` menerima PCM buffer dan mengekspos playback-position/EOS contract, sehingga adapter per deck dan sink output terpusat bisa dibangun tanpa mengubah analyser AutoMix terlebih dahulu. API ini `@UnstableApi`, jadi implementasi harus dikunci pada versi Media3 yang dipakai aplikasi.

Referensi:
- https://developer.android.com/reference/androidx/media3/exoplayer/audio/AudioSink
- https://developer.android.com/reference/androidx/media3/exoplayer/audio/DefaultAudioSink
- https://github.com/androidx/media/blob/release/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/DefaultRenderersFactory.java
- https://github.com/androidx/media/blob/release/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/audio/DefaultAudioSink.java

## 3. Arsitektur yang direkomendasikan

```text
 ExoPlayer A / decoder                         ExoPlayer B / decoder
          |                                             |
          v                                             v
    DeckAudioSink A                               DeckAudioSink B
          |                                             |
          v                                             v
  Per-deck PCM pipeline                         Per-deck PCM pipeline
  - ToFloat / decode format                     - ToFloat / decode format
  - Native DSP                                   - Native DSP
  - Stereo width / reverb                        - Stereo width / reverb
  - Signalsmith Stretch                           - Signalsmith Stretch
  - AutoMix tone / per-deck gain                  - AutoMix tone / per-deck gain
          |                                             |
          v                                             v
    bounded PCM ring A                           bounded PCM ring B
          \                                             /
           \                                           /
            +---------- SingleAudioTrackEngine --------+
                        - clock / PTS mapping
                        - C++/NEON sample-rate + channel normalize
                        - A/B alignment
                        - gain envelope / AutoMix controls
                        - C++/NEON sum + bus safety limiter
                                   |
                                   v
                          ONE DefaultAudioSink
                                   |
                                   v
                             ONE AudioTrack
                                   |
                                   v
                              AudioFlinger
```

### Ownership wajib

1. `DeckAudioSink A` dan `DeckAudioSink B` adalah adapter virtual. Keduanya **tidak boleh membuat `AudioTrack`**.
2. `SingleAudioTrackEngine` memiliki satu `DefaultAudioSink` output dan merupakan satu-satunya pemilik hardware output selama mode dual-player.
3. Hanya satu mixer/output thread yang memanggil metode stateful pada output sink. Jangan memanggil output sink bersamaan dari dua thread playback ExoPlayer.
4. Tiap deck memiliki processor state, ring buffer, playback position map, generation, dan status EOS sendiri.
5. Per-deck `flush()`/`seek()` membersihkan deck tersebut saja. Itu tidak boleh menghentikan atau me-reset deck lain maupun hardware sink.
6. `play/pause` yang diterima deck adapter mengubah status deck. Sink fisik di-play/pause oleh engine berdasarkan status global playback.
7. Sink hardware dirilis ketika engine shutdown, bukan ketika satu deck selesai atau melakukan seek.

## 4. Format PCM dan DSP placement

Mixer tidak boleh menjumlahkan buffer mentah yang berbeda format.

**Format internal bus:** PCM float, stereo, pada sample rate output yang dinegosiasikan untuk sesi. Jangan hard-code bahwa semua sumber 44.1 kHz atau 48 kHz; pilih format output yang didukung, lalu konversikan tiap deck ke format bus yang sama. Format bus boleh direkonfigurasi di batas lagu yang aman, bukan di tengah overlap.

**Pipeline per deck:**

1. Konversi input decoder ke float.
2. Native DSP dan efek yang memang perlu terisolasi per deck.
3. Stereo widening/reverb sesuai setting yang berlaku.
4. Signalsmith Stretch untuk tempo/pitch; live tempo-follow tetap menargetkan deck incoming.
5. AutoMix tone/EQ, per-deck gain dan limiter.
6. Normalisasi channel/sample-rate ke format bus PCM float. Pada build arm64, konversi +
   resampling dilakukan `pcm_native` (C++/NEON); jika native tidak tersedia dipakai
   `PcmConversions` + `SincResampler`.
7. Enqueue blok PCM ke ring milik deck tersebut.

**Bus bersama setelah mixing:**

1. Ambil sampel A/B pada indeks frame output yang sama.
2. Terapkan gain envelope bersama agar A/B memakai progress fade yang sama (`pcm_native` gain ramp pada arm64, `MixGain` sebagai referensi/fallback).
3. Jumlahkan dalam float dengan headroom (`pcm_native` dua-deck summing pada arm64).
4. Terapkan bus limiter/soft clip sebagai proteksi akhir; ini melengkapi limiter per deck, bukan menggantikannya (`pcm_native` limiter pada arm64, `BusLimiter` sebagai referensi/fallback).
5. Kirim PCM hasil mix ke satu `DefaultAudioSink`, yang menangani penulisan ke `AudioTrack`.

Pindahkan konversi akhir ke PCM16 ke output sink. Jangan mengonversi masing-masing deck ke PCM16 sebelum penjumlahan jika targetnya menjaga headroom dan menghindari clipping tambahan.

**Catatan kualitas:** software mixer tidak bit-perfect. Jika perlu mode bit-perfect, pertahankan jalur clean eksklusif dan cegah AutoMix/crossfade bekerja di mode itu.

## 5. Kontrak buffer dan backpressure

Setiap blok ring minimal membawa:

```text
DeckPcmBlock {
  generation
  sourceMediaStartUs
  sourceMediaDurationUs
  outputFrameCount
  sampleRate
  channelCount
  pcmFloatData
  flags: discontinuity / eos
}
```

Implementasi final dapat menyimpan metadata per slot ring alih-alih membuat object per buffer. Jangan melakukan alokasi, logging berat, lock yang berpotensi menunggu, atau I/O file pada jalur audio realtime.

Ketentuan:

- Ring bounded per deck; ukuran awal bisa diuji pada rentang sekitar 250–500 ms PCM per deck, lalu diukur dengan perangkat nyata.
- Ketika ring penuh, adapter memberi backpressure melalui kontrak `handleBuffer`; jangan diam-diam membuang buffer atau memajukan `ByteBuffer.position` melewati sampel yang benar-benar diterima.
- Jika salah satu deck tidak memiliki data pada waktu output yang dijadwalkan, mix policy harus membedakan underrun dari deck yang memang belum mulai atau sudah EOS. Catat underrun sebagai metrik.
- Jangan memblokir thread decoder terlalu lama. Mixer output harus tetap bisa mengonsumsi ring; jika producer terus tertinggal, gunakan mekanisme buffering/recovery, bukan drop PCM tanpa notifikasi.
- Reset ring menggunakan generation/epoch supaya buffer lama setelah seek, cancel, atau pergantian lagu tidak bocor ke transisi baru.

## 6. Sinkronisasi waktu dan posisi playback

Ini adalah bagian paling berisiko. Mixer punya satu hardware playback head, tetapi dua ExoPlayer memiliki media timeline yang berbeda.

### Clock model

- Gunakan frame clock output sebagai satu-satunya jam playout fisik.
- Tiap deck memiliki mapping antara `sourceMediaStartUs` dan rentang frame yang benar-benar dikirim ke bus.
- Deck aktif menetapkan anchor awal media-position ke output-frame timeline.
- Deck standby mendapat anchor sendiri saat dijadwalkan mulai, termasuk posisi seek untuk drop cue.
- Mapping menyimpan durasi media sumber dan jumlah frame output setelah Stretch/resampling; jangan mengasumsikan rasio tetap jika tempo-follow berubah selama fade.
- `DeckAudioSink.getCurrentPositionUs()` melaporkan media position per deck dari frame output yang sudah dimainkan, bukan sekadar posisi decoder atau indeks ring yang sudah dibaca mixer.
- `hasPendingData()` dan `isEnded()` harus menunggu data deck tersebut benar-benar melewati playback head output sebelum menyatakan selesai.
- `onPositionDiscontinuity`, seek, pause/resume, perubahan playback speed, perubahan tempo nudge dan format reconfigure harus memperbarui mapping/epoch secara eksplisit.

Jangan menggunakan `SystemClock` saja sebagai sumber kebenaran posisi. Ia boleh membantu penjadwalan, tetapi posisi audible harus dikorelasikan dengan frame yang telah diputar oleh output sink.

### Crossfade

`CrossfadeController` tetap menjadi pemilik keputusan *kapan* fade dimulai dan kapan active deck dipromosikan. Yang berubah ialah cara dua deck mencapai output:

- `prewarmStandby()` menyiapkan decoder dan mengisi ring B; tidak membuka AudioTrack kedua.
- Pada frame start yang dijadwalkan, engine menandai B sebagai audible dan mulai mencampur kedua ring.
- Progress fade berbasis output/media timeline terpetakan, bukan dua timer yang berjalan bebas.
- Pada completion, A berhenti menghasilkan data setelah tail habis, B melanjutkan sebagai active deck, lalu queue/proxy diperbarui.
- Pada abort, keluarkan A/B dari bus dengan aman, clear hanya ring/generation terkait, pulihkan gain/tempo/pitch/filter dan jangan flush sink fisik kecuali seluruh playback memang berhenti.

## 7. Batas integrasi file

Nama di bawah ini adalah usulan, bukan file yang sudah dibuat.

| Komponen | Tanggung jawab |
|---|---|
| `audio/mixer/SingleAudioTrackEngine.kt` | Lifecycle output sink, state global play/pause, output thread, metrik dan bus clock |
| `audio/mixer/DeckAudioSink.kt` | Implementasi `AudioSink` per ExoPlayer; terima format/buffer dan masukkan ke pipeline/ring deck |
| `audio/mixer/DeckAudioPipeline.kt` | Memproses PCM per deck dan mengeluarkan float stereo format bus dengan timeline metadata |
| `audio/mixer/DeckTimelineMap.kt` | Mapping source media PTS ↔ output frame cursor per deck |
| `audio/mixer/PcmRingBuffer` | Ring bounded multi-frame, backpressure, discontinuity dan EOS |
| `src/main/cpp/pcm/pcm_native.cpp` | Fast-path konversi/resampling/mixing/limiter C++/NEON |
| `src/main/cpp/pcm/pcm_native_jni.cpp` + `NativePcmBridge.kt` | Batas JNI tervalidasi, fail-open ke Kotlin |
| `Media3PlaybackService.kt` | Buat engine dulu; injeksikan adapter A/B lewat factory, wiring global play/pause/focus/shutdown |
| `CrossfadeController.kt` | Pertahankan cue/planner; ubah interface fade agar memerintah mixer envelope/output-frame schedule, tidak menulis gain hardware secara terpisah |
| `AutomixToneManager.kt` | Tetap per-deck; pisahkan target gain per-deck dari envelope master crossfade untuk mencegah gain diterapkan dua kali |

Hindari rewrite massal `Media3PlaybackService.kt`. Tambahkan interface `DeckOutput`/`SharedAudioOutput` lalu migrasi secara bertahap. Jangan mengubah algoritma analyzer, octave-lock, atau downbeat saat pekerjaan ini dimulai.

## 8. Rollout bertahap

### Phase 0 — Baseline dan instrumentasi

- Rekam jumlah `AudioTrack` aktif, sample rate, channel mask, buffer duration, underrun, audio session ID, decoder, dan posisi media tiap deck.
- Tambahkan tes/fixture transisi A→B tanpa mengganti jalur output saat ini.
- Simpan jalur lama sebagai fallback sampai semua acceptance gate terpenuhi.

**Gate:** ada bukti runtime berapa `AudioTrack` dibuat selama prewarm, overlap, abort, dan completion.

### Phase 1 — Adapter virtual per deck

- Implementasikan `DeckAudioSink` pada versi Media3 yang dipin.
- Implementasikan semantik `configure`, `handleBuffer`, `flush`, `play/pause`, EOS, readiness, position, playback parameters dan release tanpa membuka output hardware.
- Awali dengan fake output/PCM capture untuk memvalidasi kontrak sebelum hardware mixing.

**Gate:** tes kontrak sink deterministik lulus; `flush()` pada B tidak merusak A; `handleBuffer` tidak kehilangan/menggandakan byte saat backpressure.

### Phase 2 — Shared mixer + satu output sink

- Implementasikan bounded ring A/B dan satu consumer output.
- Standarkan format bus dan clock/PTS mapping.
- Buka satu `DefaultAudioSink` untuk hasil mix saja.
- Mulai dari crossfade linear/equal-power sederhana; belum pindahkan semua fitur AutoMix.

**Gate:** tes dua sine wave dengan fase/gain terkontrol menghasilkan hasil sum yang benar; instrumentasi membuktikan maksimum satu AudioTrack aktif.

### Phase 3 — Media3 timeline dan lifecycle

- Sambungkan `getCurrentPositionUs`, `hasPendingData`, EOS, discontinuity, seek, pause/resume, audio focus dan shutdown.
- Pastikan active player proxy/notification/queue index tetap konsisten ketika deck dipromosikan.
- Pastikan service tak melepas output sink ketika standby di-reset.

**Gate:** position drift dibatasi oleh ambang yang didefinisikan dalam test; tak ada READY/BUFFERING oscillation, deadlock, atau audio hilang saat pause/resume/seek.

### Phase 4 — Migrasi DSP dan AutoMix

- Pindahkan sample-domain bus (konversi, resampling, gain ramp, summing, limiter) ke
  `libpcm_mixer_native.so` (C++/NEON) dengan fallback Kotlin yang dipertahankan.
- Pindahkan semua DSP yang memang per-deck ke pipeline deck, dengan sample-rate/channel normalization setelah efek yang membutuhkan format sumber.
- Terapkan satu gain-envelope authority untuk menghindari gain ganda dari ExoPlayer volume, tone processor, dan mixer.
- Pindahkan bus headroom/limiter ke setelah summing.
- Sambungkan live tracker dan phase-lock ke media/output clock mapping yang benar; pastikan live tracker membaca PCM per deck sebelum mixing.
- Pertahankan gate beat-match dan fallback crossfade biasa bila grid tidak valid.

**Gate:** regression suite analyzer/planner tidak berubah; phase-lock dan tempo-follow stabil ketika rasio Stretch berubah di tengah fade.

### Phase 5 — Rollout dan fallback

- Aktifkan lewat feature flag internal, bukan langsung untuk seluruh pengguna.
- Canary dulu pada PCM stereo 44.1/48 kHz; kemudian mono/multichannel dan format decoder lain.
- Jalankan stress test queue panjang, shuffle/repeat, sleep timer, route/headphone changes, audio focus interruption, app background/foreground dan service teardown.
- Pertahankan jalur lama hingga semua test device dan CI lulus; sediakan rollback tanpa migrasi cache atau perubahan format preferensi pengguna.

## 9. Regression test wajib

### JVM/unit

- Ring: wraparound, full/empty, frame alignment, partial consume, discontinuity, stale generation.
- Mixing: A-only, B-only, A+B, silence, opposite phase, correlated peaks, gain ramp, limiter release.
- Timeline map: normal playback, speed changes, tempo nudge berubah, seek, timestamp jump, buffer partial, EOS.
- Sink contract: configure ulang format; panggilan flush di satu deck; release satu deck; `playToEndOfStream`; repeated `handleBuffer` saat ring penuh.
- Lifecycle: pause, resume, audio-focus duck, interruption, cancel mid-fade, outgoing EOF, standby decoder error, service destruction.

### Native DSP host tests

- Konversi semua format (U8/S16/S24/S32/F32/F64), little/big endian, mono/stereo/surround.
- Resampling block-size invariance: output untuk partisi blok berbeda harus identik (tidak ada klik di sambungan blok), plus cek amplitudo/RMS dan downsampling 48→44.1 kHz.
- Gain ramp: satu-pole 12 ms, deck nonaktif tidak mengubah gain, target 0/1.
- Limiter: ceiling 0.98, release 50 ms, perilaku sample non-finite (silence tanpa memajukan envelope), reset state.
- Batas buffer: output terlalu pendek ditolak tanpa memajukan history; blok mixer melebihi `max_frames` ditolak.
- Jalankan `src/main/cpp/pcm/tests/run_host_tests.sh` di x86-64 (scalar) dan aarch64
  (NEON, via QEMU) serta di bawah ASan/UBSan. `tests/jni/run_jni_smoke.sh` memvalidasi
  offset direct buffer, array marshalling, dan siklus handle pada JVM desktop.

### Integration/device

- Tepat satu `AudioTrack` aktif saat standby prewarm dan sepanjang overlap.
- Tak ada gap/click di start, tengah, atau akhir fade; tangkap PCM output untuk inspeksi discontinuity.
- Track B tetap sinkron setelah dipromosikan; tak ada pengulangan queue[0], timeline satu-item yang tertinggal, atau active player/proxy yang salah.
- Samplerate mismatch 44.1↔48 kHz, mono↔stereo, decoder hardware↔FFmpeg, dan file yang gagal decode.
- AutoMix: confident match, BPM mismatch, half/double tempo, downbeat tidak diketahui, edge grid tidak stabil, drop cue, bass swap, tempo-follow dan cancellation.
- Jalankan CI untuk Flutter/Dart, Kotlin, native C + ASan/UBSan, ARM64/NEON, lalu APK ARM64.

### Metrik penerimaan awal

- `activeAudioTrackCount <= 1` pada seluruh sesi dual-player; tidak boleh ada overlap dua hardware output.
- Nol dropped/duplicated PCM frames akibat ring/mixer dalam tes deterministik.
- Tidak ada nilai non-finite dan tidak ada output sample di luar batas limiter yang ditetapkan.
- Posisi tiap deck mengikuti frame yang sudah dimainkan; drift threshold ditetapkan dan diuji eksplisit, bukan hanya visual progress bar.
- Tidak ada regression pada test downbeat/octave-lock yang sudah lolos.
- Capture output dan listening test perangkat nyata lulus sebelum jalur baru menjadi default.

## 10. Risiko dan keputusan eksplisit

1. **Kompleksitas tertinggi adalah `AudioSink` clock contract**, bukan operasi menjumlahkan PCM. Salah pada pemetaan posisi/EOS akan menghasilkan posisi track melompat, buffer oscillation, atau transisi putus meskipun suara hasil sum tampak benar.
2. **Prewarm harus memanaskan decoder, bukan output kedua.** Jangan menjalankan standby dengan sink default yang membuat `AudioTrack` hardware.
3. **AudioTrack playback head hanya satu.** Posisi tiap deck wajib diturunkan melalui mapping frame output-ke-source; jangan membagi satu posisi sink yang sama kepada kedua player.
4. **Bus limiter baru memberikan proteksi setelah summing.** Limiter per deck tetap dapat dipakai, tetapi jangan klaim true-peak end-to-end tanpa validasi output akhir.
5. **Bit-Perfect Mode tetap terpisah.** Crossfade/AutoMix dan bit-perfect tidak bisa menjadi jalur serentak dalam arsitektur software PCM mixing.
6. **Jangan langsung menghapus implementasi dual-sink lama.** Pindah hanya sesudah instrumentation membuktikan tepat satu output Track dan regression suites lulus.

## 11. Keputusan yang disarankan

Pilih **dua ExoPlayer + dua virtual `DeckAudioSink` + satu `SingleAudioTrackEngine` + satu output `DefaultAudioSink`**. Pertahankan planner, analyzer, queue ownership, active-player proxy dan sebagian besar `CrossfadeController`; migrasikan hanya titik output dan timeline contract terlebih dahulu.

Jangan memulai dari penggantian total ke custom decoder/AudioTrack mentah. Itu memperbesar area risiko pada Media3 decoder compatibility, audio focus, routing, buffer sizing, playback position, dan lifecycle sekaligus. Gunakan Media3 sink contract sebagai batas integrasi dan lakukan POC output satu Track lebih dulu.
