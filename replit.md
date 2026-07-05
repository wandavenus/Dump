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
flutter build web --release --base-href /
```

The Android APK is the primary target — build with Android Studio or `flutter build apk`.

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
