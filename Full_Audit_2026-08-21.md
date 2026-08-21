# Full Code Audit — lib / android / native_audio_runtime

**Tanggal:** 21 Agustus 2026
**Commit:** `d4fffd8` ("fixx") pada `origin/main`
**Scope:** seluruh kode di `lib/`, `android/`, dan `native_audio_runtime/`
**Metode:** review manual arsitektur inti + pattern-scan otomatis (rg) untuk anti-pattern umum Dart/Kotlin/C/C++/JNI + verifikasi statis & test

---

## 1. Ringkasan Statistik

| Metrik | Nilai |
|---|---|
| Total LOC yang diaudit | ±67.000 (Dart, Kotlin, C, C++) |
| File Dart di `lib/` | 282 |
| Area native | C DSP pipeline, C++/C JNI bridges, Kotlin services |
| Temuan Critical | **0** |
| Temuan High | **0** |
| Temuan Medium | **1** |
| Temuan Low | **2** |
| Verifikasi `flutter analyze` | ✅ Bersih (0 issue) |
| Verifikasi `flutter test` | ✅ 63/63 lulus |

### Pattern-scan yang dijalankan

- Dart: catch kosong / `catch (_)` penelan error, `setState` setelah `await` tanpa guard `mounted`, interpolasi string ke raw SQL query.
- Kotlin: asersi non-null (`!!`), keseimbangan `registerReceiver`/`unregisterReceiver`, penggunaan `@Volatile`/`synchronized`, cakupan `runCatching`/`try`.
- C/C++: keseimbangan alloc/free, null-check pasca-alloc, pairing `Get*ArrayElements`/`Release*ArrayElements`, `ExceptionCheck`/`ExceptionClear`/`DeleteLocalRef` di JNI, pola `memcpy`.
- Manifest/Gradle/WebView: komponen `exported`, konfigurasi release, surface keamanan WebView.

---

## 2. Temuan

> Tidak ditemukan temuan Critical maupun High. Kode inti (audio engine, service lifecycle, DSP pipeline, JNI) dalam kondisi sangat matang dengan banyak perbaikan terdokumentasi dari audit-audit sebelumnya.

---

### [MED-1] Release build masih ditandatangani debug key

- **Severity:** Medium (release-readiness, bukan bug runtime)
- **File:** `android/app/build.gradle` (baris ~125)
- **Deskripsi:** Blok `buildTypes.release` memakai `signingConfig signingConfigs.debug` meski sudah menerapkan `minifyEnabled true`, `shrinkResources true`, dan proguard rules. Ini default scaffold Flutter.
- **Root cause:** Konfigurasi signing produksi belum dibuat.
- **Dampak:** APK/AAB tidak layak didistribusikan publik (tidak bisa upload ke Play Store, upgrade path antar-build tidak terjamin). Tidak berpengaruh pada penggunaan lokal/sideload dev.
- **Confidence:** Tinggi.
- **Rekomendasi:** Buat keystore release terpisah, definisikan `signingConfigs.release` membaca variabel dari `key.properties` (di luar git), lalu arahkan `signingConfig` release ke sana sebelum distribusi pertama.
- **Risiko jika diabaikan:** Kegagalan publish / kehilangan kemampuan update aplikasi terpasang.

---

### [LOW-1] Catch kosong tanpa logging di beberapa widget

- **Severity:** Low (observability)
- **File:** `lib/widgets/song_context_menu.dart` (2 lokasi), `lib/widgets/pages/radio_sections/station_card.dart`, `lib/widgets/pages/banners.dart` (`browse_sections`)
- **Deskripsi:** Pola `on Exception catch (_) {}` benar-benar kosong — tidak ada log maupun komentar maksud. Mayoritas situs `catch (_)` lainnya (44 total di `lib/`) sudah baik: ada guard `mounted`, fallback eksplisit, atau komentar penjelasan.
- **Root cause:** Inkonsistensi gaya error handling di layer UI.
- **Dampak:** Saat debugging, kegagalan operasi best-effort (mis. load artwork/banner/stasiun radio) tidak meninggalkan jejak sama sekali. Tidak ada risiko fungsional karena operasinya non-kritis dan sudah ada fallback UI.
- **Confidence:** Tinggi.
- **Rekomendasi:** Tambahkan `debugPrint`/logger level `fine` atau minimal komentar "intentionally ignored" agar konsisten dengan situs lain.
- **Risiko jika diabaikan:** Waktu diagnosis lebih lama saat ada regresi di area tersebut.

---

### [LOW-2] Belum ada Network Security Config eksplisit

- **Severity:** Low (hardening)
- **File:** `android/app/src/main/AndroidManifest.xml`
- **Deskripsi:** `usesCleartextTraffic` tidak diset dan `android:networkSecurityConfig` tidak ada. Pada API 28+ default Android sudah melarang cleartext, jadi perilaku runtime aman secara default; namun proteksi ini bergantung penuh pada default platform dan belum ditegaskan lewat config.
- **Root cause:** Config keamanan jaringan eksplisit belum ditambahkan.
- **Dampak:** Minimal di perangkat modern; menjadi relevan hanya bila nanti ada kebutuhan domain pengecualian.
- **Confidence:** Sedang (perlu konfirmasi minSdk).
- **Rekomendasi:** Tambahkan `network_security_config.xml` dengan `cleartextTrafficPermitted="false"` eksplisit agar niat keamanan terdokumentasi dan tahan terhadap perubahan default di masa depan.
- **Risiko jika diabaikan:** Sangat rendah.

---

## 3. Hasil Review Per-Area

### 3.1 `lib/` (Flutter/Dart)

- **Arsitektur inti audio** (`main.dart`, `services/audio/playback_manager.dart`, `services/audio_service/service.dart`, `services/audio/media3/media3_playback_bridge.dart`): struktur matang, pembagian tanggung jawab jelas antara manager, bridge Media3, dan service. Tidak ditemukan masalah lifecycle.
- **Pattern-scan UI:** dua kandidat `setState` setelah `await` ternyata false positive — keduanya sudah diguard `mounted` (`batch_scan_section.dart`, `library_sections/state.dart`).
- **SQL:** tidak ditemukan interpolasi string mentah ke query.
- **`webView/web_view_container.dart`:** bukan WebView sungguhan — hanya container gradien sederhana (nama menyesatkan tapi tanpa permukaan keamanan). Tanpa `javaScriptEnabled` dsb.
- **Error handling:** 44 situs `catch (_)`; mayoritas terdokumentasi/berfallback (lihat LOW-1 untuk pengecualiannya).

### 3.2 `android/` (Kotlin + C++ JNI)

- **Kotlin:** nol asersi `!!` di source utama. `runCatching`/`try` dipakai konsisten (MainActivity 25 situs, ArtworkCacheManager 17, Media3PlaybackService 15, dst.).
- **Receiver hygiene:** `noisyReceiver` didaftarkan di `Media3PlaybackService` dan dilepas lewat `ServiceShutdownCoordinator.unregisterReceivers()` dengan try/catch. `AudioCapabilitiesReceiver` (Media3) dilepas via `unregister()` sendiri di teardown. Seimbang — tidak ada kebocoran receiver.
- **Crossfade/Queue/SleepTimer/Preload** (`crossfade/CrossfadeController.kt`, `queue/QueueManager.kt`, `sleep_timer/SleepTimerManager.kt`, `crossfade/PreloadManager.kt`): state management dan koordinasi shutdown rapi; tidak ditemukan race atau kebocoran resource.
- **JNI (`replaygain_jni.cpp`, `stretch_jni.cpp`):**
  - `GetShortArrayElements`/`GetLongArrayElements` selalu dipasangkan `Release*ArrayElements(..., JNI_ABORT)` (read-only, tanpa copy-back) dengan null-check setelah pinning.
  - `stretch_jni.cpp` mencakup `ExceptionCheck`/`ExceptionClear` dan `DeleteLocalRef` dengan benar (8 situs DeleteLocalRef di replaygain).
  - Panjang array diverifikasi (`GetArrayLength`) sebelum indexing.
- **Manifest:** ketiga komponen `exported="true"` semuanya sah — launcher `MainActivity`, `NowPlayingOverlayActivity` (handler VIEW audio/* dengan isolasi `taskAffinity=""` terdokumentasi), dan `Media3PlaybackService` (wajib untuk MediaSession/MediaBrowser client eksternal).
- **Gradle:** R8 + shrinkResources aktif dengan proguard rules custom (lihat MED-1 untuk signing).

### 3.3 `native_audio_runtime/`

- **`dsp_pipeline.c` & stream slots:** pipeline lock-free dan bebas alokasi heap di jalur pemrosesan; slot per-stream (0 = primary, 1 = crossfade standby) mencegah tabrakan envelope follower/delay line/filter history antar dua ExoPlayer.
- **`audio_buffer.c`:** kedua `calloc` dinull-check dengan status `NATIVE_RUNTIME_ERROR_ALLOCATION_FAILED`; error path me-free memori yang sudah dialokasikan (tidak ada kebocoran parsial); satu-satunya pasangan alloc/free di runtime seimbang.
- **`memcpy` di seluruh processor** (`replaygain_processor.c`, `loudness_processor.c`, `gain_processor.c`, `dynamics_common.h`): semuanya untuk type-punning float↔int32 dengan ukuran tetap 4 byte — pola yang aman dari strict-aliasing UB dan terdokumentasi konsisten.
- **`native_dsp_jni.c` (bridge Kotlin↔C):** contoh JNI bridge yang bersih — hanya direct ByteBuffer (tanpa pinning array, tanpa alokasi objek JVM → tidak perlu ref hygiene), validasi argumen lengkap (null check, frame/channel/rate positif, `GetDirectBufferCapacity` vs required bytes), ownership model Dart-vs-Kotlin terdokumentasi eksplisit di header, dan thread-safety (atomic knob writes vs panggilan audio-thread tanpa lock).
- **Dart FFI (`runtime_impl_io.dart`):** lifecycle dispose jelas dan tidak pernah dipanggil konkuren dengan pemrosesan pipeline.

---

## 4. Matriks Prioritas Perbaikan

| # | ID | Severity | Item | Upaya | Prioritas |
|---|----|----------|------|-------|-----------|
| 1 | MED-1 | Medium | Signing config release pakai debug key | Sedang | **Sebelum distribusi publik** |
| 2 | LOW-1 | Low | Catch kosong tanpa log di 4 file widget | Kecil | Kapan saja (hygiene) |
| 3 | LOW-2 | Low | Network security config eksplisit belum ada | Kecil | Opsional (hardening) |

Tidak ada item yang menghalangi pengembangan/pengujian hari ini; MED-1 adalah gerbang wajib menjelang rilis.

---

## 5. Temuan Positif

1. **Nol temuan Critical/High** pada ±67 ribu baris lintas tiga bahasa — hasil akumulasi dari siklus audit-perbaikan berkelanjutan (terlihat dari jejak audit 11–16 Agustus 2026 di root).
2. **Kode native disiplin:** alokasi heap dinull-check dengan cleanup di error path; audio thread bebas alokasi & bebas lock; type-punning via `memcpy` konsisten dan terdokumentasi.
3. **JNI bridge teladan:** validasi menyeluruh, pairing release yang benar (`JNI_ABORT` untuk read-only), dokumentasi ownership/thread-model di header file.
4. **Hygiene lifecycle Android:** semua receiver berpasangan register/unregister melalui koordinator shutdown terpusat; nol `!!`; `runCatching` dipakai luas.
5. **Verifikasi hijau:** `flutter analyze` bersih dan 63/63 unit test lulus pada commit yang diaudit.
6. **Keamanan manifest proporsional:** komponen exported semuanya punya alasan fungsional dan mitigasi terdokumentasi (`taskAffinity=""`, intent-filter terbatas ke `audio/*`).

---

## 6. Kesimpulan

Kodebase dalam kondisi **sehat dan siap pengembangan**. Satu-satunya pekerjaan wajib menjelang rilis publik adalah konfigurasi signing release (MED-1); sisanya merupakan perbaikan hygiene opsional bertingkat rendah. Tidak ditemukan indikasi kebocoran memori, kebocoran receiver, race condition, kerentanan injeksi SQL, atau masalah keamanan WebView.
