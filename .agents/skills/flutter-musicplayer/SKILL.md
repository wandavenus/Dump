---
name: flutter-musicplayer
description: Panduan arsitektur, konvensi, dan pola pengembangan untuk proyek Flutter music player ini. Gunakan skill ini setiap kali mengerjakan fitur baru, debugging, atau refactor di repo ini — mencakup native bridge, audio engine, lirik, tema, dan konvensi koding.
---

# Flutter Music Player — Project Skill

## Aturan Wajib (Jangan Dilanggar)

- **Jangan jalankan `flutter build web`** kecuali ada perintah eksplisit dari user. Cukup `flutter analyze --no-fatal-infos` setelah selesai. Target: **No issues found!**
- **Bahasa komunikasi**: Bahasa Indonesia non-formal / gaul. Pakai "aku/kamu", bukan "gue/lu".
- Target utama adalah **Android APK**. Web build (`build/web/`) adalah preview statis pre-compiled, dijalankan via `node server.js` port 5000.
- Web preview **tidak otomatis reflect perubahan Dart** — butuh rebuild manual sebelum bisa diverifikasi visual.

---

## Struktur Folder

```
lib/
  main.dart              ← entry point; part files: main/, edge, scroll_behavior, app, app_state
  Bottom NavBar/         ← bottom_nav.dart + state/page parts
  models/                ← LocalSong, Playlist, LyricLine, LyricsSettings, LoudnessData, ReplayGainMode
  services/              ← semua business logic (audio, lyrics, playlist, media store, dll)
  pages/                 ← halaman UI; settings/ dan music_list/ punya subfolder parts
  widgets/               ← komponen reusable; player/, common/, local_song_card/
  themes/                ← ThemeController, GlassTheme, GlassNavBar
  utils/                 ← ZoomFadeRoute, dll

android/app/src/main/kotlin/com/example/musicplayer/
  MainActivity.kt            ← semua MethodChannel/EventChannel setup + delete song handler
  Media3PlaybackService.kt   ← service utama: crossfade, queue, repeat, shuffle, sleep timer
  audio_focus/               ← AudioFocusManager.kt
  crossfade/                 ← CrossfadeController.kt, PreloadManager.kt
  effects/                   ← AudioEffectsManager.kt, StereoWideningAudioProcessor.kt
  events/                    ← EventEmitter.kt
  metadata/                  ← ExoMetadataReader.kt, MetadataCacheDb.kt, MetadataPrescanner.kt
  notification/              ← PlaybackNotificationManager.kt
  queue/                     ← QueueManager.kt, QueueSync.kt
  replay_gain/               ← ReplayGainScanner.kt
  sleep_timer/               ← SleepTimerManager.kt
  transport/                 ← PlayPauseFadeController.kt, TransportCommands.kt, TransportState.kt
  utils/                     ← MediaItemFactory.kt, TrackMapper.kt
  MediaKitPlaybackService.kt ← mirror service (no audio) untuk engine MediaKit
  MediaKitStatePlayer.kt     ← SimpleBasePlayer adapter
  MediaKitEventEmitter.kt    ← transport EventChannel ke Dart
```

---

## Channel Names (Native ↔ Dart)

Semua didefinisikan di `MainActivity.kt`:

| Channel | Tipe | Arah | Kegunaan |
|---|---|---|---|
| `musicplayer/media_store` | Method | D→N | getSongs, getArtwork, getEmbeddedLyrics, getReplayGainTags, deleteSong |
| `musicplayer/audio_effects` | Method | D→N | attachEffects, setSpatialEnabled, setBassBoost, setReverb |
| `musicplayer/media3_playback` | Method | D→N | play, pause, seek, setQueue, skipNext, skipPrev, dll |
| `musicplayer/media3_*` | Event | N→D | playbackState, position, duration, currentTrack, queue, shuffleMode, repeatMode, sleepTimer, audioSessionId |
| `musicplayer/native_logs` | Event | N→D | log streaming dari Kotlin |
| `musicplayer/mediakit_service` | Method | D→N | startService, updateMetadata, updatePlaybackState, release |
| `musicplayer/mediakit_transport` | Event | N→D | transport commands (play/pause/next/prev/seek) |

### Pola Tambah MethodChannel Handler Baru
**Kotlin (MainActivity.kt):**
```kotlin
"namaMethod" -> {
  val arg = call.argument<String>("key")
  // Operasi blocking: WAJIB pakai Thread baru
  Thread {
    val result = doWork(arg)
    runOnUiThread { result.success(result) }
  }.start()
}
```
**Dart:**
```dart
static const _channel = MethodChannel('musicplayer/media_store');
final result = await _channel.invokeMethod('namaMethod', {'key': value});
```
> **Penting**: `ExoMetadataReader` dan jaudiotagger **BLOCKING** — wajib dipanggil di `Thread {}` bukan di main thread Kotlin.

---

## Audio Engine

### Init Order di `main()` (wajib urut!)
```dart
await ThemeController.init();
await LogService.init();          // sebelum AudioEngine
await LyricsSettings.init();      // sebelum AudioEngine
await AudioEngine.initialize();   // buat Player instance
await AudioEffectsService.init(); // load prefs, apply effects
LyricsService.init();             // setelah AudioEffectsService
AudioService.initialize();        // subscribe streams
SleepTimerService.initialize();   // setelah AudioService
```

### Layer Stack
```
AudioEngine          lib/services/audio/audio_engine.dart
  └─ buat AudioPlayer + AndroidEqualizer + AndroidLoudnessEnhancer pipeline (Android only)
  └─ broadcast androidAudioSessionId ke native via musicplayer/audio_effects

AudioEffectsService  lib/services/audio/audio_effects_service.dart
  └─ manage EQ, normalize, crossfade, pitch, speed, bass boost, reverb, spatial
  └─ persist semua settings ke SharedPreferences
  └─ SUDAH ADA built-in EQ presets: Normal, Classical, Dance, Folk, Heavy Metal, Hip-Hop, Jazz, Pop, Rock

CrossfadeController  lib/services/audio/crossfade_controller.dart
  └─ NO-OP STUB — real crossfade ada di native Kotlin

AudioService         lib/services/audio_service.dart
  └─ facade; pakai AudioEngine.player; expose AudioService.player untuk compat

AudioSettingsService ← SHIM ONLY, delegate ke AudioEffectsService; jangan hapus
```

### EQ Presets — AndroidEqualizerParameters
`AndroidEqualizerParameters` dari just_audio **tidak punya** `.presets` atau `.setPreset()`.
Preset diimplementasi manual di `AudioEffectsService.eqPresets` sebagai `List<Map<String, dynamic>>` dengan field `'name'` dan `'gains': List<double>`.
`applyEqPreset(index)` → iterate bands, clamp ke minDb/maxDb, panggil `band.setGain()`.

### Native Audio Effects (Android)
Channel: `musicplayer/audio_effects`, handler di `MainActivity.kt`
- **Flow**: `androidAudioSessionIdStream` → `AudioEngine._attachNativeEffects(sessionId)` → Kotlin init `Virtualizer`, `BassBoost`, `PresetReverb`
- `attachEffects` HARUS dipanggil SEBELUM set/enable effects lainnya
- BassBoost strength: 0–1000 (Short di Kotlin)
- Reverb presets: 0=NONE, 1=SMALLROOM, 2=MEDIUMROOM, 3=LARGEROOM, 4=MEDIUMHALL, 5=LARGEHALL, 6=PLATE
- Virtualizer strength: hardcode 1000 saat enabled
- LoudnessEnhancer: `setTargetGain()` menerima **double** (millibels), default 300.0 (+3 dB). Bukan int.

### Audio Output Mode
- 0 = Auto/AAudio (default, Android 8+)
- 1 = OpenSL ES
- 2 = Hi-Res Audio: coba 5 metode: `setParameters("hifi_audio=on")`, `"high_resolution_audio=on"`, `"hifi_enable=on"`, `"audio_qoe_enable=on"`, `"hi_res_audio_enabled=on"` + MIUI broadcast + ContentResolver — semua dalam independent try-catch

---

## Dual-Player Crossfade (Native-First)

**Aturan**: Semua crossfade logic jalan di `Media3PlaybackService.kt` (Handler tick).
`DualPlayerManager.dart` dan `CrossfadeController.dart` = **no-op stubs**, retained untuk call-site compat saja.

### Arsitektur
- `primaryPlayer` + `secondaryPlayer` (ExoPlayer)
- `activePlayer` = yang terhubung ke MediaSession
- `standbyPlayer()` = preload track berikutnya, volume=0
- `positionTicker` (200ms) → `maybeCrossfadeOut()` → saat remaining ≤ crossfadeDurationSec → `promoteSecondaryPlayer()`
- Promotion: switch `activePlayer`, `session.setPlayer(newPlayer)`, start `startCrossfadeFadeIn()` (25 langkah linear)

### Bug Crossfade + REPEAT_MODE_ALL
Saat A→B crossfade dengan repeat-all: queue[0] bisa main ~1 detik selama fade-in B.
**Fix di `beginCrossfade()`**: (1) hapus prefix items (0..ci-1) + suffix setelah A, sisa tepat [A]; (2) set `current.repeatMode = REPEAT_MODE_OFF` **SETELAH** `setActivePlayer(standby)`, bukan sebelumnya (agar emit Flutter tidak reset UI).

### Native Queue Ownership
Native owns: queue, shuffle (ExoPlayer `shuffleModeEnabled`), repeat mode, sleep timer, current index.
Dart **hanya konsumen EventChannel** — tidak boleh asumsi queue index dari sisi Dart.

Queue mutations dari Dart: `insertNext` / `appendToQueue` / `removeFromQueue` / `reorderQueue` → `Media3PlaybackBridge` → MethodChannel → native → emit `queueStream` → Dart update.

---

## Service & Notification

### startForeground() — Aturan MIUI 12
`startForeground()` hanya boleh dipanggil **SATU KALI** per service lifecycle.
- `ensureMediaForeground()` = satu-satunya callsite, ada guard `isForeground`
- Update notif berikutnya: `NotificationManager.notify(NOTIFICATION_ID, notification)`
- Panggil ulang `startForeground()` → ANR, flicker, foreground state corruption di MIUI 12

### startForeground() Deadline
`Media3PlaybackService.onCreate()` **tidak** panggil `startForeground()` sendiri.
Jika `needsService` allowlist menyertakan `pause/stop/seek/skip` saat service cold-start dengan queue kosong → `RemoteServiceException` (deterministik).
**Only `play` dan `setQueue` boleh ada di allowlist** — karena keduanya guarantee path ke `ensureMediaForeground()`.

### Transport Controls & Notifikasi
Tombol notif memerlukan `addAction()` eksplisit + `MediaStyle.setShowActionsInCompactView(0, 1, 2)`.
`Media3 MediaSession` saja tidak inject tombol ke custom notification.
Action constants: `ACTION_PLAY_PAUSE`, `ACTION_SKIP_NEXT`, `ACTION_SKIP_PREV` (companion object di service).

### State Restoration
`android:stopWithTask="false"` + `START_STICKY` → service tetap hidup.
`AudioService.syncFromNative()` dipanggil dari `lib/main/main.dart` (cold start) dan `lib/main/app_state.dart` (setiap `AppLifecycleState.resumed`).

---

## Sleep Timer

Jalan di native: `SleepTimerManager.kt` pakai Android `Handler.postDelayed()`.
Dart `SleepTimerService` hanya adapter tipis:
- `.startDuration(dur)` → `Media3PlaybackBridge.setSleepTimer(ms)`
- `.startEndOfSong()` → `Media3PlaybackBridge.setSleepTimerEndOfSong()`
- `.cancel()` → `Media3PlaybackBridge.cancelSleepTimer()`
- `SleepTimerService.initialize()` di `main()` **setelah** `AudioService.initialize()`

---

## Queue Persistence

SharedPreferences: `PREFS_NAME = "media3_queue_prefs"`
Keys: `queue_json` (JSONArray), `queue_index` (int), `position_ms` (long), `repeat_mode` (int), `shuffle_enabled` (bool).
`saveQueueToPrefs()` dipanggil setelah **setiap** mutasi queue.
`restoreQueueFromPrefs()` di `onCreate()`: panggil `player.prepare()` tapi **TIDAK** `player.play()` (restored paused).

---

## Metadata Engine

jaudiotagger telah **dihapus**. Diganti:
1. **MediaStore expanded projection** — year, track, album_artist, genre (API30+), bitrate/samplerate (API31+)
2. **`MetadataCacheDb`** — SQLite via SQLiteOpenHelper, WAL mode, mtime-keyed invalidation; sentinel `"\u0000NONE\u0000"` untuk "sudah di-scan, tidak ada lirik"
3. **`ExoMetadataReader`** — ExoPlayer `MetadataRetriever.retrieveMetadata()` baca ID3v2, Vorbis, MdtaMetadataEntry; BLOCKING, wajib dipanggil di `Thread {}`

`LocalSong` punya 7 optional fields: year, trackNumber, discNumber, albumArtist, genre, bitrate, sampleRate.
MediaStore TRACK field: jika `rawTrack > 1000` → disc = rawTrack/1000, track = rawTrack%1000.

### jaudiotagger (masih ada di build.gradle untuk getEmbeddedLyrics legacy path)
```gradle
implementation 'net.jthink:jaudiotagger:2.2.5'
// packagingOptions wajib:
exclude 'META-INF/LICENSE'
exclude 'META-INF/NOTICE'
exclude 'META-INF/*.kotlin_module'
```

---

## ReplayGain

| File | Peran |
|---|---|
| `lib/models/loudness_data.dart` | `LoudnessData` + `LoudnessSource` enum |
| `lib/models/replay_gain_mode.dart` | off / auto / track / album |
| `lib/services/replay_gain_service.dart` | baca tag via MethodChannel `musicplayer/media_store` → cache SharedPrefs |
| `lib/services/loudness_source_resolver.dart` | priority: RG track → RG album → R128 → iTunNORM → none |

Priority chain per track: REPLAYGAIN_TRACK_GAIN → R128_TRACK_GAIN (+5 dB offset) → iTunNORM → none.
Gain dikirim ke `AudioEngine.applyNormalize(enabled: true, targetGainMb: gainDb * 100)`.
Android: `AndroidLoudnessEnhancer.setTargetGain(mb)` clamp ±2400 mb.

---

## Sistem Lirik

### LyricsFetchManager — Pipeline
1. Memory cache (instant)
2. Failure TTL check (1 jam — skip provider jika baru-baru ini gagal)
3. Disk cache (SharedPrefs, 30 hari, key = `artist|title|album|dur`)
4. Local: Embedded → LocalFile (sequential)
5. **Online providers paralel**: LRCLIB, NetEase, Kugou, Kuwo, QQMusic, Musixmatch
6. Global deadline 15 detik; upgrade window 2 detik setelah result pertama; jika wordTimedLrc → return langsung

### LyricsQuality Enum (prioritas tinggi ke rendah)
`wordTimedLrc > charTimedLrc > lineTimedLrc > plainLrc > unsyncedLyrics > none`

### File Layout
```
lib/services/lyrics_service/
  quality.dart, cancellation.dart, provider.dart, lrc_parser.dart
  cache_manager.dart, rate_limiter.dart, fetch_manager.dart
  providers/
    embedded_provider.dart, local_file_provider.dart
    lrclib_provider.dart, netease_provider.dart, kugou_provider.dart
    kuwo_provider.dart, qq_music_provider.dart, musixmatch_provider.dart
    provider_http.dart  ← shared HTTP: 5s connect / 15s read, 2 retries, exponential backoff
```

### ELRC Word-Level Karaoke
- `ElrcWordExtractor.extractAll(rawLrc)` → `List<List<ElrcWord>>` (satu per baris)
- Renderer: binary search `word.start <= position` → currentWordIdx; fill fraction antar kata
- Fallback ke char-fill jika `rawLrc == null` atau baris tanpa word timestamps
- `ElrcWordExtractor` ada di renderer layer (bukan service layer) — `LrcParser` tidak dimodifikasi

### LyricsSettings (singleton)
Fields ValueNotifier: `fontSize`, `textAlign`, `bgDim`, `blurStrength`, `activeColor`, `showSource`, `karaokeMode`
SharedPrefs keys prefixed `lyr_`: `lyr_fontSize`, `lyr_textAlign`, `lyr_bgDim`, `lyr_blur`, `lyr_activeColor`, `lyr_showSource`, `lyr_karaoke`
Init di `main()` sebelum `AudioEngine`.

### LyricsPage
Full-screen route (bukan modal). Buka via `Navigator.push` dengan `SlideTransition` dari bawah (`Offset(0,1)` → `Offset.zero`, 380ms, `Curves.easeOutCubic`).
Tombol kanan header: icon textformat → `_LyricsAppearanceSheet` (bottom sheet dengan kontrol tampilan).

### Auto-scroll vs User Swipe
Control hiding (progress bar + transport) hanya dari genuine user swipe-up.
Guard wajib: `notification.dragDetails != null` pada `ScrollUpdateNotification` — null untuk programmatic `jumpTo`/`animateScroll`.

### Forwarded Drag + Fling
Overlay transparan yang forward drag ke `ScrollPosition.jumpTo()` harus juga wire `onVerticalDragEnd` ke `goBallistic(-velocity)` — tanpa ini scroll berhenti mendadak saat jari diangkat (tanpa momentum).

---

## UI & Widget

### Player
- `UnifiedMorphPlayer` = satu-satunya player implementation (`lib/pages/music_player/` sudah dihapus)
- `PlayerPanelController` = adapter tipis di atas `PlayerSheetController`; jangan hapus `PlayerSheetController`, `player_sheet.dart`, `mini_player.dart`
- Semua widget baru panggil `PlayerPanelController.instance.open()`, jangan direct import `PlayerSheetController`

### Player Background Shader
GLSL fluid shader (`assets/shaders/fluid.frag`) + palette_generator.
Render di 256×512 via `FittedBox.cover`. Color floats di-pre-compute per song; hanya `uTime` yang dikirim per frame.

### SwipeToDismissSheet — Aturan Penting
`showModalBottomSheet` **WAJIB** pakai `backgroundColor: Colors.transparent` (hapus `shape`).
Background + border radius diletakkan di dalam child sebagai `Material(color: ..., borderRadius: ..., clipBehavior: Clip.antiAlias)` supaya ikut `Transform.translate` saat swipe.

```dart
// ✅ BENAR
showModalBottomSheet(
  backgroundColor: Colors.transparent,  // tanpa shape
  builder: (_) => SwipeToDismissSheet(
    child: Material(
      color: const Color(0xFF1C1C1E),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(child: Column(...)),
    ),
  ),
);
// ❌ SALAH — background tidak ikut bergerak saat swipe
showModalBottomSheet(
  backgroundColor: const Color(0xFF1C1C1E),
  shape: RoundedRectangleBorder(...),
  builder: (_) => SwipeToDismissSheet(child: SafeArea(...)),
);
```

`DraggableScrollableSheet` (log viewer) **dikecualikan** dari SwipeToDismissSheet — gesture-nya akan konflik.

### ThemeController
`glassTheme` = master toggle. 9 sub-toggle: NavBar, AppBar, MiniPlayer, PlayerSheet, AlbumCard, ArtistCard, LibraryBar, SearchBar, Settings.

### Library Edit Mode
`LibraryContent` StatefulWidget; `ReorderableListView` saat `_editMode=true` (wajib `shrinkWrap: true` + `NeverScrollableScrollPhysics` karena dibungkus `SingleChildScrollView`).
Urutan disimpan ke SharedPrefs key `'library_item_order'` sebagai `List<String>` of item IDs.

### Home Sections
`home_sections.dart` pakai `part` ke `home/albums_section.dart`, `home/recently_played_section.dart`, `home/artists_section.dart`.

### Search Keyboard
`TextField autofocus: false`. Keyboard muncul hanya saat user tap field (`focusNode.requestFocus()`).
`deactivate()` di state → `_focusNode.unfocus()` untuk dismiss saat tab switch.
`wantKeepAlive = false` agar state tidak dipertahankan saat tab switch.

---

## Konvensi Koding

### File Besar → `part`
```dart
// settings_page.dart
part 'settings_page/body.dart';
part 'settings_page/audio.dart';
// part files tidak bisa declare import sendiri — import ada di barrel
```

### Context-Safe Async (hindari `use_build_context_synchronously`)
```dart
final messenger = ScaffoldMessenger.of(context);  // capture sebelum await
final navigator = Navigator.of(context);
await someFuture();
if (!mounted) return;
messenger.showSnackBar(...);  // pakai captured reference
```

### Unnecessary Underscores
Pakai `_` untuk semua wildcard parameter yang tidak dipakai:
```dart
// ✅
pageBuilder: (_, _, _) => MyPage(),
transitionsBuilder: (_, _, _, child) => child,
// ❌
pageBuilder: (_, __, ___) => MyPage(),
```

### Settings Modularisasi
`settings_page.dart` sebagai barrel + subfolder `settings_page/` untuk tiap section.
Shared widgets di `lib/pages/settings/settings_widgets.dart`: `SettingsToggleRow`, `SettingsSliderRow`, `SettingsActionRow`, dll.

---

## MediaKit Engine (Engine Alternatif)

`MediaKitPlaybackService` = mirror service (tidak produce audio sendiri); audio dari Dart `media_kit Player`.
URI normalization: `Media.normalizeURI('file:///path')` → `'/path'` (strip `file://`).
**Semua lookup key harus `song.path` (bukan `'file://${song.path}'`)**.
Untuk dikirim ke mpv tetap pakai `Media('file://${s.path}')` — ini benar.

### Dispose Order MediaKitEngine (wajib urut)
1. `_disposed = true` (sync)
2. `setTransportCommandHandler(null)` (sync)
3. `_cancelSleepTimerInternal()` (sync)
4. `final p = _player; _player = null;` (sync, null sebelum await apapun)
5. `await p?.pause()`
6. `await stopListening()`
7. `unregisterPlayer()`
8. `await stopService()`
9. cancel subscriptions
10. `await p?.dispose()`

> `stopListening()` **HARUS sebelum** `stopService()` agar event "stop" dari native tidak deliver ke Dart setelah dispose.

### MediaKit Shuffle Index Mismatch
Setelah `Player.setShuffle(true)`, `state.index` (mpv native) ≠ `_queue` index (Dart original order).
Selalu resolve via URI, jangan asumsi index dari satu space valid di space lain.

---

## Media3 Package Notes (1.10.1)

Audio processor classes pindah dari `exoplayer.audio` → `common.audio`:
- `AudioProcessor`, `BaseAudioProcessor`, `SonicAudioProcessor`, `ChannelMixingAudioProcessor` → `androidx.media3.common.audio.*`
- `DefaultAudioSink.DefaultAudioProcessorChain` masih public nested class — gunakan sebagai: `.setAudioProcessorChain(DefaultAudioSink.DefaultAudioProcessorChain(myProcessor))`
- `ChannelMixingAudioProcessor` hanya handle PCM-16; pakai `StereoWideningAudioProcessor` (custom `BaseAudioProcessor`) untuk support float audio
- `PlaybackStats.totalBufferingTimeMs` dan `totalErrorCount` dihapus di 1.10.1
- `setTunnelingEnabled()` dihapus dari `TrackSelectionParameters.Builder`

---

## MediaStore & Web

`MediaStoreService.getSongs()` melempar `MissingPluginException` di web/browser — ini **normal**.
Setiap widget yang panggil `MediaStoreService` wajib: (1) wrap try/catch, (2) set loading=false di catch, (3) tampilkan empty state bersih.

---

## LogService

`LogService.init()` di `main()` **sebelum** `AudioEngine`.
Toggles: `loggingEnabled`, `errorsOnly` — persist SharedPrefs `log_enabled`, `log_errors_only`.
Max 500 entri FIFO. `kDebugMode` guard untuk `debugPrint`.

---

## Debug Mode

Ketuk area **Versi 3× dalam 2 detik** di Settings → debug section muncul.
State `_DebugState` in-memory (tidak persist antar session): notif icon picker, audio engine info, live effect status.
Keluar: tap "Keluar Mode Debug".

---

## Workflow Setelah Setiap Perubahan

```bash
flutter analyze --no-fatal-infos
```

Target: **No issues found!** — 0 warning, 0 error.
