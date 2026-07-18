# Music Player — Flutter App

A feature-rich Flutter music player, primarily targeting Android 10+ with a web preview build included.

## Stack

- **Framework:** Flutter / Dart
- **Android backend:** Media3 (ExoPlayer), native Kotlin services
- **Native DSP (Phase 4):** C DSP pipeline (`dsp_pipeline.c`), gain processor (`gain_processor.c`), PCM buffer (`audio_buffer.c`) in `native_audio_runtime/` package — architecture established, not yet wired to Media3 audio thread
- **Key features:** Crossfade, lyrics (multi-provider), ReplayGain, sleep timer, queue persistence, themes

## How to run

The web build (`build/web/`) is pre-compiled and served by `server.js` on port 5000:

```
node server.js
```

To rebuild the web output after Dart/Flutter changes:
```
export PATH="/home/runner/flutter/bin:$PATH"
flutter build web --release --base-href /
```

The Android APK is the primary target — build with Android Studio or `flutter build apk`.

## Flutter SDK (Replit)

Flutter **3.44.5** diinstall manual di `/home/runner/flutter/` karena Nix hanya menyediakan 3.32.0.
Semua workflow sudah dikonfigurasi dengan `export PATH="/home/runner/flutter/bin:$PATH"`.

Kalau SDK hilang (environment reset), jalankan:
```
bash setup-flutter.sh
```
Script ini otomatis download dan install Flutter 3.44.5 ke `/home/runner/flutter/`.

## Project structure

- `lib/` — Dart/Flutter source (pages, services, models, widgets, themes)
- `android/` — Native Kotlin code (Media3 playback service, audio effects, etc.)
- `native_audio_runtime/` — Local Dart FFI package (native runtime foundation for future DSP/FFmpeg; see its `NATIVE_RUNTIME.md`). No DSP/FFmpeg logic yet.
- `assets/` — Fonts, images
- `build/web/` — Pre-compiled web output (served by server.js)
- `pubspec.yaml` — Flutter dependencies (depends on `native_audio_runtime` via local path)

## User preferences

- **Wajib search web** jika ada informasi, API, library, behavior, atau apapun yang berada di luar batas pengetahuan atau yang mungkin sudah berubah/usang — jangan berasumsi, jangan asal kasih jawaban/patch/saran sebelum verifikasi via web search. Ini berlaku di semua sesi.

- Setelah selesai pengerjaan, jalankan `flutter analyze` dan Restart App saja ketika build otomatis sudah selesai — **jangan rebuild web (`flutter build web`)** kecuali ada perintah eksplisit dari user.
- **Setiap pengerjaan (fitur/perubahan/perbaikan) wajib dicatat di halaman Changelog** (`lib/pages/settings_page/changelog_data.dart`, tampil di Pengaturan → Tentang → Changelog). Tambah satu entri baru di urutan paling atas berisi: versi app (dari `pubspec.yaml`), tanggal pengerjaan, dan daftar perubahan **singkat** (satu kalimat per item, tanpa detail teknis). Ini wajib, bukan opsional.
- **Setiap entri Changelog baru wajib pakai versi yang di-bump (naik), jangan sama dengan entri sebelumnya** — walaupun beberapa perubahan dikerjakan di hari/sesi yang sama. Setelah nambah entri baru, update juga `version:` di `pubspec.yaml` biar sinkron dengan versi terbaru di Changelog.
- Setelah kode selesai diubah dan analyze clean, langsung akhiri tanpa menunggu proses rebuild web selesai.
- Gunakan **Bahasa Indonesia non-formal / gaul** untuk semua pesan progres, penjelasan, dan info pengerjaan. Pakai "aku/kamu", bukan "gue/lu".
- Lakukan Pengerjaan dengan penuh pertimbangan supaya tidak membuat kesalahan yang tidak diingin kan dari hasil pengerjaan yang sudah di lakukan

## Target device (real Android testing device)

- **Model:** Xiaomi Mi 9T / K20 (hardware identik, beda nama regional)
- **Chipset:** Qualcomm Snapdragon 730 (8 nm) — octa-core 2× 2.2 GHz Kryo 470 Gold + 6× 1.8 GHz Kryo 470 Silver
- **GPU:** Adreno 618
- **RAM:** 6 GB — Android 11 + MIUI 12 baseline ~2.5 GB; efektif tersisa ~3.5 GB untuk app
- **Storage:** 64 GB UFS 2.0 (seq. read ~1.2 GB/s) — **no microSD**, semua storage internal
- **OS:** MIUI 12 (berbasis Android 11)
- **Layar:** 6.39" AMOLED, 1080×2340, ~403 ppi, Gorilla Glass 5 — full screen tanpa notch/punch-hole (kamera pop-up motorized); hitam = piksel mati → dark theme hemat baterai
- **Baterai:** 4000 mAh, 18W fast charge
- **Konektivitas:** USB-C 2.0, Bluetooth 5.0 (aptX), NFC, IR blaster, Wi-Fi ac dual-band

### Catatan hardware relevan untuk pengerjaan app
- **UFS 2.0** — I/O cukup kencang, tapi tetap kelola artwork cache & lyric cache secara ketat (no microSD, storage internal saja)
- **Adreno 618** — cukup kuat untuk shader GLSL (fluid background), tapi harus efisien; selalu render downscale + FittedBox, jangan full-res
- **RAM headroom ~3.5 GB** — hindari operasi paralel berat atau cache besar-besaran yang bisa bikin lag / boros baterai
- **AMOLED tanpa notch** — layar penuh bebas cutout; manfaatkan dark theme untuk efisiensi baterai
