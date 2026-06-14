---
name: LyricsSettings model
description: Singleton untuk pengaturan tampilan halaman lirik; harus di-init di main() setelah LogService.
---

## Fields (ValueNotifier)
- `fontSize`: double (14/18/22/26) — ukuran teks aktif
- `textAlign`: String ('left'/'center'/'right')
- `bgDim`: double (0.2–0.95) — opasitas overlay gelap
- `blurStrength`: double (0–50) — kekuatan blur latar
- `activeColor`: String ('white'/'accent'/'yellow')
- `showSource`: bool — tampilkan badge sumber lirik
- `karaokeMode`: bool — reserved untuk karaoke highlight

## SharedPreferences keys
Semua keys prefixed dengan `lyr_`: `lyr_fontSize`, `lyr_textAlign`, `lyr_bgDim`, `lyr_blur`, `lyr_activeColor`, `lyr_showSource`, `lyr_karaoke`.

## Init order in main()
```dart
await ThemeController.init();
await LogService.init();
await LyricsSettings.init();   // ← sebelum AudioEngine
await AudioEngine.initialize();
```

## Helper getters
- `LyricsSettings.resolvedTextAlign` → TextAlign enum
- `LyricsSettings.resolvedActiveColor` → Color

**Why:** LyricsSettings harus dipisah dari AudioEffectsService agar tidak ada circular dependency antara LyricsService (yang import AudioEffectsService.lyricsPath) dan settings.
