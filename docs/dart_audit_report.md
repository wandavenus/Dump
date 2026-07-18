# Comprehensive Dart Codebase Audit Report

**Tanggal:** 18 Juli 2026  
**Versi App:** 1.2.3+1  
**Total file Dart diaudit:** 263 (seluruh `lib/`, `test/`, `native_audio_runtime/lib/`)  
**Metode:** Baca langsung per-file via subagent + verifikasi grep/shell

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

**Rekomendasi:** Hapus file ini. Jika khawatir breaking library structure, cukup hapus `part 'sleep_timer.dart'` dari `settings_page.dart`.

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

`_NotifIconRow` didefinisikan dengan `// ignore_for_file: unused_element` — artinya author sendiri sadar ini tidak dipakai. Tidak ditemukan satu pun instantiasi di seluruh codebase. `_DebugState.notifIcons` dan `_DebugState.notifIcon` di `debug_state.dart` juga hanya dikonsumsi oleh widget ini.

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

### 1.8 `NativeDspBridge` — Empty Stub Methods

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/services/native/bridges/native_dsp_bridge.dart` |
| **Confidence** | High |

Method `applyPreset()`, `setBandGain()`, `setEnabled()`, `registerProcessor()` semuanya adalah empty stubs/no-ops dengan TODO. Ini adalah Phase 3 placeholder yang terdokumentasi, jadi bukan bug, tapi perlu perhatian.

**Rekomendasi:** Pastikan UI yang bergantung pada `queryCapabilities()` menampilkan state yang benar. Tidak mendesak karena sudah terdokumentasi.

---

### 1.9 `lib/services/audio/audio_session_handler/handler.dart` — Empty Stub Methods

| | |
|---|---|
| **Severity** | Low |
| **Confidence** | High |

`onAppPause()` dan `onAppResume()` adalah empty stubs. Native Media3 sudah menangani audio focus secara mandiri. Dipanggil dari `AudioFocusService` tapi tidak ada efek.

**Rekomendasi:** Hapus kedua method ini dan panggilan terkait di `AudioFocusService`.

---

### 1.10 `lib/widgets/pages/home/albums_section/state.dart` — Empty Catch Block

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/widgets/pages/home/albums_section/state.dart` |
| **Confidence** | High |

`catch (_)` yang mengabaikan semua error dari `MediaStoreService`. Jika gagal, section home albums akan diam-diam tampil kosong tanpa indikasi apapun.

**Rekomendasi:** Minimal log error ke `LogService`.

---

## Kategori 2: Folder Audit

### 2.1 `lib/Bottom NavBar/` — Folder Name dengan Spasi

| | |
|---|---|
| **Severity** | High |
| **Confidence** | High |

Folder menggunakan spasi dalam nama, melanggar konvensi Dart/Flutter (`snake_case`). Akibatnya import menggunakan URL encoding:
```dart
import 'package:musicplayer/Bottom%20NavBar/bottom_nav.dart';
```
Fragil di beberapa tools, tidak standar, dan menyulitkan refactor.

**Rekomendasi:** Rename ke `lib/bottom_nav/`, update 2 import (`lib/main.dart`, `lib/main.dart` — keduanya mengacu ke file yang sama).

---

### 2.2 `lib/webView/` — Single-File Folder

| | |
|---|---|
| **Severity** | Low |
| **Confidence** | High |

Folder hanya berisi satu file: `webViewContainer.dart`. Widget `WebView` ini digunakan sebagai layout wrapper. Folder isolasi berlebihan.

**Rekomendasi:** Pindahkan ke `lib/widgets/common/web_view_container.dart`.

---

## Kategori 3: File Audit

### 3.1 `test/widget_test.dart` — Default Template Test yang Salah

| | |
|---|---|
| **Severity** | High |
| **Confidence** | High |

Ini adalah **default Flutter counter app test** hasil `flutter create`. Mencari `find.text('0')`, `find.text('1')`, `find.byIcon(Icons.add)` — tidak ada satupun di music player ini. Test ini **pasti gagal** jika dijalankan.

**Rekomendasi:** Hapus atau replace dengan smoke test yang sesuai (misal: verify `MyApp` render tanpa crash dalam kondisi mock).

---

### 3.2 File Settings Kosong (`chip.dart`, `sleep_timer.dart`, `lyrics.dart`, `lyrics_rows.dart`)

*(Sudah dibahas di Kategori 1.2–1.4)*

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
Non-standard, berpotensi bermasalah di beberapa versi Dart analyzer.

**Rekomendasi:** Fix root cause — rename folder (lihat 2.1).

---

### 4.2 Duplicate `DateTime.now()` dalam `build()`

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/pages/settings_page/about.dart:48`, `about_app_page.dart:82` |
| **Confidence** | High |

`DateTime.now().year` dipanggil di dalam `build()`. Setiap rebuild mengalokasikan `DateTime` baru yang tidak perlu.

**Rekomendasi:** Hitung sekali di `initState()` atau sebagai constant.

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
| `lib/widgets/pages/library_sections/detail.dart` | **576** | 4 view type (Artist/Album/Songs/Playlist) dalam satu widget + search + sort |

**Dampak:** Sulit di-maintain, high merge conflict risk, cognitive load tinggi.

**Rekomendasi:**
- `detail.dart`: Pecah per view type ke widget terpisah, ekstrak sort/filter logic ke controller.
- `log_page.dart`: Ekstrak filter ke `LogFilter` class, detail sheet ke file terpisah.
- `audio.dart`: Pecah per section (normalization, EQ, engine).
- `playback_manager.dart`: Pertimbangkan facade tipis + sub-manager terpisah.

---

### 5.2 `NativeModuleRegistry.initializeAll()` — Sequential Loop

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/native/native_module_registry.dart:38-63` |
| **Confidence** | High |

`initializeAll()` menggunakan `for` loop sequential. Module DSP dan FFmpeg tidak saling bergantung, sehingga bisa diinisialisasi paralel.

**Rekomendasi:** Ganti dengan `Future.wait(_modules.map((m) => m.initialize()))` jika tidak ada ordering dependency antar module.

---

### 5.3 `NativeModuleRegistry.disposeAll()` — Error Swallowing

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/native/native_module_registry.dart:68` |
| **Confidence** | High |

`disposeAll()` membungkus setiap dispose dalam try-catch yang mengabaikan semua error. Jika disposal gagal, tidak ada indikasi sama sekali.

**Rekomendasi:** Minimal log error ke `LogService` saat disposal gagal, meski tidak re-throw.

---

### 5.4 Massive Duplicate Logic — Lyrics Providers

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/services/lyrics_service/providers/` (7 provider online) |
| **Confidence** | High |

Tujuh provider online (`AppleMusic`, `Kugou`, `Kuwo`, `NetEase`, `QQ`, `LRCLIB`, `Netease`) menduplikasi pola yang sama: HTTP handling, retry logic, rate limiting (429 check), JSON parsing. Inkonsistensi penanganan 429:
- `AppleMusicProvider`: cek 429 (baris ~81)
- `NetEaseProvider`: hanya cek 200 (baris ~50), 429 tidak di-handle

**Dampak:** Bug di satu provider tidak otomatis diperbaiki di provider lain. Sulit menambah provider baru secara konsisten.

**Rekomendasi:** Buat `AbstractOnlineLyricsProvider` yang menghandle HTTP/retry/rate-limiting. Setiap provider hanya perlu implement method `buildUrl()` dan `parseResponse()`.

---

### 5.5 `ReplayGainService` — Duplikat Method Internal

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/replay_gain_service/service.dart` |
| **Confidence** | Medium |

`_readRawTags()` dan `_readTagsNative()` hampir identik dalam struktur. Keduanya membaca metadata audio dengan cara yang berbeda tapi sangat mirip pola kodenya.

**Rekomendasi:** Refactor ke satu method dengan parameter yang membedakan source.

---

### 5.6 `ThemeController` — Mixed Responsibilities

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/themes/theme_controller.dart` |
| **Confidence** | High |

Class mencampur: state management (ValueNotifiers), persistence (SharedPreferences), dan UI logic. Private constructor `ThemeController._()` didefinisikan tapi class hanya gunakan static members — constructor tidak pernah bisa dipanggil secara eksternal.

**Rekomendasi:** Jadikan class `abstract` untuk mencegah instantiasi yang tidak perlu. Pertimbangkan memisahkan persistence layer.

---

### 5.7 Fragile Startup Chain — 20+ Service Init

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/main/main.dart` |
| **Confidence** | High |

Sequential init 20+ service dengan urutan ketat + 74 BootTrace log tersebar di antaranya. Menambah service baru atau mengubah urutan bisa menyebabkan crash yang sulit di-debug.

**Rekomendasi:** Kelompokkan service ke dalam init phases eksplisit. Setelah BootTrace dihapus, urutan lebih mudah diaudit.

---

### 5.8 Layer Violation — UI Memanggil Service Langsung

| | |
|---|---|
| **Severity** | Medium |
| **Confidence** | High |

Halaman UI (`playlist_page.dart`, `equalizer_page.dart`, `audio.dart`) mengimport dan memanggil `AudioService`, `AudioEffectsService`, `PlaybackManager`, `MediaStoreService` langsung. Ini pola umum di Flutter tanpa state management library, jadi tidak harus diubah sekarang.

**Rekomendasi:** Pertimbangkan ViewModel/Controller terpisah untuk halaman-halaman besar (>500 baris).

---

### 5.9 Duplikat Scroll Pattern di 3 Pages

| | |
|---|---|
| **Severity** | Low |
| **File** | `album_page.dart`, `artist_page.dart`, `music_list.dart` |
| **Confidence** | High |

Ketiga halaman mengimplementasikan pola identik: `ScrollController` + `_scrollOffset` + `ScrollToTopService.signal(n).addListener` di initState/dispose.

**Rekomendasi:** Ekstrak ke mixin `ScrollToTopMixin`.

---

### 5.10 Settings Code Tersebar di Dua Folder

| | |
|---|---|
| **Severity** | Medium |
| **Confidence** | High |

Settings-related code ada di:
- `lib/pages/settings/` — `equalizer_page/`, `settings_widgets/`, `sleep_timer_page/`
- `lib/pages/settings_page/` — `audio.dart`, `appearance.dart`, `lyrics.dart`, dll.

Plus `lib/pages/settings_page.dart` sebagai entry point. Tiga lokasi untuk satu fitur.

**Rekomendasi:** Konsolidasikan ke satu struktur folder. Ini pekerjaan besar — prioritaskan setelah dead file cleanup.

---

## Kategori 6: Flutter Best Practices

### 6.1 `library_sections/detail.dart` — God Widget + `setState` per Scroll Tick

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/widgets/pages/library_sections/detail.dart` |
| **Confidence** | High |

**576 baris** dalam satu widget yang menangani 4 view type berbeda (Artist, Album, Songs, Playlist), search, filter, sort, dan playback logic. Di baris 38-70, `setState(() => _offset = o)` dipanggil pada setiap scroll event dengan threshold 0.5 — masih sangat sering di scroll cepat.

**Rekomendasi:** Ganti `_offset` `setState` dengan `ValueNotifier`. Pecah 4 view type ke widget terpisah.

---

### 6.2 `about_app_page.dart` — `setState` pada Setiap Scroll Offset

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/pages/settings_page/about_app_page.dart:70` |
| **Confidence** | High |

```dart
if ((o - _offset).abs() > 0.5) setState(() => _offset = o);
```
Merebuild seluruh halaman About hanya untuk appbar fade effect.

**Rekomendasi:** Gunakan `ValueNotifier<double>` + `ValueListenableBuilder` yang hanya merebuild appbar section.

---

### 6.3 `ffmpeg_decoder_bridge.dart` — `StreamController` Tidak Di-close

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/native/bridges/ffmpeg_decoder_bridge.dart` |
| **Confidence** | High |

`dispose()` hanya memanggil `_decoderInfoSub?.cancel()` tapi tidak memanggil `_decoderInfoCtrl.close()`. StreamController broadcast yang tidak ditutup menyebabkan memory leak.

**Rekomendasi:** Tambahkan `await _decoderInfoCtrl.close();` di `dispose()`.

---

### 6.4 `MediaCapabilitiesService.dispose()` — Tidak Pernah Dipanggil

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/media_capabilities_service/service.dart:127` |
| **Confidence** | High |

`dispose()` didefinisikan (line 127) tapi tidak ada satu pun lifecycle manager yang memanggilnya. Listeners/subscriptions yang di-register di service ini tidak akan pernah dibersihkan.

**Rekomendasi:** Panggil `MediaCapabilitiesService.dispose()` dari app lifecycle disposal chain.

---

### 6.5 Missing `const` Constructors

| | |
|---|---|
| **Severity** | Low |
| **Confidence** | High |

Banyak widget yang bisa di-`const` tapi tidak:

| File | Widget |
|---|---|
| `lib/pages/settings_page/body.dart` | `_SettingsBody`, `Column` |
| `lib/pages/settings_page/effect_status.dart` | `_EffectStatusRow` |
| `lib/pages/settings_page/session_info.dart` | `_AudioSessionInfo` |
| `lib/widgets/common/scrolling_page_chrome/app_bar.dart:53` | `Text` (TextStyle sudah const tapi Text-nya tidak) |
| `lib/widgets/pages/browse_sections/section.dart` | `Icon` |
| `lib/widgets/pages/library_sections/detail.dart` | `TextStyle` instances |
| `lib/widgets/pages/home/albums_section/card.dart` | `SizedBox` |

**Rekomendasi:** Enable `prefer_const_constructors` linter rule di `analysis_options.yaml` dan jalankan `dart fix`.

---

### 6.6 Empty & Silent Catch Blocks

| | |
|---|---|
| **Severity** | Medium |
| **Confidence** | High |

Ditemukan 20+ `catch (_)` atau `catch (e) {}` yang mengabaikan error:

| File | Risiko |
|---|---|
| `lib/pages/playlist_page.dart:85` | Playlist load failure diam-diam |
| `lib/pages/settings/equalizer_page/band_slider.dart:79` | EQ error tersembunyi |
| `lib/services/audio/media3/media3_playback_bridge.dart` | 4 lokasi, playback error diabaikan |
| `lib/services/audio/playback_manager.dart:279, 822` | Native DSP call failures |
| `lib/widgets/pages/home/albums_section/state.dart` | Home section tampil kosong diam-diam |

**Rekomendasi:** Minimal `LogService.e(...)` di setiap catch block. Jangan swallow error tanpa trace.

---

## Kategori 7: Performance Audit

### 7.1 `ThemeController._save()` — `SharedPreferences.getInstance()` per Setter

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/themes/theme_controller.dart:97` |
| **Confidence** | High |

Setiap setter (`setGlassNavBar`, `setGlassAppBar`, dll.) memanggil `SharedPreferences.getInstance()` secara async. Ini memanggil platform channel setiap kali user toggle switch, padahal instance bisa di-cache sekali saat `ThemeController.load()`.

**Rekomendasi:** Cache `SharedPreferences` instance sebagai static field setelah `load()` pertama kali.

---

### 7.2 `unsafe Array Access` — `cached[2]`/`colors[2]` di Album Card

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/widgets/pages/home/albums_section/card.dart:35,43` |
| **Confidence** | High |

```dart
setState(() => _bgColor = cached[2]);  // line 35
setState(() => _bgColor = colors[2]);  // line 43
```
Jika `PaletteExtractor` mengembalikan kurang dari 3 warna (edge case: album artwork solid warna / gambar sangat kecil), ini throw `RangeError` dan crash.

**Rekomendasi:** Gunakan `cached.length > 2 ? cached[2] : cached.last` atau `elementAtOrNull(2) ?? fallbackColor`.

---

### 7.3 `SongMetadataService` — Sync I/O

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/song_metadata_service/service.dart` |
| **Confidence** | Medium |

`_mtimeMs()` dan `_fileSizeBytes()` menggunakan sync file operations. Meski per-file cepat, di library besar dengan ribuan lagu, loop ini bisa block isolate.

**Rekomendasi:** Gunakan async equivalents atau batch ke background isolate saat full library scan.

---

### 7.4 Lyrics Provider — Regex/String Manipulation Tidak Di-cache

| | |
|---|---|
| **Severity** | Low |
| **File** | `AppleMusicProvider`, `LrclibProvider` |
| **Confidence** | Medium |

String manipulations (RegExp, Split) dijalankan ulang setiap fetch. Hasil parsing bisa di-cache.

**Rekomendasi:** Cache compiled `RegExp` sebagai static final. Hasil parsing sudah di-cache oleh `LyricsCacheManager`.

---

### 7.5 `fog_painter.dart` — CustomPainter dengan Variable Cryptic

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/widgets/player/player_background/fog_painter.dart:53-59` |
| **Confidence** | High |

Variable seperti `_o0r`, `_o0g`, `_o0b`, `_c1r`, `_c1g`, `_c1b` adalah nilai warna RGB yang sangat sulit dibaca. Tidak ada dampak performa tapi maintainability sangat buruk.

**Rekomendasi:** Rename ke `_origin0Red`, `_origin0Green`, dll. atau gunakan `Color` object yang proper.

---

## Kategori 8: Null Safety Audit

### 8.1 Force Unwrap `cached[2]`/`colors[2]` — RangeError

*(Sudah dibahas di 7.2 — ini sekaligus null/bounds safety issue)*

---

### 8.2 `ModalRoute.of(context)!` — 2 Halaman

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/pages/album_page.dart`, `lib/pages/artist_page.dart` |
| **Confidence** | High |

Force unwrap `ModalRoute.of(context)!` di awal build. Jika halaman di-push tanpa ModalRoute (edge case: navigation stack manipulation), ini crash.

**Rekomendasi:** Gunakan `ModalRoute.of(context)?.settings.arguments` dengan null fallback atau guard clause di `initState`.

---

### 8.3 `widget.userPlaylist!` / `widget.smartType!` — `playlist_page.dart`

| | |
|---|---|
| **Severity** | High |
| **File** | `lib/pages/playlist_page.dart:69,71,114,162,195` |
| **Confidence** | High |

5 force unwrap pada optional constructor parameters. Jika playlist_page dinagivasi tanpa parameter yang benar, semua ini crash.

**Rekomendasi:** Guard di `initState`: `if (widget.userPlaylist == null && widget.smartType == null) { Navigator.pop(context); return; }`.

---

### 8.4 `stats!` dalam Null-check Guard — `playback_engine.dart`

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/pages/settings_page/playback_engine.dart:82,88,94,100` |
| **Confidence** | High |

```dart
// Setelah null check pada stats
(stats!['totalPlayTimeMs'] as num?)?.toInt() ?? 0)
```
Meski benar ada null check sebelumnya, force unwrap di dalam body null-check adalah code smell. Gunakan local shadowing.

**Rekomendasi:** `final s = stats; if (s == null) return; ... s['key']` — tidak perlu `!` sama sekali.

---

### 8.5 `songMap[id]!` — `recently_played_section.dart`

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/widgets/pages/home/recently_played_section.dart:45` |
| **Confidence** | High |

Force unwrap meski ada guard `where`. Gunakan `whereType<LocalSong>()` atau `?? ` pattern yang lebih aman.

---

### 8.6 Force Unwrap Umum — 264 Instance

| | |
|---|---|
| **Severity** | Medium |
| **Confidence** | High |

264 instance `!` total di codebase. Sebagian besar aman karena konteks jelas, tapi yang di atas (8.2–8.5) adalah yang paling berisiko crash di real usage.

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

*(Sudah dibahas di 7.5)*

---

### 9.4 Parameter `v` Non-Deskriptif di `ThemeController`

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/themes/theme_controller.dart:46-91` |
| **Confidence** | High |

Semua setter menggunakan `v` sebagai nama parameter: `static Future<void> setGlassTheme(bool v)`. Tidak deskriptif.

**Rekomendasi:** Rename ke `enabled` atau `value`.

---

### 9.5 `_LibraryDestination.playlist` vs `.artists` — Singular/Plural Inconsistency

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/widgets/pages/library_sections/` |
| **Confidence** | High |

Enum values menggunakan nama singular untuk beberapa item dan plural untuk lainnya.

---

### 9.6 Magic Numbers di Library Sections

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/widgets/pages/library_sections/detail.dart` dan beberapa file lain |
| **Confidence** | High |

`bottomClearance: 64.5` dan `_kLibraryControlsHeight: 140` digunakan di beberapa file tanpa central constant. Jika diubah, harus update di banyak tempat.

**Rekomendasi:** Ekstrak ke `lib/utils/constants.dart`.

---

## Kategori 10: Dependency Audit

### 10.1 Semua Package Digunakan ✓

Verifikasi semua 14 package di `pubspec.yaml`:

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
| `font_awesome_flutter` | ✓ | `about_app_page.dart` (social icons) |

**Tidak ada package yang unused.**

---

## Kategori 11: Asset Reference Audit

### 11.1 KRITIS: `assets/1.jpg`, `2.jpg`, `4.jpg` Tidak Dideklarasi di `pubspec.yaml`

| | |
|---|---|
| **Severity** | Critical |
| **Confidence** | High |

`browse_banners.dart` mereferensikan:
```dart
'img': 'assets/1.jpg'
'img': 'assets/2.jpg'
'img': 'assets/4.jpg'
```

Tapi `pubspec.yaml` hanya mendeklarasikan:
```yaml
assets:
  - assets/images/
  - assets/images/search/
```

File `assets/1.jpg`, `2.jpg`, `4.jpg` ada di root `assets/` — **tidak tercakup**. Flutter tidak bundling asset yang tidak dideklarasikan. Browse section banners **tidak bisa tampil** di build release.

**Rekomendasi:** Tambahkan ke pubspec:
```yaml
assets:
  - assets/1.jpg
  - assets/2.jpg
  - assets/4.jpg
  - assets/images/
  - assets/images/search/
```
Atau pindahkan file ke `assets/images/` dan update referensi.

---

### 11.2 `assets/images/` Tidak Berisi File Langsung

| | |
|---|---|
| **Severity** | Low |
| **Confidence** | High |

Deklarasi `assets/images/` mencakup folder yang hanya berisi subfolder `search/`. Tidak ada file langsung di `assets/images/`. Deklarasi ini redundant tapi tidak berbahaya.

---

### 11.3 Semua Font dan Shader Digunakan ✓

5 weight SF Pro Text font semuanya digunakan dalam theme system. Shader `assets/shaders/fluid.frag` digunakan oleh `artwork.dart:72`.

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

`_SmartPlaylistCardWidget` selalu dirender. Jika data kosong, tampil placeholder gelap dengan teks "Belum ada lagu". Ini UX yang membingungkan di tab yang seharusnya berisi radio stations.

**Rekomendasi:** Terapkan empty state yang lebih jelas atau sembunyikan widget jika data kosong.

---

### 12.3 Semua Route Lain Dapat Diakses ✓

`AlbumPage`, `ArtistPage`, `ArtistList`, `MusicList`, `PlaylistPage` semuanya reachable. Tidak ada halaman orphan.

---

## Kategori 13: Service Audit

### 13.1 `AudioFocusService` + Empty Stubs

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/audio_focus_service.dart` |
| **Confidence** | High |

Service diinisialisasi di `main.dart` dan memanggil `onAppPause()`/`onAppResume()` yang semuanya empty stubs. Native Media3 sudah menangani audio focus. Init overhead tanpa manfaat.

**Rekomendasi:** Evaluasi apakah `AudioFocusService` masih diperlukan. Jika tidak, hapus bersama stub methods.

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
| `PaletteExtractor` | ✓ Player background, warmUp di main |
| `ScrollToTopService` | ✓ 4+ pages |
| `PlaylistService` | ✓ playlist_page.dart |

---

## Kategori 14: Public API Audit

### 14.1 DSP Setters Seharusnya Private di `PlaybackManager`

| | |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/audio/playback_manager.dart` |
| **Confidence** | High |

Method seperti `setNativeGainDb()`, `setNativeCompressorBypass()`, `resetNativeLoudnessNorm()` adalah public tapi hanya detail implementasi internal DSP. External code bisa bypass state management internal.

**Rekomendasi:** Prefix `_` atau annotate `@internal`.

---

### 14.2 `NativeLogBridge` — Bridge Methods Seharusnya Private

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/services/log_service/native_log_bridge.dart` |
| **Confidence** | Medium |

Method bridge ke native log channel adalah public tapi hanya untuk `LogService`.

---

### 14.3 `NativeDspBridge.applyPreset()` dll. — Public Stubs

| | |
|---|---|
| **Severity** | Low |
| **File** | `lib/services/native/bridges/native_dsp_bridge.dart` |
| **Confidence** | High |

Empty stub methods (`applyPreset`, `setBandGain`, `setEnabled`, `registerProcessor`) adalah public padahal belum diimplementasi. Ini mengekspos API yang tidak berfungsi.

**Rekomendasi:** Tandai dengan `@experimental` atau `@visibleForTesting` sampai implementasi selesai.

---

## Kategori 15: Consistency Audit

### 15.1 Dua Widget Toggle Parallel — `_GlassSubToggle` vs `SettingsToggleRow`

| | |
|---|---|
| **Severity** | Medium |
| **File** | `glass_toggle.dart`, `settings_widgets/toggle.dart` |
| **Confidence** | High |

`_GlassSubToggle` (digunakan 9x di `appearance.dart`) adalah implementasi toggle custom dengan icon leading dan padding khusus. `SettingsToggleRow` di `settings_widgets/toggle.dart` melakukan hal serupa untuk settings biasa. Dua implementasi untuk tujuan yang hampir sama.

**Rekomendasi:** Tambahkan optional `leadingIcon` parameter ke `SettingsToggleRow` dan ganti `_GlassSubToggle` dengan itu.

---

### 15.2 Dua Widget Info Line Parallel — `_InfoLine` vs `SettingsInfoRow`

| | |
|---|---|
| **Severity** | Low |
| **File** | `info_line.dart`, `settings_widgets/info.dart` |
| **Confidence** | High |

`_InfoLine` (digunakan di `effect_status.dart`, `session_info.dart`) dan `SettingsInfoRow` (di `settings_widgets/info.dart`) keduanya menampilkan label-value pair. Layout sedikit berbeda tapi fungsi sama.

**Rekomendasi:** Konsolidasikan ke satu widget dengan variant layout.

---

### 15.3 Settings Tersebar di Dua Folder

*(Sudah dibahas di 5.10)*

---

### 15.4 Mixed Part/Import Pattern

| | |
|---|---|
| **Severity** | Low |
| **Confidence** | High |

Beberapa modul menggunakan `part`/`part of` (`bottom_nav/`, `music_list/`, `settings_page/`), sementara modul lain menggunakan import biasa. Tidak konsisten di seluruh project.

**Rekomendasi:** Pilih satu pola dan terapkan konsisten. Parts pattern OK untuk modul yang memang satu unit logis.

---

---

## Final Summary

### Statistik

| Metrik | Jumlah |
|---|---|
| Total file Dart diaudit | **263** |
| Total folder diaudit | **35+** |
| Dead code / placeholder | **10** |
| File kosong/tidak berguna | **6** (`chip.dart`, `sleep_timer.dart`, `lyrics.dart`, `lyrics_rows.dart`, `notif_icon.dart`, `sample_music_data.dart`) |
| File dengan test salah | **1** (`test/widget_test.dart`) |
| Naming violation | **4** |
| Architecture issue | **10** |
| Performance issue | **5** |
| Maintainability issue | **8** |
| Potential bug / crash risk | **9** |
| Asset issue | **1 Critical + 1 Low** |
| Unused package | **0** |

---

### Prioritas Perbaikan (Risk-Based)

| Pri | Temuan | Severity | Risiko |
|---|---|---|---|
| 🔴 1 | **`assets/1.jpg`/`2.jpg`/`4.jpg` tidak dideklarasi di pubspec** | Critical | Browse banner tidak tampil di release build |
| 🔴 2 | **`cached[2]`/`colors[2]` unsafe index** di album card | High | `RangeError` crash pada artwork dengan sedikit warna |
| 🔴 3 | **`ModalRoute.of(context)!`** di album/artist page | High | Crash di edge case navigation |
| 🔴 4 | **`widget.userPlaylist!`/`widget.smartType!`** di playlist_page (5x) | High | Crash jika navigasi tanpa parameter |
| 🔴 5 | **`test/widget_test.dart` adalah default counter test** | High | CI fail, zero real test coverage |
| 🔴 6 | **Folder `lib/Bottom NavBar/` dengan spasi** | High | Build fragility, URL-encoded import |
| 🟡 7 | **`BootTrace` — 74 refs TEMPORARY** | High | Production overhead, code noise |
| 🟡 8 | **`_decoderInfoCtrl` StreamController tidak di-close** | Medium | Memory leak setiap kali service di-dispose |
| 🟡 9 | **`MediaCapabilitiesService.dispose()` tidak pernah dipanggil** | Medium | Listener leak |
| 🟡 10 | **God files** (detail.dart 576L, log_page 889L, audio 869L, playback_manager 833L) | High | Maintainability debt |
| 🟡 11 | **Duplicate HTTP logic di 7 lyrics providers** | High | Bug fix di satu provider tidak otomatis fix lain |
| 🟡 12 | **`ThemeController._save()` calls `SharedPreferences.getInstance()` setiap toggle** | Medium | Platform channel call yang tidak perlu |
| 🟡 13 | **20+ silent `catch (_)` blocks** | Medium | Error tersembunyi, debug sulit |
| 🟡 14 | **Settings tersebar di dua folder** | Medium | Developer confusion |
| 🟡 15 | **RadioPage tab aktif, data kosong** | Medium | Bad UX |
| 🟢 16 | **6 file settings kosong** (`chip`, `sleep_timer`, `lyrics`, dll.) | Medium | Clutter tidak perlu |
| 🟢 17 | **`_GlassSubToggle` duplikat `SettingsToggleRow`** | Medium | Inconsistency |
| 🟢 18 | **`setState` per scroll tick** di `about_app_page` dan `detail.dart` | Medium | Unnecessary rebuilds |
| 🟢 19 | **`NativeModuleRegistry.initializeAll()` sequential** | Medium | Startup lebih lambat dari perlu |
| 🟢 20 | **Missing `const` constructors** di banyak widget | Low | Minor rebuild inefficiency |
| 🟢 21 | **`fog_painter.dart` cryptic variable names** | Low | Maintainability |
| 🟢 22 | **`webViewContainer.dart` camelCase filename** | Low | Style violation |
| 🟢 23 | **`NativeDspBridge` stubs public** | Low | API surface misleading |
| 🟢 24 | **Magic numbers di library sections** | Low | Maintainability |

---

*Laporan ini hanya untuk audit dan pelaporan. Tidak ada perubahan kode yang dilakukan.*  
*Audit Round 1 mencakup: dead code, architecture, imports, routing, flutter perf, services, native, themes.*  
*Audit Round 2 mencakup: themes, native bridges, 12 service/provider files, 30+ widget/page files, semua settings files.*
