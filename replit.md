# Music Player — Flutter App

A feature-rich Flutter music player, primarily targeting Android 10+ with a web preview build included.

## Stack

- **Framework:** Flutter / Dart
- **Android backend:** Media3 (ExoPlayer) + Media-Kit, native Kotlin services
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
Script ini otomatis download dan install Flutter 3.44.4 ke `/home/runner/flutter/`.

## Project structure

- `lib/` — Dart/Flutter source (pages, services, models, widgets, themes)
- `android/` — Native Kotlin code (Media3 playback service, audio effects, etc.)
- `assets/` — Fonts, images
- `build/web/` — Pre-compiled web output (served by server.js)
- `pubspec.yaml` — Flutter dependencies

## User preferences

- Setelah selesai pengerjaan, jalankan `flutter analyze` saja — **jangan rebuild web (`flutter build web`)** kecuali ada perintah eksplisit dari user.
- Gunakan **Bahasa Indonesia non-formal / gaul** untuk semua pesan progres, penjelasan, dan info pengerjaan. Pakai "aku/kamu", bukan "gue/lu".
- Lakukan Pengerjaan dengan penuh pertimbangan supaya tidak membuat kesalahan yang tidak diingin kan dari hasil pengerjaan yang sudah di lakukan

## Target device (real Android testing device)

- **Model:** Xiaomi Mi 9T / K20 (sama hardware, beda nama regional)
- **Chipset:** Snapdragon 730 (Kryo 470, octa-core, ~2.2GHz)
- **RAM:** 6GB
- **Storage:** 64GB
- **OS:** MIUI 12 (berbasis Android 11)
- Ini adalah device mid-range — pertimbangkan batasan RAM/CPU/storage saat menambahkan fitur baru (misal: prefetch/cache warm-up harus konservatif, hindari operasi berat/paralel besar-besaran yang bisa bikin app lag atau boros storage/baterai di device ini).
