# Comprehensive Dart Codebase Audit Report

**Tanggal:** 18 Juli 2026  
**Versi App:** 1.2.3+1  
**Total file Dart diaudit:** 263 / 263 (100% — `lib/`, `test/`, `native_audio_runtime/lib/`)  
**Audit dilakukan dalam 3 round paralel + verifikasi grep/shell per temuan**

---

> **Tidak ada perubahan kode yang dilakukan.** Laporan ini murni audit dan pelaporan. Semua temuan harus diverifikasi sebelum ditindaklanjuti.

---

## Kategori 1: Dead Code Analysis

### 1.1 `lib/services/boot_trace.dart` — Temporary Instrumentation

| | |
|---|---|
| **Severity** | High |
| **Confidence** | High |

74 referensi tersebar di seluruh init chain (`lib/main/main.dart` dan semua service). File ini secara eksplisit di-comment sebagai *"TEMPORARY startup instrumentation untuk Phase 9 debugging"*. Overhead runtime tidak perlu, code bloat, noise untuk debugging ke depan.

**Rekomendasi:** Hapus seluruh `BootTrace.step()`, `BootTrace.log()`, `BootTrace.begin()`/`end()`, lalu hapus `boot_trace.dart`.

---

### 1.2 `lib/pages/settings_page/sleep_timer.dart` — Intentionally Empty File

| | |
|---|---|
| **Severity** | Medium |
| **Confidence** | High |

File berisi satu baris komentar: *"Sleep Timer has been moved to the player 3-dot menu (PlayerMoreMenu). This file is intentionally empty"*. `part of` directive dipertahankan tanpa alasan kuat.

**Rekomendasi:** Hapus file ini dan `part 'sleep_timer.dart'` dari `settings_page.dart`.

---

### 1.3 `lib/pages/settings_page/chip.dart` — Empty File

| | |
|---|---|
| **Severity** | Medium |
| **Confidence** | High |

Hanya berisi `part of '../settings_page.dart';` dan satu comment `// ─── DEBUG`. Tidak ada class, widget, atau kode apapun. `SettingsChip` tidak terdefinisi di sini maupun di tempat lain.

**Rekomendasi:** Hapus file ini dan `part 'chip.dart'` dari parent.

---

### 1.4 `lib/pages/settings_page/lyrics.dart` & `lyrics_rows.dart` — Empty Files

| | |
|---|---|
| **Severity** | Medium |
| **Confidence** | High |

Keduanya hanya berisi `part of '../settings_page.dart';` tanpa konten. Tidak ada kode apapun.

**Rekomendasi:** Hapus kedua file dan entry `part` terkait.

---

### 1.5 `lib/pages/settings_page/notif_icon.dart` — Widget Tidak Pernah Dipakai

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/pages/settings_page/notif_icon.dart`, `debug_state.dart` |
| **Confidence** | High |

`_NotifIconRow` didefinisikan dengan `// ignore_for_file: unused_element` — author sendiri sadar ini tidak dipakai. Tidak ditemukan satu pun instantiasi di seluruh codebase. `_DebugState.notifIcons` dan `_DebugState.notifIcon` di `debug_state.dart` juga hanya dikonsumsi oleh widget ini.

**Rekomendasi:** Hapus `notif_icon.dart` dan field `notifIcons`/`notifIcon` dari `debug_state.dart`.

---

### 1.6 `lib/utils/data/radio_stations.dart` — Empty Data List

| | |
|---|---|
| **Severity** | Medium |
| **Confidence** | High |

`final List radioStations = [];` — list kosong tanpa tipe. RadioPage aktif di BottomNav tab ke-3 dan merender kontennya dari list ini. User melihat tab kosong.

**Rekomendasi:** Isi data atau tampilkan placeholder "Coming Soon" yang jelas, atau sembunyikan tab Radio dari BottomNav sementara belum siap.

---

### 1.7 `lib/utils/sample_music_data.dart` — Pure Re-export File

| | |
|---|---|
| **Severity** | Low |
| **Confidence** | High |

Hanya berisi `export 'data/radio_stations.dart';`. Satu-satunya consumer adalah `search_sections.dart`. Abstraksi tanpa nilai tambah.

**Rekomendasi:** Import `radio_stations.dart` langsung atau hapus file ini dan update import.

---

### 1.8 `FutureLocalSongCarousel` — Dead Class

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/widgets/local_song_carousel.dart` |
| **Confidence** | High |

`FutureLocalSongCarousel` didefinisikan di file yang sama dengan `LocalSongCarousel`. `LocalSongCarousel` dipakai di banyak tempat (browse_sections, recently_played_section, radio_sections). Tapi `FutureLocalSongCarousel` tidak diimport maupun dipakai di manapun dalam seluruh codebase.

**Rekomendasi:** Hapus class `FutureLocalSongCarousel`.

---

### 1.9 `CommonActions._cast()` — TODO Stub yang Muncul di UI

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/widgets/common_actions.dart` |
| **Confidence** | High |

Method `_cast(BuildContext context)` hanya berisi komentar `// TODO: Cast function`. Widget `CommonActions` sendiri aktif dipakai di 5 halaman (album_page, artist_page, artist_list, library_page, music_list) sebagai action button di AppBar. Artinya ada tombol cast yang visible di UI tapi tidak melakukan apa-apa saat ditekan.

**Dampak:** User experience buruk — user menekan tombol dan tidak ada respons.

**Rekomendasi:** Implementasikan fitur cast atau sembunyikan tombol sampai fitur siap.

---

### 1.10 `WebView` — 5 Dead Parameters

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/webView/webViewContainer.dart` |
| **Confidence** | High |

`WebView` widget mendefinisikan parameter berikut tapi **tidak satu pun dipakai** di dalam `build()`:
- `innerContainerHeight` (default: 866)
- `innerContainerWidth` (default: 400)
- `shadowColor` (default: Colors.black54)
- `shadowBlurRadius` (default: 10.0)
- `shadowSpreadRadius` (default: 0.0)

`build()` hanya menggunakan `gradientColors`, `gradientStops`, `padding`, `borderRadius`, `innerContainerColor`, dan `child`. Container inner selalu pakai `double.infinity`, tidak pernah `innerContainerHeight`/`Width`.

**Rekomendasi:** Hapus 5 parameter mati tersebut.

---

### 1.11 `native_runtime_last_status()` — Unused FFI Binding

| | |
|---|---|
| **Severity** | Low |
| **File** | `native_audio_runtime/lib/native_audio_runtime_bindings_generated.dart:63` |
| **Confidence** | High |

```dart
external int native_runtime_last_status();
```
Binding ini didefinisikan tapi tidak pernah dipanggil dari Dart manapun (verified via grep). Binding lain (`nar_audio_buffer_*`, `native_runtime_aaudio_*`, `nar_dsp_pipeline_*`) semuanya dipakai.

**Rekomendasi:** Hapus binding ini dari generated file, atau dokumentasikan bahwa ini reserved untuk future use.

---

### 1.12 `NativeDspBridge` — Empty Stub Methods

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/services/native/bridges/native_dsp_bridge.dart` |
| **Confidence** | High |

Method `applyPreset()`, `setBandGain()`, `setEnabled()`, `registerProcessor()` semuanya empty stubs/no-ops dengan TODO. Phase 3 placeholder yang terdokumentasi.

**Rekomendasi:** Sudah terdokumentasi dengan baik. Tidak mendesak.

---

### 1.13 `lib/services/audio/audio_session_handler/handler.dart` — Empty Stub Methods

| | |
|---|---|
| **Severity** | Low |
| **Confidence** | High |

`onAppPause()` dan `onAppResume()` empty stubs. Native Media3 sudah menangani audio focus secara mandiri.

**Rekomendasi:** Hapus kedua method dan panggilan terkait di `AudioFocusService`.

---

### 1.14 `lib/widgets/pages/home/albums_section/state.dart` — Empty Catch Block

| | |
|---|---|
| **Severity** | Low |
| **Confidence** | High |

`catch (_)` mengabaikan semua error dari `MediaStoreService`. Jika gagal, section home albums diam-diam tampil kosong.

**Rekomendasi:** Minimal log error ke `LogService`.

---

## Kategori 2: Folder Audit

### 2.1 `lib/Bottom NavBar/` — Folder Name dengan Spasi

| | |
|---|---|
| **Severity** | High |
| **Confidence** | High |

Folder menggunakan spasi, melanggar konvensi Dart/Flutter (`snake_case`). Akibatnya import menggunakan URL encoding:
```dart
import 'package:musicplayer/Bottom%20NavBar/bottom_nav.dart';
```

**Rekomendasi:** Rename ke `lib/bottom_nav/`, update 2 import terkait.

---

### 2.2 `lib/webView/` — Single-File Folder

| | |
|---|---|
| **Severity** | Low |
| **Confidence** | High |

Folder hanya berisi satu file: `webViewContainer.dart` (nama juga camelCase — lihat 9.2). Folder isolasi berlebihan.

**Rekomendasi:** Pindahkan ke `lib/widgets/common/web_view_container.dart`.

---

## Kategori 3: File Audit

### 3.1 `test/widget_test.dart` — Default Template Test yang Salah

| | |
|---|---|
| **Severity** | High |
| **Confidence** | High |

Default Flutter counter app test hasil `flutter create`. Mencari `find.text('0')`, `find.text('1')`, `find.byIcon(Icons.add)` — tidak ada satupun di music player ini. **Pasti gagal** jika dijalankan.

**Rekomendasi:** Hapus atau replace dengan smoke test yang sesuai.

---

### 3.2 File Settings Kosong

*(`chip.dart`, `sleep_timer.dart`, `lyrics.dart`, `lyrics_rows.dart` — sudah dibahas di 1.2–1.4)*

---

## Kategori 4: Import Audit

### 4.1 URL-Encoded Import — `lib/main.dart`

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/main.dart:5` |
| **Confidence** | High |

```dart
import 'package:musicplayer/Bottom%20NavBar/bottom_nav.dart';
```

**Rekomendasi:** Fix root cause — rename folder (lihat 2.1).

---

### 4.2 `DateTime.now()` dalam `build()`

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/pages/settings_page/about.dart:48`, `about_app_page.dart:82` |
| **Confidence** | High |

`DateTime.now().year` dipanggil di dalam `build()`. Setiap rebuild mengalokasikan `DateTime` baru yang tidak perlu.

**Rekomendasi:** Hitung sekali di `initState()` atau sebagai static constant.

---

## Kategori 5: Architecture Audit

### 5.1 God Files — File Terlalu Besar

| | |
|---|---|
| **Severity** | High |
| **Confidence** | High |

| File | Baris | Masalah |
|---|---|---|
| `lib/pages/log_page.dart` | **889** | Mixing log display + filter logic + export + detail sheet |
| `lib/pages/settings_page/audio.dart` | **869** | Semua audio settings: normalization, EQ, compressor, engine stats |
| `lib/services/audio/playback_manager.dart` | **833** | Queue, volume, DSP, normalization, sleep timer, stats, native bridge |
| `lib/widgets/pages/library_sections/detail.dart` | **576** | 4 view type (Artist/Album/Songs/Playlist) + search + sort |

**Rekomendasi:** Pecah per concern. `detail.dart`: widget terpisah per view type + controller untuk logic. `audio.dart`: section jadi file terpisah. `playback_manager.dart`: facade tipis + sub-manager.

---

### 5.2 `NativeModuleRegistry.initializeAll()` — Sequential Loop

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/native/native_module_registry.dart:38` |
| **Confidence** | High |

`initializeAll()` loop sequential meskipun module DSP dan FFmpeg tidak saling bergantung.

**Rekomendasi:** `await Future.wait(_modules.map((m) => m.initialize()))` jika tidak ada ordering dependency.

---

### 5.3 `NativeModuleRegistry.disposeAll()` — Error Swallowing

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/native/native_module_registry.dart:68` |
| **Confidence** | High |

`disposeAll()` membungkus setiap dispose dalam try-catch yang mengabaikan semua error.

**Rekomendasi:** Minimal log error ke `LogService` saat disposal gagal.

---

### 5.4 Massive Duplicate Logic — 7 Lyrics Providers

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/services/lyrics_service/providers/` |
| **Confidence** | High |

Tujuh provider online menduplikasi pola yang sama: HTTP handling, retry logic, rate limiting (429 check), JSON parsing. Inkonsistensi: `AppleMusicProvider` cek 429, `NetEaseProvider` hanya cek 200. Bug di satu provider tidak otomatis fix di yang lain.

**Rekomendasi:** Buat `AbstractOnlineLyricsProvider` yang handle HTTP/retry/rate-limiting. Provider hanya implement `buildUrl()` dan `parseResponse()`.

---

### 5.5 `ReplayGainService` — Duplikat Method Internal

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/replay_gain_service/service.dart` |
| **Confidence** | Medium |

`_readRawTags()` dan `_readTagsNative()` hampir identik dalam struktur.

**Rekomendasi:** Refactor ke satu method dengan parameter yang membedakan source.

---

### 5.6 `ThemeController` — Mixed Responsibilities

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/themes/theme_controller.dart` |
| **Confidence** | High |

Class mencampur state management (ValueNotifiers), persistence (SharedPreferences), dan UI logic. Private constructor `ThemeController._()` didefinisikan tapi class hanya gunakan static members — constructor tidak pernah bisa dipanggil dari luar.

**Rekomendasi:** Jadikan class `abstract`. Pertimbangkan memisahkan persistence layer.

---

### 5.7 Fragile Startup Chain — 20+ Service Init

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/main/main.dart` |
| **Confidence** | High |

Sequential init 20+ service dengan urutan ketat + 74 BootTrace log di antaranya. Menambah service baru atau mengubah urutan bisa menyebabkan crash yang sulit di-debug.

**Rekomendasi:** Kelompokkan ke init phases eksplisit setelah BootTrace dihapus.

---

### 5.8 Layer Violation — UI Memanggil Service Langsung

| | |
|---|---|
| **Severity** | Medium |
| **Confidence** | High |

Halaman UI memanggil `AudioService`, `AudioEffectsService`, `PlaybackManager`, `MediaStoreService` langsung. Pola umum di Flutter tanpa state management library.

**Rekomendasi:** Pertimbangkan ViewModel/Controller terpisah untuk halaman >500 baris.

---

### 5.9 Static `_current` Singleton-lite di `player_content/content.dart`

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/widgets/player/player_content/content.dart` |
| **Confidence** | High |

Public static methods `forwardExternalDrag*` berkomunikasi antar widget melalui static `_current` instance. Pola ini bisa menyebabkan state leak jika widget di-dispose tapi static reference tidak dibersihkan.

**Rekomendasi:** Gunakan `InheritedWidget`, `Provider`, atau `GlobalKey` yang lebih aman untuk cross-widget communication.

---

### 5.10 Duplikat Scroll Pattern di 3 Pages

| | |
|---|---|
| **Severity** | Low |
| **File** | `album_page.dart`, `artist_page.dart`, `music_list.dart` |
| **Confidence** | High |

Ketiga halaman mengimplementasikan pola identik: `ScrollController` + `_scrollOffset` + `ScrollToTopService.signal(n).addListener` di initState/dispose.

**Rekomendasi:** Ekstrak ke mixin `ScrollToTopMixin`.

---

### 5.11 Settings Code Tersebar di Dua Folder

| | |
|---|---|
| **Severity** | Medium |
| **Confidence** | High |

`lib/pages/settings/` dan `lib/pages/settings_page/` — dua folder untuk satu fitur yang sama.

**Rekomendasi:** Konsolidasikan ke satu folder. Pekerjaan besar — prioritaskan setelah dead file cleanup.

---

## Kategori 6: Flutter Best Practices

### 6.1 `library_sections/detail.dart` — God Widget + `setState` per Scroll Tick

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/widgets/pages/library_sections/detail.dart:38,70` |
| **Confidence** | High |

576 baris widget yang menangani 4 view type berbeda + search + filter + sort + playback logic. `setState(() => _offset = o)` dipanggil setiap scroll event (threshold 0.5) — merebuild seluruh halaman hanya untuk appbar fade.

**Rekomendasi:** Ganti `_offset` setState dengan `ValueNotifier`. Pecah 4 view type ke widget terpisah.

---

### 6.2 `about_app_page.dart` — `setState` per Scroll Offset

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/pages/settings_page/about_app_page.dart:70` |
| **Confidence** | High |

`setState(() => _offset = o)` merebuild seluruh halaman About hanya untuk fade appbar title.

**Rekomendasi:** `ValueNotifier<double>` + `ValueListenableBuilder` yang hanya merebuild appbar.

---

### 6.3 `ffmpeg_decoder_bridge.dart` — `StreamController` Tidak Di-close

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/native/bridges/ffmpeg_decoder_bridge.dart` |
| **Confidence** | High |

`dispose()` memanggil `_decoderInfoSub?.cancel()` tapi **tidak** `_decoderInfoCtrl.close()`. StreamController broadcast yang tidak ditutup = memory leak.

**Rekomendasi:** Tambahkan `await _decoderInfoCtrl.close();` di `dispose()`.

---

### 6.4 `MediaCapabilitiesService.dispose()` — Tidak Pernah Dipanggil

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/media_capabilities_service/service.dart:127` |
| **Confidence** | High |

`dispose()` didefinisikan tapi tidak ada satu pun lifecycle manager yang memanggilnya. Listeners tidak akan pernah dibersihkan.

**Rekomendasi:** Panggil dari app lifecycle disposal chain.

---

### 6.5 Player Sheet `build()` — Nested ValueListenableBuilder Terlalu Luas

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/widgets/player/player_sheet/state.dart:56` |
| **Confidence** | High |

`build()` berisi dua nested `ValueListenableBuilder` dan `MediaQuery.sizeOf` yang menyebabkan seluruh player sheet (background + content + controls) rebuild setiap progress update dan setiap playback state change.

**Rekomendasi:** Pecah ke sub-widget yang lebih kecil dengan builder scope yang targeted per data yang berubah.

---

### 6.6 Missing `const` Constructors

| | |
|---|---|
| **Severity** | Low |
| **Confidence** | High |

| File | Widget |
|---|---|
| `lib/pages/settings_page/body.dart` | `_SettingsBody`, `Column` |
| `lib/pages/settings_page/effect_status.dart` | `_EffectStatusRow` |
| `lib/pages/settings_page/session_info.dart` | `_AudioSessionInfo` |
| `lib/widgets/common/scrolling_page_chrome/app_bar.dart:53` | `Text` (TextStyle sudah const) |
| `lib/widgets/pages/browse_sections/section.dart` | `Icon` |
| `lib/widgets/pages/library_sections/detail.dart` | `TextStyle` instances |
| `lib/widgets/pages/home/albums_section/card.dart` | `SizedBox` |

**Rekomendasi:** Enable `prefer_const_constructors` di `analysis_options.yaml` dan jalankan `dart fix`.

---

### 6.7 Silent `catch (_)` Blocks — 20+ Lokasi

| | |
|---|---|
| **Severity** | Medium |
| **Confidence** | High |

| File | Risiko |
|---|---|
| `lib/pages/playlist_page.dart:85` | Playlist load failure diam-diam |
| `lib/pages/settings/equalizer_page/band_slider.dart:79` | EQ error tersembunyi |
| `lib/services/audio/media3/media3_playback_bridge.dart` | 4 lokasi, playback error diabaikan |
| `lib/services/audio/playback_manager.dart:279, 822` | Native DSP call failures |
| `lib/services/artwork_repository.dart` | 3 lokasi |
| `lib/widgets/pages/home/albums_section/state.dart` | Home section kosong diam-diam |
| `lib/widgets/common_actions.dart` | Rescan failure (ada SnackBar, tapi inner catch diam) |

**Rekomendasi:** Minimal `LogService.e(...)` di setiap catch block. Jangan swallow error tanpa trace.

---

## Kategori 7: Performance Audit

### 7.1 `ThemeController._save()` — `SharedPreferences.getInstance()` per Setter

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/themes/theme_controller.dart:97` |
| **Confidence** | High |

Setiap toggle switch memanggil `SharedPreferences.getInstance()` via platform channel. Instance bisa di-cache sekali saat `load()`.

**Rekomendasi:** Cache `SharedPreferences` instance sebagai static field.

---

### 7.2 Unsafe Array Access `cached[2]`/`colors[2]` — Album Card

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/widgets/pages/home/albums_section/card.dart:35,43` |
| **Confidence** | High |

```dart
setState(() => _bgColor = cached[2]);  // line 35
setState(() => _bgColor = colors[2]);  // line 43
```
Jika `PaletteExtractor` mengembalikan < 3 warna (artwork solid / sangat kecil), ini throw `RangeError` dan crash.

**Rekomendasi:** `cached.elementAtOrNull(2) ?? cached.last` atau guard `if (cached.length > 2)`.

---

### 7.3 `SongMetadataService` — Sync I/O

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/song_metadata_service/service.dart` |
| **Confidence** | Medium |

`_mtimeMs()` dan `_fileSizeBytes()` menggunakan sync file operations. Di library besar, loop ini bisa block isolate.

**Rekomendasi:** Gunakan async equivalents atau batch ke background isolate saat full library scan.

---

### 7.4 `ShaderMask` di Lyrics Overlay — Aktif Saat Tidak Perlu

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/widgets/player/player_content/lyrics_overlay.dart:80` |
| **Confidence** | Medium |

`ShaderMask` digunakan untuk fading effect. GPU-intensive operation yang seharusnya non-aktif saat lyrics hidden atau fully scrolled.

**Rekomendasi:** Pastikan `ShaderMask` hanya dirender saat lyrics benar-benar visible dan ada konten untuk di-fade.

---

### 7.5 `lerpDouble` di dalam `AnimatedPositioned` — Redundant Computation

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/widgets/player/player_content/content.dart:470` |
| **Confidence** | Medium |

`lerpDouble` digunakan di dalam `AnimatedPositioned` yang sudah handle interpolasi secara internal. Perhitungan ganda yang tidak perlu.

---

### 7.6 `fog_painter.dart` — Variable Names Cryptic

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/widgets/player/player_background/fog_painter.dart:53-59` |
| **Confidence** | High |

Variable `_o0r`, `_o0g`, `_o0b`, `_c1r`, `_c1g`, `_c1b` adalah nilai warna RGB yang sangat sulit dibaca. Bukan masalah performa tapi maintainability sangat buruk.

**Rekomendasi:** Rename ke nama deskriptif atau gunakan `Color` object.

---

### 7.7 Lyrics Provider — Regex Tidak Di-cache

| | |
|---|---|
| **Severity** | Low |
| **File** | `AppleMusicProvider`, `LrclibProvider` |
| **Confidence** | Medium |

String manipulations (RegExp, Split) dijalankan ulang setiap fetch.

**Rekomendasi:** Cache compiled `RegExp` sebagai `static final`.

---

## Kategori 8: Null Safety Audit

### 8.1 CRASH BUG: Color Picker `'Putih'` → `Colors.black`

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/widgets/player/player_content/lyrics_pickers.dart:112` |
| **Confidence** | High |

```dart
(label: 'Putih', color: Colors.black, value: 'white'),
```
Label `'Putih'` (putih/white) di-map ke `Colors.black`. User yang memilih warna "Putih" di color picker lirik akan mendapatkan warna hitam. Ini **display bug** yang aktif.

**Rekomendasi:** Ubah ke `Colors.white`.

---

### 8.2 Unsafe Array Access `cached[2]`/`colors[2]`

*(Sudah dibahas di 7.2 — sekaligus bounds safety issue)*

---

### 8.3 `ModalRoute.of(context)!` — 2 Halaman

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/pages/album_page.dart`, `lib/pages/artist_page.dart` |
| **Confidence** | High |

Force unwrap `ModalRoute.of(context)!` yang akan crash jika halaman di-push tanpa ModalRoute.

**Rekomendasi:** Gunakan `ModalRoute.of(context)?.settings.arguments` dengan null fallback.

---

### 8.4 `widget.userPlaylist!` / `widget.smartType!` — `playlist_page.dart`

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/pages/playlist_page.dart:69,71,114,162,195` |
| **Confidence** | High |

5 force unwrap pada optional constructor parameters. Crash jika navigasi tanpa parameter yang benar.

**Rekomendasi:** Guard di `initState`: early return atau `Navigator.pop()` jika kedua parameter null.

---

### 8.5 `_current!` di `player_content/content.dart:82`

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/widgets/player/player_content/content.dart:82` |
| **Confidence** | High |

Force unwrap static `_current!` dalam static method. Race condition selama dispose bisa menyebabkan crash.

**Rekomendasi:** Guard dengan null check sebelum unwrap, atau gunakan `_current?.method()`.

---

### 8.6 `nextSong!` di `player_up_next_card.dart:69`

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/widgets/player/player_up_next_card.dart:69` |
| **Confidence** | Medium |

`nextSong` adalah nullable (`null` jika tidak ada lagu berikutnya). Meski ada boolean `visible` sebagai guard, unwrap `nextSong!` di dalam `_UpNextCardContent(song: nextSong!)` bisa race jika playlist berubah antara check dan build.

**Rekomendasi:** Gunakan `if (nextSong == null) return const SizedBox.shrink();` sebelum unwrap.

---

### 8.7 `stats!` di `playback_engine.dart` — Dalam Null-check Guard

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/pages/settings_page/playback_engine.dart:82,88,94,100` |
| **Confidence** | High |

Force unwrap `stats!` meski sudah ada null check di atas. Gunakan local shadowing: `final s = stats; if (s == null) return; ... s['key']`.

---

### 8.8 `songMap[id]!` — `recently_played_section.dart:45`

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/widgets/pages/home/recently_played_section.dart:45` |
| **Confidence** | High |

Force unwrap meski ada guard. Lebih aman dengan `whereType<LocalSong>()`.

---

### 8.9 Unsafe Type Cast di Lyrics Providers

| | |
|---|---|
| **Severity** | Medium |
| **File** | Semua online providers |
| **Confidence** | High |

Frequent `as List`, `as Map`, `entry['trackId'] as int?` tanpa fallback. Jika API schema berubah, `TypeError` tidak tertangkap.

**Rekomendasi:** Gunakan `(data['key'] as num?)?.toInt()` atau try-catch per field.

---

### 8.10 Force Unwrap Umum — 264 Instance

| | |
|---|---|
| **Severity** | Medium |
| **Confidence** | High |

264 instance `!` total. Yang paling berisiko crash sudah dibahas di 8.1–8.9. Sisanya perlu review per-case.

---

## Kategori 9: Naming Audit

### 9.1 `lib/Bottom NavBar/` — Spasi dalam Nama Folder

*(Sudah dibahas di 2.1)*

---

### 9.2 `webViewContainer.dart` — camelCase Filename

| | |
|---|---|
| **Severity** | Medium |
| **Confidence** | High |

Satu-satunya file dengan camelCase nama. Dart style guide: `lowercase_with_underscores` untuk semua filename.

**Rekomendasi:** Rename ke `web_view_container.dart`.

---

### 9.3 `fog_painter.dart` — Cryptic Variable Names

*(Sudah dibahas di 7.6)*

---

### 9.4 Parameter `v` Non-Deskriptif di `ThemeController`

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/themes/theme_controller.dart:46-91` |
| **Confidence** | High |

Semua setter menggunakan `v` sebagai nama parameter: `static Future<void> setGlassTheme(bool v)`.

**Rekomendasi:** Rename ke `enabled` atau `value`.

---

### 9.5 Untyped `List` di Data Files

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/utils/data/browse_banners.dart`, `search_categories.dart` |
| **Confidence** | High |

`final List browseBanners = [...]` dan `final List searchCategories = [...]` tanpa generic type. Seharusnya `List<Map<String, dynamic>>`.

**Rekomendasi:** Tambahkan generic type untuk type safety.

---

### 9.6 `_LibraryDestination` — Singular/Plural Inconsistency

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/widgets/pages/library_sections/` |
| **Confidence** | High |

Enum values menggunakan nama singular untuk beberapa item dan plural untuk lainnya.

---

### 9.7 Magic Numbers di Library Sections

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/widgets/pages/library_sections/detail.dart` dll. |
| **Confidence** | High |

`bottomClearance: 64.5` dan `_kLibraryControlsHeight: 140` digunakan di beberapa file tanpa central constant. `lib/utils/constants.dart` sudah ada dan bisa digunakan.

**Rekomendasi:** Tambahkan ke `constants.dart`.

---

## Kategori 10: Dependency Audit

### Semua Package Digunakan ✓

| Package | Status | Lokasi |
|---|---|---|
| `text_scroll` | ✓ | `player_content/content.dart` |
| `cupertino_icons` | ✓ | Flutter standard |
| `http` | ✓ | Semua lyrics online providers |
| `cached_network_image` | ✓ | Artwork display |
| `audio_session` | ✓ | `audio_session_handler` |
| `permission_handler` | ✓ | Storage permissions |
| `shared_preferences` | ✓ | Queue persistence, settings, theme |
| `rxdart` | ✓ | Stream merging di berbagai service |
| `path` | ✓ | File path operations |
| `path_provider` | ✓ | Artwork cache storage |
| `scrollable_positioned_list` | ✓ | Lyrics view + queue overlay |
| `palette_generator_plus` | ✓ | `palette_extractor.dart` |
| `url_launcher` | ✓ | Settings about page, bug report |
| `font_awesome_flutter` | ✓ | `about_app_page.dart` — social icons |

**Tidak ada package yang unused.**

---

## Kategori 11: Asset Reference Audit

### 11.1 KRITIS: `assets/1.jpg`, `2.jpg`, `4.jpg` Tidak Dideklarasi di `pubspec.yaml`

| | |
|---|---|
| **Severity** | Critical |
| **Confidence** | High |

`browse_banners.dart` mereferensikan `assets/1.jpg`, `assets/2.jpg`, `assets/4.jpg`. Tapi `pubspec.yaml` hanya mendeklarasikan `assets/images/` dan `assets/images/search/`. File di root `assets/` **tidak tercakup** — Flutter tidak akan bundle mereka. Browse section banners **tidak bisa tampil** di release build.

**Rekomendasi:** Tambahkan ke pubspec:
```yaml
assets:
  - assets/1.jpg
  - assets/2.jpg
  - assets/4.jpg
  - assets/images/
  - assets/images/search/
```

---

### 11.2 Semua Font, Shader, dan Asset Images Digunakan ✓

5 weight SF Pro Text semuanya digunakan. Shader `fluid.frag` digunakan oleh `artwork.dart:72`. Semua file di `assets/images/search/` direferensikan via `searchCategories` data.

---

## Kategori 12: Routing Audit

### 12.1 `RadioPage` Aktif tapi Data Kosong

*(Sudah dibahas di 1.6)*

---

### 12.2 `radio_sections` Merender Widget Meski Data Kosong

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/widgets/pages/radio_sections/stations.dart:98` |
| **Confidence** | High |

`_SmartPlaylistCardWidget` selalu dirender. Jika kosong, tampil placeholder gelap "Belum ada lagu" — UX membingungkan di tab radio.

**Rekomendasi:** Terapkan empty state lebih jelas atau sembunyikan widget saat data kosong.

---

### 12.3 Semua Route Dapat Diakses ✓

Semua halaman reachable. `ZoomFadeRoute` digunakan secara konsisten di 10+ lokasi navigasi. Tidak ada orphan route.

---

## Kategori 13: Service Audit

### 13.1 `AudioFocusService` + Empty Stubs

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/audio_focus_service.dart` |
| **Confidence** | High |

Service diinisialisasi di `main.dart` dan memanggil stub methods yang tidak melakukan apa-apa. Init overhead tanpa manfaat.

**Rekomendasi:** Evaluasi apakah service ini masih diperlukan. Jika tidak, hapus.

---

### 13.2 `MediaCapabilitiesService.dispose()` Tidak Pernah Dipanggil

*(Sudah dibahas di 6.4)*

---

### 13.3 Semua Service Utama Aktif dan Dikonsumsi ✓

| Service | Status |
|---|---|
| `ReplayGainService` | ✓ Dikonsumsi oleh `LoudnessSourceResolver` |
| `SongMetadataService` | ✓ Dikonsumsi oleh `ReplayGainService` |
| `HistoryService` | ✓ warmUp di main, trackPlay di AudioService |
| `ArtworkRepository` | ✓ 3-layer cache, prewarm di main |
| `LyricsService` | ✓ Full multi-provider aktif |
| `PaletteExtractor` | ✓ Player background + warmUp di main |
| `ScrollToTopService` | ✓ BottomNav + 4 halaman utama |
| `PlaylistService` | ✓ `playlist_page.dart`, `radio_sections/stations.dart` |
| `ZoomFadeRoute` | ✓ 10+ lokasi navigasi |

---

## Kategori 14: Public API Audit

### 14.1 DSP Setters Seharusnya Private di `PlaybackManager`

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/audio/playback_manager.dart` |
| **Confidence** | High |

`setNativeGainDb()`, `setNativeCompressorBypass()`, `resetNativeLoudnessNorm()` dll. adalah public tapi detail implementasi internal.

**Rekomendasi:** Prefix `_` atau annotate `@internal`.

---

### 14.2 `NativeLogBridge` — Bridge Methods Seharusnya Private

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/services/log_service/native_log_bridge.dart` |
| **Confidence** | Medium |

Bridge methods public tapi hanya untuk `LogService`.

---

### 14.3 `NativeDspBridge` Stub Methods — Public Tapi Tidak Berfungsi

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/services/native/bridges/native_dsp_bridge.dart` |
| **Confidence** | High |

`applyPreset`, `setBandGain`, `setEnabled`, `registerProcessor` adalah public stubs yang tidak melakukan apa-apa.

**Rekomendasi:** Annotate dengan `@experimental` atau pindahkan ke interface saja.

---

## Kategori 15: Consistency Audit

### 15.1 Dua Widget Toggle Parallel — `_GlassSubToggle` vs `SettingsToggleRow`

| | |
|---|---|
| **Severity** | Medium |
| **File** | `glass_toggle.dart`, `settings_widgets/toggle.dart` |
| **Confidence** | High |

`_GlassSubToggle` dipakai 9x di `appearance.dart`. `SettingsToggleRow` di `settings_widgets/toggle.dart` fungsinya hampir sama. Dua implementasi toggle untuk tujuan yang serupa.

**Rekomendasi:** Tambahkan optional `leadingIcon` ke `SettingsToggleRow` dan ganti `_GlassSubToggle`.

---

### 15.2 Dua Widget Info Line Parallel — `_InfoLine` vs `SettingsInfoRow`

| | |
|---|---|
| **Severity** | Low |
| **File** | `info_line.dart`, `settings_widgets/info.dart` |
| **Confidence** | High |

`_InfoLine` dan `SettingsInfoRow` keduanya menampilkan label-value pair dengan layout sedikit berbeda.

**Rekomendasi:** Konsolidasikan ke satu widget dengan variant layout.

---

### 15.3 Settings Tersebar di Dua Folder

*(Sudah dibahas di 5.11)*

---

### 15.4 Mixed Part/Import Pattern

| | |
|---|---|
| **Severity** | Low |
| **Confidence** | High |

Beberapa modul menggunakan `part`/`part of`, yang lain tidak. Pola tidak konsisten di seluruh project.

---

### 15.5 Untyped `List` di Data Files

*(Sudah dibahas di 9.5)*

---

---

## Final Summary

### Statistik

| Metrik | Jumlah |
|---|---|
| **Total file Dart diaudit** | **263 / 263 (100%)** |
| Total folder diaudit | 35+ |
| Dead code / placeholder ditemukan | **14** |
| File kosong / tidak berguna | **7** (`chip.dart`, `sleep_timer.dart`, `lyrics.dart`, `lyrics_rows.dart`, `notif_icon.dart`, `sample_music_data.dart`, `FutureLocalSongCarousel` class) |
| File dengan test salah | **1** (`test/widget_test.dart`) |
| Bug aktif (crash / display error) | **4** (asset undeclared, `cached[2]` RangeError, `Colors.black` label Putih, `_cast()` silent no-op) |
| Architecture issue | **11** |
| Performance issue | **7** |
| Maintainability issue | **9** |
| Potential crash (force unwrap) | **8** |
| Unused package | **0** |
| Dead parameter di widget | **5** (WebView) + 1 FFI binding |

---

### Prioritas Perbaikan (Risk-Based)

| Pri | Temuan | Severity | Risiko |
|---|---|---|---|
| 🔴 1 | **`assets/1.jpg`/`2.jpg`/`4.jpg` tidak dideklarasi di pubspec** | Critical | Browse banner tidak tampil di release build |
| 🔴 2 | **`'Putih'` → `Colors.black` di color picker lirik** | High | Display bug aktif — white option tampil hitam |
| 🔴 3 | **`cached[2]`/`colors[2]` unsafe array index** | High | `RangeError` crash pada artwork dengan < 3 warna |
| 🔴 4 | **`ModalRoute.of(context)!`** di album/artist page | High | Crash di edge case navigation |
| 🔴 5 | **`widget.userPlaylist!`/`widget.smartType!`** (5x) di playlist_page | High | Crash jika navigasi tanpa parameter |
| 🔴 6 | **`_current!` static di player_content** | High | Crash saat rapid navigation/dispose |
| 🔴 7 | **`test/widget_test.dart` adalah default counter test** | High | CI fail, zero real test coverage |
| 🔴 8 | **Folder `lib/Bottom NavBar/` dengan spasi** | High | URL-encoded import, build fragility |
| 🟡 9 | **`BootTrace` — 74 refs TEMPORARY** | High | Production overhead, code noise |
| 🟡 10 | **`_cast()` TODO di `CommonActions` — tombol di 5 halaman** | Medium | User tap tombol, tidak ada respons |
| 🟡 11 | **`_decoderInfoCtrl` StreamController tidak di-close** | Medium | Memory leak |
| 🟡 12 | **`MediaCapabilitiesService.dispose()` tidak pernah dipanggil** | Medium | Listener leak |
| 🟡 13 | **God files** (detail.dart 576L, log_page 889L, audio 869L, playback_manager 833L) | High | Maintainability debt |
| 🟡 14 | **Duplicate HTTP logic di 7 lyrics providers** | High | Bug fix tidak propagate antar provider |
| 🟡 15 | **`ThemeController._save()` — platform channel per toggle** | Medium | Unnecessary overhead |
| 🟡 16 | **20+ silent `catch (_)` blocks** | Medium | Error tersembunyi, debug sulit |
| 🟡 17 | **Player sheet build scope terlalu luas** | Medium | Unnecessary full-sheet rebuild |
| 🟡 18 | **Settings tersebar di dua folder** | Medium | Developer confusion |
| 🟡 19 | **RadioPage tab aktif, data kosong** | Medium | Bad UX |
| 🟡 20 | **`nextSong!` force unwrap di up_next_card** | Medium | Potential race condition crash |
| 🟢 21 | **7 file settings kosong / dead** | Medium | Dead code clutter |
| 🟢 22 | **`FutureLocalSongCarousel` dead class** | Medium | Unreachable code |
| 🟢 23 | **`WebView` — 5 dead parameters** | Medium | API surface misleading |
| 🟢 24 | **`_GlassSubToggle` duplikat `SettingsToggleRow`** | Medium | Inconsistency |
| 🟢 25 | **`setState` per scroll tick** di about_app + detail.dart | Medium | Unnecessary rebuilds |
| 🟢 26 | **`NativeModuleRegistry.initializeAll()` sequential** | Medium | Startup lebih lambat |
| 🟢 27 | **Untyped `List` di browse_banners / search_categories** | Low | Type safety |
| 🟢 28 | **Unsafe type cast di lyrics providers** | Medium | TypeError jika API schema berubah |
| 🟢 29 | **Missing `const` constructors** (7+ lokasi) | Low | Minor rebuild inefficiency |
| 🟢 30 | **`fog_painter.dart` cryptic variable names** | Low | Maintainability |
| 🟢 31 | **`native_runtime_last_status()` unused FFI binding** | Low | Dead symbol |
| 🟢 32 | **`webViewContainer.dart` camelCase filename** | Low | Style violation |
| 🟢 33 | **Magic numbers di library sections** | Low | Maintainability |
| 🟢 34 | **`NativeDspBridge` stubs public tapi tidak berfungsi** | Low | Misleading API |

---

*Audit dilakukan dalam 3 round menggunakan subagent paralel + verifikasi grep/shell per temuan kritis.*  
*Round 1: dead code, architecture, imports, routing, flutter perf, services, native, themes (area utama).*  
*Round 2: themes, native bridges, 12 service/provider files, 30+ widget/page files, semua settings files.*  
*Round 3: semua player widgets (38 file), utils, misc services, Bottom NavBar, webView, native_audio_runtime.*
