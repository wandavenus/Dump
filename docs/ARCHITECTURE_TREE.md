# Dump — Technical Architecture Tree

> Diagram arsitektur aktual repo `wandavenus/Dump` pada `main` (`6314cd6`).
> Hanya memuat komponen yang benar-benar ada di repository.

---

## 1. Master Dependency Graph

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│  ①  FLUTTER UI LAYER                          lib/pages · lib/widgets · lib/themes │
│  ────────────────────────────────────────────────────────────────────────────────  │
│                                                                                   │
│  bottom_nav_bar/  ─┬─  FirstPage (5-tab shell)                                    │
│                    ├─  _TabNavObserver ×5   (rebuild PopScope.canPop)            │
│                    └─  GlassNavBar / FloatingPillNavBar / UnifiedMorphPlayer     │
│                                                                                   │
│  pages/  home · browse · radio · library · search · album · artist · artist_list │
│          music_list · settings_page (11 part-files) · log_page · equalizer_page  │
│          sleep_timer_page                                                        │
│  widgets/  player/* (20 sub-widgets) · pages/* (section per halaman) · common/*  │
│  themes/  AppColors · AppThemes · ThemeController · glass_navbar                  │
└───────────────────────────────────┬───────────────────────────────────────────────┘
                                    │  ValueNotifier<T> · Stream (one-way, read-only)
                                    │  context.l10n
                                    ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│  ②  DART SERVICE / MANAGER LAYER                     lib/services (22 service)   │
│  ────────────────────────────────────────────────────────────────────────────────  │
│                                                                                   │
│  PLAYBACK FACADE CHAIN                                                           │
│   AudioService ──▶ PlaybackManager ──▶ Media3PlaybackBridge                       │
│   (business logic)   (static facade,     (★ SATU-SATUNYA MethodChannel/           │
│                       artwork prefetch)     EventChannel edge ke native)           │
│                                                                                   │
│  SETTINGS / STATE (ValueNotifier + SharedPreferences)                             │
│   AudioEffectsService   EQ · ReplayGain · Loudness · Crossfeed · Bass · BitPerfect│
│   MediaCapabilitiesService  stereo widening · reverb · skip-silence (prefix mcap_) │
│   DeviceDsp  ·  AudioFocusService  ·  SleepTimerService  ·  AudioSessionHandler   │
│   UpNextSettings  ·  LyricsSettings (models/)                                     │
│                                                                                   │
│  CONTENT / LIBRARY                                                               │
│   MediaStoreService  (scan pustaka, warm-up cache sinkron, rescanNotifier)        │
│   HistoryService     PlaylistService  ArtworkRepository  (2-lapis LRU+disk)        │
│   NativePaletteService  SongMetadataService  OpenFileService (ACTION_VIEW)        │
│   ReplayGainService  (tag RG/R128/iTunNORM, 3-level cache + in-flight dedup)     │
│   LoudnessSourceResolver                                                   │
│                                                                                   │
│  LYRICS  (8 provider paralel)                                                     │
│   LyricsService ─▶ LyricsFetchManager ─▶ LyricsCacheManager (memory+disk+TTL)     │
│        ├─ embedded ─ local_file ─ lrclib ─ netease ─ qq_music                     │
│        └─ kugou ─ kuwo ─ apple_music   (RateLimiter · CancellationToken)         │
│                                                                                   │
│  UTIL   LogService (+NativeLogBridge) · WatermarkService · LanguageManager        │
│         PlayerSheetController · ScrollToTopService                                │
│                                                                                   │
│  NATIVE BRIDGES (services/native/)                                               │
│   NativeDspBridge ──▶ dart:ffi ──▶ native_audio_runtime                          │
│   FfmpegDecoderBridge · NativeModuleRegistry · NativeModule contract              │
└───────────────┬───────────────────────────────┬──────────────────────────────────┘
                │                               │
                │ ③ AUDIO ENGINE ABSTRACTION    │  platform channels
                │ (library: native_audio_runtime)│ musicplayer/media_store
                ▼                               │ musicplayer/open_file
┌──────────────────────────────────────────────┐│ musicplayer/native_logs
│  ③  native_audio_runtime  (Dart FFI wrapper)  ││ musicplayer/audio_effects
│  ──────────────────────────────────────────── ││ musicplayer/ffmpeg_decoder[_events]
│  lib/native_audio_runtime.dart                ││ musicplayer/media3_*
│    └─ conditional export: io ⇄ unsupported     ││   (15 EventChannel + 1 MethodChannel)
│  lib/src/runtime_types.dart                   ││
│  lib/src/runtime_impl_io.dart                  │└──────────┬──────────────────────┘
│  lib/src/dsp_pipeline_io.dart   ◀── pipeline   │           │
│    register slot 0..7 (initialize())          │           │
│  lib/src/dsp_pipeline_unsupported.dart  (web) │           │
└───────────────┬──────────────────────────────┘           │
                │  dart:ffi  (zero-copy)                    │
                ▼                                          ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│  ④  NATIVE ANDROID / MEDIA3 LAYER                android/app/src/main/kotlin    │
│  package dev.wndavenz.music          (47 file)                                    │
│  ────────────────────────────────────────────────────────────────────────────────  │
│                                                                                   │
│  MainActivity.kt ──── method/event channel handler, ActivityResult (hapus tag)     │
│  NowPlayingOverlayActivity.kt  (translucent, "Open with" dari app lain)           │
│  Media3PlaybackService.kt   ★ engine: queue · 2×ExoPlayer · crossfade · session  │
│                                                                                   │
│  queue/  QueueManager · QueueSync                                                │
│  transport/  PlayPauseFadeController · TransportCommands · TransportState         │
│  effects/  ┌ AudioEffectsManager                                                │
│            ├ NativeDspAudioProcessor   ──Jni──▶ libnative_audio_runtime.so      │
│            ├ ReverbAudioProcessor · ReverbManager  (Schroeder)                    │
│            ├ StereoWideningAudioProcessor · StereoWidthManager                   │
│            └ SignalsmithStretchAudioProcessor · StretchManager                   │
│               └ StretchAwareAudioProcessorChain                                    │
│               ──Jni──▶ libstretch_native.so                                      │
│  crossfade/  CrossfadeController · PreloadManager · CrossfadeTimelineLogger       │
│  audio_focus/  AudioFocusManager          audio_offload/  AudioOffloadManager      │
│  replaygain/  ReplayGainService ──Jni──▶ libreplaygain_native.so                 │
│               ReplayGainBridge · ReplayGainNative · ReplayGainModels             │
│               PcmDecoder · MediaStoreWriteGate                                   │
│  sleep_timer/  SleepTimerManager      notification/  PlaybackNotificationManager │
│  metadata/  ExoMetadataReader · MetadataCacheDb · MetadataPrescanner · TagBuilder │
│  artwork  ArtworkCacheManager · BitmapUtils · FallbackBitmapLoader               │
│           ColorScience · NativePaletteBridge · NativePaletteModels                │
│           SessionArtworkProvider                                                  │
│  utils/  MediaItemFactory · TrackMapper     events/  EventEmitter                 │
│  ffmpeg/  FfmpegCapabilityProbe  root/  ActivePlayerProxy · ServiceShutdownCoord  │
└───────────────┬───────────────────────────────┬──────────────────────────────────┘
                │ ⑤ JNI                        │
                ▼                               │
┌──────────────────────────────────────────────┐│
│  ⑥  NATIVE C/C++ MODULES                     ││
│  ──────────────────────────────────────────── ││
│                                              ││
│  ▸ libnative_audio_runtime.so                ││
│    native_audio_runtime/src/                 ││
│      native_audio_runtime.c   lifecycle · kCapabilities · module registry        │
│      dsp_pipeline.c           rantai 8 processor (vtable)                       │
│      dsp_processor.h          ★ kontrak 1 processor                               │
│      audio_buffer.c/.h        NarAudioBuffer (PCM float32 interleaved)          │
│      gain_processor.c    slot 0  · dsp.gain                                     │
│      replaygain_processor.c slot 1 · dsp.replaygain                              │
│      loudness_processor.c  slot 2  · EBU R128 / BS.1770-4                        │
│      acoustic_engine_processor.c slot 3 · dsp.acoustic_engine                     │
│      comp_processor.c      slot 4  · dsp.compressor                              │
│      crossfeed_processor.c slot 5  · dsp.crossfeed                               │
│      limiter_processor.c   slot 6  · dsp.limiter                                 │
│      soft_clipper_processor.c slot 7 · dsp.soft_clipper                          │
│      biquad_filter.c/.h   stereo_matrix.h  dynamics_common.h   (helper)         │
│      neon_kernels.S  (ARM64 SIMD)   aaudio_probe.c (dlopen libaaudio.so)        │
│      native_dsp_jni.c   ◀── JNI: nativeProcessFloat / nativeIsInitialized       │
│    hook/build.dart  (FFI build hook: sumber + -llog -ldl + neon, Android-only)   │
│    tool/ffigen.dart  (binding generator)                                        │
│    test/native_audio_runtime_test.dart (60 test via FFI)                         │
│                                              ││
│  ▸ libreplaygain_native.so   (C++17, CMake FetchContent)                          │
│    android/app/src/main/cpp/replaygain/                                         │
│      replaygain_jni.cpp   ◀── JNI ◀── ReplayGainNative.kt                       │
│      ebur128_analyzer.cpp  → libebur128 v1.2.6 (MIT, FetchContent)                │
│      tag_writer.cpp        → TagLib v2.3 (LGPL/MPL, FetchContent)                │
│      metadata_region.cpp   backup/restore region tag (tanpa re-encode)            │
│                                              ││
│  ▸ libstretch_native.so    (Signalsmith Stretch 1.1.0 + Linear 0.3.1)             │
│    android/app/src/main/cpp/stretch/                                            │
│      stretch_jni.cpp       ◀── JNI ◀── SignalsmithStretchAudioProcessor.kt       │
│      CMakeLists.txt  builds 2 .so di atas                                        │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Layer Breakdown

### ① Flutter UI — `lib/pages` · `lib/widgets` · `lib/bottom_nav_bar` · `lib/themes`

```
lib/
├── main.dart ──────────────────── bootstrap + part-file aggregator
│   └── main/  main.dart · app.dart · app_state.dart · edge.dart · scroll_behavior.dart
├── bottom_nav_bar/
│   ├── bottom_nav.dart          FirstPage (part aggregator)
│   └── bottom_nav/  page.dart · state.dart  (_FirstPageState, 5× Navigator, 5× observer)
├── domain/
│   └── app_router.dart          pushSettings/Album/Artist/ArtistList/MusicList
├── pages/
│   ├── home_page · browse_page · radio · library_page · search_page
│   ├── album_page · artist_page · artist_list · music_list
│   ├── settings_page.dart ────── 11 part: body · appearance · audio · bit_perfect
│   │   │                          equalizer · system · debug · about · changelog_data
│   │   ├── audio/  replaygain_section · loudness_section · crossfeed_section
│   │   │          crossfade_picker · batch_scan_section
│   │   └── settings/  settings_widgets/ · equalizer_page/ (band slider, preset, painter)
│   ├── log_page/  app_bar_badge · bar_btn · entry_tile · filter_bar · log_level_selector
│   └── settings/  equalizer_page · sleep_timer_page/
├── widgets/
│   ├── unified_morph_player.dart  + bottom_reveal_clipper · playback_content
│   ├── player/  player_background/(animated·artwork·fallback·fog_painter)
│   │            player_content/(content·lyrics_*·queue_*)
│   │            player_transport_controls · player_progress_section
│   │            player_song_header · player_song_info_sheet/
│   │            synced_lyrics_view/ (state_*, karaoke_*, elrc_word, view)
│   │            player_hero_tags · player_more_menu · player_up_next_card · …
│   ├── pages/  home_sections/ · browse_sections/ · library_sections/detail/
│   │           detail_sections/ · search_sections/ · radio_sections/ · artist_list_sections/
│   ├── common/  scrolling_page_chrome/ · swipe_to_dismiss_sheet
│   └── song_context_menu/ · song_artwork · common_actions · play_shuffle_buttons · …
├── themes/  app_themes · theme_builder · theme_controller · glass_navbar · app_theme_extension
├── theme/   app_colors.dart          ← AppColors.of(context), token semantik
├── l10n/    app_localizations{,_en,_id}.dart (380 key) + app_{en,id}.arb
├── models/  LocalSong · LoudnessData · LyricLine · LyricsSettings · Playlist
│            ReplayGainMode · SongInfo
├── utils/   constants · duration_text · lyrics_text_direction · safe_num
│            zoom_fade_route · sample_music_data → data/{browse_banners, radio_stations,
│                                                     search_categories}
├── extensions/  localization_extension.dart   ← context.l10n
└── webView/ web_view_container.dart          ← wrapper Scaffold+gradient (bukan webview)
```

**Dependency (↓ satu arah, read-only):** UI hanya membaca `ValueNotifier`/stream dari service. Tidak ada service yang menyentuh widget.

---

### ② Dart Services — `lib/services`

```
services/
├── audio/                                       ★ playback facade chain
│   ├── playback_manager.dart (905)  ← static facade, artwork prefetch (max 2 konkuren)
│   │   └── media3/media3_playback_bridge.dart  ★★ SATU channel edge
│   │       MethodChannel  musicplayer/media3_playback
│   │       EventChannel   musicplayer/media3_{playbackState,position,duration,
│   │                     currentTrack,queue,bufferingState,audioSessionId,shuffleMode,
│   │                     repeatMode,sleepTimer,offloadState,audioFormat,
│   │                     stereoWidening,reverb,serviceReady}
│   │   └── equalizer_models.dart
│   ├── device_dsp.dart            inspeksi kapabilitas hardware
│   ├── audio_effects_service.dart + /service.dart  (1038) · /replay_gain_applicator.dart
│   ├── audio_session_handler/ · equalizer_parameters.dart
├── audio_service.dart + /service.dart (1014) + /replay_gain_applicator.dart
├── media_capabilities_service.dart + /service.dart   ← prefix key "mcap_"
├── audio_focus_service.dart · audio_playback_state.dart
├── media_store_service.dart (533)   MethodChannel musicplayer/media_store
├── history_service.dart · playlist_service.dart · artwork_repository.dart (322)
├── native_palette_service.dart (324)  MethodChannel (NativePaletteBridge.CHANNEL)
├── replay_gain_service.dart + /service.dart (1091) + /models.dart
├── loudness_source_resolver.dart · song_metadata_service/ · open_file_service.dart
│       (MethodChannel musicplayer/open_file)
├── sleep_timer_service.dart (156)   ← logika timer di native, ini adapter UI
├── log_service.dart + /{service,entry,level,native_log_bridge}.dart
│       EventChannel musicplayer/native_logs
├── lyrics_service/  service · provider · lrc_parser · cache_manager · fetch_manager
│                   cancellation · quality · rate_limiter · result · source
│   └── providers/  embedded · local_file · lrclib · netease · qq_music
│                   kugou · kuwo · apple_music · provider_http
├── native/  bridges/{native_dsp_bridge, ffmpeg_decoder_bridge}.dart
│            contracts/native_module.dart · models/native_module_status.dart
│            native_module_registry.dart      ← lifecycle dimiliki PlaybackManager
└── (util) player_sheet_controller · scroll_to_top_service · up_next_settings
         watermark_service · language_manager
```

> **Aturan yang ditegakkan:** tidak ada layer di atas `PlaybackManager` yang boleh
> menyentuh `Media3PlaybackBridge` secara langsung.

---

### ③ Audio Engine Abstraction — `native_audio_runtime/lib`

```
native_audio_runtime/
├── lib/native_audio_runtime.dart
│     export runtime_types.dart
│     export runtime_impl_unsupported.dart   if (dart.library.ffi) runtime_impl_io.dart
│     export dsp_pipeline_unsupported.dart   if (dart.library.ffi) dsp_pipeline_io.dart
│          ↑ conditional export: satu import valid di web & native
├── lib/src/
│   ├── runtime_types.dart           NarAudioRuntime (singleton facade)
│   ├── runtime_impl_io.dart         versi FFI        | runtime_impl_unsupported.dart  stub
│   ├── dsp_pipeline_io.dart         NativeDspPipeline + NativeAudioBuffer (zero-copy)
│   └── dsp_pipeline_unsupported.dart stub no-op, bypass => true
├── lib/native_audio_runtime_bindings_generated.dart  (dari tool/ffigen.dart)
├── hook/build.dart   FFI build hook → daftarkan 13 sumber .c/.S + -llog -ldl (Android)
├── tool/ffigen.dart  generator binding
└── test/  native_audio_runtime_test.dart (60 test) · native_benchmark.dart
```

**Pipeline registration order** (`dsp_pipeline_io.dart` → `initialize()`):

```
slot 0  gain_processor        → slot 1  replaygain_processor
slot 2  loudness_processor    → slot 3  acoustic_engine_processor   ★ (PR #152)
slot 4  comp_processor        → slot 5  crossfeed_processor
slot 6  limiter_processor     → slot 7  soft_clipper_processor
```

---

### ④ Native Android / Media3 — `android/app/src/main/kotlin/dev/wndavenz/music`

```
MainActivity.kt · NowPlayingOverlayActivity.kt · Media3PlaybackService.kt
ActivePlayerProxy.kt · ArtworkCacheManager.kt · BitmapUtils.kt · ColorScience.kt
FallbackBitmapLoader.kt · NativePaletteBridge.kt · NativePaletteModels.kt
ServiceShutdownCoordinator.kt · SessionArtworkProvider.kt

queue/        QueueManager · QueueSync
transport/    PlayPauseFadeController · TransportCommands · TransportState
effects/      AudioEffectsManager
              NativeDspAudioProcessor        ──JNI──▶ libnative_audio_runtime.so
              ReverbAudioProcessor · ReverbManager
              StereoWideningAudioProcessor · StereoWidthManager
              SignalsmithStretchAudioProcessor · StretchManager
              StretchAwareAudioProcessorChain ──JNI──▶ libstretch_native.so
crossfade/    CrossfadeController · PreloadManager
diagnostics/  CrossfadeTimelineLogger
audio_focus/  AudioFocusManager
audio_offload/ AudioOffloadManager
replaygain/   ReplayGainService · ReplayGainBridge · ReplayGainModels
              ReplayGainNative                 ──JNI──▶ libreplaygain_native.so
              PcmDecoder · MediaStoreWriteGate
sleep_timer/  SleepTimerManager
notification/ PlaybackNotificationManager
metadata/     ExoMetadataReader · MetadataCacheDb · MetadataPrescanner · TagBuilder
events/       EventEmitter
ffmpeg/       FfmpegCapabilityProbe
utils/        MediaItemFactory · TrackMapper

src/test/kotlin/…  9 unit test (ActivePlayerProxy · NativePaletteBridge ·
                    ServiceShutdownCoordinator · AudioFocusManager · CrossfadeController ·
                    ReverbManager · EventEmitter · TagBuilder · QueueManager)
```

**Media3 1.11.1** dipakai lewat 6 artifact: `exoplayer · session · ui · extractor · inspector · container`.
`org.jellyfin.media3:media3-ffmpeg-decoder:1.9.0+1` (GPL v3) di-exclude transitive-nya.

---

### ⑤⑥ JNI + C/C++ DSP

```
JNIEXPORT  java_dev_wndavenz_music_effects_NativeDspAudioProcessor_
             ├── nativeProcessFloat   (native_dsp_jni.c)  → DSP pipeline C
             └── nativeIsInitialized                    → native_audio_runtime.c
```
`native_dsp_jni.c` **hanya** dikompilasi untuk `targetOS == OS.android` (butuh `<jni.h>` NDK).

**3 shared library, 2 build system:**

| `.so` | Build system | Sumber | Upstream |
|---|---|---|---|
| `libnative_audio_runtime.so` | `hook/build.dart` (FFI/native-assets) | `native_audio_runtime/src/*.c` + `neon_kernels.S` | — |
| `libreplaygain_native.so` | `android/app/src/main/cpp/CMakeLists.txt` (FetchContent) | `cpp/replaygain/*.cpp` | libebur128 v1.2.6, TagLib v2.3 |
| `libstretch_native.so` | idem | `cpp/stretch/stretch_jni.cpp` | Signalsmith Stretch 1.1.0 + Linear 0.3.1 |

---

## 3. Data & Control Flow

### 3.1 Kontrol (Dart → Native, top-down)

```
UI (slider / toggle)
   │  AudioEffectsService / MediaCapabilitiesService  → set ValueNotifier + persist SharedPrefs
   ▼
AudioService
   ▼
PlaybackManager
   ▼
Media3PlaybackBridge  ──MethodChannel "musicplayer/media3_playback"──▶ MainActivity
                                                                        ▼
                                                          Media3PlaybackService.kt
                                                                        ▼
                                             ExoPlayer pipeline (2× player saat crossfade)
                                                                        ▼
                                              NativeDspAudioProcessor ──JNI──▶ DSP chain C
                                                                        ▼
                                                                   PCM → speaker
```
> Semua knob DSP adalah atomic; audio thread tidak pernah diblokir.

### 3.2 State (Native → Dart, bottom-up)

```
ExoPlayer / queue
   ▼  EventEmitter (Kotlin)
15× EventChannel "musicplayer/media3_*"
   ▼
Media3PlaybackBridge  ──▶ PlaybackManager (pass-through; currentTrack+queue di-intercept
                          untuk mirror queue lokal → artwork prefetch)
   ▼
AudioService  ──▶ AudioPlaybackState (ValueNotifier)  ──▶ UI rebuild
```

### 3.3 DSP pipeline (C, in-place, per buffer)

```
PCM float32 interleaved (NarAudioBuffer)
   ▼ slot 0  gain_processor          (linear, zero-latency)
   ▼ slot 1  replaygain_processor    (metadata RG/R128/iTunNORM + clip protection)
   ▼ slot 2  loudness_processor      (K-weighting BS.1770-4, LFE weight 0, gate, NaN fail-open)
   ▼ slot 3  acoustic_engine_processor (intensi 1 atomic; audio thread rebuild sendiri)
   ▼ slot 4  comp_processor          (soft-knee, stereo-linked, attack/release)
   ▼ slot 5  crossfeed_processor     (LF bleed ke channel opposite)
   ▼ slot 6  limiter_processor       (brickwall look-ahead, release IIR)
   ▼ slot 7  soft_clipper_processor  (tanh, C¹ kontinu di threshold)
   ▼
PCM out
```

### 3.4 Empat jalur masuk ke `libnative_audio_runtime.so`

```
(1) Dart FFI  ────────────► dsp_pipeline.c / *_processor.c     (pipeline penuh, 8 slot)
                                        ▲
(2) JNI ◄── NativeDspAudioProcessor.kt ─┘  (dipakai ExoPlayer saat playback nyata)
```
`libreplaygain_native.so` & `libstretch_native.so` **tidak** disentuh pipeline di atas — berdiri sendiri,
dipanggil langsung dari Kotlin masing-masing.

---

## 4. Channel Map (batas Dart ↔ Native)

| Channel | Tipe | Arah | Owner |
|---|---|---|---|
| `musicplayer/media3_playback` | Method | → Native | `Media3PlaybackBridge` |
| `musicplayer/media3_<15 nama>` | Event | → Dart | `Media3PlaybackBridge` |
| `musicplayer/media_store` | Method | → Native | `MediaStoreService`, `ReplayGainService` |
| `musicplayer/open_file` | Method | ↔ | `OpenFileService` (ACTION_VIEW) |
| `musicplayer/native_logs` | Event | → Dart | `NativeLogBridge` → `LogService` |
| `musicplayer/audio_effects` | Method | → Native | `AudioEffectsService` |
| `musicplayer/ffmpeg_decoder` | Method | → Native | `FfmpegDecoderBridge` |
| `musicplayer/ffmpeg_decoder_events` | Event | → Dart | `FfmpegDecoderBridge` |
| `NativePaletteBridge.CHANNEL` | Method | → Native | `NativePaletteService` |

---

## 5. Repository Tree (ringkas, Annotated)

```
.
├── android/app/
│   ├── build.gradle                    media3_version 1.11.1 · ndkVersion 28.2.13676358
│   │                                   · externalNativeBuild → src/main/cpp/CMakeLists.txt
│   ├── src/main/kotlin/dev/wndavenz/music/      ← ④ (47 file)
│   ├── src/main/cpp/                            ← ⑥ C++ (2 .so)
│   │   ├── CMakeLists.txt                        FetchContent: ebur128, TagLib, Signalsmith
│   │   ├── replaygain/  replaygain_jni · ebur128_analyzer · tag_writer · metadata_region
│   │   └── stretch/    stretch_jni
│   ├── src/main/AndroidManifest.xml              READ_MEDIA_AUDIO · FOREGROUND_SERVICE_MEDIA_PLAYBACK
│   ├── src/test/kotlin/                          9 unit test
│   └── local.properties                          ← gitignored, diisi sdk.dir
├── lib/                                           ← ① ② (282 file)
├── native_audio_runtime/                         ← ③ FFI plugin
│   ├── src/  14×.c  20×.h  1×.S                    ← ⑥ C11 DSP
│   ├── lib/ · hook/ · tool/ · test/
├── test/                                          63 Dart test
├── docs/ARCHITECTURE.md                           dokumentasi naratif
├── web/ · server.js · package.json                build/serve web (Node)
├── build-apk.sh · setup-flutter.sh                pasang JDK · SDK 36 · NDK r28c · CMake 3.22.1
└── .github/workflows/  android · kotlin-tests · native-tests · flutter-check · codeql · pages
```

---

## 6. Verifikasi

Struktur di atas dibaca langsung dari repo pada `main` (`6314cd6`), bukan dari asumsi.

- `lib/` — 282 file `.dart`
- `android/.../dev/wndavenz/music/` — 47 file `.kt` + 9 test
- `native_audio_runtime/src/` — 14 `.c` + 20 `.h` + 1 `.S`
- `android/app/src/main/cpp/` — 5 `.cpp` + 3 `.h`
- **3 shared library** total, **2 build system** (FFI build hook + CMake)
- **9 platform channel** (batas Dart ↔ Native)
- **8 slot** DSP pipeline

**Belum terverifikasi lokal:** kompilasi Kotlin/C++ tetap butuh Android SDK + NDK, yang tidak muat
di filesystem sandbox (4 GB). 3 CI workflow (`kotlin-tests`, `android`, `native-tests`) yang memegang
pembuktian itu.
