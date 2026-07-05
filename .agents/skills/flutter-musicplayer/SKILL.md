---
name: flutter-musicplayer
description: Panduan arsitektur, konvensi, dan pola pengembangan untuk proyek Flutter music player ini. Gunakan skill ini setiap kali mengerjakan fitur baru, debugging, atau refactor di repo ini — mencakup native bridge, audio engine, lirik, tema, dan konvensi koding.
---

# Flutter Music Player — Project Skill

## Aturan Wajib (Jangan Dilanggar)

- **Jangan jalankan `flutter build web`** kecuali ada perintah eksplisit dari user. Cukup `flutter analyze --no-fatal-infos` setelah selesai.
- **Bahasa komunikasi**: Bahasa Indonesia non-formal / gaul. Pakai "aku/kamu", bukan "gue/lu".
- Target utama adalah **Android APK**. Web build (`build/web/`) adalah preview statis yang sudah pre-compiled, dijalankan lewat `node server.js` di port 5000.

---

## Arsitektur Umum

```
lib/
  main.dart              ← entry point, part files: main/, edge, scroll_behavior, app, app_state
  Bottom NavBar/         ← bottom_nav.dart + state/page parts
  models/                ← LocalSong, Playlist, LyricLine, LyricsSettings, LoudnessData
  services/              ← semua business logic (audio, lyrics, playlist, media store, dll)
  pages/                 ← halaman UI (settings punya subfolder parts)
  widgets/               ← komponen reusable (player/, common/, local_song_card/)
  themes/                ← ThemeController, GlassTheme, GlassNavBar
  utils/                 ← ZoomFadeRoute, dll

android/app/src/main/kotlin/com/example/musicplayer/
  Media3PlaybackService.kt   ← service utama: crossfade, queue, repeat, shuffle, sleep timer
  MainActivity.kt            ← MethodChannel handler (delete song, dll)
  AudioEffectsManager.kt     ← EQ, bass boost, reverb, stereo widening
  ExoMetadataReader.kt       ← baca tag audio via ExoPlayer MetadataRetriever
  MetadataCacheDb.kt         ← SQLite cache metadata (mtime-keyed)
  crossfade/                 ← CrossfadeController.kt + PreloadManager.kt
  effects/                   ← StereoWideningAudioProcessor.kt, StereoWidthManager.kt
```

---

## Audio Engine

### Init Order (wajib urut)
```
ThemeController → LogService → LyricsSettings → AudioEngine →
AudioEffectsService → LyricsService.init() → AudioService
```

### Arsitektur Dual-Player
- **Native-first**: semua crossfade, queue, shuffle, repeat, sleep timer dikerjain di `Media3PlaybackService.kt` (Handler tick)
- **Dart sisi**: `DualPlayerManager` + `CrossfadeController` Dart adalah no-op stubs — Dart hanya konsumen EventChannel
- Queue mutations (insertNext, appendToQueue, removeFromQueue, reorderQueue) → native, konfirmasi via `queueStream`

### Native Queue Ownership
Native owns: queue, shuffle (ExoPlayer shuffleModeEnabled), repeat, sleep timer
Dart: subscribe ke EventChannel stream saja, jangan asumsi queue index dari sisi Dart

---

## Native ↔ Dart Bridge

### Channel Names (dari Media3PlaybackService)
- **MethodChannel** `com.example.musicplayer/audio` → perintah ke native
- **EventChannel** `com.example.musicplayer/events` → state updates ke Dart
- **EventChannel** `com.example.musicplayer/queue` → queue changes

### Pola Tambah MethodChannel Handler Baru
**Kotlin side (MainActivity.kt):**
```kotlin
"namaMethod" -> {
  val arg = call.argument<String>("key")
  // logic...
  result.success(returnValue)
}
```
**Dart side (service terkait):**
```dart
static const _channel = MethodChannel('com.example.musicplayer/audio');
await _channel.invokeMethod('namaMethod', {'key': value});
```

---

## Lirik

- `LyricsService` pakai `LyricsFetchManager` yang orkestrasikan local (Embedded, LocalFile) + 6 online provider (LRCLIB, NetEase, Kugou, Kuwo, QQMusic, Musixmatch) secara paralel
- `LyricsSettings` adalah singleton (fontSize, textAlign, bgDim, blurStrength, activeColor, showSource, karaokeMode) — init di `main()` setelah `LogService.init()`
- `LyricsPage` adalah full-screen route (bukan modal) — dibuka via `Navigator.push` dengan `SlideTransition` dari bawah
- ELRC word-level karaoke: `ElrcWordExtractor` parse timestamps kata; binary search di `_buildElrcText`

---

## Tema & UI

### ThemeController
- `glassTheme` = master toggle
- 9 sub-toggle: NavBar, AppBar, MiniPlayer, PlayerSheet, AlbumCard, ArtistCard, LibraryBar, SearchBar, Settings

### Player UI
- `UnifiedMorphPlayer` = satu-satunya implementasi player (folder `lib/pages/music_player/` sudah dihapus)
- `PlayerPanelController` = adapter tipis di atas `PlayerSheetController`
- `MiniPlayer` + `PlayerSheet` + `PlayerSheetController` masih dipakai

### Bottom Sheet / SwipeToDismissSheet
- **Wajib**: `showModalBottomSheet` pakai `backgroundColor: Colors.transparent` (bukan warna langsung)
- Background + border radius diletakkan di dalam child sebagai `Material(color: ..., borderRadius: ...)` supaya ikut bergerak saat swipe dismiss
- Jangan pasang warna di level `showModalBottomSheet` — itu di-render di luar widget tree dan tidak ikut `Transform.translate`

---

## Pola Umum & Konvensi

### File Besar → Pakai `part`
Halaman/widget besar dipecah pakai `part` directive. Contoh:
```dart
// settings_page.dart
part 'settings_page/body.dart';
part 'settings_page/audio.dart';
// dst...
```

### Context-Safe Async (hindari use_build_context_synchronously)
```dart
// Capture sebelum await
final messenger = ScaffoldMessenger.of(context);
final navigator = Navigator.of(context);
await someFuture();
if (!mounted) return;
messenger.showSnackBar(...); // pakai captured reference
```

### Metadata & Cache
- `ExoMetadataReader` (ExoPlayer MetadataRetriever) baca tag audio
- `MetadataCacheDb` (SQLite, mtime-keyed) simpan hasil scan
- jaudiotagger sudah dihapus

### ReplayGain
- `LoudnessData` model + `ReplayGainService`
- Tags via `ExoMetadataReader` + `MetadataCacheDb`
- Target Android 10+ MIUI 11+

---

## MediaStore & Web

- `MediaStoreService.getSongs()` melempar `MissingPluginException` di web/browser — ini normal
- Semua section harus handle list kosong dengan graceful empty state
- Di web, fitur yang butuh native (MediaStore, audio playback) tidak akan jalan

---

## Debug Mode

Ketuk area **Versi 3x dalam 2 detik** → debug section muncul di Settings (notif icon picker, effect status, audio session info)

---

## Workflow Setelah Setiap Perubahan

```bash
flutter analyze --no-fatal-infos
```

Target: **No issues found!** — 0 warning, 0 error.
Jangan rebuild web kecuali ada perintah eksplisit dari user.
