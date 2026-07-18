# Comprehensive Dart Codebase Audit Report

**Tanggal:** 18 Juli 2026  
**Versi App:** 1.2.3+1  
**Total file Dart:** 263  
**Scope:** `lib/`, `test/`, `native_audio_runtime/lib/`

---

## Catatan Penting

> **Tidak ada perubahan kode yang dilakukan.** Laporan ini murni audit dan pelaporan sesuai instruksi. Semua temuan harus diverifikasi sebelum ditindaklanjuti.

---

## Kategori 1: Dead Code Analysis

### 1.1 `lib/services/boot_trace.dart` — Temporary Instrumentation

| Atribut | Detail |
|---|---|
| **Severity** | High |
| **File** | `lib/services/boot_trace.dart` |
| **Confidence** | High |

**Deskripsi:** `BootTrace` secara eksplisit di-comment sebagai "TEMPORARY startup instrumentation" yang harus dihapus setelah bug Phase 9 selesai diinvestigasi. Terdapat **74 referensi** tersebar di `lib/main/main.dart` dan hampir semua service init chain.

**Dampak:** Overhead runtime tidak perlu, code bloat, noise saat debugging ke depan. Setiap init step membawa string logging yang tidak berguna di production.

**Rekomendasi:** Hapus seluruh `BootTrace.step()`, `BootTrace.log()`, dan `BootTrace.begin()`/`BootTrace.end()` dari init chain, lalu hapus file `boot_trace.dart` itu sendiri.

---

### 1.2 `lib/services/audio/audio_session_handler/handler.dart` — Empty Stub Methods

| Atribut | Detail |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/audio/audio_session_handler/handler.dart` |
| **Confidence** | High |

**Deskripsi:** Method `onAppPause()` dan `onAppResume()` adalah empty stubs. Dipanggil oleh `AudioFocusService` tapi tidak melakukan operasi apa pun. Native Media3 sudah menangani audio focus secara mandiri.

**Dampak:** Dead call path yang membingungkan pembaca kode — terlihat seperti ada perilaku padahal tidak.

**Rekomendasi:** Hapus kedua method stub tersebut dan panggilan terkait di `AudioFocusService`, atau jadikan `private` + dokumentasikan sebagai intentional no-op.

---

### 1.3 `lib/utils/data/radio_stations.dart` — Empty Data List

| Atribut | Detail |
|---|---|
| **Severity** | Medium |
| **File** | `lib/utils/data/radio_stations.dart`, `lib/utils/sample_music_data.dart` |
| **Confidence** | High |

**Deskripsi:** `radio_stations.dart` mendefinisikan `final List radioStations = [];` — list kosong tanpa tipe. Diekspos via `lib/utils/sample_music_data.dart` (yang hanya berisi export). RadioPage aktif di BottomNav dan merender konten dari list ini.

**Dampak:** RadioPage tampil tapi kosong. `sample_music_data.dart` hanya jadi passthrough file tanpa nilai tambah.

**Rekomendasi:** Isi data radio atau tandai fitur sebagai "Coming Soon" dengan UI yang jelas. Pertimbangkan merge `sample_music_data.dart` ke lokasi yang lebih logis atau hapus jika tidak diperlukan.

---

### 1.4 `lib/services/native/bridges/native_dsp_bridge.dart` — Phase 3 TODO Stub

| Atribut | Detail |
|---|---|
| **Severity** | Low |
| **File** | `lib/services/native/bridges/native_dsp_bridge.dart` |
| **Confidence** | High |

**Deskripsi:** `NativeDspBridge` terdokumentasi secara eksplisit sebagai Phase 3 placeholder. `queryCapabilities()` selalu return "unsupported". Runtime load benar, registrasi benar, tapi tidak ada DSP algorithm yang diimplementasi.

**Dampak:** Tidak ada dampak fungsional negatif. Hanya menambah init overhead kecil. Sudah didokumentasikan dengan baik.

**Rekomendasi:** Tidak perlu aksi mendesak. Pastikan UI yang bergantung pada `queryCapabilities()` menampilkan state yang benar (sudah ditangani via `PlaybackManager.failOpen`).

---

## Kategori 2: Folder Audit

### 2.1 `lib/Bottom NavBar/` — Folder Name dengan Spasi

| Atribut | Detail |
|---|---|
| **Severity** | High |
| **File** | `lib/Bottom NavBar/` |
| **Confidence** | High |

**Deskripsi:** Folder menggunakan spasi dalam nama (`Bottom NavBar`), melanggar konvensi Dart/Flutter yang menggunakan `snake_case`. Akibatnya, import harus menggunakan URL encoding:

```dart
import 'package:musicplayer/Bottom%20NavBar/bottom_nav.dart';
```

Ini tidak lazim, berpotensi bermasalah di beberapa tools (linter, analyzer, IDE), dan membingungkan.

**Dampak:** Fragil di beberapa build environment, tidak sesuai standar Dart, menyulitkan refactor ke depan.

**Rekomendasi:** Rename ke `lib/bottom_nav/` dan update semua import terkait (2 file: `lib/main.dart`, `lib/main.dart`).

---

### 2.2 `lib/webView/` — Single-File Folder

| Atribut | Detail |
|---|---|
| **Severity** | Low |
| **File** | `lib/webView/webViewContainer.dart` |
| **Confidence** | High |

**Deskripsi:** Folder `lib/webView/` hanya berisi satu file: `webViewContainer.dart`. File ini mendefinisikan widget `WebView` yang digunakan sebagai wrapper layout di `bottom_nav/state.dart` dan `app_state.dart`.

**Dampak:** Folder isolasi berlebihan untuk satu file kecil.

**Rekomendasi:** Pindahkan ke `lib/widgets/common/web_view_container.dart` dan sesuaikan import.

---

## Kategori 3: File Audit

### 3.1 `test/widget_test.dart` — Default Template Test yang Salah

| Atribut | Detail |
|---|---|
| **Severity** | High |
| **File** | `test/widget_test.dart` |
| **Confidence** | High |

**Deskripsi:** File ini adalah **default Flutter counter app test** yang di-generate otomatis saat `flutter create`. Isinya mencari widget `'0'`, `'1'`, dan `Icons.add` — semua tidak ada di `MyApp` music player ini. Test ini **pasti gagal** jika dijalankan.

```dart
expect(find.text('0'), findsOneWidget);  // tidak ada di music player
await tester.tap(find.byIcon(Icons.add)); // tidak ada di music player
```

**Dampak:** Memberikan false sense of test coverage. Jika CI diaktifkan, langsung fail.

**Rekomendasi:** Hapus atau replace dengan smoke test yang sesuai (e.g., verify `MyApp` render tanpa crash dalam kondisi mock).

---

### 3.2 `lib/utils/sample_music_data.dart` — Pure Re-export File

| Atribut | Detail |
|---|---|
| **Severity** | Low |
| **File** | `lib/utils/sample_music_data.dart` |
| **Confidence** | High |

**Deskripsi:** File ini hanya berisi satu baris:
```dart
export 'data/radio_stations.dart';
```
Tidak ada logika, hanya passthrough export. Satu-satunya consumer adalah `lib/widgets/pages/search_sections.dart`.

**Dampak:** Indirection tidak berguna — abstraksi yang tidak perlu.

**Rekomendasi:** Import `radio_stations.dart` langsung dari consumer atau hapus file ini dan update import.

---

## Kategori 4: Import Audit

### 4.1 URL-Encoded Import di `lib/main.dart`

| Atribut | Detail |
|---|---|
| **Severity** | High |
| **File** | `lib/main.dart:5` |
| **Confidence** | High |

**Deskripsi:** Import menggunakan URL encoding karena nama folder mengandung spasi:
```dart
import 'package:musicplayer/Bottom%20NavBar/bottom_nav.dart';
```

**Dampak:** Non-standard, berpotensi bermasalah dengan beberapa versi Dart analyzer, dan mengindikasikan masalah penamaan folder (lihat Kategori 2.1).

**Rekomendasi:** Fix root cause-nya — rename folder ke snake_case.

---

### 4.2 Import yang Tidak Digunakan — `audio_focus_service.dart` di `main.dart`

| Atribut | Detail |
|---|---|
| **Severity** | Low |
| **File** | `lib/main.dart:14` |
| **Confidence** | Medium — Needs Manual Verification |

**Deskripsi:** `lib/main.dart` mengimport `audio_focus_service.dart` namun actual usage ada di `lib/main/main.dart`. Perlu dicek apakah import di `main.dart` memang diperlukan atau duplikat.

**Rekomendasi:** Verifikasi dan hapus jika tidak digunakan langsung di `lib/main.dart`.

---

## Kategori 5: Architecture Audit

### 5.1 God Files — File Terlalu Besar

| Atribut | Detail |
|---|---|
| **Severity** | High |
| **File** | Multiple |
| **Confidence** | High |

| File | Baris | Masalah |
|---|---|---|
| `lib/pages/log_page.dart` | **889** | Mixing log display UI + filter logic + export + detail sheet |
| `lib/pages/settings_page/audio.dart` | **869** | Mixing semua audio settings: normalization, EQ, compressor, session info, engine stats |
| `lib/services/audio/playback_manager.dart` | **833** | God service: queue, volume, DSP, normalization, sleep timer, stats, native bridge |

**Dampak:** Sulit di-maintain, high merge conflict risk, sulit di-test unit, cognitive load tinggi.

**Rekomendasi:** 
- `log_page.dart`: Ekstrak filter logic ke `LogFilter` class, ekstrak detail sheet ke file terpisah.
- `audio.dart`: Pecah per section (normalization, EQ, engine) masing-masing jadi file terpisah.
- `playback_manager.dart`: Pertimbangkan memecah ke `VolumeManager`, `QueueManager`, `DspManager` dengan `PlaybackManager` sebagai facade tipis.

---

### 5.2 Startup Chain — Fragile Service Initialization

| Atribut | Detail |
|---|---|
| **Severity** | High |
| **File** | `lib/main/main.dart` |
| **Confidence** | High |

**Deskripsi:** `main.dart` secara sequential menginisialisasi 20+ service dengan urutan yang sangat ketat. BootTrace logging tersebar di antara setiap step. Ini menciptakan strong ordering dependency yang fragil — menambah service baru atau mengubah urutan bisa menyebabkan crash yang sulit di-debug.

**Dampak:** Startup time sulit di-optimize, testing individual service sulit, kesalahan urutan init mengakibatkan crash diam.

**Rekomendasi:** Kelompokkan service ke dalam init phases yang eksplisit (pre-runApp, post-runApp, on-demand). Gunakan dependency injection pattern ringan alih-alih global singletons yang bergantung pada urutan init.

---

### 5.3 Layer Violation — UI Memanggil Service Langsung

| Atribut | Detail |
|---|---|
| **Severity** | Medium |
| **File** | Multiple pages |
| **Confidence** | High |

**Deskripsi:** Halaman UI seperti `playlist_page.dart`, `equalizer_page.dart`, `audio.dart` mengimport dan memanggil `AudioService`, `AudioEffectsService`, `PlaybackManager`, `MediaStoreService` langsung tanpa abstraksi ViewModel/Controller di antara keduanya.

**Dampak:** Business logic tersebar di layer UI, menyulitkan testing dan refactor service.

**Rekomendasi:** Ini pola yang umum di Flutter tanpa state management library. Tidak harus diubah sekarang, tapi pertimbangkan mengekstrak logic ke controller terpisah untuk halaman-halaman besar.

---

### 5.4 Duplicate Scrolling Pattern

| Atribut | Detail |
|---|---|
| **Severity** | Low |
| **File** | `lib/pages/album_page.dart`, `lib/pages/artist_page.dart`, `lib/pages/music_list.dart` |
| **Confidence** | Medium |

**Deskripsi:** Ketiga halaman mengimplementasikan pola yang identik: `ScrollController` + `_scrollOffset` + `ScrollToTopService.signal(n).addListener(_onScrollToTop)` di `initState` dan `dispose`.

**Dampak:** Duplicate boilerplate yang harus diubah di 3+ tempat jika ada perubahan.

**Rekomendasi:** Ekstrak ke mixin `ScrollToTopMixin` atau base class.

---

## Kategori 6: Flutter Best Practices

### 6.1 `band_slider.dart` — AnimationController Tidak Di-dispose di Satu dispose()

| Atribut | Detail |
|---|---|
| **Severity** | Medium |
| **File** | `lib/pages/settings/equalizer_page/band_slider.dart:51` |
| **Confidence** | Medium — Needs Manual Verification |

**Deskripsi:** File ini memiliki dua State class. State class pertama (dispose di baris 51) tidak memanggil `_pressCtrl.dispose()` — hanya memanggil `removeListener` dan `super.dispose()`. Perlu verifikasi apakah `_pressCtrl` memang dimiliki State class ini atau State class kedua.

**Dampak:** Jika `_pressCtrl` tidak di-dispose, AnimationController leak setiap kali EQ slider di-rebuild.

**Rekomendasi:** Verifikasi dan tambahkan `_pressCtrl.dispose()` di dispose() yang benar.

---

### 6.2 Async void Event Handler — Potensi Unhandled Exception

| Atribut | Detail |
|---|---|
| **Severity** | Medium |
| **File** | Multiple (tersebar di pages dan services) |
| **Confidence** | Medium |

**Deskripsi:** Beberapa callback/event handler menggunakan `async void` tanpa try-catch. Jika future throws, exception tidak tertangkap dan bisa crash atau diam.

**Rekomendasi:** Wrap `async void` handler dengan try-catch, atau gunakan `.catchError()`. Minimal log error jika terjadi.

---

## Kategori 7: Performance Audit

### 7.1 Player Content Build — State Unwrapping Agresif

| Atribut | Detail |
|---|---|
| **Severity** | Medium |
| **File** | `lib/widgets/player/player_content/content.dart` |
| **Confidence** | Medium |

**Deskripsi:** Build method melakukan multiple aggressive unwrapping pada `_current!` (state/controller). Selain risiko null crash (lihat Kategori 8), ini juga berarti banyak rebuild dependency yang tidak perlu jika hanya subset state yang berubah.

**Rekomendasi:** Pecah `ValueListenableBuilder` yang besar menjadi beberapa builder yang lebih kecil dan targeted, sehingga rebuild hanya terjadi pada widget yang benar-benar berubah datanya.

---

### 7.2 Lyrics Timeline — Pre-computation vs Runtime

| Atribut | Detail |
|---|---|
| **Severity** | Low |
| **File** | `lib/widgets/player/synced_lyrics_view/state_timeline.dart` |
| **Confidence** | Medium |

**Deskripsi:** Timeline indexing menggunakan binary search (baik). Namun perlu dipastikan bahwa semua pre-computation dilakukan sekali saat lyrics load, bukan diulang per-frame di `build()`.

**Rekomendasi:** Verifikasi `_buildElrcText` dan karaoke line computation tidak dipanggil dari build context secara berulang.

---

## Kategori 8: Null Safety Audit

### 8.1 Force Unwrap Masif — 264 Instance

| Atribut | Detail |
|---|---|
| **Severity** | High |
| **File** | Tersebar di seluruh `lib/` |
| **Confidence** | High |

**Deskripsi:** Terdapat **264 instance** penggunaan force unwrap (`!`) di seluruh codebase. Sebagian besar aman karena konteks yang jelas, namun beberapa kritis:

**Instance Berisiko Tinggi:**

| File | Baris | Pattern | Risiko |
|---|---|---|---|
| `lib/pages/album_page.dart` | ~awal | `ModalRoute.of(context)!` | Crash jika route state hilang saat navigasi |
| `lib/pages/artist_page.dart` | ~awal | `ModalRoute.of(context)!` | Sama dengan atas |
| `lib/pages/playlist_page.dart` | 69, 71, 114, 162, 195 | `widget.smartType!`, `widget.userPlaylist!` | Crash jika parameter null saat navigasi edge case |
| `lib/widgets/player/player_content/content.dart` | Multiple | `_current!` | Race condition saat rapid navigation |
| `lib/services/audio/audio_session_handler/handler.dart` | 27 | `_session!` | Race condition saat init belum selesai |
| `lib/models/loudness_data.dart` | 47 | `peakLinear!` | Crash jika peak data null |

**Dampak:** Setiap instance adalah potensial `Null check operator used on a null value` crash yang sulit di-reproduce dan di-debug karena hanya terjadi di edge case.

**Rekomendasi (prioritas tinggi ke rendah):**
1. `ModalRoute.of(context)!` → Gunakan `ModalRoute.of(context)?.settings.arguments` dengan fallback.
2. `widget.userPlaylist!`/`widget.smartType!` → Gunakan pattern `if (widget.userPlaylist == null) return;` di awal.
3. `_current!` di content.dart → Gunakan null-aware operators `?.` atau guard clause di awal build.
4. Sisanya: review per-case, replace `!` dengan `?? defaultValue` atau explicit null check.

---

### 8.2 Redundant Null Check di ReplayGain

| Atribut | Detail |
|---|---|
| **Severity** | Low |
| **File** | `lib/services/replay_gain_service/service.dart` |
| **Confidence** | Medium |

**Deskripsi:** Service menggunakan `LoudnessData.none()` sebagai guaranteed fallback, tapi beberapa consumer masih melakukan null-aware check pada hasilnya. Ini adalah redundant check.

**Rekomendasi:** Konsistensikan: jika `ReplayGainService` selalu return non-null, update consumer untuk memperlakukannya sebagai non-nullable.

---

## Kategori 9: Naming Audit

### 9.1 Folder dengan Spasi — `lib/Bottom NavBar/`

| Atribut | Detail |
|---|---|
| **Severity** | High |
| **File** | `lib/Bottom NavBar/` |
| **Confidence** | High |

**Deskripsi:** Melanggar konvensi Dart. Semua folder package Dart harus menggunakan `lowercase_with_underscores`. Nama saat ini juga menggunakan PascalCase.

**Rekomendasi:** Rename ke `lib/bottom_nav/`.

---

### 9.2 CamelCase Filename — `webViewContainer.dart`

| Atribut | Detail |
|---|---|
| **Severity** | Medium |
| **File** | `lib/webView/webViewContainer.dart` |
| **Confidence** | High |

**Deskripsi:** Dart style guide mensyaratkan file menggunakan `lowercase_with_underscores`. File ini menggunakan `camelCase` (`webViewContainer.dart`) dan berada di folder yang juga bermasalah (`webView/`).

**Rekomendasi:** Rename ke `lib/widgets/common/web_view_container.dart`.

---

### 9.3 Inconsistent Part File Naming Pattern

| Atribut | Detail |
|---|---|
| **Severity** | Low |
| **File** | Multiple |
| **Confidence** | High |

**Deskripsi:** Beberapa modul menggunakan `part`/`part of` pattern (e.g., `bottom_nav/page.dart`, `music_list/page.dart`) sementara yang lain tidak. Pola ini tidak konsisten di seluruh project — beberapa feature folder menggunakan parts, sebagian lainnya menggunakan import biasa.

**Dampak:** Membingungkan — dua pola untuk tujuan yang sama.

**Rekomendasi:** Pilih satu pola dan terapkan konsisten. Parts pattern oke untuk modul yang benar-benar satu unit logis.

---

## Kategori 10: Dependency Audit

### 10.1 Semua Package Digunakan ✓

| Atribut | Detail |
|---|---|
| **Confidence** | High |

Verifikasi terhadap seluruh package di `pubspec.yaml`:

| Package | Digunakan | Lokasi |
|---|---|---|
| `text_scroll` | ✓ | `player_content/content.dart` |
| `cupertino_icons` | ✓ | Flutter default |
| `http` | ✓ | Lyrics providers |
| `cached_network_image` | ✓ | Artwork display |
| `audio_session` | ✓ | `audio_session_handler` |
| `permission_handler` | ✓ | Storage permissions |
| `shared_preferences` | ✓ | Queue persistence, settings |
| `rxdart` | ✓ | Stream merging |
| `path` | ✓ | File path operations |
| `path_provider` | ✓ | Artwork cache storage |
| `scrollable_positioned_list` | ✓ | Lyrics view + queue overlay |
| `palette_generator_plus` | ✓ | `palette_extractor.dart` |
| `url_launcher` | ✓ | Settings about page, bug report |
| `font_awesome_flutter` | ✓ | `about_app_page.dart` (social icons) |

**Tidak ada package yang unused.** Semua dependencies memiliki penggunaan aktif.

---

## Kategori 11: Asset Reference Audit

### 11.1 KRITIS: Assets Root Images Tidak Dideklarasi di pubspec.yaml

| Atribut | Detail |
|---|---|
| **Severity** | Critical |
| **File** | `pubspec.yaml`, `lib/utils/data/browse_banners.dart` |
| **Confidence** | High |

**Deskripsi:** File `browse_banners.dart` mereferensikan tiga asset:
```dart
'img': 'assets/1.jpg'
'img': 'assets/2.jpg'  
'img': 'assets/4.jpg'
```

Namun `pubspec.yaml` hanya mendeklarasikan:
```yaml
assets:
  - assets/images/
  - assets/images/search/
```

File `assets/1.jpg`, `assets/2.jpg`, `assets/4.jpg` berada di root `assets/` — **tidak tercakup** oleh deklarasi tersebut. Dalam Flutter, trailing slash (`assets/images/`) hanya mencakup file langsung di folder tersebut, bukan parent folder.

**Dampak:** Browse section kemungkinan besar tidak bisa menampilkan banner images (akan error `Unable to load asset`). Ini adalah **bug production** yang aktif.

**Rekomendasi:** Tambahkan ke `pubspec.yaml`:
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

### 11.2 `assets/images/` Hanya Berisi Subfolder, Bukan Files Langsung

| Atribut | Detail |
|---|---|
| **Severity** | Low |
| **File** | `pubspec.yaml` |
| **Confidence** | High |

**Deskripsi:** `assets/images/` dideklarasikan sebagai asset directory, tapi folder ini tidak berisi file langsung — hanya subfolder `search/`. Deklarasi ini tidak salah tapi berlebihan.

**Dampak:** Tidak ada dampak negatif, hanya redudansi kecil di pubspec.

---

### 11.3 Semua Font Digunakan ✓

Seluruh 5 weight SF Pro Text font (regular, medium, semibold, bold, black) digunakan dalam theme system. Shader `fluid.frag` digunakan oleh `artwork.dart`.

---

## Kategori 12: Routing Audit

### 12.1 `RadioPage` Aktif tapi Datanya Kosong

| Atribut | Detail |
|---|---|
| **Severity** | Medium |
| **File** | `lib/pages/radio.dart`, `lib/utils/data/radio_stations.dart` |
| **Confidence** | High |

**Deskripsi:** `RadioPage` adalah tab ke-3 di BottomNav (index 2), jadi selalu bisa diakses user. Tapi kontennya dirender dari `radioStations = []` — list kosong.

**Dampak:** User melihat tab Radio yang tampil kosong tanpa penjelasan.

**Rekomendasi:** Tampilkan "Coming Soon" placeholder atau isi data, atau sembunyikan tab Radio dari BottomNav sementara fitur belum siap.

---

### 12.2 Semua Route Lain Dapat Diakses ✓

`AlbumPage`, `ArtistPage`, `ArtistList`, `MusicList` dapat diakses via BottomNav. `PlaylistPage` dapat diakses via `radio_sections.dart`. Tidak ada halaman orphan yang terdeteksi.

---

## Kategori 13: Service Audit

### 13.1 `AudioFocusService` — Empty Lifecycle Methods

| Atribut | Detail |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/audio_focus_service.dart` |
| **Confidence** | High |

**Deskripsi:** Service ini diinisialisasi di `main.dart` dan memanggil `AudioSessionHandler.onAppPause()`/`onAppResume()` yang keduanya empty stubs. Service ini berfungsi minimal karena native Media3 sudah menangani audio focus.

**Dampak:** Init overhead tanpa manfaat nyata.

**Rekomendasi:** Evaluasi apakah `AudioFocusService` masih diperlukan atau bisa dihapus/disederhanakan bersama stub methods-nya.

---

### 13.2 `NativeDspBridge` — Documented Architectural Placeholder

*(Sudah dibahas di Kategori 1.4)*

---

### 13.3 Semua Service Utama Dikonsumsi ✓

| Service | Status |
|---|---|
| `ReplayGainService` | ✓ Dikonsumsi oleh `LoudnessSourceResolver` |
| `SongMetadataService` | ✓ Dikonsumsi oleh `ReplayGainService` |
| `MediaCapabilitiesService` | ✓ Init di main, consumed oleh UI via ValueNotifier |
| `HistoryService` | ✓ `warmUp()` di main, `trackPlay()` di AudioService |
| `ArtworkRepository` | ✓ Highly optimized, prewarm di main |
| `LyricsService` | ✓ Full multi-provider system aktif |
| `PaletteExtractor` | ✓ Digunakan di artwork background player |
| `ScrollToTopService` | ✓ Digunakan di 4+ pages |
| `PlaylistService` | ✓ Digunakan di `playlist_page.dart` |

---

## Kategori 14: Public API Audit

### 14.1 DSP Setter Seharusnya Private di `PlaybackManager`

| Atribut | Detail |
|---|---|
| **Severity** | Medium |
| **File** | `lib/services/audio/playback_manager.dart` |
| **Confidence** | High |

**Deskripsi:** Method-method seperti `setNativeGainDb()`, `setNativeCompressorBypass()`, `resetNativeLoudnessNorm()` adalah public tapi merupakan detail implementasi internal komunikasi DSP. Consumer external seharusnya menggunakan method high-level seperti `setVolume()`, `setCompressorEnabled()` dll.

**Dampak:** API surface terlalu lebar — external code bisa bypass state management internal `PlaybackManager`.

**Rekomendasi:** Prefix dengan `_` atau annotate dengan `@visibleForTesting` / `@internal`. Atau pindahkan ke inner class private.

---

### 14.2 `NativeLogBridge` — Bridge Methods Seharusnya Private

| Atribut | Detail |
|---|---|
| **Severity** | Low |
| **File** | `lib/services/log_service/native_log_bridge.dart` |
| **Confidence** | Medium |

**Deskripsi:** Method bridge ke native log channel adalah public tapi hanya dimaksudkan untuk digunakan oleh `LogService`.

**Rekomendasi:** Prefix dengan `_` atau buat inner class private di dalam `LogService`.

---

### 14.3 `LyricsService/FetchManager` — Internal Methods Exposed

| Atribut | Detail |
|---|---|
| **Severity** | Low |
| **File** | `lib/services/lyrics_service/fetch_manager.dart` |
| **Confidence** | Medium |

**Deskripsi:** Beberapa method internal cancellation dan provider-specific logic terekspos sebagai public.

**Rekomendasi:** Enkapsulasi di dalam `LyricsService` atau jadikan private.

---

## Kategori 15: Consistency Audit

### 15.1 Inkonsistensi Struktur Folder — Settings Pages

| Atribut | Detail |
|---|---|
| **Severity** | Medium |
| **File** | `lib/pages/settings/`, `lib/pages/settings_page/` |
| **Confidence** | High |

**Deskripsi:** Settings-related code tersebar di **dua folder berbeda**:
- `lib/pages/settings/` — contains `equalizer_page/`, `settings_widgets/`, `sleep_timer_page/`
- `lib/pages/settings_page/` — contains `audio.dart`, `appearance.dart`, `lyrics.dart`, dll.

Dan ada juga `lib/pages/settings_page.dart` sebagai entry point. Tiga lokasi untuk satu fitur.

**Dampak:** Sangat membingungkan. Developer baru tidak tahu di mana harus mencari atau menambahkan code settings.

**Rekomendasi:** Konsolidasikan semua settings-related code ke dalam satu struktur folder yang konsisten, misalnya `lib/pages/settings/` dengan subfolder yang jelas.

---

### 15.2 Mixed Part/Import Pattern

*(Sudah dibahas di Kategori 9.3)*

---

### 15.3 Inkonsistensi Penamaan File — camelCase vs snake_case

| Atribut | Detail |
|---|---|
| **Severity** | Medium |
| **File** | `lib/webView/webViewContainer.dart` |
| **Confidence** | High |

Satu-satunya file dengan camelCase filename. Semua file lain sudah menggunakan `snake_case`.

---

---

## Final Summary

### Statistik

| Metrik | Jumlah |
|---|---|
| Total file Dart | 263 |
| Total folder diaudit | 25+ |
| Total dead code / placeholder | 4 |
| Total unused file | 2 (`test/widget_test.dart`, `sample_music_data.dart`) |
| Total naming violation | 3 |
| Total architecture issue | 5 |
| Total performance issue | 2 |
| Total maintainability issue | 6 |
| Total potential bug / crash risk | 8 |
| Total asset issue | 1 Critical + 1 Low |
| Unused packages | 0 |

---

### Daftar Prioritas Perbaikan (Risk-Based)

| Prioritas | Temuan | Severity | Risk |
|---|---|---|---|
| 🔴 1 | **Asset 1.jpg/2.jpg/4.jpg tidak dideklarasi di pubspec** | Critical | Browse page banner tidak tampil |
| 🔴 2 | **264 force unwrap** — terutama `ModalRoute.of(context)!`, `widget.userPlaylist!` | High | Crash di edge case navigation |
| 🔴 3 | **`test/widget_test.dart` adalah default counter test** | High | CI fail, zero real coverage |
| 🔴 4 | **Folder `lib/Bottom NavBar/` dengan spasi** | High | Build fragility, tooling issues |
| 🟡 5 | **`lib/services/boot_trace.dart` — 74 refs, TEMPORARY** | High | Production overhead, code noise |
| 🟡 6 | **God files** (log_page 889L, audio 869L, playback_manager 833L) | High | Maintainability debt |
| 🟡 7 | **Settings code di dua folder berbeda** | Medium | Developer confusion |
| 🟡 8 | **RadioPage tab aktif dengan data kosong** | Medium | Bad UX |
| 🟡 9 | **`AudioFocusService` + `onAppPause`/`onAppResume` stubs** | Medium | Dead init overhead |
| 🟡 10 | **DSP setters public di PlaybackManager** | Medium | API surface terlalu lebar |
| 🟢 11 | **`webViewContainer.dart` — camelCase filename** | Medium | Style violation |
| 🟢 12 | **`radio_stations.dart` — empty list** | Medium | UX (covered by #8) |
| 🟢 13 | **`sample_music_data.dart` — pure re-export** | Low | Unnecessary indirection |
| 🟢 14 | **`NativeDspBridge` — documented stub** | Low | Documented, intentional |
| 🟢 15 | **NativeLogBridge methods public** | Low | Minor API cleanliness |

---

*Laporan ini hanya untuk audit dan pelaporan. Tidak ada perubahan kode yang dilakukan.*
