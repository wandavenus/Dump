# Roadmap Penyempurnaan Aplikasi Flutter

Dokumen ini menjadi rencana kerja bertahap untuk menyempurnakan aplikasi musik
tanpa migrasi ke Jetpack Compose. Flutter tetap menjadi framework utama, dengan
Media3/Kotlin dan native DSP sebagai backend audio Android.

**Tanggal dibuat:** 2 Agustus 2026  
**Target utama:** Xiaomi Mi 9T/K20, Android 11, MIUI 12  
**Prinsip utama:** jangan mengorbankan stabilitas audio demi refactor besar.

## Urutan pengerjaan

Urutan di bawah dibuat berdasarkan risiko dan ketergantungan. Tahap audio dan
startup dikerjakan lebih dulu karena menjadi fondasi semua fitur UI.

1. Stabilitas startup dan service readiness
2. Konsistensi state queue, player, dan notification
3. Pengujian audio pada perangkat target
4. Optimasi artwork, lyrics, dan player animation
5. Validasi DSP agar tidak aktif tanpa opt-in
6. Penyempurnaan Settings dan pengalaman pengguna
7. Pengujian otomatis, analyzer, dan build APK secara rutin

---

## 1. Stabilitas startup dan service readiness

### Tujuan

Memastikan app selalu melewati startup dengan aman, termasuk fresh install,
cold start, service yang belum pernah dibuat, dan startup tanpa queue.

### Rencana

- Audit ulang urutan init di `lib/main/main.dart`.
- Pastikan panggilan MethodChannel yang bisa lambat tidak memblokir `runApp()`.
- Pertahankan `ServiceReadyGate` sebagai sumber readiness, bukan retry berbasis
  timer.
- Pastikan service tidak dimulai hanya karena inisialisasi settings.
- Uji startup dengan cache kosong, queue kosong, dan service belum pernah hidup.
- Catat error startup melalui `BootTrace` tanpa membuat UI blank.

### Selesai jika

- Fresh install bisa masuk Home tanpa layar blank.
- Tidak ada `PlatformException(not_ready)` yang tidak tertangani.
- Service tidak crash karena deadline `startForeground()`.
- Startup tetap aman ketika MediaStore atau native runtime belum siap.

### Validasi

- Flutter Analyze target `lib test`.
- APK debug pada fresh install.
- Cold start berulang setelah force-stop.
- Log `BootTrace` dan log native tidak menunjukkan error startup fatal.

---

## 2. Konsistensi state queue, player, dan notification

### Tujuan

Membuat satu sumber kebenaran yang konsisten untuk lagu aktif, queue, posisi,
shuffle, repeat, play/pause, dan notification.

### Rencana

- Pastikan native tetap menjadi pemilik queue, shuffle, repeat, dan posisi.
- Pastikan Dart hanya mengonsumsi stream native dan tidak menyimpan state
  tandingan yang dapat menjadi stale.
- Audit transisi crossfade dan pergantian active player.
- Pastikan metadata notification selalu mengikuti active player terbaru.
- Pertahankan perilaku notification:
  - saat play: ongoing dan tidak bisa di-swipe,
  - saat pause: bisa di-swipe,
  - banner/head-up default off.
- Uji restore queue setelah proses service dihentikan dan dibuat ulang.

### Selesai jika

- UI, notification, dan MediaSession menampilkan lagu yang sama.
- Tidak ada lagu lama muncul sesaat setelah crossfade atau skip.
- Queue tetap benar setelah restart service.
- Swipe notification saat pause tidak menghapus queue atau menghentikan state
  player secara tidak sengaja.

### Validasi

- Uji play/pause/next/previous/seek.
- Uji shuffle dan repeat-all.
- Uji crossfade dengan queue minimal tiga lagu.
- Uji notification dari lock screen, notification shade, dan tombol headset.

---

## 3. Pengujian audio pada perangkat target

### Tujuan

Memastikan perilaku audio nyata sesuai desain pada Xiaomi Mi 9T/K20, bukan hanya
lulus di web preview atau JVM test.

### Rencana

- Buat checklist pengujian manual khusus Snapdragon 730, Android 11, MIUI 12.
- Uji format audio yang didukung: MP3, AAC/M4A, FLAC, ALAC, dan format lain
  yang tersedia di library.
- Uji cold start, background playback, screen-off, lock screen, dan Bluetooth.
- Uji crossfade, gapless transition, seek, speed, pitch, dan sleep timer.
- Uji audio output mode, offload, Hi-Res, dan Bit-Perfect.
- Catat artifact audio, silence, click/pop, drift posisi, dan crash.

### Selesai jika

- Tidak ada crash atau silent playback pada skenario utama.
- Crossfade tidak memutar item queue yang salah.
- Posisi lagu tetap akurat setelah speed/pitch dan crossfade.
- Audio tetap berjalan saat layar mati dan app berada di background.

### Validasi

- Manual test matrix pada perangkat target.
- Logcat dengan filter service/audio/Media3.
- Native DSP tests.
- APK debug dan release candidate.

---

## 4. Optimasi artwork, lyrics, dan player animation

### Tujuan

Menjaga scrolling, artwork, lyrics, dan player morph tetap halus dengan batas
RAM dan GPU perangkat target.

### Rencana

- Audit ukuran bitmap dan lifetime cache artwork.
- Pastikan kegagalan ekstraksi artwork tetap retryable dan tidak menyimpan
  fallback sementara sebagai palette permanen.
- Kurangi pekerjaan decode/prewarm yang bersamaan saat Home atau crossfade.
- Uji lyrics scrolling, karaoke word timing, fling, auto-follow, dan manual
  scroll.
- Pertahankan jalur morph player bebas dari implicit animation yang berat.
- Profiling shader/background dan RepaintBoundary pada player.

### Selesai jika

- Tidak ada flicker artwork saat shuffle atau crossfade.
- Tidak ada jank yang terlihat saat membuka player dan lyrics.
- Lyrics tetap bisa fling setelah forwarded drag.
- Memory cache tidak tumbuh tanpa batas selama sesi panjang.

### Validasi

- Scroll test pada Home, Browse, lyrics, dan queue.
- Sesi playback panjang dengan banyak lagu/artwork.
- Profiling Flutter frame timing dan memory.
- Uji artwork tanpa embedded image dan artwork yang gagal dibaca.

---

## 5. Validasi DSP agar tidak aktif tanpa opt-in

### Tujuan

Memastikan instalasi baru tidak mengubah audio sebelum user mengaktifkan fitur
di Settings.

### Rencana

- Pertahankan native default bypass untuk compressor, crossfeed, limiter, dan
  soft clipper.
- Pastikan ReplayGain dan Loudness Normalization tetap native-bypassed.
- Pastikan EQ, BassBoost, LoudnessEnhancer, stereo widening, dan crossfade
  default off atau identity.
- Audit setiap startup sync di `AudioEffectsService`.
- Pastikan mutual exclusion Bit-Perfect, EQ, ReplayGain, dan Loudness Norm tetap
  konsisten.
- Tambahkan regression test untuk default bypass dan perubahan setting.

### Selesai jika

- Fresh install menghasilkan audio passthrough/identity.
- Tidak ada processor audible selama startup race.
- Mengaktifkan satu fitur hanya mengubah processor yang dipilih.
- Mematikan fitur mengembalikannya ke bypass tanpa perlu restart app.

### Validasi

- Native DSP test suite.
- Uji setting satu per satu dan kombinasi yang saling eksklusif.
- Uji first play segera setelah fresh install.
- Bandingkan output dengan semua DSP off dan mode Bit-Perfect.

---

## 6. Penyempurnaan Settings dan pengalaman pengguna

### Tujuan

Membuat Settings lebih jelas, aman, dan mudah dipahami tanpa mengubah perilaku
audio secara diam-diam.

### Rencana

- Pastikan setiap setting memiliki label, status, dan feedback yang jelas.
- Jelaskan fitur yang saling eksklusif sebelum user mengaktifkannya.
- Tampilkan status native capability hanya jika informasinya akurat.
- Audit modal sheet, gesture, slider, dan empty/error state.
- Pertahankan modal sheet dengan animasi naik/turun normal tanpa efek fade yang
  tidak diinginkan.
- Pastikan perubahan setting tersimpan dan dipulihkan setelah restart.
- Perbarui localization EN/ID untuk label dan pesan baru.

### Selesai jika

- User dapat memahami apakah sebuah DSP aktif atau bypass.
- Tidak ada toggle yang tampak aktif tetapi tidak diterapkan.
- Settings tetap responsif saat service belum ready.
- State settings konsisten setelah force-stop dan restart.

### Validasi

- Uji seluruh halaman Settings pada fresh install dan upgrade install.
- Uji locale Indonesia dan Inggris.
- Uji slider multitouch dan konflik dengan scroll.
- Uji status disabled/locked pada mode Bit-Perfect dan interlock DSP.

---

## 7. Pengujian otomatis, analyzer, dan build APK rutin

### Tujuan

Mencegah regresi saat penyempurnaan dilakukan bertahap.

### Rencana

- Jalankan analyzer dengan target eksplisit `lib test`.
- Pertahankan native DSP tests untuk processor default, bypass, dan processing.
- Tambahkan unit test untuk state/decision logic yang belum terlindungi.
- Tambahkan widget test untuk komponen player, Settings, lyrics, dan modal
  penting.
- Jalankan `git diff --check` pada setiap perubahan.
- Build APK setelah perubahan Kotlin/native yang menyentuh runtime Android.
- Simpan laporan audit penting sebagai Markdown di root repo.
- Bedakan error runtime, type error, dan lint style-only saat membaca analyzer.

### Selesai jika

- Analyzer bersih pada target `lib test`.
- Native DSP test suite lulus.
- APK debug berhasil dibuat setelah perubahan Android.
- Tidak ada trailing whitespace atau file audit yang tertinggal.
- Regression test tersedia untuk setiap bug audio atau state yang sudah pernah
  diperbaiki.

### Validasi rutin

```bash
# Flutter analyzer
bash setup-flutter.sh
export PATH="/home/runner/workspace/flutter-ws/flutter/bin:$PATH"
flutter analyze lib test

# Native DSP tests
cd native_audio_runtime
dart test

# APK debug
cd ..
bash setup-flutter.sh && bash build-apk.sh

# Diff hygiene
git diff --check
```

---

## Cara memakai roadmap ini

Setiap pengerjaan berikutnya sebaiknya:

1. Memilih satu area utama atau satu sub-item kecil.
2. Membaca memory dan dokumentasi terkait sebelum mengubah kode.
3. Menentukan kriteria selesai sebelum implementasi.
4. Membuat perubahan sekecil mungkin.
5. Menjalankan validasi yang tercantum pada area tersebut.
6. Menambahkan changelog app jika perubahan menyentuh fitur atau perilaku user.
7. Memperbarui dokumen/memory jika ada keputusan arsitektur baru.

Roadmap ini bukan target untuk dikerjakan sekaligus. Prioritasnya adalah
stabilitas, audio yang aman, dan pengalaman playback yang konsisten.