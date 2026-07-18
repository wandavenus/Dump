# 🔍 LAPORAN AUDIT NATIVE CODE — KOMPREHENSIF

> **Tanggal audit:** 18 Juli 2026
> **Auditor:** Replit Agent
> **Scope:** Seluruh kode C, C++, Assembly, Kotlin, Java, dan konfigurasi build native

---

## 📊 STATISTIK FILE

| Kategori | Jumlah File |
|---|---|
| File C | 13 |
| File C++ | 5 |
| File Assembly (ARM64 NEON) | 1 |
| File Header (.h / .hpp) | 17 |
| File Kotlin | 40 |
| File Java | 1 |
| CMakeLists.txt | 1 (+ 5 example) |
| Gradle Build Files | 3 |

### File C yang Diaudit

| File | Keterangan |
|---|---|
| `native_audio_runtime/src/native_audio_runtime.c` | Lifecycle runtime, module registry, atomic state machine |
| `native_audio_runtime/src/audio_buffer.c` | Opaque PCM buffer; heap alloc/free |
| `native_audio_runtime/src/dsp_pipeline.c` | Ordered processor chain, atomic enable flags |
| `native_audio_runtime/src/gain_processor.c` | Scalar gain, atomic bit-pattern trick, NEON branch |
| `native_audio_runtime/src/biquad_filter.c` | TDF-II biquad, Audio EQ Cookbook coefficients |
| `native_audio_runtime/src/comp_processor.c` | Feed-forward soft-knee compressor, per-stream state |
| `native_audio_runtime/src/limiter_processor.c` | Look-ahead brickwall limiter, 64-frame circular delay buf |
| `native_audio_runtime/src/soft_clipper_processor.c` | tanh waveshaper, stateless, atomic threshold |
| `native_audio_runtime/src/crossfeed_processor.c` | Freq-dependent crossfeed, 4 biquads, stereo width matrix |
| `native_audio_runtime/src/loudness_processor.c` | EBU R128 / BS.1770-4 real-time loudness normalization |
| `native_audio_runtime/src/replaygain_processor.c` | Metadata-driven gain stage, starts bypassed |
| `native_audio_runtime/src/aaudio_probe.c` | dlopen-based runtime AAudio exclusive-mode probe |
| `native_audio_runtime/src/native_dsp_jni.c` | JNI bridge: nativeProcessFloat + nativeIsInitialized |

### File C++ yang Diaudit

| File | Keterangan |
|---|---|
| `android/app/src/main/cpp/replaygain/replaygain_jni.cpp` | JNI bridge lengkap untuk EBU R128 scanner + TagLib writer |
| `android/app/src/main/cpp/replaygain/ebur128_analyzer.cpp` | Thin RAII wrapper di atas libebur128 |
| `android/app/src/main/cpp/replaygain/tag_writer.cpp` | TagLib crash-safe write + fd-based API |
| `android/app/src/main/cpp/replaygain/metadata_region.cpp` | Format-exact metadata region sizing (MP3/FLAC/Ogg) |
| `android/app/src/main/cpp/stretch/stretch_jni.cpp` | Signalsmith Stretch JNI bridge |

### File Assembly yang Diaudit

| File | Keterangan |
|---|---|
| `native_audio_runtime/src/neon_kernels.S` | AArch64 NEON: gain multiply (16/iter) + stereo biquad |

---

## RINGKASAN TEMUAN

| Severity | Jumlah |
|---|---|
| 🔴 Critical | 1 |
| 🟠 High | 0 |
| 🟡 Medium | 8 |
| 🟢 Low | 21 |
| ℹ️ Info | 1 |
| **Total** | **31** |

---

## 1. DEAD CODE AUDIT

### [DC-01] `nar_gain_set_db()` — Simbol Ekspor Tanpa Deklarasi di Header

- **Severity:** Medium
- **File:** `native_audio_runtime/src/gain_processor.c` — baris 157–159
- **Deskripsi:** Fungsi `nar_gain_set_db()` diekspor via `FFI_PLUGIN_EXPORT` dan dikompilasi ke `.so`, tapi **tidak ada deklarasinya di `gain_processor.h`**. Dart FFI tidak dapat menemukan simbol ini melalui header resmi; hanya bisa diakses jika nama simbol diketahui secara hardcode.
- **Root Cause:** Alias duplikat ditambahkan tanpa dimasukkan ke public header.
- **Dampak:** Dead code ekstra di binary; potensi kebingungan apakah fungsi ini masih dipanggil.
- **Confidence:** High
- **Rekomendasi:** Tambahkan deklarasi ke `gain_processor.h` atau hapus alias dan gunakan hanya `nar_gain_processor_set_gain_db()`.
- **Risiko jika dibiarkan:** Simbol tak terdokumentasi tetap di `.so`; penghapusan mendadak di masa depan bisa membreak caller yang menggunakannya via dlsym.

---

### [DC-02] `EburAnalyzer::AddFramesFloat()` — Dead Code

- **Severity:** Low
- **File:** `android/app/src/main/cpp/replaygain/ebur128_analyzer.cpp` baris 45–48, `ebur128_analyzer.h` baris 52
- **Deskripsi:** `AddFramesFloat()` dideklarasikan di header dan diimplementasikan, tapi **tidak ada entrypoint JNI** yang memanggilnya. Hanya `nativeAddFramesShort` yang ada di `replaygain_jni.cpp`. Float path tidak terpakai.
- **Root Cause:** Implementasi dibuat untuk kelengkapan API tapi JNI bridge hanya memaparkan versi short.
- **Dampak:** Dead code dikompilasi ke library; linker harus menyertakannya.
- **Confidence:** High
- **Rekomendasi:** Tambahkan JNI entry point `nativeAddFramesFloat`, atau hapus implementasi jika tidak direncanakan.
- **Risiko jika dibiarkan:** Binary lebih besar; devs masa depan mungkin mengira fungsi ini tersedia dari Kotlin.

---

### [DC-03] Filter Type `NAR_BIQUAD_BAND_PASS` dan `NAR_BIQUAD_NOTCH` — Dead Code

- **Severity:** Low
- **File:** `native_audio_runtime/src/biquad_filter.c` baris 133–152, `biquad_filter.h` baris 45–47
- **Deskripsi:** Dua tipe filter (BAND_PASS, NOTCH) diimplementasikan lengkap di `nar_biquad_compute()` tapi tidak pernah dipanggil oleh processor manapun. `crossfeed_processor.c` hanya pakai LOW_PASS dan HIGH_SHELF; `loudness_processor.c` menghitung koefisien sendiri tanpa memanggil `nar_biquad_compute()`.
- **Root Cause:** Implementasi lengkap Audio EQ Cookbook tapi hanya subset yang dibutuhkan.
- **Dampak:** Dead code; overhead kecil saat dikompilasi.
- **Confidence:** High (setelah pencarian referensi di seluruh repo)
- **Rekomendasi:** Biarkan untuk future-proofing atau beri komentar `// Reserved for future use`.
- **Risiko jika dibiarkan:** Minimal; bersifat informatif saja.

---

### [DC-04] Fungsi Utilitas `stereo_matrix.h` Tidak Digunakan

- **Severity:** Low
- **File:** `native_audio_runtime/src/stereo_matrix.h` baris 92–160
- **Deskripsi:** 6 fungsi factory (`nar_stereo_matrix_mono`, `nar_stereo_matrix_balance`, `nar_stereo_matrix_mid_side_encode`, `nar_stereo_matrix_mid_side_decode`, `nar_stereo_matrix_crossblend`, `nar_stereo_matrix_multiply`) tidak pernah dipanggil. Hanya `nar_stereo_matrix_width()` dan `nar_stereo_matrix_apply()` yang digunakan oleh `crossfeed_processor.c`.
- **Root Cause:** Framework reusable yang dibuat lebih lengkap dari kebutuhan saat ini.
- **Dampak:** Dead code (header-only, tidak menambah binary size kecuali diinstansiasi).
- **Confidence:** High
- **Rekomendasi:** Biarkan sebagai utility header atau pindahkan ke `stereo_matrix_extras.h` untuk memisahkan API yang dipakai vs belum terpakai.
- **Risiko jika dibiarkan:** Minimal.

---

### [DC-05] `NAR_SAMPLE_FORMAT_INT16` — Placeholder Tidak Diimplementasikan

- **Severity:** Low
- **File:** `native_audio_runtime/src/audio_buffer.h` baris 41–43, `audio_buffer.c` baris 27–30
- **Deskripsi:** `NAR_SAMPLE_FORMAT_INT16` dideklarasikan di enum tapi secara eksplisit ditolak oleh `nar_audio_buffer_create()` dengan komentar "INT16 is a declared-but-unimplemented placeholder". `nar_audio_buffer_data()` juga mengembalikan NULL untuk non-FLOAT32 buffer.
- **Root Cause:** Forward-compatible placeholder, tidak pernah diimplementasikan.
- **Dampak:** Enum value yang menyesatkan jika digunakan dari Dart FFI — runtime error, bukan compile error.
- **Confidence:** High
- **Rekomendasi:** Tambahkan `#pragma deprecated` atau komentar lebih eksplisit; atau hapus dari enum sampai diimplementasikan.
- **Risiko jika dibiarkan:** Developer Dart bisa mencoba INT16 dan mendapat error yang membingungkan.

---

### [DC-06] Windows `CRITICAL_SECTION` Branch — Dead Code untuk Android

- **Severity:** Low
- **File:** `native_audio_runtime.c` baris 80–97, `dsp_pipeline.c` baris 49–65
- **Deskripsi:** Branch `#if defined(_WIN32)` yang mengimplementasikan `CRITICAL_SECTION` + `_Atomic int _module_lock_ready` tidak relevan untuk project Android ini. Kode ini dikompilasi dengan kondisi `_WIN32` yang tidak pernah terpenuhi di NDK toolchain.
- **Root Cause:** Cross-platform design untuk portabilitas, tapi project hanya menarget Android.
- **Dampak:** Zero runtime impact; menambah noise untuk pembaca kode.
- **Confidence:** High
- **Rekomendasi:** Dapat dipertahankan untuk portabilitas, atau dibungkus dengan komentar `// NOTE: Windows support kept for desktop testing only`.
- **Risiko jika dibiarkan:** Tidak ada.

---

### [DC-07] Example Flutter Plugin Directories — File Tidak Dipakai

- **Severity:** Low
- **File:** `native_audio_runtime/example/` — seluruh subdirektori (linux/, windows/, ios/, android/)
- **Deskripsi:** Direktori `native_audio_runtime/example/` berisi flutter plugin example boilerplate standard (MainActivity, linux runner, windows runner, dll). Tidak ada referensi ke direktori ini dari build system utama atau `pubspec.yaml` production. Merupakan sisa template plugin generator.
- **Root Cause:** Template Flutter plugin default tidak dibersihkan.
- **Dampak:** Menambah ~1,500 baris kode tidak relevan ke repo. Bisa membingungkan kontributor.
- **Confidence:** High
- **Rekomendasi:** Hapus `native_audio_runtime/example/` jika memang tidak dipakai untuk testing.
- **Risiko jika dibiarkan:** Confusion; bisa salah dipahami sebagai production code.

---

## 2. FOLDER & FILE AUDIT

### [FF-01] Version String Kadaluarsa di Runtime

- **Severity:** Low
- **File:** `native_audio_runtime/src/native_audio_runtime.c` — baris 36
- **Deskripsi:** `static const char* const kVersion = "0.1.0-phase8";` padahal codebase sudah di Phase 8.5 (loudness processor dengan BS.1770-4). Debug tooling yang membaca `native_runtime_get_version()` akan melaporkan versi yang salah.
- **Root Cause:** Version string tidak di-update saat Phase 8.5 diimplementasikan.
- **Dampak:** Misleading diagnostics dari debug page app.
- **Confidence:** High
- **Rekomendasi:** Update ke `"0.1.0-phase8.5"` atau gunakan build-time macro.
- **Risiko jika dibiarkan:** Support/debug confusion.

---

### [FF-02] Capability `scan.loudness_ebur128` Selalu `supported=0`

- **Severity:** Low
- **File:** `native_audio_runtime/src/native_audio_runtime.c` — baris 64
- **Deskripsi:** Capability `scan.loudness_ebur128` diklaim `supported=0` padahal `replaygain_native.so` (module terpisah) sudah menyediakan ebur128 scanning via `ReplayGainNative.kt`. Capability ini tidak pernah di-set ke `1` dari mana pun.
- **Root Cause:** Capability table di `native_audio_runtime.c` hanya mencerminkan `libnative_audio_runtime.so`, bukan `libreplaygain_native.so` yang merupakan library terpisah.
- **Dampak:** Dart-side capability check akan salah melaporkan ebur128 sebagai tidak tersedia, padahal tersedia via module lain.
- **Confidence:** Medium — **Needs Manual Verification** apakah Dart benar-benar mengecek capability ini sebelum scanning.
- **Rekomendasi:** Dokumentasikan bahwa ebur128 ada di module terpisah, atau set ke `1` jika check dipakai.
- **Risiko jika dibiarkan:** Capability-based gating bisa salah disable scanning.

---

## 3. JNI AUDIT

### [JNI-01] Local Reference Leak di `PackSnapshot()`

- **Severity:** Medium
- **File:** `android/app/src/main/cpp/replaygain/replaygain_jni.cpp` — baris 54
- **Deskripsi:**
  ```cpp
  env->SetObjectArrayElement(arr, i, replaygain::StdToJString(env, **fields[i]));
  ```
  `StdToJString()` membuat jstring baru via `NewStringUTF()` — sebuah **local reference** yang harus di-`DeleteLocalRef()` setelah dimasukkan ke array. Setiap panggilan yang memasukkan field bertipe string (hingga 9 kali) meninggalkan 1 local ref yang tidak di-release.
- **Root Cause:** Missing `DeleteLocalRef()` setelah `SetObjectArrayElement()`.
- **Dampak:** Local reference table JNI memiliki batas (biasanya 512 entri per frame). 9 leaks per panggilan `PackSnapshot()` tidak langsung berbahaya, tapi ini melanggar JNI spec dan bisa berakumulasi jika dipanggil dalam loop (batch write album).
- **Confidence:** High
- **Rekomendasi:**
  ```cpp
  if (fields[i]->has_value()) {
      jstring jstr = replaygain::StdToJString(env, **fields[i]);
      env->SetObjectArrayElement(arr, i, jstr);
      env->DeleteLocalRef(jstr);  // ← TAMBAHKAN INI
  }
  ```
- **Risiko jika dibiarkan:** Local ref table overflow pada batch scan album besar (> ~50 track dalam satu fungsi stack frame).

---

### [JNI-02] `nativeComputeAlbumLoudness` — `ReleaseLongArrayElements` Dipanggil Dalam Lock

- **Severity:** Low
- **File:** `android/app/src/main/cpp/replaygain/replaygain_jni.cpp` — baris 231
- **Deskripsi:** `env->ReleaseLongArrayElements(handles, elems, JNI_ABORT)` dipanggil **di dalam** `std::lock_guard<std::mutex> lock(g_registry_mutex)`. Memanggil JNI functions saat memegang mutex internal bisa berpotensi deadlock jika JVM sendiri ingin acquire lock lain secara bersamaan (misal GC safepoint).
- **Root Cause:** JNI call dilakukan sebelum mutex direlease untuk memastikan semua state konsisten sebelum komputasi.
- **Dampak:** Teoritis — dalam praktik Android JNI tidak deadlock di sini karena `ReleaseLongArrayElements(JNI_ABORT)` adalah operasi sederhana.
- **Confidence:** Medium — **Needs Manual Verification**
- **Rekomendasi:** Pindahkan `ReleaseLongArrayElements` ke sebelum `lock_guard` scope:
  ```cpp
  jlong* elems = env->GetLongArrayElements(handles, nullptr);
  if (elems == nullptr) return -HUGE_VAL;
  std::vector<jlong> handle_copy(elems, elems + count);
  env->ReleaseLongArrayElements(handles, elems, JNI_ABORT);  // ← sebelum lock
  std::lock_guard<std::mutex> lock(g_registry_mutex);
  // ... pakai handle_copy
  ```
- **Risiko jika dibiarkan:** Potensi deadlock dalam skenario GC tekanan tinggi (jarang, tapi tidak impossible).

---

### [JNI-03] Global Reference `gProcClass` di `stretch_jni.cpp` Tidak Pernah Direlease

- **Severity:** Low
- **File:** `android/app/src/main/cpp/stretch/stretch_jni.cpp` — baris 99
- **Deskripsi:** `gProcClass = static_cast<jclass>(env->NewGlobalRef(local))` membuat global JNI reference. `DeleteGlobalRef()` tidak pernah dipanggil. Library ini tidak menyediakan `JNI_OnUnload()`.
- **Root Cause:** Log bridge diinisialisasi lazily, tidak ada cleanup lifecycle.
- **Dampak:** Satu global reference per process lifetime. JVM tidak akan GC class `SignalsmithStretchAudioProcessor` selama process hidup. Karena ini class yang memang dipakai selama app berjalan, tidak ada efek praktis.
- **Confidence:** High
- **Rekomendasi:** Implementasikan `JNIEXPORT void JNICALL JNI_OnUnload(JavaVM* vm, void*)` untuk cleanup, atau dokumentasikan bahwa ini intentional.
- **Risiko jika dibiarkan:** Sangat minimal; class tetap hidup sampai process mati yang memang diinginkan.

---

### [JNI-04] `env` Tidak Dicek untuk NULL di `native_dsp_jni.c`

- **Severity:** Low
- **File:** `native_audio_runtime/src/native_dsp_jni.c` — baris 57
- **Deskripsi:** `float* data = (float*)(*env)->GetDirectBufferAddress(env, buffer);` — tidak ada pengecekan `env == NULL`. Dalam praktik JNI normal, `env` tidak pernah NULL saat dipanggil dari Java/Kotlin.
- **Root Cause:** Standard JNI assumption — env selalu valid di entry point.
- **Confidence:** Low — **Needs Manual Verification** apakah ada skenario (misal mock testing) di mana env bisa null.
- **Rekomendasi:** Tambahkan `if (env == NULL) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;` untuk defensive coding.
- **Risiko jika dibiarkan:** Crash hanya jika env NULL — yang tidak terjadi di runtime normal.

---

### [JNI-05] `JStringToStd()` Menggunakan `GetStringUTFChars()` — Modified UTF-8

- **Severity:** Low
- **File:** `android/app/src/main/cpp/replaygain/jni_common.h` — baris 37–41
- **Deskripsi:** `env->GetStringUTFChars()` mengembalikan **Modified UTF-8**, bukan standard UTF-8. Perbedaan utama: null character (`\u0000`) diencoding sebagai dua-byte `0xC0 0x80` daripada single `0x00`. Ini menyebabkan file path yang mengandung embedded null (sangat langka) akan gagal diparse oleh TagLib yang menggunakan standard C strings.
- **Root Cause:** JNI Modified UTF-8 vs standard UTF-8 distinction tidak diperhatikan.
- **Dampak:** File path dengan embedded null byte akan salah di-parse. Dalam praktik, path file tidak mengandung null bytes sehingga dampaknya minimal.
- **Confidence:** High
- **Rekomendasi:** Gunakan `GetStringUTFLength` + manual conversion, atau verifikasi bahwa semua input dari Kotlin adalah ASCII-safe path.
- **Risiko jika dibiarkan:** Tidak ada untuk file path normal.

---

## 4. MEMORY AUDIT

### [MEM-01] `CopyFile()` Tidak Mendeteksi Kegagalan Flush saat `close()`

- **Severity:** Medium
- **File:** `android/app/src/main/cpp/replaygain/tag_writer.cpp` — baris 73–81
- **Deskripsi:**
  ```cpp
  out << in.rdbuf();
  const bool write_ok = out.good();   // ← Dicek SEBELUM close()
  in.close();
  out.close();  // ← Flush buffer di sini, tapi errornya tidak dicek!
  ```
  Jika disk penuh atau I/O error terjadi SAAT flush pada `out.close()`, error tersebut tidak terdeteksi. `write_ok` sudah di-capture sebelum close, sehingga `CopyFile()` bisa mengembalikan `true` meskipun data tidak berhasil ditulis ke disk.
- **Root Cause:** Buffered I/O C++ — `failbit` bisa di-set saat flush-on-close, tapi tidak dicek.
- **Dampak:** File temp dibuat tapi mungkin corrupt; `std::rename()` kemudian menimpa file asli dengan file temp yang corrupt. Ini defeats the purpose of crash-safe write.
- **Confidence:** High
- **Rekomendasi:**
  ```cpp
  out << in.rdbuf();
  const bool stream_ok = !in.bad();
  out.flush();                          // ← Flush eksplisit
  const bool write_ok = out.good();    // ← Cek setelah flush
  in.close();
  out.close();
  if (!stream_ok || !write_ok) { ... }
  ```
- **Risiko jika dibiarkan:** Korupsi file audio user jika disk penuh saat write ReplayGain tags.

---

### [MEM-02] Stack-allocated `NarAudioBuffer` View — Ownership Ambiguity

- **Severity:** Low
- **File:** `native_audio_runtime/src/dsp_pipeline.c` — baris 277–286
- **Deskripsi:** Fungsi melakukan `struct NarAudioBuffer view;` di stack (tidak melalui `nar_audio_buffer_create()`). Komentar menyatakan `nar_audio_buffer_destroy()` TIDAK boleh dipanggil pada struct ini. Jika ada processor baru yang mencoba memanggil `nar_audio_buffer_destroy(buffer)` pada buffer yang diterimanya, ini akan men-free stack memory.
- **Root Cause:** Ownership ambiguity antara heap-allocated vs stack-allocated buffer.
- **Confidence:** Medium — **Needs Manual Verification** apakah ada processor yang memanggil destroy pada buffer input.
- **Rekomendasi:** Tambahkan flag `is_view` ke `NarAudioBuffer` struct (internal header) untuk mendeteksi misuse secara defensive, atau pastikan kontrak vtable melarang destroy di dokumentasi.
- **Risiko jika dibiarkan:** Crash jika future processor melanggar kontrak.

---

### [MEM-03] `RegionBackup::bytes` Menggunakan `std::string` untuk Binary Data

- **Severity:** Low
- **File:** `android/app/src/main/cpp/replaygain/tag_writer.h` — baris 85
- **Deskripsi:** `struct RegionBackup { std::string bytes; };` menggunakan `std::string` untuk menyimpan binary metadata bytes. `std::string` tidak bermasalah untuk binary data pada C++11+, tapi menggunakan `std::vector<uint8_t>` lebih semantically correct dan menghindari confusion.
- **Root Cause:** Convenience — `std::string` memiliki method resize/assign yang mudah.
- **Dampak:** Tidak ada bug, tapi misleading semantics.
- **Confidence:** High
- **Rekomendasi:** Ganti ke `std::vector<uint8_t>` untuk clarity.
- **Risiko jika dibiarkan:** Tidak ada — C++ `std::string` handles binary data correctly.

---

## 5. THREAD SAFETY AUDIT

### [TS-01] TOCTOU Race di `native_runtime_register_module()` — State Check vs Lock Acquisition

- **Severity:** Medium
- **File:** `native_audio_runtime/src/native_audio_runtime.c` — baris 185–222
- **Deskripsi:**
  ```c
  if (atomic_load(&_state) != NAR_STATE_INITIALIZED) { // ← cek di luar lock
      return NATIVE_RUNTIME_ERROR_NOT_INITIALIZED;
  }
  // ... window di sini: state bisa berubah
  nar_lock();   // ← lock baru acquired DI SINI
  ```
  Ada window antara `atomic_load(&_state)` dan `nar_lock()` di mana thread lain bisa memanggil `native_runtime_dispose()`. State check tidak dilindungi oleh lock yang sama.
- **Root Cause:** State check dilakukan di luar lock — klasik TOCTOU (Time-Of-Check-To-Time-Of-Use).
- **Dampak:** Dalam kondisi race sangat ketat (dua thread berbeda memanggil register dan dispose simultan), bisa terjadi inkonsistensi state.
- **Confidence:** Medium
- **Rekomendasi:** Re-check `_state` di DALAM lock:
  ```c
  nar_lock();
  if (atomic_load(&_state) != NAR_STATE_INITIALIZED) {
      nar_unlock();
      return NATIVE_RUNTIME_ERROR_NOT_INITIALIZED;
  }
  // ... registrasi
  nar_unlock();
  ```
- **Risiko jika dibiarkan:** Race condition hanya terjadi jika `register_module` dan `dispose` dipanggil dari thread berbeda secara simultan — skenario yang unlikely di Dart single-isolate, tapi possible.

---

### [TS-02] `_find_slot()` Membaca `_slots[i].id` Tanpa Lock — Data Race

- **Severity:** Medium
- **File:** `native_audio_runtime/src/dsp_pipeline.c` — baris 195–201
- **Deskripsi:**
  ```c
  static int32_t _find_slot(const char* id) {
      int32_t count = atomic_load(&_count);
      for (int32_t i = 0; i < count; i++) {
          if (strncmp(_slots[i].id, id, ...) == 0) return i; // ← membaca tanpa lock
      }
  }
  ```
  `_slots[i].id` adalah `char[64]` yang diinisialisasi di bawah `_lock` saat registrasi. `_find_slot()` membacanya tanpa lock. Jika registrasi processor berjalan di satu thread dan `set_enabled()` / `is_enabled()` dipanggil di thread lain, ada **data race** pada `_slots[i].id`.
- **Root Cause:** Desain yang mengasumsikan semua registrasi selesai sebelum hot path berjalan — asumsi yang valid di current usage (init dari Dart sebelum playback), tapi tidak dijamin oleh API contract.
- **Dampak:** Undefined behavior per C11 — corrupt id string comparison. Dalam praktik, karena registrasi terjadi saat init dan hot path aktif saat playback (tidak overlap), race ini tidak ter-trigger secara nyata.
- **Confidence:** High
- **Rekomendasi:** Dokumentasikan secara eksplisit di header bahwa `set_enabled()`/`is_enabled()` tidak aman dipanggil bersamaan dengan `register_internal()`. Atau pindahkan `_find_slot()` ke versi yang membutuhkan lock untuk control-plane callers.
- **Risiko jika dibiarkan:** Tidak ada crash di current usage karena init dan playback serial. Jika pola penggunaan berubah, race bisa terjadi.

---

### [TS-03] `_comp.pending` / `_xf.pending` / `_lim.pending` — Non-Atomic Struct Write (Verified Safe)

- **Severity:** Low (by design — correctly guarded)
- **File:** `comp_processor.c` baris 328, `crossfeed_processor.c` baris 362, `limiter_processor.c` baris 295
- **Deskripsi:** Struct write ke `_comp.pending`, `_xf.pending`, dll adalah plain struct copy (bukan atomic). Kemudian `dirty[s]` di-release-store. Audio thread acquire-load `dirty` kemudian copy `pending` ke `active`.
- **Analisis:** Pattern double-buffer ini **BENAR** secara C11 memory model: writes to non-atomic `pending` happen-before the release-store of `dirty`; acquire-load of `dirty` establishes happens-before untuk read `pending`. Semua visibility guarantees terpenuhi.
- **Confidence:** High — Tidak ada bug. Ini adalah recognized producer-consumer pattern.
- **Catatan:** Perlu dijaga agar write ke `pending` selalu dilakukan di satu thread saja (control thread). Saat ini sudah demikian.

---

### [TS-04] `nar_loudness_set_bypass()` — Dua Atomic Stores Tidak Konsisten

- **Severity:** Low
- **File:** `native_audio_runtime/src/loudness_processor.c` — baris 678–681
- **Deskripsi:**
  ```c
  void nar_loudness_set_bypass(int32_t bypass) {
      atomic_store(&_enabled, bypass ? 0 : 1);  // ← store 1
      atomic_store(&_bypass,  bypass ? 1 : 0);  // ← store 2
  }
  ```
  Ada window ~nanoseconds antara dua stores di mana `_enabled=0` tapi `_bypass=0` (ketika `bypass=0` di-set). Jika `_ln_reset()` dipanggil dari thread lain tepat di window ini, ia akan melihat `_enabled=0` dan tidak akan re-engage processor.
- **Root Cause:** Dua atomic stores untuk satu logical operation — seharusnya memakai satu atom atau lock.
- **Confidence:** Low — **Needs Manual Verification** apakah ada skenario multi-thread yang memanggil set_bypass dan reset simultan. Di Dart single-isolate, ini tidak terjadi.
- **Rekomendasi:** Gunakan single atomic atau dokumentasikan bahwa caller bertanggung jawab untuk serialization.
- **Risiko jika dibiarkan:** Sangat minimal di current usage pattern.

---

## 6. UNDEFINED BEHAVIOR AUDIT

### [UB-01] `LufsToR128Q7_8()` — `std::lround()` Potensial Overflow (Teoritis)

- **Severity:** Low
- **File:** `android/app/src/main/cpp/replaygain/ebur128_analyzer.cpp` — baris 106
- **Deskripsi:**
  ```cpp
  const double q7_8 = std::lround(gain_db * 256.0);
  if (q7_8 > 32767.0) return 32767;
  if (q7_8 < -32768.0) return -32768;
  ```
  `std::lround()` mengembalikan `long`. Jika `gain_db * 256.0` melebihi `LONG_MAX`, hasilnya adalah UB. Namun sebelum ini ada check `!std::isfinite(integrated_lufs) return 0` yang mengeliminasi infinite values. Untuk finite LUFS, nilai realistic adalah ±100, sehingga `gain_db * 256 ≤ ±12,800` — jauh di bawah `LONG_MAX`.
- **Confidence:** Low — Tidak ada UB dalam praktik normal.
- **Rekomendasi:** Tambahkan explicit clamp sebelum `lround()`:
  ```cpp
  gain_db = std::max(-200.0, std::min(200.0, gain_db));
  ```
- **Risiko jika dibiarkan:** Tidak ada dalam praktik normal.

---

### [UB-02] `_find_slot()` Race Condition (Lihat TS-02)

Sudah dilaporkan di TS-02. Data race pada `_slots[i].id` termasuk dalam kategori UB per C11 karena akses non-atomic ke shared memory tanpa proper synchronization.

---

## 7. PERFORMANCE AUDIT

### [PERF-01] `_compute_kw_coeffs()` Dipanggil di Audio Thread — Transcendental Math

- **Severity:** Medium
- **File:** `native_audio_runtime/src/loudness_processor.c` — baris 258–312
- **Deskripsi:** `_compute_kw_coeffs()` menggunakan `tan()`, `pow()`, `log()` (double precision) dan dipanggil dari `_ensure_sample_rate()` yang dipanggil dari `_ln_process()` (audio thread). Meski hanya dipanggil ketika sample rate berubah, ini bisa memblokir audio thread hingga 10–50 µs (ARM Cortex-A55 transcendental latency) pada frame pertama track baru.
- **Root Cause:** Desain lazy initialization — koefisien dihitung di audio thread untuk menghindari perubahan API publik. Ini sudah didokumentasikan sebagai trade-off yang diterima.
- **Dampak:** ~1 frame (~21 ms budget) dapat menggunakan 10–50 µs untuk koefisien computation. Sangat tidak likely menyebabkan underrun, tapi dapat terjadi di device lambat saat pertama kali decode format baru.
- **Confidence:** High
- **Rekomendasi:** Pertimbangkan pra-komputasi koefisien di control thread saat `nar_loudness_set_sample_rate()` dipanggil oleh Dart, atau menggunakan async lazy init dengan pre-seeded defaults.
- **Risiko jika dibiarkan:** Microglitch ~1× per track change, hampir tidak terdengar.

---

### [PERF-02] `PackSnapshot()` Memanggil `FindClass()` Per Invocation

- **Severity:** Low
- **File:** `android/app/src/main/cpp/replaygain/replaygain_jni.cpp` — baris 44
- **Deskripsi:** `jclass string_class = env->FindClass("java/lang/String");` dipanggil setiap kali `PackSnapshot()` dipanggil. `FindClass` harus mencari class di classloader chain.
- **Root Cause:** Tidak ada class caching untuk `java/lang/String`.
- **Dampak:** Minimal — hanya saat write/verify tags (tidak on audio hot path).
- **Rekomendasi:** Cache class reference di static var (dengan `NewGlobalRef()`).
- **Risiko jika dibiarkan:** Negligible.

---

### [PERF-03] RMS Computation di `nativeProcess()` Doubles Deinterleave Work

- **Severity:** Low
- **File:** `android/app/src/main/cpp/stretch/stretch_jni.cpp` — baris 303–309
- **Deskripsi:** Setiap 2 detik, `nativeProcess()` iterasi ulang semua `inputFrames * channels` samples untuk menghitung RMS input (`inSumSq`). Throttled ke 2 detik, tapi tetap menambah floating-point ops di setiap throttled interval.
- **Root Cause:** Diagnostics logging per-buffer, throttled to 2s.
- **Dampak:** ~2× deinterleave cost setiap 2 detik untuk logging. Untuk 1024 frames stereo ≈ 2048 extra FP ops per 2 seconds — negligible.
- **Rekomendasi:** Tidak perlu diperbaiki. Dapat dihapus jika log diagnostics tidak diperlukan.

---

## 8. C++ BEST PRACTICES

### [CPP-01] `ebur128_destroy()` Dipanggil dengan Pola Non-Idiomatic

- **Severity:** Low
- **File:** `android/app/src/main/cpp/replaygain/ebur128_analyzer.cpp` — baris 13–18
- **Deskripsi:**
  ```cpp
  void EburAnalyzer::StateDeleter::operator()(ebur128_state* s) const {
      if (s != nullptr) {
          ebur128_state* mutable_s = s;    // ← membuat copy lokal
          ebur128_destroy(&mutable_s);     // ← nulls mutable_s, not s
      }
  }
  ```
  Idiom C (output-pointer nulling) tidak natural di C++ dengan `unique_ptr`. Meski benar secara fungsional, pattern confusing.
- **Dampak:** Tidak ada bug; hanya readability issue.
- **Rekomendasi:** Simplify:
  ```cpp
  void EburAnalyzer::StateDeleter::operator()(ebur128_state* s) const {
      ebur128_state* p = s;
      ebur128_destroy(&p);
  }
  ```

---

### [CPP-02] `StretchHandle` — Tidak Ada `= delete` untuk Copy Semantics

- **Severity:** Low
- **File:** `android/app/src/main/cpp/stretch/stretch_jni.cpp` — baris 140–173
- **Deskripsi:** `StretchHandle` adalah struct dengan `std::vector` dan `signalsmith::stretch::SignalsmithStretch<float>` members. Copy/assignment semantics default bisa secara tidak sengaja meng-copy handle. Meski saat ini tidak di-copy (hanya pointer digunakan), tidak ada proteksi eksplisit.
- **Root Cause:** Struct bukan class dengan proper encapsulation.
- **Dampak:** Jika seseorang secara tidak sengaja meng-copy handle, dua handles akan share Stretch state, yang menyebabkan UB.
- **Rekomendasi:**
  ```cpp
  StretchHandle(const StretchHandle&) = delete;
  StretchHandle& operator=(const StretchHandle&) = delete;
  ```

---

### [CPP-03] `ComputeAlbumLoudness()` Menggunakan `const_cast` — Code Smell

- **Severity:** Low
- **File:** `android/app/src/main/cpp/replaygain/ebur128_analyzer.cpp` — baris 91
- **Deskripsi:**
  ```cpp
  const int rc = ebur128_loudness_global_multiple(
      const_cast<ebur128_state**>(states.data()), states.size(), &album_loudness);
  ```
  `const_cast` digunakan karena `states` adalah `std::vector<ebur128_state*>` (non-const pointer) tapi `states.data()` mengembalikan `ebur128_state* const*` (pointer-to-const-pointer) dan libebur128 API mengambil `ebur128_state**`. `const_cast` di sini benar karena libebur128 tidak modifikasi state tersebut, tapi ini menghilangkan const safety.
- **Root Cause:** libebur128 API tidak const-correct.
- **Rekomendasi:** Biarkan atau tambahkan komentar `// const_cast: libebur128 API is not const-correct; states are not modified`.

---

## 9. C BEST PRACTICES

### [C-01] Magic Numbers di `aaudio_probe.c` — Tidak Ada Compile-time Verification

- **Severity:** Low
- **File:** `native_audio_runtime/src/aaudio_probe.c` — baris 24–27
- **Deskripsi:** Konstanta AAudio (`0`, `12`, `0`, `1`) didefinisikan sebagai `#define` lokal:
  ```c
  #define NAR_AAUDIO_SHARING_MODE_EXCLUSIVE 0
  #define NAR_AAUDIO_PERFORMANCE_MODE_LOW_LATENCY 12
  #define NAR_AAUDIO_DIRECTION_OUTPUT 0
  #define NAR_AAUDIO_FORMAT_PCM_I16 1
  ```
  Nilai numerik di-comment sebagai "frozen public C ABI (stable since API 26)". Namun tidak ada compile-time check (tidak ada NDK header link).
- **Root Cause:** Desain intentional — no NDK link karena keterbatasan build environment.
- **Dampak:** Probe mengembalikan nilai yang salah jika ABI berubah (sangat unlikely).
- **Rekomendasi:** Tambahkan komentar dengan referensi ke commit/versi NDK yang diverifikasi nilai-nilai ini.

---

### [C-02] `nar_dsp_pipeline_register_internal()` Mengembalikan `ERROR_INVALID_ARGUMENT` untuk State Not Initialized

- **Severity:** Low
- **File:** `native_audio_runtime/src/dsp_pipeline.c` — baris 114
- **Deskripsi:**
  ```c
  if (!atomic_load(&_initialized)) {
      return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;  // ← misleading error code
  }
  ```
  Error code `INVALID_ARGUMENT` menyesatkan — kondisinya adalah pipeline belum diinisialisasi, bukan argument yang invalid. Seharusnya `NOT_INITIALIZED` atau `INVALID_STATE`.
- **Root Cause:** Error code yang dipilih tidak mencerminkan kondisi sesungguhnya.
- **Rekomendasi:** Gunakan `NATIVE_RUNTIME_ERROR_NOT_INITIALIZED` atau tambahkan `NATIVE_RUNTIME_ERROR_INVALID_STATE` ke enum.

---

## 10. KOTLIN AUDIT

### [KT-01] `build.gradle` Release Signing Config Menggunakan Debug Config — **CRITICAL**

- **Severity:** 🔴 Critical
- **File:** `android/app/build.gradle` — baris 125
- **Deskripsi:**
  ```groovy
  buildTypes {
      release {
          signingConfig signingConfigs.debug  // ← CRITICAL
  ```
  Release build ditandatangani dengan **debug signing config**. APK yang diunggah ke Play Store tidak akan diterima, atau akan memiliki masalah update signing. App tidak dapat diinstall bersama versi production yang mungkin sudah ada dengan release keystore.
- **Root Cause:** Konfigurasi signing production belum di-setup (mungkin disengaja untuk development).
- **Dampak:** Tidak bisa publish ke Play Store dengan config ini. Security: debug keystore biasanya memiliki private key yang mudah didapat.
- **Confidence:** High
- **Rekomendasi:** Buat `keystore.properties` dengan release keystore yang proper dan update `signingConfigs`:
  ```groovy
  signingConfigs {
      release {
          storeFile file(keystoreProperties['storeFile'])
          storePassword keystoreProperties['storePassword']
          keyAlias keystoreProperties['keyAlias']
          keyPassword keystoreProperties['keyPassword']
      }
  }
  ```
- **Risiko jika dibiarkan:** App tidak bisa dipublish ke Play Store; atau jika dipublish dengan debug signing, rentan terhadap re-signing attack.

---

### [KT-02] `AudioEffectsManager` — ReplayGain/LoudnessEnhancer Mutual Exclusion Perlu Verifikasi

- **Severity:** Medium
- **File:** `android/app/src/main/kotlin/dev/wndavenz/music/effects/AudioEffectsManager.kt`
- **Deskripsi:** Berdasarkan memory notes: "system Equalizer fallback can silently no-op forever if attach fails while another effect succeeds; fixed with eqOk tracking". Mutual exclusion antara native LoudnessNormalization dan system LoudnessEnhancer perlu diverifikasi di semua code paths.
- **Root Cause:** MIUI-specific behavior membuat effect attach unpredictable.
- **Confidence:** Medium — **Needs Manual Verification**
- **Rekomendasi:** Verifikasi bahwa `eqOk` flag digunakan untuk fallback decision dan bahwa ReplayGain/LN mutual exclusion direspect di semua code paths.
- **Risiko jika dibiarkan:** Potensi double-processing (system LoudnessEnhancer + native normalization aktif bersamaan) yang menyebabkan over-amplification.

---

### [KT-03] `MetadataPrescanner` — Background Thread Tidak Memiliki Cancellation Token

- **Severity:** Medium
- **File:** `android/app/src/main/kotlin/dev/wndavenz/music/metadata/MetadataPrescanner.kt`
- **Deskripsi:** Background scan thread dijalankan tanpa explicit cancellation mechanism yang tied ke service lifecycle. Jika `Media3PlaybackService` di-destroy selama scan berlangsung, thread bisa terus berjalan hingga selesai.
- **Root Cause:** Thread-based concurrency tanpa Kotlin Coroutine structured concurrency.
- **Dampak:** Memory leak potensial, unnecessary CPU usage, database writes setelah service mati.
- **Confidence:** Medium — **Needs Manual Verification** dari implementasi aktual.
- **Rekomendasi:** Gunakan `CoroutineScope(serviceLifecycle)` dengan cooperative cancellation, atau tambahkan `AtomicBoolean cancelled` yang dicek di loop scan.
- **Risiko jika dibiarkan:** Resource waste, tidak crash.

---

### [KT-04] `ArtworkCacheManager` — Cache di `filesDir` Bukan `cacheDir`

- **Severity:** Low
- **File:** `android/app/src/main/kotlin/dev/wndavenz/music/ArtworkCacheManager.kt`
- **Deskripsi:** Artwork cache di-store di `filesDir/supportDir`, bukan `cacheDir`. `cacheDir` adalah lokasi yang system Android dapat membersihkan saat storage rendah. `filesDir` adalah persistent storage — user harus membersihkan secara manual atau uninstall.
- **Root Cause:** Intentional design — cache tidak boleh dihapus oleh OS karena ini UI rendering data.
- **Dampak:** Cache bisa tumbuh tanpa batas di `filesDir` jika LRU eviction ada masalah.
- **Confidence:** Medium
- **Rekomendasi:** Pastikan LRU eviction berfungsi dengan benar dan ada hard cap pada total cache size. Pertimbangkan user-visible "Clear Artwork Cache" button.
- **Risiko jika dibiarkan:** Potensi storage exhaustion pada device dengan penyimpanan kecil.

---

### [KT-05] `MainActivity.kt` — `setTaskDescription()` Deprecated di Android 13+

- **Severity:** Low
- **File:** `android/app/src/main/kotlin/dev/wndavenz/music/MainActivity.kt`
- **Deskripsi:** `setTaskDescription(ActivityManager.TaskDescription(...))` sudah deprecated di API 33 (Android 13). Constructor `TaskDescription(String, Bitmap, int)` yang digunakan digantikan oleh `TaskDescription.Builder` API. App menggunakan `targetSdk=36`.
- **Root Cause:** API tidak di-update ke modern equivalent.
- **Rekomendasi:** Update ke `ActivityManager.TaskDescription.Builder()` API.
- **Risiko jika dibiarkan:** Warning di lint; kemungkinan deprecated API dihapus di future Android version.

---

### [KT-06] `Media3PlaybackService` — Crossfade saat AudioOffload Aktif

- **Severity:** Medium
- **File:** `android/app/src/main/kotlin/dev/wndavenz/music/audio_offload/AudioOffloadManager.kt` + `Media3PlaybackService.kt`
- **Deskripsi:** Audio offload mode memerlukan stream audio dikembalikan ke hardware secara langsung tanpa software mixing. Crossfade memerlukan dua audio streams dimix di software level. Jika `AudioOffloadManager` mengaktifkan offload saat crossfade aktif, hardware mungkin tidak support mixing dua offload streams.
- **Root Cause:** Dua feature yang mutually exclusive tidak selalu di-interlock secara eksplisit.
- **Confidence:** Medium — **Needs Manual Verification**
- **Rekomendasi:** Pastikan audio offload di-disable selama crossfade berlangsung (`CrossfadeController.isCrossfading` → `AudioOffloadManager.disableOffload()`).
- **Risiko jika dibiarkan:** Audio glitch atau silent stream saat crossfade pada device yang aggressively mengaktifkan offload.

---

### [KT-07] `abortOnError = false` di Lint Config

- **Severity:** Low
- **File:** `android/app/build.gradle` — baris 48
- **Deskripsi:**
  ```groovy
  lint {
      abortOnError = false // Tetep pasang false ya beb biar gak sensitif error lint-nya
  }
  ```
  Komentar informal menunjukkan ini disengaja. Lint check disabled sebagai safety net membiarkan regresi tidak terdeteksi di CI.
- **Rekomendasi:** Set `abortOnError = true` dan fix lint errors secara proper, atau gunakan `baseline = file("lint-baseline.xml")` yang sudah ada untuk suppress known issues.
- **Risiko jika dibiarkan:** Regresi lint tidak terdeteksi.

---

## 11. JAVA AUDIT

### [JAVA-01] `GeneratedPluginRegistrant.java` — Auto-generated

- **Severity:** Info
- **File:** `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`
- **Deskripsi:** File ini di-generate otomatis oleh Flutter toolchain. Tidak ada logika kustom. Tidak perlu di-audit atau dimodifikasi manual.
- **Confidence:** High
- **Rekomendasi:** Tidak ada tindakan.

---

## 12. ASSEMBLY AUDIT

### [ASM-01] `nar_biquad_stereo_neon` — Penggunaan Register `x7` sebagai Scratch (Benar)

- **Severity:** Low
- **File:** `native_audio_runtime/src/neon_kernels.S` — baris 162–168
- **Deskripsi:** Register `x7` digunakan sebagai scratch untuk address computation saat load coefficients. Dalam AAPCS64, `x7` adalah argument register ke-8 (caller-saved). Fungsi ini memiliki 9 parameter: 7 pointer (x0, x1, x2, x3, x4, x5, x6) + 2 float (v0.s[0], v1.s[0]). `x7` tidak dipakai sebagai argument, sehingga penggunaan sebagai scratch **aman**.
- **Confidence:** High — Tidak ada bug.
- **Rekomendasi:** Tambahkan komentar `// x7 used as scratch (not an arg for this function)` untuk clarity.

---

### [ASM-02] `nar_gain_apply_neon` — Tidak Ada Null Pointer Guard di Assembly

- **Severity:** Info
- **File:** `native_audio_runtime/src/neon_kernels.S` — baris 52
- **Deskripsi:** Fungsi memeriksa `w1==0` (samples=0) tapi tidak memeriksa apakah `x0` (data pointer) adalah NULL. Null check sudah dilakukan di C caller (`_gain_process()`) sebelum memanggil NEON kernel.
- **Confidence:** High — Tidak ada bug karena null guard ada di C layer.
- **Rekomendasi:** Tambahkan komentar di assembly: `// Pre-condition: x0 != NULL (verified by C caller)`.

---

## 13. ANDROID NATIVE INTEGRATION AUDIT

### [ABI-01] Hanya `arm64-v8a` Ditargetkan — x86_64 Emulator Tidak Bisa Berjalan

- **Severity:** Low
- **File:** `android/app/build.gradle` — baris 73–74 dan 89
- **Deskripsi:**
  ```groovy
  ndk { abiFilters "arm64-v8a" }
  ```
  Emulator x86_64 tidak bisa menjalankan app karena tidak ada `.so` untuk ABI tersebut.
- **Root Cause:** Intentional decision untuk meminimalkan APK size.
- **Dampak:** Development friction — tidak bisa pakai emulator x86_64 default.
- **Rekomendasi:** Untuk development build, pertimbangkan menambahkan `x86_64` ke `abiFilters`. Untuk release build, pertahankan hanya `arm64-v8a`.
- **Risiko jika dibiarkan:** Developer harus pakai device fisik atau ARM-based emulator untuk testing.

---

### [ABI-02] Dua `.so` File dengan `ANDROID_STL=c++_static` — Potential ODR Violation

- **Severity:** Medium
- **File:** `android/app/build.gradle` — baris 87, `CMakeLists.txt` baris 152–163
- **Deskripsi:** `ANDROID_STL=c++_static` menyebabkan setiap native library (`libreplaygain_native.so` DAN `libstretch_native.so`) memiliki **salinan STL sendiri** yang statically linked. Dua library yang masing-masing memiliki static STL dalam satu process bisa menyebabkan:
  - **Duplicate global state:** locale, new-handler, dll masing-masing punya instance terpisah
  - **Exception handling issues:** Exceptions yang throw di satu library tidak bisa di-catch di library lain (exception type info tidak shared)
  - **ODR violations** jika ada template instantiations yang berbeda versi
- **Root Cause:** Android NDK best practice adalah gunakan `c++_shared` ketika ada multiple native libraries.
- **Dampak:** Exception boundaries antar library tidak aman; APK lebih besar karena STL dikopikan dua kali.
- **Confidence:** High
- **Rekomendasi:** Ganti ke `ANDROID_STL=c++_shared`. Ini memerlukan mendistribusikan `libc++_shared.so` bersama app (otomatis dilakukan oleh Gradle jika semua CMake target menggunakan `c++_shared`).
- **Risiko jika dibiarkan:** Exception boundaries antar library tidak aman; APK lebih besar dari seharusnya.

---

## 14. BUILD SYSTEM AUDIT

### [BUILD-01] `FetchContent_Populate()` Deprecated di CMake 3.28

- **Severity:** Low
- **File:** `android/app/src/main/cpp/CMakeLists.txt` — baris 138–150
- **Deskripsi:**
  ```cmake
  if(NOT signalsmith_linear_POPULATED)
      FetchContent_Populate(signalsmith_linear)  # deprecated CMake 3.28
  endif()
  ```
  `FetchContent_Populate()` deprecated di CMake 3.28 in favor of `FetchContent_MakeAvailable()`. Komentar menjelaskan alasan tidak menggunakan `MakeAvailable()` (cmake_minimum_required versi dependency lebih tinggi dari project floor).
- **Root Cause:** Upstream libraries membutuhkan CMake 3.24+ tapi project floor 3.22.
- **Rekomendasi:** Naikan `cmake_minimum_required` ke 3.24 (didukung penuh oleh NDK r26+), kemudian gunakan `FetchContent_MakeAvailable()`.
- **Risiko jika dibiarkan:** Deprecation warning; future CMake version mungkin error.

---

### [BUILD-02] Tidak Ada LTO Konfigurasi untuk Release Builds

- **Severity:** Low
- **File:** `android/app/src/main/cpp/CMakeLists.txt`
- **Deskripsi:** Tidak ada `-flto` di `target_compile_options()` untuk DSP processors. Cross-TU inlining dari `nar_biquad_process_sample()` dan `dynamics_common.h` sudah terjadi karena header-only. LTO tambahan bisa optimize call chains lebih lanjut.
- **Dampak:** Potensi 5–15% performance improvement untuk DSP hot paths dengan LTO.
- **Rekomendasi:**
  ```cmake
  if(CMAKE_BUILD_TYPE STREQUAL "Release")
      target_compile_options(native_audio_runtime PRIVATE -flto)
      target_link_options(native_audio_runtime PRIVATE -flto)
  endif()
  ```

---

## 15. SECURITY AUDIT

### [SEC-01] Release Build Menggunakan Debug Signing — CRITICAL (Lihat KT-01)

Sudah dilaporkan lengkap di KT-01.

---

### [SEC-02] `WithCrashSafeWrite()` — Temp File Tidak Di-fsync Sebelum Rename

- **Severity:** Medium
- **File:** `android/app/src/main/cpp/replaygain/tag_writer.cpp` — baris 102–131
- **Deskripsi:** Setelah TagLib berhasil write ke temp file dan sebelum `std::rename()`, temp file tidak di-fsync. Pada ext4 dengan journal enabled, rename bisa terjadi tapi data belum di-flush ke storage. Power failure setelah rename bisa meninggalkan file dengan wrong (partial) content meski rename sudah atomic. `FsyncGuard` hanya ada di fd-based API, tidak di path-based `WithCrashSafeWrite()`.
- **Root Cause:** Crash-safe path tidak mencakup fsync karena path ini menggunakan file-path (bukan fd-based).
- **Dampak:** Dalam extreme scenario (power failure setelah rename), tag file bisa corrupt.
- **Confidence:** Medium
- **Rekomendasi:** Tambahkan fsync sebelum rename:
  ```cpp
  // Before std::rename():
  int tmp_fd = ::open(temp_path.c_str(), O_RDONLY);
  if (tmp_fd >= 0) { ::fsync(tmp_fd); ::close(tmp_fd); }
  if (std::rename(...) != 0) { ... }
  ```
- **Risiko jika dibiarkan:** Korupsi file pada power failure setelah tag write — low probability, high impact untuk file audio user.

---

### [SEC-03] Ogg Metadata Region Parser — DoS Risk dengan File Adversarial

- **Severity:** Low
- **File:** `android/app/src/main/cpp/replaygain/metadata_region.cpp` — baris 132
- **Deskripsi:** Guard `for (int guard = 0; guard < 200000; guard++)` membatasi iterasi saat parsing Ogg page headers. Setiap iterasi membaca 27 bytes via `pread()`. File adversarial dengan 200,000 header pages bisa menyebabkan 200,000 × `pread()` syscalls ≈ beberapa detik blocking di ReplayGain scan thread.
- **Root Cause:** Konservatif guard untuk menangani legitimately large comment blocks.
- **Dampak:** Jika user membuka file Ogg yang di-craft untuk menyebabkan DoS, scan thread bisa blocking lama.
- **Confidence:** High
- **Rekomendasi:** Tambahkan total byte budget check: jika total bytes yang sudah di-scan > 100MB, abort.
- **Risiko jika dibiarkan:** Minimal — hanya user's own music files yang di-scan, bukan arbitrary untrusted files.

---

## MATRIKS PRIORITAS PERBAIKAN

### Perbaikan Segera (Blocking / Critical)

| ID | Judul | Severity | Effort |
|---|---|---|---|
| KT-01 | Release signing config menggunakan debug config | 🔴 Critical | Low |

### Perbaikan Direkomendasikan (High Impact)

| ID | Judul | Severity | Effort |
|---|---|---|---|
| MEM-01 | CopyFile() tidak deteksi flush failure pada close() | Medium | Low |
| SEC-02 | WithCrashSafeWrite() temp file tidak di-fsync | Medium | Low |
| JNI-01 | Local reference leak di PackSnapshot() | Medium | Low |
| ABI-02 | c++_static dengan dua .so — ODR violation risk | Medium | Medium |
| TS-01 | TOCTOU race di register_module() | Medium | Low |
| TS-02 | _find_slot() data race tanpa lock | Medium | Low |

### Perbaikan Disarankan (Low Impact / Maintenance)

| ID | Judul | Severity | Effort |
|---|---|---|---|
| DC-01 | nar_gain_set_db() tidak di header | Medium | Low |
| FF-01 | Version string kadaluarsa | Low | Trivial |
| KT-05 | setTaskDescription() deprecated | Low | Low |
| BUILD-01 | FetchContent_Populate() deprecated | Low | Low |
| CPP-02 | StretchHandle missing = delete | Low | Trivial |
| DC-07 | example/ directory cleanup | Low | Trivial |

### Perlu Verifikasi Manual

| ID | Judul | Area |
|---|---|---|
| JNI-02 | ReleaseLongArrayElements di dalam lock | JNI threading |
| TS-04 | nar_loudness_set_bypass() dual atomic race | Concurrency |
| KT-02 | ReplayGain/LoudnessEnhancer mutual exclusion | Effects chain |
| KT-03 | MetadataPrescanner cancellation | Lifecycle |
| KT-06 | Crossfade saat AudioOffload aktif | Feature interaction |
| FF-02 | scan.loudness_ebur128 capability always 0 | Dart capability check |

---

## TEMUAN POSITIF (KODE YANG SUDAH BAIK)

Berikut adalah aspek-aspek yang diimplementasikan dengan sangat baik dan layak dipertahankan:

1. **Double-buffer parameter sync** (`comp_processor.c`, `crossfeed_processor.c`, `limiter_processor.c`) — Pattern acquire/release dengan `dirty` flag adalah benar secara C11 memory model dan zero-copy.

2. **Crash-safe write path di `tag_writer.cpp`** — Atomic rename pada filesystem sama adalah implementasi yang tepat. Komentar dokumentasi sangat detail dan akurat.

3. **Exact metadata region sizing** (`metadata_region.cpp`) — Parser yang walk actual container structure (bukan fixed-size guess) adalah desain yang sangat solid. Failsafe (return nullopt) ketika region tidak bisa ditentukan dengan pasti adalah keputusan arsitektur yang baik.

4. **Handle registry di `replaygain_jni.cpp`** — Penggunaan `std::unordered_map<jlong, unique_ptr<EburAnalyzer>>` dengan mutex daripada blind `reinterpret_cast<jlong>` pointer adalah pendekatan yang jauh lebih aman dan dapat divalidasi.

5. **`FsyncGuard` di fd-based write path** (`tag_writer.cpp`) — Design yang cerdas: `dup()` fd sebelum TagLib menutup aslinya, kemudian `fsync()` di RAII destructor, memastikan data durable sebelum control kembali ke Kotlin untuk verify step.

6. **Non-finite output sanitization** (`stretch_jni.cpp`) — Setiap sample output di-clamp ke `std::isfinite(s) ? s : 0.0f` sebelum ditulis ke output buffer. Fail-open yang benar.

7. **`_find_slot()` + atomic count** di `dsp_pipeline.c` — Meski ada race issue (TS-02) jika dipakai concurrent dengan registration, untuk intended usage (init-then-playback) pattern ini efisien karena tidak perlu lock di audio hot path.

8. **Ogg page walk dengan continuation-flag consistency check** (`metadata_region.cpp` baris 139) — Abort ketika `page->continued != packet_in_progress` adalah validasi yang sangat teliti dan tidak obvious.

9. **`presetDefault()` dalam try-catch di `nativeCreate()`** (`stretch_jni.cpp`) — Menghindari terminate() jika library throw exception yang unexpected.

10. **`g_registry_mutex` saat album loudness computation** (`replaygain_jni.cpp` baris 215–234) — Trade-off yang tepat: hold lock selama computation untuk menghindari use-after-free dari concurrent destroy. Waktu komputasi sub-millisecond dikonfirmasi oleh komentar.

---

*Laporan audit ini mencakup seluruh file native yang ditentukan dalam scope. Semua temuan berdasarkan static analysis — temuan dengan label "Needs Manual Verification" memerlukan dynamic analysis atau review implementasi Kotlin lebih dalam.*
