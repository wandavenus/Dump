# Dump — Dokumentasi Lengkap Aplikasi

> **Music player lokal untuk Android, ditulis dengan Flutter, dengan seluruh pemrosesan audio berat dijalankan di lapisan native (Kotlin + C/DSP FFI).**
>
> Versi aplikasi: **1.5.30** · Package: `musicplayer` · Bundle ID: `dev.wndavenz.music`
> Repo: `github.com/wandavenus/Dump` · Lisensi: lihat `LICENSE`

Dokumen ini adalah peta lengkap codebase: apa yang dibangun, bagaimana setiap bagian bekerja, dan mengapa arsitekturnya seperti itu.

---

## Daftar Isi

1. [Gambaran Umum](#1-gambaran-umum)
2. [Filosofi & Prinsip Desain](#2-filosofi--prinsip-desain)
3. [Stack Teknologi](#3-stack-teknologi)
4. [Arsitektur Lapisan](#4-arsitektur-lapisan)
5. [Siklus Hidup Aplikasi](#5-siklus-hidup-aplikasi)
6. [Navigasi & Rute](#6-navigasi--rute)
7. [Fitur: Beranda](#7-fitur-beranda)
8. [Fitur: Browse](#8-fitur-browse)
9. [Fitur: Radio](#9-fitur-radio)
10. [Fitur: Library](#10-fitur-library)
11. [Fitur: Search](#11-fitur-search)
12. [Fitur: Halaman Detail](#12-fitur-halaman-detail)
13. [Fitur: Player](#13-fitur-player)
14. [Fitur: Lirik](#14-fitur-lirik)
15. [Fitur: Playlist](#15-fitur-playlist)
16. [Fitur: Pengaturan](#16-fitur-pengaturan)
17. [Lapisan Audio](#17-lapisan-audio)
18. [Native Audio Runtime (C/DSP)](#18-native-audio-runtime-cdsp)
19. [Lapisan Native Android (Kotlin)](#19-lapisan-native-android-kotlin)
20. [Layanan](#20-layanan)
21. [Model Data](#21-model-data)
22. [Tema & Tampilan](#22-tema--tampilan)
23. [Sistem Logging](#23-sistem-logging)
24. [Internasionalisasi](#24-internasionalisasi)
25. [Build, Tooling & CI](#25-build-tooling--ci)
26. [Pengujian](#26-pengujian)
27. [Catatan Teknis & Batasan](#27-catatan-teknis--batasan)

---

## 1. Gambaran Umum

**Dump** adalah pemutar musik **lokal** (offline-first) untuk Android. Aplikasi memindai pustaka audio perangkat melalui Android `MediaStore`, lalu memutar, mengatur, dan menata koleksinya sendiri — tanpa akun, tanpa server, tanpa dependensi streaming.

Yang membuat Dump berbeda dari pemutar musik rata-rata adalah **mesin audio-nya sendiri**. Alih-alih menggunakan `AudioTrack`/pipeline Android standar, Dump membangun:

- **Runtime DSP C11** sendiri (`native_audio_runtime/`) yang diakses lewat `dart:ffi` — 8 tahap pemrosesan audio written from scratch, termasuk limiter brickwall, kompresor, loudness EBU R128, dan **Acoustic Engine**.
- **Service Media3/ExoPlayer** (`Media3PlaybackService.kt`) yang memproses audio **di dalam** pipeline ExoPlayer — sehingga equalizer sistem, crossfade, dan efekSoftware benar-benar bekerja pada kedua player saat transisi tumpang-tindih.
- **Bridges** (`MethodChannel` / `EventChannel`) yang menjadi satu-satunya batas antara Dart dan native.

### Filosofi inti

| Prinsip | Implementasi |
|---|---|
| **Native adalah sumber kebenaran** | Queue, urutan shuffle, repeat mode, sleep timer, dan semua efek audio dimiliki Media3. Dart hanya mencerminkan (`mirror`) state — tidak pernah menghitung ulang sendiri. |
| **Audio thread tidak boleh diblokir** | Semua knob DSP adalah atomic. Tidak ada `malloc`, logging, atau transisi konteks di jalur render. |
| **Fail-open, bukan fail-closed** | DSP yang gagal → audio tetap diputar (bypass), bukan ditutup. |
| **C cold start = zero spinner** | Setiap service punya `warmUp()` yang membaca cache sinkron sebelum `runApp`, sehingga frame pertama sudah berisi konten. |
| **Satu responsibility per layer** | `Media3PlaybackBridge` adalah satu-satunya file yang boleh menyentuh channel. Semua lapisan di atasnya bilang: *"No layer in this file may reference Media3PlaybackBridge directly."* |

---

## 2. Filosofi & Prinsip Desain

### 2.1 Arsitektur berlapis (satu arah)

```
┌──────────────────────────────────────────────────────────────┐
│  PRESENTATION       widgets/ · pages/ · bottom_nav_bar/    │
│                     theme/ · themes/ · l10n/                 │
└───────────────────────────┬──────────────────────────────────┘
                            │ ValueNotifier · Stream (read-only)
┌───────────────────────────▼──────────────────────────────────┐
│  DOMAIN / SERVICE     services/ (22 service)                │
│                     Business logic, persistensi, state facade│
└───────────────────────────┬──────────────────────────────────┘
                            │ MethodChannel · EventChannel · dart:ffi
┌───────────────────────────▼──────────────────────────────────┐
│  BRIDGE               Media3PlaybackBridge                  │
│                       NativeDspBridge · FfmpegDecoderBridge  │
│                       NativeLogBridge · NativePaletteBridge  │
│                       MediaStoreService · OpenFileService    │
└───────────────────────────┬──────────────────────────────────┘
                            │
┌───────────────────────────▼──────────────────────────────────┐
│  NATIVE               Media3PlaybackService.kt (Media3)     │
│                       MainActivity.kt · QueueManager · ...  │
│                       ┌───────────────────────────────────┐   │
│                       │ native_audio_runtime (C11)        │   │
│                       │ DSP pipeline via JNI → FFI        │   │
│                       └───────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

### 2.2 Aturan yang ditegakkan di codebase

- **Single edge:** hanya `Media3PlaybackBridge` yang menyentuh `musicplayer/*` MethodChannel. Semua service lain import bridge itu secara transitif lewat `PlaybackManager`.
- **Part-file untuk file besar:** `settings_page.dart` (11 sub-file), `audio_service.dart` (3 part), `log_service.dart`, `lyrics_service/*` — semua pakai `part`/`part of`.
- **DDD ringan:** `lib/domain/app_router.dart`.edge, `lib/models/`, `lib/services/`.
- **Web-compatible:** banyak `if (kIsWeb)` guard; `web/` + `server.js` menyediakan build web (Node static server) meski target utama Android.

---

## 3. Stack Teknologi

### Frontend
| Teknologi | Versi | Peran |
|---|---|---|
| **Flutter** | SDK `>=3.12.2 <4.0.0` (teruji di **3.47.5**, Dart 3.13.4) | Framework UI |
| **Dart** | — | Bahasa |
| `flutter_localizations` + `intl` ^0.20.2 | — | i18n (EN + ID) |
| `shared_preferences` ^2.5.3 | — | Persistensi key-value |
| `path_provider` ^2.1.5 | — | Path cache/file |
| `permission_handler` ^12.0.3 | — | Runtime permission |
| `http` ^1.6.0 | — | Fetch lirik online |
| `url_launcher` ^6.3.2 | — | Buka link eksternal (QRIS, GitHub, dsb) |
| `gal` ^2.3.3 | — | Simpan screenshot artwork ke galeri |
| `font_awesome_flutter` ^11.0.0 | — | Ikon |
| `text_scroll`, `scrollable_positioned_list` | — | Marquee judul, list besar |
| `cupertino_icons` | — | Ikon iOS-style |
| `native_audio_runtime` | path (lokal) | Plugin FFI DSP |

### Native Android (Kotlin, package `dev.wndavenz.music`)
- **Media3 / ExoPlayer 1.11.1** — engine playback.
- **FFmpeg decoder** — `org.jellyfin.media3:media3-ffmpeg-decoder` (AAR prebuilt, GPL v3) untuk format uncommon.
- **Kotlin JVM toolchain 21**, `compileSdk 36`, `ndkVersion 28.2.13676358`.
- **AndroidX** — `palette` (MMCQ color quantization), `media3-*`.

### Native Audio Runtime (C11)
- Standar **C11** + `dart:ffi` + **JNI** (`native_dsp_jni.c`).
- **NEON** SIMD (`neon_kernels.h`) untuk path hot di arm64.
- Header-only helper: `biquad_filter.h`, `stereo_matrix.h`, `dynamics_common.h`.

### Build & Tooling
- **Gradle** (Kotlin DSL), **CMake 3.22.1** (prebuilt, via `build-apk.sh`).
- **Node.js** — hanya untuk build/serve web (`server.js`, `watch-rebuild.js`, `rebuild-web.js`).
- **NDK r28c** — clang arm64 untuk kompilasi `.c`/`.h` DSP.
- **JDK 21** (Temurin).
- **GitHub Actions** — 6 workflow.
- **CodeQL** — security-extended + security-and-quality.

---

## 4. Arsitektur Lapisan

### 4.1 `lib/` — Dart (282 file `.dart`)

| Direktori | Isi |
|---|---|
| `main/` | Entry point, `MaterialApp`, lifecycle observer, `part`-files. |
| `bottom_nav_bar/` | Shell 5-tab + glass/pill navbar + morph player. |
| `domain/` | `app_router.dart` — helper navigasi terpusat. |
| `models/` | 7 model data (immutable). |
| `pages/` | Semua halaman: home, browse, radio, library, search, detail, settings, log, equalizer, sleep timer. |
| `services/` | 22 service + subfolder (audio, native, lyrics, replaygain, log). |
| `theme/` + `themes/` | Token warna, `ThemeExtension`, builder, controller, glass navbar. |
| `widgets/` | Komponen reusable: player, sections per halaman, common chrome, context menu. |
| `l10n/` | Generated `AppLocalizations` (EN + ID) + `.arb` sumber. |
| `utils/` | Konstanta, duration format, data statis, safe-num, text direction LTR/RTL. |
| `webView/` | `WebView` — wrapper `Scaffold` dengan gradient (bukan web view!). |
| `extensions/` | `context.l10n` sugar. |

### 4.2 `android/` — Kotlin (47 file utama + 9 test)
Semua di `dev.wndavenz.music`, dikelompokkan sub-package:

| Sub-package | File inti |
|---|---|
| root | `Media3PlaybackService.kt`, `MainActivity.kt`, `NowPlayingOverlayActivity.kt`, `ActivePlayerProxy.kt` |
| `queue/` | `QueueManager.kt`, `QueueSync.kt` |
| `transport/` | `PlayPauseFadeController.kt`, `TransportCommands.kt`, `TransportState.kt` |
| `effects/` | `AudioEffectsManager.kt`, `NativeDspAudioProcessor.kt`, `ReverbAudioProcessor.kt`, `StereoWideningAudioProcessor.kt`, `SignalsmithStretchAudioProcessor.kt`, `StretchAwareAudioProcessorChain.kt`, `ReverbManager.kt`, `StereoWidthManager.kt`, `StretchManager.kt` |
| `replaygain/` | `ReplayGainService.kt`, `ReplayGainBridge.kt`, `ReplayGainNative.kt`, `ReplayGainModels.kt`, `PcmDecoder.kt`, `MediaStoreWriteGate.kt` |
| `crossfade/` | `CrossfadeController.kt`, `PreloadManager.kt` |
| `audio_focus/` | `AudioFocusManager.kt` |
| `audio_offload/` | `AudioOffloadManager.kt` |
| `metadata/` | `ExoMetadataReader.kt`, `MetadataCacheDb.kt`, `MetadataPrescanner.kt`, `TagBuilder.kt` |
| `notification/` | `PlaybackNotificationManager.kt` |
| `sleep_timer/` | `SleepTimerManager.kt` |
| `diagnostics/` | `CrossfadeTimelineLogger.kt` |
| `events/` | `EventEmitter.kt` |
| `ffmpeg/` | `FfmpegCapabilityProbe.kt` |
| `utils/` | `MediaItemFactory.kt`, `TrackMapper.kt` |
| artwork/color | `ArtworkCacheManager.kt`, `BitmapUtils.kt`, `FallbackBitmapLoader.kt`, `ColorScience.kt`, `NativePaletteBridge.kt`, `NativePaletteModels.kt`, `SessionArtworkProvider.kt` |

### 4.3 `native_audio_runtime/` — C11 FFI plugin
Struktur khas plugin FFI: `src/` (C), `lib/` (Dart), `hook/build.dart` (build hook yang menambahkan `.c` ke daftar kompilasi), `tool/ffigen.dart` (binding generator), `test/` (Dart test yang memanggil C lewat FFI).

---

## 5. Siklus Hidup Aplikasi

`lib/main/main.dart` — `main()` dibungkus `runZonedGuarded` dengan handler yang mencatat error zone ke `LogService`.

**Urutan startup (penting & beralasan):**

1. `WidgetsFlutterBinding.ensureInitialized()`.
2. **Edge-to-edge** system UI (kecuali web).
3. **`LogService.init()`** — harus pertama agar log permission failure tercatat (sebelum `loggingEnabled` false, `log()` early-return).
4. **Permission audio** (`storage`, `audio`) — Android fresh install bisa mengembalikan library kosong; menunggu di sini membuat query pertama otoritatif.
5. **Warm-up paralel** (`Future.wait`): `LanguageManager`, `ThemeController`, `LyricsSettings`, `WatermarkService`, `ArtworkRepository`, `NativePaletteService`, `MediaStoreService`, `HistoryService`.
6. **Prewarm artwork** dua tahap: 4 item prioritas (3s timeout) lalu sisanya (2s, background).
7. `NativeLogBridge.init()` — subscribe log native.
8. **Global error handler**: `FlutterError.onError` + `PlatformDispatcher.instance.onError` → `LogService`.
9. `OpenFileService.registerHandler()` (Android) — tangkap intent "open with" yang datang sebelum UI siap.
10. **Inisialisasi audio** (berurutan): `PlaybackManager` → `DeviceDsp` → `AudioEffectsService` → `LyricsService` → `MediaCapabilitiesService` → `AudioService` → `AudioFocusService` → `SleepTimerService` → `AudioService.syncFromNative()`.
11. `runApp(MyApp)`.
12. `OpenFileService.checkInitialUri()` — tangani cold-start URI.

**Lifecycle observer (`_MyAppState`):**
- `resumed` → re-apply edge-to-edge, `syncFromNative()`, `OpenFileService.onResume()`.
- `paused`/`detached` → `NativePaletteService.clearMemoryCache()` (free RAM), `LyricsSettings.flush()`.

---

## 6. Navigasi & Rute

### 6.1 Shell 5-tab (`bottom_nav_bar/`)
`FirstPage` = StatefulWidget dengan:
- **5 `GlobalKey<NavigatorState>`** — satu per tab (Home, Browse, Radio, Library, Search).
- **`IndexedStack`** — semua tab tetap hidup, state tidak hilang.
- **`_TabNavObserver`** per tab — rebuild saat route push/pop agar `PopScope.canPop` selalu akurat.
- **Tap tab yang sama** → `ScrollToTopService.trigger(index)` (scroll ke atas).
- **Route generator bersama** (`_tabRoute`) untuk detail: `/album`, `/artist`, `/artistlist`, `/musiclist`.

### 6.2 Navbar (3 gaya)
Dikontrol `ThemeController`:
- **Solid** — `BottomNavigationBar` biasa.
- **Glass** — `GlassNavBar` (blur).
- **Pill** — `FloatingPillNavBar` (kapsul 4 tab berlabel + tombol search bundar terpisah di kanan).

Navbar **mengikuti jari player**: saat player sheet digeser, navbar ikut translate (kurva deselerasi dua-segmen) lalu tersembunyi. Glass + pill = navbar ikut bergeser melebihi tinggi layar agar benar-benar hilang.

### 6.3 `AppRouter` (`domain/app_router.dart`)
Helper navigasi terpusat — **menghindari** `Navigator.pushNamed` di root `MaterialApp` karena di web menghasilkan selector CSS invalid (`#/routename`). Semua push ke detail/settings lewat `AppRouter.pushAlbum/pushArtist/pushArtistList/pushMusicList/pushSettings`, memakai `ZoomFadeRoute`.

### 6.4 WebView wrapper
`lib/webView/web_view_container.dart` — **bukan** web view. Ini wrapper `Scaffold` + gradient (`WebView(child: ...)`) yang membungkus halaman detail untuk konsistensi transisi.

---

## 7. Fitur: Beranda

`pages/home_page.dart` → `widgets/pages/home_sections/`.

Section yang tersedia:
- **Recently played** — `recently_played_section.dart` (dari `HistoryService`).
- **Albums** — carousel kartu album (`albums_section/`, dengan `card`/`section`/`state`).
- **Artists** — carousel kartu artist (`artists_section/`).
- Scroll-to-top via `ScrollToTopService.signal(0)`.
- `ScrollingPageChrome` — app bar yang menyusut jadi glass saat scroll (`animated_state`).

Data album/artist cover dihitung dari `MediaStoreService.cachedSongs` dengan dedup `albumId` / `artist`.

---

## 8. Fitur: Browse

`pages/browse_page.dart` → `widgets/pages/browse_sections/`:
- **Banners** (`banners.dart`) — banner carousel.
- **Content** (`content.dart`) — daftar konten.
- **New music grid** (`new_music_grid.dart`) — grid lagu baru.
- Section state di `state.dart`.
- Data banner dari `utils/data/browse_banners.dart`.

---

## 9. Fitur: Radio

`pages/radio.dart` → `widgets/pages/radio_sections/`:
- `stations.dart` (daftar station), `station_card.dart` (kartu), `content.dart`.
- **Data station saat ini kosong** — `utils/data/radio_stations.dart` berisi `const List<Map<String, String>> radioStations = [];` (disiapkan untuk diisi manual). Radio online bukan backend aktif.

---

## 10. Fitur: Library

`pages/library_page.dart` → `widgets/pages/library_sections/`. Library = koleksi lokal + favorit + playlist.

Sub-view detail:
- `songs_list_view.dart` — daftar lagu.
- `albums_list_view.dart` — daftar album.
- `artists_grid_view.dart` — grid artist.
- `frequent_songs_view.dart` — lagu sering diputar.
- `playlist_banner_card.dart` — kartu banner playlist.
- `sticky_controls_delegate.dart` — kontrol lengket (sort/filter) saat scroll.
- `editable.dart` — mode edit (pilih/hapus/pindah).
- `row.dart` / `row_edit.dart` — baris item dalam mode biasa vs edit.

Edit dengan **swipe-to-dismiss** (`widgets/common/swipe_to_dismiss_sheet.dart`) + context menu (`song_context_menu/`).

---

## 11. Fitur: Search

`pages/search_page.dart` → `widgets/pages/search_sections/`.
- Pencarian **lokal** di pustaka MediaStore (`_allSongs` difilter dengan debounce).
- `bar.dart` — search bar; `cat_grid.dart`/`cat_tile.dart` — grid kategori (data statis `utils/data/search_categories.dart`: 16 genre dari K-Pop, Jazz, Metal, dst).
- `results.dart`/`result_tile.dart` — hasil; `slivers.dart` — sliver layout; `title.dart` — judul seksi.
- `ScrollToTopService.signal(4)`.
- Keyboard **tidak** auto-focus; di-unfocus saat pindah tab.

---

## 12. Fitur: Halaman Detail

| Halaman | File | Isi |
|---|---|---|
| **Album** | `pages/album_page.dart` → `widgets/pages/detail_sections/album.dart` | Daftar lagu album + `top_bar` gradient. |
| **Artist** | `pages/artist_page.dart` → `detail_sections/artist.dart` | Album + lagu artist. |
| **Artist list** | `pages/artist_list.dart` → `artist_list_sections/` | Grid/list semua artist (`content`/`info`/`row`/`state`). |
| **Music list** | `pages/music_list.dart` → `music_list/page.dart`+`state.dart` | Daftar semua lagu. |

Semua memakai `detail_sections/songs.dart`, `song_row.dart`, `top_bar.dart`.

---

## 13. Fitur: Player

### 13.1 Morph player terpadu
`widgets/unified_morph_player.dart` — satu widget menangani **mini player** dan **full player** (morphing). `bottom_reveal_clipper.dart` (klip reveal), `playback_content.dart`.

### 13.2 Kontrol sheet
`services/player_sheet_controller.dart` — adapter tipis:
- `progress` (0..1) & `expanded` ValueNotifier.
- Animasi pakai `SchedulerBinding.createTicker` (sinkron vsync, auto-pause saat background).
- `open/close/toggle/setProgress`.

### 13.3 Komponen player
| Komponen | File |
|---|---|
| Background animasi (artwork + gradient + fog) | `player_background/` (`animated`, `animated_state`, `artwork`, `fallback`, `fog_painter`) |
| Konten (lirik/queue overlay) | `player_content/` (`content`, `lyrics_overlay`, `lyrics_appearance`, `lyrics_pickers`, `queue_overlay`, `queue_control_button`) |
| Transport | `player_transport_controls.dart`, `player_secondary_controls/` (`controls`) |
| Progress | `player_progress_section.dart` |
| Header & info | `player_song_header.dart`, `player_song_info_row.dart`, `player_song_info_sheet/` |
| Favorite | `player_favorite_button.dart` |
| Hero art | `player_hero_tags.dart` |
| More menu | `player_more_menu.dart` |

**Background:** artwork difog-blur di belakang (shader `assets/shaders/fluid.frag` untuk efek fluid), dengan `fallback` bila artwork tidak ada. `Hero` tag menghubungkan artwork album-list ↔ artwork player.

**Mini player** ikut hilang/slide saat sheet digeser, navbar juga (lihat §6.2).

---

## 14. Fitur: Lirik

Sistem lirik multi-provider, sinkron kata-per-kata (karaoke).

### 14.1 Arsitektur
```
LyricsService (facade)
  ↓
LyricsFetchManager  — jalankan SEMUA provider online PARALEL
  ├─ LyricsCacheManager  — memory + disk + failure TTL (satu-satunya sumber cache)
  └─ cancellation.dart    — CancellationToken
Provider:
  embedded · local_file · lrclib · netease · qq_music · kugou · kuwo · apple_music
```

Urutan sumber: **embedded** → file `.lrc` lokal → memory cache → disk cache → semua provider online paralel.

### 14.2 Provider (`lyrics_service/providers/`)
| Provider | Sumber |
|---|---|
| `embedded_provider` | Tag USLT/SYLT/LYRICS di file audio. |
| `local_file_provider` | File `.lrc` di folder konfigurasi. |
| `lrclib_provider` | LRCLIB.net (open lyrics DB). |
| `netease_provider` | NetEase Cloud Music. |
| `qq_music_provider` | QQ Music. |
| `kugou_provider` | KuGou. |
| `kuwo_provider` | KuWo. |
| `apple_music_provider` | Apple Music. |
| `provider_http.dart` | HTTP client bersama (rate-limit, header, UA). |

`rate_limiter.dart` membatasi request; `cancellation.dart` membatalkan request usang saat user geser lagu.

### 14.3 Enhanced LRC & karaoke
`lrc_parser.dart` meng-parse LRC biasa + **Enhanced LRC** (inline word timestamps). `models/lyric_line.dart` menyimpan `LyricLine` per baris. `quality.dart` menilai kualitas (`LyricsQuality`) — lyric dipilih yang terbaik.

### 14.4 Tampilan sinkron
`widgets/player/synced_lyrics_view/` dipecah ketat:
- `state.dart`, `state_build/indexing/playback/scroll/timeline.dart` — logika state dipecah per concern.
- `karaoke_controller.dart` — timing karaoke.
- `karaoke_line.dart`, `karaoke_line_painter.dart` — render per baris.
- `elrc_word.dart` — highlight kata (Enhanced LRC).
- `view.dart` — view.

### 14.5 Pengaturan lirik (`models/lyrics_settings.dart`)
`fontSize` (34), `lineSpacing` (18), `textAlign`, `bgDim`, `blurStrength`, `activeColor`, `showSource`, `karaokeMode` (default **true**). Persistensi di-flush (debounce) saat app pause.

---

## 15. Fitur: Playlist

`services/playlist_service.dart` + `models/playlist.dart`.
- **User playlist** (key `user_playlists`) — JSON di SharedPreferences, cache in-memory write-through.
- **Favorit** (key `favorite_song_ids`).
- Dialog & tile: `widgets/playlist_dialogs.dart`, `playlist_song_tile.dart`, `playlist_empty_state.dart`, `playlist_play_all_button.dart`.
- Tambah ke playlist: `song_context_menu/add_to_playlist_sheet.dart`.
- Button shuffle/play: `play_shuffle_buttons.dart`.

---

## 16. Fitur: Pengaturan

`pages/settings_page.dart` — 11 part-file. Section berurutan (`body.dart`):

1. **Appearance** (`appearance.dart`) — tema terang/gelap/system, glass theme, gaya navbar, glass appbar/mini-player.
2. **Language** (`language_section.dart`) — pilih EN/ID.
3. **Bit Perfect** (`bit_perfect.dart`) — mode bit-perfect + `bit_perfect_lock.dart`; konfirmasi dialog sebelum toggle.
4. **Audio** (`audio.dart` + sub):
   - **ReplayGain** (`replaygain_section.dart`) — mode (off/track/album/auto), preamp, clipping protection.
   - **Loudness** (`loudness_section.dart`) — normalisasi real-time EBU R128, target LUFS.
   - **Crossfeed** (`crossfeed_section.dart`) — simulasi headphone crossfeed.
   - **Crossfade** (`crossfade_picker.dart`) — durasi crossfade.
   - **Batch scan** (`batch_scan_section.dart`) — pemindaian massal loudness/ReplayGain.
   - **Playback engine** (`playback_engine.dart`) — info engine.
   - **Effect status** (`effect_status.dart`) — status efek native.
5. **Equalizer** (`equalizer.dart` → `pages/settings/equalizer_page.dart`) — band EQ (system Equalizer Android) dengan band slider vertikal/horizontal, preset chips, custom painter track.
6. **System** (`system.dart`) — sleep timer, log, dll.
7. **Debug** (`debug.dart`, `debug_state.dart`) — hanya tampil bila `_DebugState.enabled`.
8. **About** (`about.dart`, `about_app_page.dart`) — versi, kredit, `qris_support.webp` (donasi), `bug_report_page.dart`, `changelog_page.dart` + `changelog_data.dart`.

**Changelog** wajib diisi tiap perubahan — entri terbaru di paling atas, berisi versi (dari `pubspec.yaml`) + tanggal. Versi saat ini `1.5.30` (14 Agustus 2026).

---

## 17. Lapisan Audio

### 17.1 Rantai pemanggilan
```
Flutter UI
  ↓
AudioService              (facade business logic)
  ↓
PlaybackManager           (routing stream + prefetch artwork)
  ↓
Media3PlaybackBridge      (SATU MethodChannel/EventChannel edge)
  ↓
Media3PlaybackService.kt  → ExoPlayer
```

- **Native (Media3) memiliki:** queue, urutan shuffle, repeat mode, sleep timer, crossfade, semua efek audio, persistensi.
- **Flutter memiliki:** `AudioPlaybackState` (cermin dari stream engine) dan objek model `LocalSong` mentah.
- **Dart tidak pernah** menghitung shuffle/repeat/next-index sendiri.

### 17.2 `AudioService` (facade)
Menyediakan `ValueNotifier<AudioPlaybackState> playbackState` (state yang jadi simbol) dan API tingkat tinggi: play/pause/seek/skip, set queue, shuffle, repeat, favorite, add-to-queue, ReplayGain apply (`replay_gain_applicator.dart`), loudness source resolve.

### 17.3 `AudioPlaybackState` (`audio_playback_state.dart`)
Immutable: `currentSong`, `isPlaying`, `isLoading`, `currentIndex`, `currentPlaylist`, `processingState`, `duration`, `position`, `loopMode`, `shuffleEnabled`, `speed`, `sleepTimerActive`, `sleepTimerRemainingMs`, `nextTrackIndex`.

### 17.4 `PlaybackManager` (god file, ~905 baris, **statis**)
- Facade statis murni; method didelegasikan ke `Media3PlaybackBridge`.
- Forwarding stream untuk `currentTrack` & `queue` (untuk mirror queue lokal → prefetch artwork).
- **Artwork prefetch:** maks 2 konkuren, prewarm lagu berikutnya saat buffer, `_lastPrefetchedIndex` tracking.
- Ekspor ulang `equalizer_parameters.dart` (backward-compatible import).
- Catatan renocs: file ini sengaja monolitik (facade statis, tanpa state mutable berarti); renocs ekstraksi hanya bila tiap bagian ≥150 baris & tanpa shared-field.

### 17.5 `Media3PlaybackBridge` — channel yang di-mapping
- **MethodChannel** `musicplayer/media3_commands` (perintah).
- **EventChannel** (state, 15 channel): playback state, position, duration, current track, queue, buffering, audio session id, shuffle mode, repeat mode, sleep timer, offload state, audio format, stereo widening, reverb, service ready.
- Perintah: play/pause/stop/seek/skip/setTrack/setQueue/repeat/shuffle/volume/insertNext/append/remove/reorder/speed/pitch/equalizer/loudness/trackGain/bassBoost/reverb/stereo/acoustic engine, dll.

### 17.6 Kontrak stream
| Stream | Bentuk |
|---|---|
| `playbackStateStream` | `Map: 'playing' bool, 'processingState' String` |
| `currentTrackStream` | `Map?: 'index' int, 'id' int, 'nextTrackIndex' int` |
| `queueStream` | `List of LocalSong.toMap()` |
| `sleepTimerStream` | `Map: 'active' bool, 'endOfSong' bool, 'remainingMs' int` |

### 17.7 Sub-layanan audio
| Service | Peran |
|---|---|
| `DeviceDsp` | Inspeksi kapabilitas hardware (bass boost, dll), routing loudness/ReplayGain, re-query saat session rotate. |
| `AudioEffectsService` | Controller DSP utama (UI + state saja). ValueNotifier per setting + persistensi + forward ke engine. |
| `MediaCapabilitiesService` | Kapabilitasadvanced: stereo widening, reverb, dll (prefix key `mcap_`). |
| `AudioFocusService` | Koordinasi audio focus. |
| `audio_session_handler/` | Handler `audio_session`. |
| `SleepTimerService` | Adapter tipis; logika timer native (Handler Kotlin) agar tetap jalan saat background. |
| `LoudnessSourceResolver` | Resolusi sumber loudness untuk mode album-gain auto. |
| `ReplayGainService` | Baca tag ReplayGain/R128/iTunNORM (lihat §20). |
| `loudness_source_resolver` + `media3/equalizer_models.dart` | Model equalizer platform. |

---

## 18. Native Audio Runtime (C/DSP)

`native_audio_runtime/` — plugin FFI (`dart:ffi`) yang membungkus runtime DSP C11. Diakses dua arah: **Dart → C** (FFI, via JNI di sisi Android) dan seterusnya C memproses audio.

### 18.1 Arsitektur
- **ABI FFI** (`native_audio_runtime.h`) — API stabil (versi, `NarCapabilityEntry`, module registry, status).
- **Pipeline** (`dsp_pipeline.c/h`) — rantai processor yang didorong vtable.
- **Kontrak processor** (`dsp_processor.h`) — SATU interface untuk semua processor; setiap processor daftarkan diri via `*_register_internal()`.
- **Stream context** (`dsp_stream.h`) — `NAR_DSP_MAX_STREAMS` stream paralel (untuk crossfade dua player).
- **Helper** — `biquad_filter.h` (`nar_biquad_compute`, `NAR_BIQUAD_MAX_CHANNELS`), `stereo_matrix.h`, `dynamics_common.h`, `neon_kernels.h` (SIMD).
- **Buffer** (`audio_buffer.c/h`, `audio_buffer_internal.h`) — PCM float32 interleaved; `NarAudioBuffer` punya `sample_rate` (authoritative).
- **JNI** (`native_dsp_jni.c`) — jembatan ke Kotlin (`NativeDspAudioProcessor` disisipkan ke chain ExoPlayer).
- **FFI build hook** (`hook/build.dart`) — menambahkan `src/*.c` ke kompilasi.
- **Bindings** (`lib/src/third_party/native_audio_runtime.g.dart`, generated via `tool/ffigen.dart`).

### 18.2 DSP Pipeline — 8 slot
Urutan registrasi di `dsp_pipeline_io.dart` → `initialize()`:

| Slot | Processor | Capability | Peran |
|---|---|---|---|
| 0 | `gain_processor` | `dsp.gain` | Gain linear (scaffold/infra). |
| 1 | `replaygain_processor` | `dsp.replaygain` | Gain metadata (RG/R128/iTunNORM), clipping protection. |
| 2 | `loudness_processor` | `dsp.loudness` / `scan.loudness_ebur128` | Loudness real-time EBU R128 / BS.1770-4. |
| 3 | `acoustic_engine_processor` | `dsp.acoustic_engine` | **Acoustic Engine** (enhancement perseptual speaker). |
| 4 | `comp_processor` | `dsp.compressor` | Kompresor feed-forward soft-knee, stereo-linked. |
| 5 | `crossfeed_processor` | `dsp.crossfeed` | Crossfeed headphone frequency-dependent. |
| 6 | `limiter_processor` | `dsp.limiter` | Brickwall look-ahead limiter. |
| 7 | `soft_clipper_processor` | `dsp.soft_clipper` | Soft clipper `tanh` (C¹ kontinu). |

> Slot 1 "Parametric EQ" dicabut (EQ native dihapus; Band EQ memakai **system Equalizer Android** — makanya `dsp.equalizer = 0`).

### 18.3 Table `kCapabilities` (`native_audio_runtime.c`)
```
dsp.pipeline=1, dsp.gain=1, dsp.media3_integration=1, dsp.equalizer=0,
dsp.compressor=1, dsp.crossfeed=1, dsp.limiter=1, dsp.soft_clipper=1,
dsp.replaygain=1, dsp.acoustic_engine=1, dsp.bass_boost=0, dsp.virtualizer=0,
dsp.resampler=0, decoder.flac_hires=0, decoder.dsd=0, scan.loudness_ebur128=1
```
UI membaca daftar ini untuk menentukan fitur mana yang ditampilkan/aktif.

### 18.4 Acoustic Engine (PR #152)
`src/acoustic_engine_processor.{c,h}` — enhancement perseptual berorientasi speaker, **nol latensi**, satu knob `intensity ∈ [0,1]`.

**Kontrak race-free (hasil audit/fix terakhir):**
- Intensitas dipublikasikan sebagai **satu atomic scalar** (`_Atomic uint32_t intensity_bits` = bit IEEE-754 float; release store / acquire load).
- **Audio thread sendiri** mendeteksi perubahan (via `applied_bits[]`, `applied_rate[]`) lalu membangun ulang `AeParams` + `_clear_stream()` miliknya. **Control thread tidak pernah menulis struct DSP** → slider cepat tidak bisa *tear*.
- `bypass` jadi atomic; `set_bypass()` tidak memset dari control thread — tiap audio thread merespons transisi lewat `last_bypass[s]`.
- `nar_acoustic_engine_reset()` → `atomic_fetch_add(&_ae.reset_gen, 1)`; tiap stream clear saat `seen_reset_gen[s]` berubah.
- `set_sample_rate()` hanya menyimpan `rate_hint` fallback (`sample_rate` buffer yang otoritatif).
- `_build()` tetap pure function dengan clamp 0..1 dan fallback 48000 Hz.
- `_clear_stream()` hanya di audio thread.

### 18.5 Loudness — EBU R128 (BS.1770-4)
`loudness_processor` terpisah & komplementer terhadap ReplayGain:
- **K-weighting:** dua tahap biquad per channel, memakai **koefisien literal ITU-R BS.1770-4 Annex 1** (formulasi tan/pow, diturunkan langsung pada sample rate hidup), bukan aproksimasi RBJ.
- **Channel weighting BS.1770-4:** depan L/R/C = 1.0; surround/back = +1.5 dB (≈1.41254); **LFE = 0.0** (dihapus dari pengukuran).
- **Channel averaging bug fix:** BS.1770-4 menjumlahkan *channel power*, **bukan** rata-rata — ada regression test khusus.
- **Fail-open:** satu sample NaN tidak meracuni state filter / menghasilkan output non-finite.
- Absolute gate; reset mengembalikan ke sentinel.

### 18.6 Thread-safety
- Knob lintas thread **wajib atomic** (dokumentasi di `dsp_processor.h`).
- Audio thread bebas dari `malloc`/logging/ctx-switch.
- Module registry dikunci mutex, tapi hot path init/dispose lock-free via `_state` atomic.
- Bypass = *zero-copy* (early return, tidak menyentuh sample).

---

## 19. Lapisan Native Android (Kotlin)

### 19.1 `Media3PlaybackService.kt`
Service foreground-ish playback (Media3 `MediaSessionService` + custom). Memiliki queue, ExoPlayer, audio processors, crossfade (dua player overlap), dan notifikasi.

### 19.2 Audio processors di chain ExoPlayer
- `NativeDspAudioProcessor` — menjembatani ke `native_audio_runtime` C DSP (JNI).
- `ReverbAudioProcessor` / `ReverbManager` — Schroeder room reverb (comb + all-pass).
- `StereoWideningAudioProcessor` / `StereoWidthManager` — stereo widening via `ChannelMixingAudioProcessor` (di pipeline ExoPlayer, bukan AudioFlinger → tetap jalan saat crossfade overlap dua player).
- `SignalsmithStretchAudioProcessor` / `StretchManager` / `StretchAwareAudioProcessorChain` — time-stretch (pitch preservation).

### 19.3 Crossfade
- `CrossfadeController` — timing & fade.
- `PreloadManager` — pre-load next track.
- `CrossfadeTimelineLogger` — diagnostics.
- `PlayPauseFadeController` (transport) — fade saat play/pause.

### 19.4 ReplayGain / Loudness scanning
- `ReplayGainService` — worker yang memindai file, dekode PCM (`PcmDecoder`), hitung gain.
- `ReplayGainNative` — C-level analysis.
- `MediaStoreWriteGate` —JX gate sebelum menulis tag ke MediaStore.
- `MetadataPrescanner` + `MetadataCacheDb` (SQLite) + `TagBuilder` — prascanning & cache metadata (bitrate, samplerate, tag).
- `ExoMetadataReader` — baca metadata dari track ExoPlayer.

### 19.5 Audio focus & offload
- `AudioFocusManager` — fokus audio (interrupt, ducking, gain transient).
- `AudioOffloadManager` — offload ke hardware (battery).

### 19.6 Notification & Now Playing
- `PlaybackNotificationManager` — notifikasi media.
- `SessionArtworkProvider` — artwork untuk session.
- `NowPlayingOverlayActivity` — activity translucent untuk "Open with" dari file manager/Telegram; `taskAffinity=""`, `excludeFromRecents=true` supaya Back kembali ke app asal.

### 19.7 Artwork & warna
- `ArtworkCacheManager`, `BitmapUtils`, `FallbackBitmapLoader` — cache & decode artwork.
- `NativePaletteBridge` / `NativePaletteModels` / `ColorScience` — ekstraksi palet (MMCQ, OKLab clustering; 5-role: primary, secondary, accent, highlight, shadow). Menggantikan `palette_generator_plus`.

### 19.8 Utilitas
- `MediaItemFactory` / `TrackMapper` — konversi Dart `LocalSong` → `MediaItem` ExoPlayer.
- `EventEmitter` — emitter event ke Dart.
- `ActivePlayerProxy` — proxy player aktif (untuk delegasi command).
- `ServiceShutdownCoordinator` — shut down service dengan benar.
- `FfmpegCapabilityProbe` — deteksi dukungan FFmpeg.

---

## 20. Layanan

Semua di `lib/services/`. 22 service utama:

| Service | Peran Detail |
|---|---|
| `AudioService` | Facade playback business logic + replay gain applicator. |
| `PlaybackManager` | Facade stream playback + prefetch artwork. |
| `MediaStoreService` | Query pustaka audio lokal via MediaStore (`musicplayer/media_store`); warm-up cache sinkron + `rescanNotifier`. |
| `HistoryService` | Recently played + play count (song & artist), cache warm-up. |
| `PlaylistService` | Playlist user + favorit. |
| `ReplayGainService` | Baca tag loudness (RG/R128/iTunNORM) dengan cache memory + SharedPrefs + dedup in-flight. |
| `LoudnessSourceResolver` | Resolusi sumber loudness (album/track). |
| `LyricsService` (+ `lyrics_service/`) | Multi-provider fetch lirik (lihat §14). |
| `LogService` (+ `log_service/`) | Log in-app ringkas dengan filter level (lihat §23). |
| `SleepTimerService` | Adapter sleep timer (native-backed). |
| `ArtworkRepository` | Cache artwork 2-lapis (memory LRU + disk), prewarm. |
| `NativePaletteService` | Cache palet warna per lagu (delegasi ke `NativePaletteBridge.kt`). |
| `WatermarkService` | Watermark opsional di atas UI (default tersembunyi; teks "IG : Wndavenznchole"). |
| `OpenFileService` | Tangani intent "open with" dari app lain. |
| `LanguageManager` | Manage locale EN/ID. |
| `AudioFocusService` | Koordinasi audio focus. |
| `DeviceDsp` | Inspeksi kapabilitas + routing. |
| `AudioEffectsService` | Controller semua setting DSP. |
| `MediaCapabilitiesService` | Kapabilitas advanced (stereo widening, reverb). |
| `PlayerSheetController` | Animasi bottom-sheet player. |
| `ScrollToTopService` | Scroll-to-top per tab. |
| `SongMetadataService` | Metadata lagu. |
| `MediaStoreService` | (tersebut di atas). |
| `Native/bridges/*` | `NativeDspBridge`, `FfmpegDecoderBridge`, `NativeLogBridge`. |
| `Native/contracts`, `Native/models`, `Native/native_module_registry` | Registri modul native. |

---

## 21. Model Data

`lib/models/` — immutable, `toMap`/`fromMap` friendly:

| Model | Isi |
|---|---|
| `LocalSong` | `id`, `title`, `artist`, `path`, `album`, `albumId`, `artworkUri`, `duration`, `year`, `trackNumber`, `discNumber`, `albumArtist`, `genre`, `bitrate`, `sampleRate`, `dateAdded`. |
| `LoudnessData` | Data loudness (RG track/album, R128, iTunNORM) + `LoudnessData.none`. |
| `LyricLine` | Satu baris lirik ( Enhanced LRC support). |
| `LyricsSettings` | Preferensi tampilan lirik. |
| `Playlist` | Playlist user (id, nama, songIds, cover, dll) dengan `encodeList`/`decodeList`. |
| `ReplayGainMode` | Enum: off / track / album / auto. |
| `SongInfo` | Info lagu tambahan. |

---

## 22. Tema & Tampilan

| File | Peran |
|---|---|
| `theme/app_colors.dart` | Token warna semantic (primary, secondaryLabel, surface, subtleSeparator, dll) — accessed via `AppColors.of(context)`. |
| `themes/app_theme_extension.dart` | `ThemeExtension` untuk token kustom. |
| `themes/app_themes.dart` | `AppThemes.light` & `AppThemes.dark`. |
| `themes/theme_builder.dart` | Builder theme. |
| `themes/theme_controller.dart` | Controller: `mode` (system/light/dark), `glassTheme`, `navBarStyle` (solid/glass/pill), `glassAppBar`, `glassMiniPlayer`. |
| `themes/glass_navbar.dart` | `GlassNavBar` & `FloatingPillNavBar` (bodyHeight, bottomGap). |

Font: **SF Pro Text** (regular/bold dari `assets/fonts/`). Shader: `assets/shaders/fluid.frag` untuk efek fluid pada player background.

---

## 23. Sistem Logging

`services/log_service/` — log in-app ringkas (maks 5000 entri) dengan:
- Level: error, warn, info, verbose.
- Filter: `loggingEnabled`, `errorsOnly`, `verboseEnabled`, `liveTailEnabled`.
- **`NativeLogBridge`** — subscribe EventChannel `musicplayer/native_logs`, teruskan log Media3/MainActivity ke viewer. (Bug fix: native `debug` dipetakan ke `verbose`, bukan jatuh ke `info`.)
- **`LogPage`** (`pages/log_page/`) — viewer dengan `app_bar_badge` (jumlah), `bar_btn` (ekspor/bersihkan), `entry_tile`, `filter_bar`, `log_level_selector`.
- Semua exception (Flutter error, PlatformDispatcher, zone) diteruskan ke sini.

---

## 24. Internasionalisasi

- Sumber: `lib/l10n/app_{en,id}.arb`.
- Generated: `app_localizations.dart` + `app_localizations_en.dart` + `app_localizations_id.dart` (**380 key** per bahasa).
- Delegate: `AppLocalizations.delegate` + Global Material/Widgets/Cupertino.
- Supported locale: **EN** & **ID** (Indonesia). `localeResolutionCallback`: pakai pilihan user jika ada, selain itu ikuti device, fallback EN.
- Akses via `context.l10n` (`extensions/localization_extension.dart`).
- `utils/lyrics_text_direction.dart` — dukung teks RTL pada lirik.

---

## 25. Build, Tooling & CI

### 25.1 Build lokal
```bash
flutter pub get
flutter run                 # Android
flutter build apk           # APK
```

### 25.2 Build web (Node)
```bash
npm run dev     # node server.js   (static server)
npm run build   # flutter build web --release --base-href /
```
`watch-rebuild.js` / `rebuild-web.js` untuk auto-rebuild saat dev web.

### 25.3 Build APK otomatis (CI/Replit)
- `setup-flutter.sh` — pasang JDK 21, Flutter SDK.
- `build-apk.sh` — pasang Android SDK (platform-36, build-tools 36.0.0), **NDK r28c** (clang arm64), **CMake 3.22.1** + Ninja, lalu `flutter build apk`. (Handle `/home/runner/` quota penuh dengan redirect `HOME`/tmp.)
- `replit.nix` / `.replit` / `.devcontainer` — environment dev.

### 25.4 GitHub Actions (`.github/workflows/`)
| Workflow | Trigger | Isi |
|---|---|---|
| `flutter-check.yml` | push/PR pada `android/lib/assets/pubspec` | Lint + debug assemble. |
| `kotlin-tests.yml` | push/PR pada `android/` | Unit test Kotlin (JDK 21). |
| `native-tests.yml` | push/PR pada `native_audio_runtime/src`+`test` | Test C/DSP (FFI). |
| `android.yml` | push/PR pada lib/android/native | Build Android. |
| `codeql.yml` | push/PR + mingguan (Sen 03:00 UTC) | CodeQL security-extended + quality. |
| `pages.yml` | — | Deploy web (GitHub Pages). |

Semua workflow pakai `concurrency` cancel-in-progress.

---

## 26. Pengujian

### Dart (`test/`)
- `models/`: `local_song_test`, `loudness_data_test`, `playlist_test`, `playlist_edge_cases_test`.
- `services/lyrics_service/lrc_parser_test` — parser LRC/Enhanced LRC.
- `utils/`: `lyrics_text_direction_test`, `safe_num_test`.
- `widget_test` — smoke test.

### Kotlin (`android/app/src/test/`)
9 unit test: `ActivePlayerProxy`, `NativePaletteBridge`, `ServiceShutdownCoordinator`, `AudioFocusManager`, `CrossfadeController`, `ReverbManager`, `EventEmitter`, `TagBuilder`, `QueueManager`.

### Native C/FFI (`native_audio_runtime/test/`)
- `native_audio_runtime_test.dart` — **60 test** yang memanggil C DSP lewat FFI (pipeline, kapabilitas, kapabiltas 8 processor & urutannya, loudness BS.1770-4, gate, NaN guard, bypass, dll).
- `native_benchmark.dart` — benchmark throughput DSP.

**Status verifikasi saat ini (clone bersih, `main` @ `bf16fcb`, Flutter 3.47.5):**
- `flutter test` (root) — **63/63 lulus**.
- `dart test` (native_audio_runtime) — **60/60 lulus**.
- `flutter analyze lib test` & `dart analyze lib test` — **No issues found**.
- `gcc -std=c11 -Wall -Wextra -Werror` — bersih.

---

## 27. Catatan Teknis & Batasan

### 27.1 Target perangkat
README menyatakan app **fokus pada Xiaomi Mi 9T, MIUI 12.1.4, Android 11, Snapdragon 730, RAM 6GB, storage 64GB**. Belum ada rencana dukungan perangkat lain di luar perangkat utama. Kode tetap ditulis portabel & teruji di CI multi-ABI, tapi primario Android flagship/midrange.

### 27.2 Batasan & keputusan sadar
- **Radio & Browse online belum backend** — data station kosong; search adalah **lokal** (bukan streaming search).
- **Web build** ada (web/ + server.js) tapi target & fitur berat (Media3/ExoPlayer) adalah Android; web lebih ke preview/portability.
- **Parametric EQ native dihapus** — Band EQ memakai **system Equalizer Android** (`dsp.equalizer = 0`).
- **Loudness vs ReplayGain** sengaja dua processor: metadata (stateless) vs real-time measurement.
- **Changelog wajib** diisi tiap perubahan (`changelog_data.dart`) — bukan opsional.
- **Watermark** default tersembunyi; teks & default diatur di `watermark_service.dart`.
- **Paket FFmpeg** berlisensi **GPL v3** (Jellyfin AAR) — perhatikan konsekuensi distribusi.

### 27.3 State vs UI
- Pattern dominan: `ValueNotifier`/`ValueListenableBuilder` (bukan Provider/Bloc). Service menyiarkan state; UI rebuild granular.
- Tidak ada state management eksternal — semuanya via `ValueNotifier` + `Stream` + `setState`.

### 27.4 Web-compat guard
Banyak `if (kIsWeb) return;` di service (replaygain, log bridge, palette, media store) agar build web tidak crash, walau fiturnya nonaktif di web.

---

## Lampiran: Peta File → Peran

| Path | Peran |
|---|---|
| `lib/main.dart` + `lib/main/*` | Bootstrap, `MaterialApp`, lifecycle. |
| `lib/bottom_nav_bar/*` | Shell tab, navbar, morph player host. |
| `lib/domain/app_router.dart` | Helper navigasi. |
| `lib/pages/*` | Halaman (home, browse, radio, library, search, detail, settings, log). |
| `lib/services/*` | Business logic, persistensi, state. |
| `lib/services/audio/*` | Playback facade, bridge Media3, device DSP, equalizer params. |
| `lib/services/lyrics_service/*` | Multi-provider lyrics engine. |
| `lib/services/native/*` | Bridge ke modul native. |
| `lib/services/log_service/*` | In-app logging. |
| `lib/models/*` | Data model. |
| `lib/widgets/*` | Komponen UI reusable. |
| `lib/theme(s)/*` | Token & controller tema. |
| `lib/l10n/*` | Localization (EN + ID). |
| `lib/utils/*` | Konstanta, format, data statis. |
| `android/app/src/main/kotlin/dev/wndavenz/music/**` | Native Android (Kotlin/Media3). |
| `native_audio_runtime/src/*.c,h` | DSP C11 (FFI). |
| `native_audio_runtime/lib/**` | Binding Dart FFI + pipeline wrapper. |
| `test/`, `android/app/src/test/`, `native_audio_runtime/test/` | Test suites. |
| `.github/workflows/` | CI. |

---

*Dokumen ini dibuat dari codebase `Dump` @ `main` (`bf16fcb`). Untuk perubahan perilaku, rujuk komentar di source — codebase ini sangat ber-komentar dan itu rujukan terbaik.*
