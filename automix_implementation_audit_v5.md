# Audit Implementasi AutoMix — v5 (2026-10-23)

**Status:** Audit lanjutan atas v4, dipicu oleh laporan transisi A→B yang terdengar terpotong pada jalur *early handover*. Dua bug **Tinggi** ditemukan dan diperbaiki.
**Repository:** `wandavenus/Dump`
**Basis kode:** `e8dd52b8` + patch perbaikan AutoMix `55fa5adf`
**Perubahan kode/test:** 11 berkas (8 diubah, 3 baru), tidak termasuk `GeneratedPluginRegistrant.java` yang sudah berubah sebelum audit ini. Dokumentasi diperbarui di `docs/automix-production-wiring.md` dan v4 diberi pointer ke dokumen ini.
**Metode:** penelusuran call-site Dart → MethodChannel → Kotlin → `CrossfadeController` → `ExoPlayer`/Media3, pembacaan test yang ada, regression test Flutter/Kotlin, lalu render PCM offline 48 kHz dan pengukuran independen dengan FFmpeg `astats`.
**Batasan:** tidak ada perangkat/emulator atau capture output AudioFlinger. Validasi audio dilakukan offline dari sinyal 48 kHz dan envelope produksi; scheduling ExoPlayer/AudioFlinger serta kualitas audible di perangkat tetap memerlukan listening test.

## Ringkasan eksekutif

Laporan "transisi A→B kadang kasar, terutama saat early handover" bukan disebabkan oleh kurva fade atau cue drop yang buruk. Ada dua jalur independen yang dapat memotong fade yang sedang berjalan:

1. **Update durasi crossfade di tengah fade** — native `setCrossfadeDuration` selalu memanggil `cancel(resetVolume = true)`. Dart mengirim update ini setiap kali track berganti, dan promosi B pada awal fade A→B memang dianggap track berganti. Fade baru saja dimulai, lalu dibatalkan: A dihentikan dan B langsung berbunyi pada volume sebelum duck (biasanya mendekati penuh).
2. **Promosi deck menyalin volume deck keluar** — `ActivePlayerProxy.switchTo` menyalin volume A ke B yang baru saja di-mute. B sudah `play()` sebelum tick fade pertama, sehingga ada jendela audible di mana B berbunyi pada volume A (sering mendekati penuh di awal fade).

Keduanya diperbaiki dengan pertahanan berlapis: guard di Dart, guard otoritatif di native, dan test regresi di kedua sisi.

| ID | Severity | Topik | Status |
|---|---|---|---|
| AM5-01 | Tinggi | `setCrossfadeDuration` membatalkan fade yang sedang berjalan | Fixed |
| AM5-02 | Tinggi | Promosi deck menyalin volume deck keluar sehingga B tidak tetap mute | Fixed |

## Alur yang diaudit

1. Dart menghitung `transitionStartMs` 30–65 detik sebelum EOF bila drop incoming dan kedua beat grid cukup yakin. Nilai ini dikirim bersama target AutoMix.
2. Native memvalidasi lead terhadap durasi Media3 yang sebenarnya (`AutomixTransitionPolicy.resolveEarlyHandoverStartMs`), lalu `CrossfadeController.maybeCrossfadeOut` menjadwalkan fade dan memanggil `beginCrossfade`.
3. `beginCrossfade` mempromosikan standby B: `standby.volume = 0`, `setActivePlayer(standby)`, `setActiveQueueIndex(nextIndex)`, lalu `switchSessionPlayer(standby)`.
4. Promosi memicu `emitAll()`/callback playback. Dart melihat B sebagai current, lalu menjalankan replan untuk pasangan B→C.
5. Replan memanggil `_engageCrossfade` dan `AudioService.setAutomixTransition`. Target transisi sudah ditunda oleh native saat fade aktif, tetapi **durasi crossfade belum ditunda** sebelum perbaikan ini.
6. Secara paralel, `AudioService._syncCurrentTrackFromNative` memanggil `AudioEffectsService.applyAll()` pada setiap perubahan track. `applyAll` juga mengirim `setCrossfadeDuration`.

Urutan inilah yang membuat bug sangat terasa pada early handover: fade dimulai puluhan detik sebelum EOF, jadi pembatalan terjadi saat A masih memiliki banyak materi audio yang seharusnya ikut memudar, bukan di detik terakhir ketika potongan mungkin tertutup oleh akhir lagu.

## Temuan rinci

### AM5-01 — Update durasi crossfade membatalkan fade yang sedang berjalan (Tinggi, Fixed)

**Lokasi:** `android/app/src/main/kotlin/dev/wndavenz/music/transport/TransportCommands.kt:445-477`, `lib/services/automix_service/service.dart:1646-1671`, `lib/services/audio/audio_effects_service/service.dart:301`.

**Akar masalah:** handler `setCrossfadeDuration` sebelumnya tidak membedakan "ubah durasi untuk transisi berikutnya" dari "batalkan transisi sekarang". Untuk nilai positif apa pun, urutannya adalah:

```kotlin
crossfadeController.setDuration(sec)
crossfadeController.cancel(resetVolume = true)
preloadManager.clearStandbyQueue()
restoreQueueAfterCrossfadeCancel(...)
```

`cancel(resetVolume = true)` saat `crossfadeInProgress`:

- menghentikan `promotionOwner`, yaitu deck A yang sedang fade-out (`CrossfadeController.kt:432-445`);
- menghapus runnable fade sehingga tidak ada tick berikutnya;
- mengembalikan volume deck aktif B ke `volumeBeforeDuck` (`CrossfadeController.kt:452`).

Hasilnya adalah hard cut: A berhenti mendadak, B yang baru dipromosikan langsung berbunyi pada volume sebelum duck (biasanya mendekati penuh). Pada early handover, A berhenti 30–65 detik sebelum akhir lagu, sehingga potongannya jelas terdengar.

**Mengapa terpicu setiap transisi:** signature rencana native memuat `currentSong.id`. Begitu B dipromosikan, signature berubah, `_prepareUpcomingTracks` menjalankan `_engageCrossfade` lagi, dan nilai `fadeSeconds` biasanya sama dengan yang sudah aktif. Sebelum perbaikan, nilai yang sama tetap dikirim ke native. Selain itu, `AudioService._syncCurrentTrackFromNative` memanggil `AudioEffectsService.applyAll()` pada setiap track change (`lib/services/audio_service/service.dart:497`), dan `applyAll` selalu mengirim `PlaybackManager.setCrossfadeDuration(crossfadeDuration.value)` (`lib/services/audio/audio_effects_service/service.dart:301`). Jadi guard di Dart saja tidak cukup: caller lain tetap dapat memicu jalur native yang sama.

**Perbaikan:**

- **Native (otoritatif):** bila `crossfadeInProgress && sec > 0f`, handler hanya memperbarui durasi untuk transisi berikutnya dan eligibility offload, lalu return. Tidak ada `cancel`, `clearStandbyQueue`, atau queue restore. Nilai `sec <= 0` tetap memakai jalur lama karena nol berarti crossfade dimatikan dan fade aktif memang harus dihentikan (`TransportCommands.kt:454-462`).
- **Dart (mengurangi round-trip):** `_engageCrossfade` tidak lagi mengirim durasi yang sama saat sesi AutoMix sudah aktif (toleransi 0,01 detik). Durasi yang benar-benar berbeda tetap dikirim dan native menerapkannya ke transisi berikutnya (`service.dart:1660-1671`).
- Hook `engageCrossfadeForTesting` ditambahkan agar guard Dart dapat diuji tanpa membuka seluruh pipeline.

**Regresi:**

- `TransportCommandsTest.kt` — durasi positif saat fade aktif hanya memanggil `setDuration` + `onCrossfadeDurationChanged`; `cancel`, `clearStandbyQueue`, dan pemulihan queue tidak dipanggil. Durasi nol tetap membatalkan fade.
- `automix_start_test.dart` — engagement pertama mengirim durasi; engagement ulang dengan nilai sama tidak mengirim apa pun; nilai berbeda dikirim tepat sekali.

**Catatan desain:** pembatalan fade oleh aksi pengguna yang memang menghentikan playback (pause/stop, headphones unplug, audio focus loss, atau menonaktifkan crossfade) tetap memakai `cancel(resetVolume = true)`. Yang diperbaiki adalah rekonfigurasi durasi, bukan seluruh jalur cancel.

### AM5-02 — Promosi deck menyalin volume deck keluar (Tinggi, Fixed)

**Lokasi:** `android/app/src/main/kotlin/dev/wndavenz/music/ActivePlayerProxy.kt:87-109`, `android/app/src/main/kotlin/dev/wndavenz/music/Media3PlaybackService.kt:493-500`, `android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt:630-663`.

**Akar masalah:** `CrossfadeController.beginCrossfade` sudah melakukan hal yang benar dengan mengeset `standby.volume = 0f` sebelum promosi. Namun `ActivePlayerProxy.switchTo(newPlayer)` selalu menyalin volume deck lama ke deck baru:

```kotlin
newPlayer.volume = _current.volume.coerceIn(0f, 1f)
```

Pada crossfade, `newPlayer` adalah B yang baru saja di-mute, sedangkan `_current.volume` adalah volume A yang pada awal fade masih mendekati penuh. Urutan setelah itu adalah `standby.play()`, baru kemudian `runEqualPowerFade` memposting tick pertama. Antara `play()` dan tick pertama, B dapat berbunyi pada volume A. Jika main thread sibuk, jendela ini bisa lebih panjang dari 16 ms. Ini menghasilkan blip/hentakan masuk yang tidak sesuai dengan kurva equal-power.

**Perbaikan:**

- `switchTo` sekarang memiliki parameter `copyVolume: Boolean = true`. Default tetap menyalin volume agar perpindahan engine seperti Bit-Perfect Mode tidak mengubah volume pengguna.
- Jalur promosi crossfade memanggil `switchTo(newPlayer, copyVolume = false)` sehingga gain B tetap di bawah kendali `CrossfadeController`.
- Sebagai pertahanan tambahan, controller mengeset ulang `standby.volume = 0f` segera setelah `switchSessionPlayer(standby)`, sebelum `play()`. Ini melindungi implementasi switch alternatif atau perubahan urutan di masa depan.

**Regresi:**

- `ActivePlayerProxyTest.kt` G09 memastikan switch default tetap membawa volume pengguna; G10 memastikan `copyVolume = false` tidak menyentuh volume deck baru.
- `CrossfadeControllerTest.kt` F13 mensimulasikan switch yang menyalin volume 1.0 dan memastikan volume terakhir B setelah promosi adalah 0, sebelum tick fade dijalankan.

### Jalur terkait yang diperiksa dan tidak memerlukan perubahan

- **Target AutoMix saat fade aktif:** sudah ditunda dengan benar. `Media3PlaybackService.applyAutomixTransition` menyimpan update ke `pendingAutomixTransition` selama `crossfadeInProgress` dan menerapkannya setelah fade selesai (`Media3PlaybackService.kt:2382-2396`). Guard durasi melengkapi perilaku ini.
- **Reorder queue saat fade aktif:** `QueueManager.reorderUpcomingByIds` menolak selama crossfade (`QueueManager.kt:194`). Replan yang tertunda akan di-retry, bukan memutasi timeline yang sedang dipakai fade.
- **Promosi dan state fade:** `crossfadeInProgress` sudah diset sebelum promosi, sehingga jalur deferral di atas aktif sejak awal fade.
- **Tick fade:** kurva equal-power dan integrasi waktu media tidak diubah. Perbaikan hanya memastikan fade tidak dibatalkan dan deck masuk tidak dibunyikan sebelum tick pertama.

## Verifikasi

Seluruh pemeriksaan dijalankan di lingkungan ini setelah perubahan.

| Pemeriksaan | Perintah | Hasil |
|---|---|---|
| Analyzer Dart | `dart analyze lib/services/automix_service/service.dart test/services/automix_service/automix_start_test.dart` | `No issues found!` |
| Suite AutoMix Dart | `flutter test test/services/automix_service` | 124 test lulus |
| Suite Kotlin penuh | `./gradlew :app:testDebugUnitTest` | `BUILD SUCCESSFUL`; 431 test, 0 failure, 0 error |
| Regresi audio FFmpeg + JVM | `tools/automix_ffmpeg_regression.sh` | `RESULT: PASS` |
| Whitespace | `git diff --check` | Lulus |

Test regresi baru yang dijalankan di dalam suite tersebut:

| Test | Yang dikunci |
|---|---|
| `TransportCommandsTest` — positive duration during fade | Fade aktif tidak dibatalkan; hanya durasi transisi berikutnya yang berubah |
| `TransportCommandsTest` — zero duration during fade | Mematikan crossfade tetap membatalkan fade dan membersihkan standby |
| `CrossfadeControllerTest` F13 | Deck masuk tetap mute setelah promosi meskipun switch menyalin volume |
| `ActivePlayerProxyTest` G09/G10 | Copy volume default tetap aman; jalur crossfade tidak menimpa gain |
| `automix_start_test.dart` re-engage | Durasi sama tidak dikirim ulang; durasi berbeda dikirim sekali |

### Validasi audio offline (FFmpeg + JVM render)

`tools/automix_ffmpeg_regression.sh` menjalankan rantai berikut:

1. FFmpeg membuat dua sinyal sumber 48 kHz mono, 32-bit float, durasi 4 detik: A 220 Hz/0,5 dan B 330 Hz/0,4. Fase dipilih agar sample pada 1,7 detik bernilai A=−0,5 dan B=+0,4, sehingga hard cut pada skenario lama deterministik.
2. `AutomixFadeRenderTest` membaca WAV sumber tersebut, menerapkan `AutomixGainEnvelope` produksi pada tick 16 ms, dan menulis WAV hasil render untuk jalur saat ini serta dua model regresi lama.
3. FFmpeg `astats` mengukur peak level dan max sample-to-sample difference secara independen dari kode Kotlin.

Hasil aktual:

| Render | max sample step | Peak | Interpretasi |
|---|---:|---:|---|
| `current_envelope_gamma1.wav` | 0,019556 | −6,0206 dBFS | Kontinu; tidak ada lompatan sebesar klik |
| `current_envelope_gamma135_trims.wav` | 0,018705 | −6,0206 dBFS | Kurva/trim lain juga kontinu |
| `legacy_midfade_cancel.wav` | 0,525177 | −6,0206 dBFS | Model bug AM5-01 terdeteksi sebagai hard cut |
| `legacy_volume_copy.wav` | 0,399793 | −0,9153 dBFS | Model bug AM5-02 terdeteksi; peak tick pertama 5,1 dB di atas jalur saat ini |

Ambang yang dipakai: jalur saat ini `< 0,05` max sample step; kedua model lama `> 0,25` dan `> 0,20`; semua peak `≤ 0 dBFS`; format `pcm_f32le/48000 Hz/mono`; durasi 4 detik. Semua ambang lulus.

Artefak tersimpan di `build/automix-audio-regression/` (WAV, waveform PNG, `metrics.txt`). Model `legacy_*` adalah simulasi fault path lama, bukan rekaman output perangkat; nilainya berfungsi sebagai kontrol sensitivitas metrik, bukan bukti kondisi lapangan.

Render ini menguji `AutomixGainEnvelope` (jalur fallback Kotlin). Saat AutoMix crossfade aktif dan `setAutoMixCrossfadeGains` tersedia, envelope per-deck diterapkan di native C/NEON; jalur native tersebut tidak dirender oleh harness ini. Sinyal sumber juga berupa sine deterministik, bukan musik, sehingga metrik ini mengukur continuity dan peak, bukan persepsi musikal.

## Risiko residual

1. **Belum ada validasi perangkat.** Validasi offline sudah mengukur sample continuity dan peak dari `AutomixGainEnvelope` Kotlin, tetapi belum menguji jalur native C/NEON per-deck, listening test, log `CrossfadeTimelineLogger` dari perangkat, atau capture output AudioFlinger. Scheduling ExoPlayer, buffer AudioTrack, dan perilaku main thread pada perangkat lambat belum tercakup.
2. **Durasi nol di tengah fade tetap hard-stop.** Ini disengaja: `sec <= 0` berarti pengguna/UI mematikan crossfade. Jika UI mengirim nol secara tidak sengaja saat AutoMix aktif, gejalanya masih dapat berupa potongan. Guard Dart hanya menghindari pengiriman nilai yang sama; nilai nol yang eksplisit tetap diteruskan.
3. **Keterlambatan tick pertama.** Dengan `copyVolume = false`, jika main thread tertahan setelah `play()`, B tetap mute sampai fade mulai menaikkan gain-nya. Render offline menunjukkan sisa gejala berupa keheningan singkat, bukan blip volume penuh; durasi jeda pada perangkat nyata belum diukur.
4. **Kualitas cue early handover tetap heuristik.** Perbaikan ini menghilangkan hard cut, bukan menjamin bahwa titik handover 30–65 detik selalu tepat secara musikal. Pemilihan drop/breakdown tetap bergantung pada confidence analyzer dan live tracker.
5. **Batas true-peak bus.** Dua deck masih disumkan downstream oleh AudioFlinger tanpa limiter bus bersama. Per-deck limiter bersifat kausal dan bukan jaminan true-peak end-to-end; ini batasan lama yang tidak berubah pada audit ini.
6. **Guard Dart bergantung pada `automixActive`.** Caller lain tetap dapat mengirim durasi; karena itu guard native adalah lapisan yang harus dipertahankan. Menghapus guard native dan hanya mengandalkan Dart akan membuka kembali bug ini.

## Berkas yang berubah

- `android/app/src/main/kotlin/dev/wndavenz/music/transport/TransportCommands.kt`
- `android/app/src/main/kotlin/dev/wndavenz/music/ActivePlayerProxy.kt`
- `android/app/src/main/kotlin/dev/wndavenz/music/Media3PlaybackService.kt`
- `android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt`
- `android/app/src/test/kotlin/dev/wndavenz/music/transport/TransportCommandsTest.kt` (baru)
- `android/app/src/test/kotlin/dev/wndavenz/music/ActivePlayerProxyTest.kt`
- `android/app/src/test/kotlin/dev/wndavenz/music/crossfade/CrossfadeControllerTest.kt`
- `android/app/src/test/kotlin/dev/wndavenz/music/automix/AutomixFadeRenderTest.kt` (baru)
- `tools/automix_ffmpeg_regression.sh` (baru)
- `lib/services/automix_service/service.dart`
- `test/services/automix_service/automix_start_test.dart`
- `docs/automix-production-wiring.md`

`android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` ikut terbawa di commit patch, tetapi perubahannya sudah ada sebelum audit ini dan tidak terkait AutoMix.

## Kesimpulan

Kedua penyebab hard cut pada early handover sudah ditutup di lapisan yang berbeda: Dart berhenti mengirim ulang durasi yang tidak berubah, native tidak lagi membatalkan fade aktif saat menerima durasi positif, dan promosi deck tidak lagi menyalin volume deck keluar. Regression test mengunci urutan-urutan tersebut. Validasi offline 48 kHz dengan FFmpeg `astats` menunjukkan jalur saat ini tidak memiliki lompatan sample sebesar klik, sementara dua model bug lama terdeteksi dengan jelas. Langkah berikutnya yang masih diperlukan adalah validasi audible di perangkat, idealnya dengan log timeline fade dan capture output AudioFlinger pada transisi early handover.
