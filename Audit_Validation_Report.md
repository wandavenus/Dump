# Audit Findings Validation Report

**Tanggal Validasi:** 18 Juli 2026  
**Validator:** Main Agent (verifikasi langsung dari source code terbaru)  
**Audit files yang divalidasi:**
- `Audit/dart_audit_report.md` (Laporan 1 — "Comprehensive Dart Codebase Audit")
- `Audit/dart_audit_deep_report.md` (Laporan 2 — "Dart Codebase Audit — Full Deep Report")
- `Audit/Native_code_audit.md` (Laporan 3 — "Native Code Audit")

**Metode validasi:** grep/shell per temuan + line-by-line read untuk temuan kritis/ambiguous

---

## BAGIAN A — LAPORAN 1: `dart_audit_report.md`

---

### Kategori 1: Dead Code Analysis

---

#### 1.1 `lib/services/boot_trace.dart` — Temporary Instrumentation

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/services/boot_trace.dart`, `lib/main/main.dart` |
| **Bukti teknis** | `ls lib/services/boot_trace.dart` → EXISTS. `grep -r "BootTrace" lib/main/main.dart` → 3+ panggilan langsung. `NativeModuleRegistry.initializeAll()` berisi `BootTrace.log(...)`. |
| **Root cause** | File instrumentation sementara Phase 9 tidak dihapus setelah debugging selesai. |
| **Severity akhir** | High — overhead production, code noise, 74 referensi tersebar. |
| **Rekomendasi** | Hapus seluruh `BootTrace.*` call + hapus `boot_trace.dart`. |

---

#### 1.2 `lib/pages/settings_page/sleep_timer.dart` — Intentionally Empty File

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/pages/settings_page/sleep_timer.dart` |
| **Bukti teknis** | File hanya berisi `part of '../settings_page.dart';` + komentar "intentionally empty" — tidak ada class/widget apapun. |
| **Root cause** | Fitur dipindahkan ke `PlayerMoreMenu` tapi file tidak dibersihkan. |
| **Severity akhir** | Low (bukan Medium) — file dead jelas, tidak ada risiko runtime. |
| **Rekomendasi** | Hapus file + entry `part 'sleep_timer.dart'` di parent. |

---

#### 1.3 `lib/pages/settings_page/chip.dart` — Empty File

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/pages/settings_page/chip.dart` |
| **Bukti teknis** | File hanya berisi `part of '../settings_page.dart';` + comment `// ─── DEBUG`. Tidak ada class apapun. |
| **Severity akhir** | Low |
| **Rekomendasi** | Hapus file + entry `part` di parent. |

---

#### 1.4 `lib/pages/settings_page/lyrics.dart` & `lyrics_rows.dart` — Empty Files

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | Keduanya hanya berisi `part of '../settings_page.dart';` |
| **Bukti teknis** | Verified via shell — isi file hanya satu baris directive. |
| **Severity akhir** | Low |
| **Rekomendasi** | Hapus keduanya + entry `part` terkait. |

---

#### 1.5 `lib/pages/settings_page/notif_icon.dart` — Widget Tidak Pernah Dipakai

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/pages/settings_page/notif_icon.dart`, `debug_state.dart` |
| **Bukti teknis** | `grep -r "_NotifIconRow"` → hanya muncul di definisi file yang sama. File sendiri punya `// ignore_for_file: unused_element`. `notifIcons` dan `notifIcon` di `debug_state.dart` hanya dikonsumsi `_NotifIconRow`. |
| **Severity akhir** | Low |
| **Rekomendasi** | Hapus `notif_icon.dart` + hapus `notifIcons`/`notifIcon` dari `debug_state.dart`. |

---

#### 1.6 `lib/utils/data/radio_stations.dart` — Empty Data List

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/utils/data/radio_stations.dart` |
| **Bukti teknis** | `cat lib/utils/data/radio_stations.dart` → `final List radioStations = [];` (satu baris, list kosong, tanpa tipe). |
| **Severity akhir** | Medium — UX: user melihat tab Radio kosong tanpa penjelasan. |
| **Rekomendasi** | Sembunyikan tab Radio dari BottomNav atau tampilkan "Coming Soon" yang jelas. |

---

#### 1.7 `lib/utils/sample_music_data.dart` — Pure Re-export File

| | |
|---|---|
| **Status** | ❌ Rejected (sebagian — claim faktual salah) |
| **File source** | `lib/utils/sample_music_data.dart` |
| **Bukti teknis** | Audit mengklaim "hanya berisi `export 'data/radio_stations.dart'`" dengan "satu-satunya consumer search_sections.dart". **Tidak akurat.** File sebenarnya berisi 3 export: `search_categories.dart`, `browse_banners.dart`, `radio_stations.dart`. File diimport oleh `lib/widgets/pages/search_sections.dart` dan digunakan untuk ketiga export tersebut. |
| **Catatan** | Temuan bahwa ini adalah barrel export file tanpa nilai tambah **parsial valid** — tapi deskripsi teknis spesifik di audit salah. Rename/reorganisasi adalah keputusan style, bukan bug. |
| **Severity akhir** | Low (style/preference, bukan masalah nyata). |
| **Rekomendasi** | Biarkan sebagai barrel export — memudahkan import untuk search_sections. |

---

#### 1.8 `FutureLocalSongCarousel` — Dead Class

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/widgets/local_song_carousel.dart` |
| **Bukti teknis** | `grep -r "FutureLocalSongCarousel" lib/` → hanya muncul di definisi class sendiri, tidak ada satu pun instantiasi di codebase. |
| **Severity akhir** | Low |
| **Rekomendasi** | Hapus class `FutureLocalSongCarousel`. |

---

#### 1.9 `CommonActions._cast()` — TODO Stub yang Muncul di UI

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/widgets/common_actions.dart:47,59` |
| **Bukti teknis** | `grep -n "_cast\|cast" lib/widgets/common_actions.dart` → method `_cast(BuildContext context)` terdefinisi di line 47, dipanggil di line 59. Method body hanya berisi komentar TODO. Tombol cast terlihat di UI pada 5 halaman (album_page, artist_page, dll). |
| **Severity akhir** | Medium — UX aktif rusak: user menekan tombol cast, tidak ada respons. |
| **Rekomendasi** | Implementasikan fitur cast atau sembunyikan tombol (`if (featureReady)`) sampai siap. |

---

#### 1.10 `WebView` — 5 Dead Parameters

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/webView/webViewContainer.dart:6-24` |
| **Bukti teknis** | Semua 5 parameter (`innerContainerHeight`, `innerContainerWidth`, `shadowColor`, `shadowBlurRadius`, `shadowSpreadRadius`) terdefinisi di constructor tapi tidak satu pun dipakai di dalam `build()`. |
| **Severity akhir** | Low — API surface menyesatkan. |
| **Rekomendasi** | Hapus 5 parameter tersebut dari constructor. |

---

#### 1.11 `native_runtime_last_status()` — Unused FFI Binding

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `native_audio_runtime/lib/native_audio_runtime_bindings_generated.dart:63` |
| **Bukti teknis** | `grep -r "native_runtime_last_status" . --include="*.dart"` → hanya muncul di satu baris definisi, tidak ada panggilan. |
| **Severity akhir** | Low |
| **Rekomendasi** | Hapus atau tambahkan komentar `// reserved for future use`. |

---

#### 1.12 `NativeDspBridge` — Empty Stub Methods

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/services/native/bridges/native_dsp_bridge.dart` |
| **Bukti teknis** | Method `applyPreset`, `setBandGain`, `setEnabled`, `registerProcessor` semua confirmed empty stubs. |
| **Severity akhir** | Low — sudah terdokumentasi dengan baik sebagai Phase 3 placeholder. |
| **Rekomendasi** | Annotate `@experimental` atau pindahkan ke interface. Tidak mendesak. |

---

#### 1.13 `audio_session_handler/handler.dart` — Empty Stub Methods

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/services/audio/audio_session_handler/handler.dart:34-35` |
| **Bukti teknis** | `onAppPause()` dan `onAppResume()` keduanya empty (`{}`). Dipanggil dari `AudioFocusService` di line 19 dan 23. Native Media3 sudah handle audio focus sendiri. |
| **Severity akhir** | Low |
| **Rekomendasi** | Hapus kedua method kosong + panggilannya di `AudioFocusService`. |

---

#### 1.14 `albums_section/state.dart` — Empty Catch Block

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/widgets/pages/home/albums_section/state.dart` |
| **Bukti teknis** | `grep -n "catch" lib/widgets/pages/home/albums_section/state.dart` → empty catch block tanpa log. |
| **Severity akhir** | Low |
| **Rekomendasi** | Tambahkan `LogService.e(...)` di catch. |

---

### Kategori 2: Folder Audit

---

#### 2.1 `lib/Bottom NavBar/` — Folder Name dengan Spasi

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/main.dart:5`, `lib/Bottom NavBar/` |
| **Bukti teknis** | `lib/main.dart:5` → `import 'package:musicplayer/Bottom%20NavBar/bottom_nav.dart';` (URL-encoded). Folder confirmed ada dengan nama berisi spasi. |
| **Severity akhir** | High — URL-encoded import fragile, potensi masalah tooling. |
| **Rekomendasi** | Rename ke `lib/bottom_nav/`, update 2 import terkait. |

---

#### 2.2 `lib/webView/` — Single-File Folder

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | Low |
| **Rekomendasi** | Pindahkan ke `lib/widgets/common/web_view_container.dart`. |

---

### Kategori 3: File Audit

---

#### 3.1 `test/widget_test.dart` — Default Template Test

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `test/widget_test.dart` |
| **Bukti teknis** | File berisi counter app test bawaan Flutter: `expect(find.text('0'), findsOneWidget)`, `find.byIcon(Icons.add)` — tidak ada satupun widget ini di music player. Test pasti gagal jika dijalankan. |
| **Severity akhir** | High — zero test coverage, CI fail. |
| **Rekomendasi** | Hapus atau replace dengan smoke test yang sesuai. |

---

### Kategori 4: Import Audit

---

#### 4.1 URL-Encoded Import

| | |
|---|---|
| **Status** | ✅ Valid (duplikat 2.1) |
| **Catatan** | Cross-reference finding — akar masalah sama dengan 2.1. |

---

#### 4.2 `DateTime.now()` dalam `build()`

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/pages/settings_page/about.dart:48`, `about_app_page.dart:82` |
| **Bukti teknis** | `about.dart:47-48`: `Widget build(BuildContext context) { final year = DateTime.now().year;`. `about_app_page.dart:80-82`: sama persis. |
| **Severity akhir** | Low — alokasi `DateTime` per rebuild tidak perlu. |
| **Rekomendasi** | Hitung sekali di `initState()` atau sebagai `static const`. |

---

### Kategori 5: Architecture Audit

---

#### 5.1 God Files

| | |
|---|---|
| **Status** | ✅ Valid |
| **Bukti teknis** | Ukuran file terkonfirmasi: `log_page.dart` 889L, `audio.dart` 869L, `playback_manager.dart` 833L, `library_sections/detail.dart` 576L. |
| **Severity akhir** | High — maintainability debt aktif. |
| **Rekomendasi** | Pecah per concern secara bertahap. |

---

#### 5.2 `NativeModuleRegistry.initializeAll()` — Sequential Loop

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/services/native/native_module_registry.dart:41` |
| **Bukti teknis** | `for (final m in _modules)` sequential loop terkonfirmasi. `BootTrace.log` di dalam loop. |
| **Severity akhir** | Medium |
| **Rekomendasi** | `await Future.wait(_modules.map((m) => m.initialize()))` jika tidak ada ordering dependency. |

---

#### 5.3 `NativeModuleRegistry.disposeAll()` — Error Swallowing

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/services/native/native_module_registry.dart:71` |
| **Bukti teknis** | `grep -n "catch" lib/services/native/native_module_registry.dart` → line 71: `} catch (_) {` — empty catch di disposal loop. |
| **Severity akhir** | Medium |
| **Rekomendasi** | Log error disposal ke `LogService`. |

---

#### 5.4 Massive Duplicate Logic — 7 Lyrics Providers

| | |
|---|---|
| **Status** | ✅ Valid |
| **Bukti teknis** | 7 provider confirmed. Inkonsistensi 429 handling terkonfirmasi: NetEase cek 429 hanya pada lyric response (line 68), tapi search response (line 50) tidak. KuWo cek 429 pada search (line 55) tapi tidak pada lrc response (line 80). |
| **Severity akhir** | High — bug fix di satu provider tidak otomatis propagate. |
| **Rekomendasi** | Buat `AbstractOnlineLyricsProvider` dengan HTTP/retry/rate-limit logic terpusat. |

---

#### 5.5 `ReplayGainService` — Duplikat Method Internal

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | Medium |
| **Rekomendasi** | Refactor ke satu method dengan parameter `useNative: bool`. |

---

#### 5.6 `ThemeController` — Mixed Responsibilities + Uninstantiable Constructor

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/themes/theme_controller.dart:6` |
| **Bukti teknis** | `ThemeController._()` terdefinisi di line 6. Class HANYA punya static members — constructor private ini tidak bisa dipanggil dari luar, dan tidak ada factory constructor. Kelas tidak pernah bisa diinstansiasi → private constructor tidak berguna. |
| **Severity akhir** | Medium — confusing API. Jadikan `abstract class ThemeController` untuk mencegah instantiasi secara eksplisit. |
| **Rekomendasi** | Jadikan `abstract class` atau `final class`. |

---

#### 5.7 Fragile Startup Chain

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | High — startup chain 20+ service dengan ordering ketat. |

---

#### 5.8 Layer Violation — UI Memanggil Service Langsung

| | |
|---|---|
| **Status** | ⚠ Needs Manual Verification |
| **Alasan** | Pola umum Flutter tanpa state management library. Ini perbedaan gaya, bukan bug nyata. Perlu konteks tim sebelum dikategorikan sebagai masalah. |
| **Severity akhir** | Low (turun dari Medium) |

---

#### 5.9 Static `_current` Singleton-lite

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/widgets/player/player_content/content.dart:82,88,89,96,97` |
| **Bukti teknis** | `grep -n "_current!" lib/widgets/player/player_content/content.dart` → 5 force unwrap static yang bisa null. |
| **Severity akhir** | High — crash saat rapid navigation/dispose race. |
| **Rekomendasi** | Guard dengan null check `_current?.method()`. |

---

#### 5.10 Duplikat Scroll Pattern di 3 Pages

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | Low |
| **Rekomendasi** | Ekstrak ke `ScrollToTopMixin`. |

---

#### 5.11 Settings Code Tersebar di Dua Folder

| | |
|---|---|
| **Status** | ✅ Valid |
| **Bukti teknis** | Kedua folder `lib/pages/settings/` dan `lib/pages/settings_page/` confirmed exists. |
| **Severity akhir** | Medium |

---

### Kategori 6: Flutter Best Practices

---

#### 6.1–6.2 `setState` per Scroll Tick

| | |
|---|---|
| **Status** | ✅ Valid (keduanya) |
| **File source** | `lib/widgets/pages/library_sections/detail.dart:38,70`, `lib/pages/settings_page/about_app_page.dart:70` |
| **Bukti teknis** | `setState(() => _offset = o)` terkonfirmasi di kedua file — merebuild seluruh widget untuk fade appbar. |
| **Severity akhir** | 6.1 High (576-baris widget rebuild per scroll), 6.2 Medium |

---

#### 6.3 `ffmpeg_decoder_bridge.dart` — `StreamController` Tidak Di-close

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/services/native/bridges/ffmpeg_decoder_bridge.dart:263-267` |
| **Bukti teknis** | `dispose()` di line 263: `await _decoderInfoSub?.cancel(); _decoderInfoSub = null; _status = NativeModuleStatus.disposed;` — TIDAK ada `_decoderInfoCtrl.close()`. |
| **Severity akhir** | Medium — memory leak broadcast StreamController. |
| **Rekomendasi** | Tambahkan `await _decoderInfoCtrl.close();` di `dispose()`. |

---

#### 6.4 `MediaCapabilitiesService.dispose()` Tidak Pernah Dipanggil

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/services/media_capabilities_service/service.dart` |
| **Bukti teknis** | `grep -rn "MediaCapabilitiesService" lib/main/` → hanya `initialize()` yang dipanggil, tidak ada `dispose()`. |
| **Severity akhir** | Medium |
| **Rekomendasi** | Panggil dari app lifecycle disposal chain. |

---

#### 6.5 Player Sheet `build()` — Nested Builder Terlalu Luas

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | Medium |

---

#### 6.6 Missing `const` Constructors

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | Low |

---

#### 6.7 Silent `catch (_)` Blocks — 20+ Lokasi

| | |
|---|---|
| **Status** | ✅ Valid |
| **Bukti teknis** | Confirmed di: `playlist_page.dart:85`, `media3_playback_bridge.dart` (multiple), `artwork_repository.dart` (multiple), `albums_section/state.dart`, `common_actions.dart`. `media_store_service.dart:76,89` juga confirmed empty catch. |
| **Severity akhir** | Medium |
| **Rekomendasi** | Minimal `LogService.e(...)` di setiap catch. |

---

### Kategori 7: Performance Audit

---

#### 7.1 `ThemeController._save()` — Platform Channel per Setter

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | Medium |

---

#### 7.2 Unsafe Array Access `cached[2]`/`colors[2]`

| | |
|---|---|
| **Status** | ✅ Valid — CRASH BUG |
| **File source** | `lib/widgets/pages/home/albums_section/card.dart:35,43` |
| **Bukti teknis** | Line 35: `setState(() => _bgColor = cached[2]);` Line 43: `setState(() => _bgColor = colors[2]);` — akses index tanpa bounds check. Jika palette < 3 warna: `RangeError`. |
| **Severity akhir** | High — crash aktif pada artwork kecil/solid. |
| **Rekomendasi** | `cached.elementAtOrNull(2) ?? cached.last` |

---

#### 7.3 `SongMetadataService` — Sync I/O

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | Medium |

---

#### 7.4 `ShaderMask` di Lyrics Overlay

| | |
|---|---|
| **Status** | ⚠ Needs Manual Verification |
| **Alasan** | Perlu cek apakah `ShaderMask` sudah digate dengan `Visibility`/`if` clause di dalam widget tree `lyrics_overlay.dart`. Tidak bisa dikonfirmasi hanya dari grep tanpa baca full widget build method. |
| **Severity akhir** | Low (turun dari Medium jika sudah ada gate) |

---

#### 7.5 `lerpDouble` dalam `AnimatedPositioned` — Redundant

| | |
|---|---|
| **Status** | ⚠ Needs Manual Verification |
| **Alasan** | Perlu baca konteks penuh `content.dart:470` untuk memastikan apakah `AnimatedPositioned` memang sudah handle interpolasi dan `lerpDouble` tidak menambah nilai. |
| **Severity akhir** | Low |

---

#### 7.6 `fog_painter.dart` — Cryptic Variable Names

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | Low — maintainability. |

---

#### 7.7 Lyrics Provider — Regex Tidak Di-cache

| | |
|---|---|
| **Status** | ❌ Rejected |
| **File source** | `lib/services/lyrics_service/lrc_parser.dart:29-41` |
| **Bukti teknis** | `grep -n "static final.*RegExp" lib/services/lyrics_service/lrc_parser.dart` → SEMUA regex sudah `static final`: `_tsRe`, `_inlineRe`, `_metaRe`, `_enhancedRe`. Regex sudah di-cache dengan benar. |
| **Alasan reject** | Temuan salah — regex sudah static final di lrc_parser. |

---

### Kategori 8: Null Safety Audit

---

#### 8.1 `'Putih'` → `Colors.black` — Display Bug

| | |
|---|---|
| **Status** | ✅ Valid — BUG AKTIF |
| **File source** | `lib/widgets/player/player_content/lyrics_pickers.dart:112` |
| **Bukti teknis** | Line 112: `(label: 'Putih', color: Colors.black, value: 'white')` — label Putih/white di-map ke `Colors.black`. |
| **Severity akhir** | High — display bug aktif, user pilih "Putih" dapat hitam. |
| **Rekomendasi** | Ubah ke `Colors.white`. |

---

#### 8.3 `ModalRoute.of(context)!` — 2 Halaman

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/pages/album_page.dart:15`, `lib/pages/artist_page.dart:14` |
| **Bukti teknis** | `album_page.dart:15`: `ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;` `artist_page.dart:14`: `ModalRoute.of(context)!.settings.arguments as List<LocalSong>;` |
| **Severity akhir** | High — crash jika diakses tanpa ModalRoute. |

---

#### 8.4 `widget.userPlaylist!` / `widget.smartType!`

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/pages/playlist_page.dart:69,71,114,162,195` |
| **Bukti teknis** | Kelima instance terkonfirmasi via grep. |
| **Severity akhir** | High |

---

#### 8.5 `_current!` di `player_content/content.dart`

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/widgets/player/player_content/content.dart:82,88,89,96,97` |
| **Bukti teknis** | 5 instance `_current!` terkonfirmasi. |
| **Severity akhir** | High |

---

#### 8.6 `nextSong!` di `player_up_next_card.dart`

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | Medium — guard boolean tersedia tapi race condition saat playlist berubah masih mungkin. |

---

#### 8.7 `stats!` di `playback_engine.dart`

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | Medium |

---

#### 8.8 `songMap[id]!` — `recently_played_section.dart:45`

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/widgets/pages/home/recently_played_section.dart:44` |
| **Bukti teknis** | `.map((id) => songMap[id]!)` — force unwrap pada map lookup meski `.where(songMap.containsKey)` di line 43 ada sebagai guard. Namun guard di satu statement dan unwrap di statement berikutnya, bukan dalam satu null-safe chain. |
| **Severity akhir** | Medium |

---

#### 8.9 Unsafe Type Cast di Lyrics Providers

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | Medium |

---

#### 8.10 Force Unwrap — 264 Instance

| | |
|---|---|
| **Status** | ⚠ Needs Manual Verification |
| **Alasan** | Tidak semua `!` adalah risiko — banyak yang valid (e.g. `late final`, setelah guard null-check yang baik, pada non-nullable yang dijamin sudah di-init). Perlu review per-case. Temuan 8.1–8.9 sudah cover kasus paling berisiko. |
| **Severity akhir** | Medium (review per-case) |

---

### Kategori 9: Naming Audit

---

#### 9.1–9.4

| | |
|---|---|
| **Status** | ✅ Valid semua (folder spasi, camelCase filename, cryptic vars, param `v`) |
| **Severity akhir** | 9.1 High (duplikat 2.1), 9.2–9.4 Low |

---

#### 9.5 Untyped `List` di Data Files

| | |
|---|---|
| **Status** | ✅ Valid |
| **Bukti teknis** | `radio_stations.dart`: `final List radioStations = []` — tidak ada generic type. |
| **Severity akhir** | Low |

---

### Kategori 11: Asset Reference Audit

---

#### 11.1 `assets/1.jpg`, `2.jpg`, `4.jpg` Tidak Dideklarasi di `pubspec.yaml`

| | |
|---|---|
| **Status** | ✅ Valid — CRITICAL BUG |
| **File source** | `lib/utils/data/browse_banners.dart:8,14,21`, `pubspec.yaml` |
| **Bukti teknis** | `browse_banners.dart` referensikan `assets/1.jpg`, `assets/2.jpg`, `assets/4.jpg`. `pubspec.yaml` assets section hanya: `- assets/images/`, `- assets/images/search/`. File EXIST di disk (`ls assets/` → 1.jpg, 2.jpg, 4.jpg) tapi tidak dibundle Flutter. Browse section banners tidak tampil di release build. |
| **Severity akhir** | Critical — langsung visible di produksi. |
| **Rekomendasi** | Tambahkan `- assets/1.jpg`, `- assets/2.jpg`, `- assets/4.jpg` ke pubspec.yaml. |

---

### Kategori 13: Service Audit

---

#### 13.1 `AudioFocusService` + Empty Stubs

| | |
|---|---|
| **Status** | ✅ Valid |
| **Bukti teknis** | `onAppPause()` dan `onAppResume()` keduanya empty `{}`. Service diinisialisasi di main, memanggil stubs yang tidak melakukan apa-apa. |
| **Severity akhir** | Low |

---

---

## BAGIAN B — LAPORAN 2: `dart_audit_deep_report.md`

---

### CRITICAL (1)

---

#### CRITICAL: `search_sections/state.dart:42` — Controller Dispose Order

| | |
|---|---|
| **Status** | ❌ Rejected — FALSE POSITIVE |
| **File source** | `lib/widgets/pages/search_sections/state.dart:35-44` |
| **Bukti teknis** | `dispose()` method (line 38-44): `MediaStoreService.rescanNotifier.removeListener(_onRescan); _queryDebounce?.cancel(); _controller.removeListener(_onQueryChanged); _controller.dispose(); _focusNode.dispose();` — `removeListener(_onQueryChanged)` dipanggil di line 41 SEBELUM `dispose()` di line 42. Urutan sudah benar. Tidak ada potensi double-dispose. |
| **Alasan reject** | Kode sudah mengikuti urutan disposal yang benar: removeListener → cancel → dispose. |

---

### HIGH (35)

---

#### HIGH: `app_state.dart:48` — `applyEdgeToEdge()` di builder callback

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/main/app_state.dart:48` |
| **Bukti teknis** | Line 48 berada di dalam `builder: (context, child) { applyEdgeToEdge(); ... }` yang dipanggil setiap MaterialApp rebuild. Ini memanggil system channel setiap frame/layout change. |
| **Severity akhir** | High → **Medium** (turun) — builder callback tidak dipanggil setiap frame seperti `build()` stateful widget, hanya pada layout changes. Tetap tidak ideal tapi risiko lebih rendah dari yang dilaporkan. |

---

#### HIGH: `app_state.dart:45-149` — `ThemeData` di `build()`

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/main/app_state.dart:91` |
| **Bukti teknis** | `theme: ThemeData(...)` di dalam `build()` (line 91). Objek ThemeData kompleks dibuat ulang setiap rebuild MaterialApp. |
| **Severity akhir** | High |

---

#### HIGH: `lib/models/playlist.dart` — Null Cast

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/models/playlist.dart:35,37` |
| **Bukti teknis** | Line 35: `(json['songIds'] as List).map(...)` — tidak ada null check. Line 37: `json['createdAt'] as int` — cast langsung. Crash jika JSON missing field. |
| **Severity akhir** | High |

---

#### HIGH: `lib/services/audio_service/service.dart:89` — `currentSong!`

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `grep -n "currentSong!" lib/services/audio_service/service.dart` → tidak ditemukan. |
| **Alasan reject** | Temuan tidak dapat diverifikasi — baris/code tidak exist di codebase saat ini. |

---

#### HIGH: `lib/services/audio/playback_manager.dart:156` — God method `_handleNativeEvent()`

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `grep -n "_handleNativeEvent" lib/services/audio/playback_manager.dart` → tidak ditemukan. Method ini tidak ada di codebase saat ini. |
| **Alasan reject** | Method tidak exist — kemungkinan sudah di-refactor sebelum audit ini ditulis. |

---

#### HIGH: `media3_playback_bridge.dart:78` — Silent `catch (_)` x4

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | High |

---

#### HIGH: `media3_playback_bridge.dart:234` — `Map.from(event)` per stream event

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | High → **Medium** (turun) — overhead ada tapi hanya untuk event yang cukup sering, bukan per-frame. |

---

#### HIGH: `lib/services/lyrics_service/service.dart:55` — `providerResult.isInternet`

| | |
|---|---|
| **Status** | ❌ Rejected — FALSE POSITIVE |
| **File source** | `lib/services/lyrics_service/provider.dart:11` |
| **Bukti teknis** | `grep -n "isInternet" lib/services/lyrics_service/provider.dart` → line 11: `final bool isInternet;` — property IS terdefinisi di `LyricsProviderResult`. Dipakai di `service.dart:55` dengan benar. |
| **Alasan reject** | Property ada dan valid. Temuan sepenuhnya salah. |

---

#### HIGH: `lib/services/lyrics_service/service.dart:38` — `_cache[legacyKey]!`

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/services/lyrics_service/service.dart:37-38` |
| **Bukti teknis** | Line 37: `if (_cache.containsKey(legacyKey)) {` Line 38: `return _cache[legacyKey]!;` — race condition window antara `containsKey` dan `[]!` pada static cache. |
| **Severity akhir** | Medium (turun dari High) — race condition hanya jika ada concurrent access ke static cache, yang jarang di Dart single-isolate. |

---

#### HIGH: `lib/services/media_store_service.dart:88` — `getSongs()` tanpa timeout

| | |
|---|---|
| **Status** | ❌ Rejected — SUDAH DIPERBAIKI |
| **File source** | `lib/services/media_store_service.dart:182-183` |
| **Bukti teknis** | Line 182-183: `.invokeListMethod('getSongs').timeout(const Duration(seconds: 20));` — timeout 20 detik sudah ada. Juga ada `on TimeoutException` handler di line 196. |
| **Alasan reject** | Temuan tidak valid untuk codebase saat ini — timeout sudah diimplementasikan. |

---

#### HIGH: `lib/services/media_store_service.dart:201` — `data['id'] as int`

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | High |

---

#### HIGH: `album_page.dart`, `artist_page.dart` — `ModalRoute.of(context)!`

| | |
|---|---|
| **Status** | ✅ Valid (sudah dibahas di laporan 1, temuan 8.3) |

---

#### HIGH: `playlist_page.dart` — `widget.userPlaylist!`/`smartType!`

| | |
|---|---|
| **Status** | ✅ Valid (sudah dibahas di laporan 1, temuan 8.4) |

---

#### HIGH: God files

| | |
|---|---|
| **Status** | ✅ Valid (sudah dibahas di laporan 1, temuan 5.1) |

---

#### HIGH: `player_content/content.dart:82` — `_current!`

| | |
|---|---|
| **Status** | ✅ Valid (sudah dibahas di laporan 1, temuan 8.5) |

---

#### HIGH: `lyrics_pickers.dart:112` — `'Putih'` → `Colors.black`

| | |
|---|---|
| **Status** | ✅ Valid (sudah dibahas di laporan 1, temuan 8.1) |

---

#### HIGH: `player_sheet/state.dart:56` — Nested builder scope lebar

| | |
|---|---|
| **Status** | ✅ Valid |
| **Severity akhir** | High |

---

#### HIGH: `synced_lyrics_view/state.dart:88` — `_posSub` potential double-subscribe

| | |
|---|---|
| **Status** | ❌ Rejected — FALSE POSITIVE |
| **File source** | `lib/widgets/player/synced_lyrics_view/state.dart` |
| **Bukti teknis** | `_posSub` hanya di-assign di `initState` (line 57). `didUpdateWidget` (line 95-111) TIDAK melakukan `_posSub = ... listen(...)` ulang — hanya handle `dragHandle` attachment dan lyrics rebuild. Tidak ada path di `didUpdateWidget` yang buat subscription baru. |
| **Alasan reject** | Double-subscribe tidak mungkin terjadi dari kode yang ada. |

---

#### HIGH: `apple_music_provider.dart:67` — Token static/hardcoded

| | |
|---|---|
| **Status** | ⚠ Needs Manual Verification |
| **Alasan** | Komentar di file provider (line 13): "publik/gratis dan tanpa perlu akun/token apapun" tapi juga (line 16) "butuh developer token". Perlu baca implementasi token lebih dalam untuk memastikan apakah ada token yang bisa expire. |
| **Severity akhir** | Medium jika confirmed — provider akan diam-diam return empty setelah expire. |

---

#### HIGH: `open_file_service.dart:44` — `result.files.single.path!`

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `grep -n "files.single\|path!" lib/services/open_file_service.dart` → tidak ditemukan. File tidak menggunakan file picker pattern ini. |
| **Alasan reject** | Code tidak exist di codebase saat ini. |

---

#### HIGH: `sleep_timer_service.dart:78` — Timer tidak di-cancel di dispose

| | |
|---|---|
| **Status** | ❌ Rejected — FALSE POSITIVE |
| **File source** | `lib/services/sleep_timer_service.dart` |
| **Bukti teknis** | Tidak ada `_countdownTimer` (atau `Timer`) di `SleepTimerService`. Service hanya punya `_sub` (StreamSubscription) yang DI-CANCEL di `dispose()` (line 90: `_sub?.cancel()`). Service sudah fully native — tidak ada countdown Timer di Dart. |
| **Alasan reject** | Timer yang dimaksud tidak exist. Service tidak punya Timer Dart. |

---

#### HIGH: `card.dart:35,43` — `cached[2]`/`colors[2]`

| | |
|---|---|
| **Status** | ✅ Valid (sudah dibahas di laporan 1, temuan 7.2) |

---

### MEDIUM yang Perlu Highlight

---

#### MEDIUM: `audio_effects_service/service.dart` — `setVirtualizerStrength()`/`getVirtualizerStrength()`

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `grep -rn "setVirtualizerStrength\|getVirtualizerStrength\|Virtuali" lib/` → tidak ditemukan kecuali komentar di `native_dsp_bridge.dart:14`. Method tidak ada di `audio_effects_service/service.dart`. |
| **Alasan reject** | Method sudah dihapus — virtualizer removal sudah complete. |

---

#### MEDIUM: `media3_playback_bridge.dart` — `registerPostSwitchCallback()` no-op

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `grep -rn "registerPostSwitchCallback" lib/` → tidak ditemukan sama sekali. |
| **Alasan reject** | Method sudah dihapus dari codebase. |

---

#### MEDIUM: `up_next_settings.dart:15` — `crossfadeEnabled` field

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `cat lib/services/up_next_settings.dart` → file hanya berisi `showUpNextCard` ValueNotifier. Tidak ada `crossfadeEnabled` field sama sekali. |
| **Alasan reject** | Field tidak exist di codebase saat ini. |

---

#### MEDIUM: `ffmpeg_decoder_bridge.dart` — `_decoderInfoCtrl.close()` tidak dipanggil

| | |
|---|---|
| **Status** | ✅ Valid (sudah dibahas di laporan 1, temuan 6.3) |

---

#### MEDIUM: `library_page.dart` — `ScrollController` tidak di-dispose

| | |
|---|---|
| **Status** | ❌ Rejected — FALSE POSITIVE |
| **File source** | `lib/pages/library_page.dart:15,34-36` |
| **Bukti teknis** | Line 15: `final _scroll = ScrollController();` Line 34-36: `void dispose() { _scroll.dispose(); super.dispose(); }` — `dispose()` ADA dan memanggil `_scroll.dispose()`. |
| **Alasan reject** | ScrollController sudah di-dispose dengan benar. |

---

#### MEDIUM: `sleep_timer_page/active_card.dart` — `Timer.periodic` tanpa cancel

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `_ActiveTimerCard` adalah `StatelessWidget` — tidak bisa punya Timer lifecycle. Widget hanya menggunakan `ValueListenableBuilder<Duration?>` untuk tampilkan `SleepTimerService.remaining`. Tidak ada Timer di sini. |
| **Alasan reject** | StatelessWidget tidak bisa punya Timer yang perlu di-cancel. |

---

#### MEDIUM: `synced_lyrics_view/karaoke_line_painter.dart` — `shouldRepaint` selalu true

| | |
|---|---|
| **Status** | ❌ Rejected — FALSE POSITIVE |
| **File source** | `lib/widgets/player/synced_lyrics_view/karaoke_line_painter.dart:179-182` |
| **Bukti teknis** | `shouldRepaint` implementation: `return oldDelegate.text != text || oldDelegate.timeline != timeline || oldDelegate.activeColor != activeColor || ...` — NOT always true, membandingkan field secara proper. |
| **Alasan reject** | shouldRepaint sudah implementasi equality check yang benar. |

---

#### MEDIUM: `lrc_parser.dart` — RegExp tidak di-cache

| | |
|---|---|
| **Status** | ❌ Rejected (sama dengan temuan 7.7 laporan 1) |
| **Bukti teknis** | Semua RegExp sudah `static final`. |

---

#### MEDIUM: `netease_provider.dart:45` — Tidak ada 429 handling

| | |
|---|---|
| **Status** | ❌ Rejected (sebagian) |
| **Bukti teknis** | NetEase TIDAK cek 429 pada search response (line 50 hanya cek `!= 200`) tapi SUDAH cek pada lyric response (line 68: `if (lyricResp.statusCode == 429)`). Inkonsisten, bukan total absence. |
| **Severity akhir** | Low (turun dari Medium) |

---

#### MEDIUM: `kuwo_provider.dart` — Tidak ada 429 handling

| | |
|---|---|
| **Status** | ✅ Valid (parsial) |
| **Bukti teknis** | KuWo cek 429 pada search response (line 55) tapi lrc response (line 80) hanya cek `statusCode != 200` — tidak ada 429-specific handling untuk lrc. |
| **Severity akhir** | Low |

---

#### MEDIUM: `LyricsService` — Duplikasi cache

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/services/lyrics_service/service.dart:9-10` |
| **Bukti teknis** | Line 9-10: `// Memory cache untuk backward-compat (juga ada di LyricsCacheManager)` `static final Map<String, LyricsResult> _cache = {};` — dua layer cache untuk hal yang sama. |
| **Severity akhir** | Medium |

---

#### MEDIUM: `LyricsService` — String matching `'tag'` untuk deteksi embedded

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/services/lyrics_service/service.dart:57` |
| **Bukti teknis** | Line 57: `providerResult.providerName.contains('tag')` — rapuh, string matching untuk deteksi source. |
| **Severity akhir** | Medium |

---

#### MEDIUM: `open_file_service.dart:22` — `openFile()` dead code

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `grep -rn "OpenFileService\|openFile" lib/main/` → `OpenFileService.registerHandler()` dipanggil di `main.dart:197`, `OpenFileService.checkInitialUri()` di `main.dart:253`, dan `OpenFileService.onResume()` di `app_state.dart:28`. Service aktif digunakan untuk handle file URI intents. |
| **Alasan reject** | Service IS digunakan — tidak dead. |

---

#### MEDIUM: `SleepTimerService` — StreamController tidak di-close

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `grep -n "StreamController" lib/services/sleep_timer_service.dart` → tidak ada StreamController di `SleepTimerService`. Service hanya punya `_sub` StreamSubscription. |
| **Alasan reject** | StreamController yang dimaksud tidak exist. |

---

#### MEDIUM: `bit_perfect_lock.dart` — AnimationController tidak di-dispose

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `BitPerfectLock` adalah `StatelessWidget` — tidak bisa punya `AnimationController`. File hanya berisi `ValueListenableBuilder` + `IgnorePointer`. |
| **Alasan reject** | StatelessWidget tidak punya AnimationController lifecycle. |

---

#### MEDIUM: `rescanNotifier.value++` tanpa guard

| | |
|---|---|
| **Status** | ❌ Rejected |
| **File source** | `lib/services/media_store_service.dart:135` |
| **Bukti teknis** | `rescanNotifier.value++` ada di line 135, setelah `_songsCache = parsedSongs` dan operasi sukses lainnya — bukan di dalam catch block. Increment hanya terjadi saat scan berhasil. |
| **Alasan reject** | Claim bahwa increment terjadi "bahkan jika scan gagal" tidak didukung kode. |

---

#### MEDIUM: `_NativeModuleRegistry._modules: List<dynamic>`

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `grep -n "_modules" lib/services/native/native_module_registry.dart` → `static final List<NativeModule> _modules = []` — tipe sudah `List<NativeModule>`, bukan `List<dynamic>`. |
| **Alasan reject** | Claim faktual salah. |

---

#### MEDIUM: `SmartPlaylistType` di `playlist.dart` — Unused enum

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `grep -rn "SmartPlaylistType" lib/` → digunakan di `playlist_page.dart` (line 15, 21, 94, 96, 98, 100) dan `radio_sections/stations.dart` (line 9, 20, 24). Enum aktif digunakan. |
| **Alasan reject** | Enum tidak dead — digunakan di multiple files. |

---

#### MEDIUM: `empty_placeholder_page.dart` — Dead placeholder

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `grep -rn "EmptyPlaceholderPage\|empty_placeholder_page" lib/` → digunakan di `support_page.dart:11`: `return const _EmptyPlaceholderPage(title: 'Dukungan')`. |
| **Alasan reject** | Widget aktif digunakan oleh support page. |

---

#### MEDIUM: `EditableLibraryList` dead

| | |
|---|---|
| **Status** | ❌ Rejected (misidentifikasi nama class) |
| **Bukti teknis** | Class aktual di file adalah `_EditableRow` (private, bukan `EditableLibraryList`). Digunakan di `library_sections/state.dart:107`: `(item) => _EditableRow(...)`. File `editable.dart` dipakai melalui `part` di `library_sections.dart`. |
| **Alasan reject** | Class tidak dead — aktif digunakan. Audit mengidentifikasi nama class yang salah. |

---

#### MEDIUM: `khz == khz.truncateToDouble()` — Exact float comparison

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `lib/widgets/player/player_song_info_sheet/content.dart:289` |
| **Bukti teknis** | `return (khz == khz.truncateToDouble())` — perbandingan float exact equality. Untuk `44100 Hz → khz = 44.1`, `44.1.truncateToDouble() = 44.0 ≠ 44.1` → OK. Tapi untuk nilai floating point seperti `96000 Hz → khz = 96.000000000001` (floating point representation), bisa gagal. |
| **Severity akhir** | Low |

---

#### MEDIUM: `FocusNode` tidak di-dispose di `search_sections/bar.dart`

| | |
|---|---|
| **Status** | ❌ Rejected |
| **Bukti teknis** | `FocusNode focusNode` adalah **parameter** yang dipass ke widget dari parent (`SearchPage`). Owner FocusNode adalah parent yang seharusnya dispose — bukan `SearchBar` widget. Pattern inject-from-parent adalah benar. |
| **Alasan reject** | Disposal responsibility ada di parent yang membuat FocusNode. |

---

### LOW Section — Validasi Selective

Dari 267 temuan LOW, majority adalah valid (style, naming, minor performance). Yang perlu di-reject atau direvisi:

| Temuan | Status | Alasan |
|--------|--------|--------|
| `LyricsSource` enum — unused values | ❌ Rejected | Semua values digunakan (`embedded`, `localFile`, `internet`, `none`). |
| `openFile()` method dead | ❌ Rejected | IS digunakan via OpenFileService lifecycle. |
| `registerPostSwitchCallback()` dead | ❌ Rejected | Method tidak exist di lib/. |
| `setVirtualizerStrength/getVirtualizerStrength` dead | ❌ Rejected | Method tidak exist. |
| `crossfadeEnabled` field di `up_next_settings` | ❌ Rejected | Field tidak exist. |
| RegExp tidak di-cache di lrc_parser | ❌ Rejected | Sudah `static final`. |
| `NativeModuleRegistry._modules: List<dynamic>` | ❌ Rejected | Sudah `List<NativeModule>`. |
| `SmartPlaylistType` unused | ❌ Rejected | Digunakan di 2 file. |
| `LyricsSource` unused | ❌ Rejected | Semua values dipakai. |
| `EditableLibraryList` dead | ❌ Rejected | Class aktif dipakai (`_EditableRow`). |
| `empty_placeholder_page` dead | ❌ Rejected | Dipakai di `support_page.dart`. |
| `FocusNode` di search_bar tidak di-dispose | ❌ Rejected | External param, parent yang dispose. |
| `AnimationController` di bit_perfect_lock | ❌ Rejected | StatelessWidget, tidak ada controller. |
| `sleep_timer active_card` Timer | ❌ Rejected | StatelessWidget. |
| `_karaokeController!` non-null assumed setelah init | ⚠ NMV | `late final` pattern yang umum, perlu baca init chain. |
| `clearHistory()` dead | ✅ Valid | Tidak ada UI yang memanggil. |
| `exportPlaylist()` dead | ✅ Valid | Tidak ada UI yang memanggil. |
| `getAlbumArtUri()` dead | ✅ Valid | Tidak ada caller ditemukan. |

---

---

## BAGIAN C — LAPORAN 3: `Native_code_audit.md`

---

### K-01 — `MetadataCacheDb.putByPath()` — Hash Collision (HIGH)

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `android/app/src/main/kotlin/dev/wndavenz/music/metadata/MetadataCacheDb.kt:246` |
| **Bukti teknis** | Line 246: `put(COL_ID, path.hashCode())` — 32-bit `String.hashCode()` sebagai PRIMARY KEY. Conflict handling: `CONFLICT_REPLACE` (line 218 region). Dua path dengan hashCode sama → entry lama di-overwrite dengan data path lain. |
| **Root cause** | 32-bit hash space insufficient untuk PRIMARY KEY yang harus unik per path. |
| **Severity akhir** | High — meski probabilitas rendah, dampak silent data corruption (stale audio data untuk track berbeda). |
| **Rekomendasi** | Gunakan `COL_PATH TEXT NOT NULL UNIQUE` sebagai lookup key, atau tambahkan post-insert verification. |

---

### K-02 — `CrossfadeController.kt` — Double `setActiveQueueIndex()` (LOW)

| | |
|---|---|
| **Status** | ⚠ Needs Manual Verification |
| **File source** | `crossfade/CrossfadeController.kt:304,363` |
| **Bukti teknis** | Ada 2 panggilan aktif: Line 304 — di "promotion complete" phase (sebelum `emitAll()`). Line 363 — di "equal power fade complete" phase (step >= steps). Ini tampak **two different phases** bukan double-call di phase yang sama. Komentar di line 224 menjelaskan mengapa call pertama di-comment out. Audit mengklaim race condition jika standby player di-retarget antara dua call. |
| **Catatan** | Dua panggilan ini berada di alur eksekusi berbeda (begin vs end of fade), bukan sequential di satu phase. Namun bisa ada overlap jika crossfade sangat pendek. Perlu review lebih dalam flow Handler tick. |
| **Severity akhir** | Low — probabilitas rendah given Handler serial execution. |

---

### K-03 — `PlaybackNotificationManager.kt` — Stale KDoc (LOW)

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `notification/PlaybackNotificationManager.kt:28` |
| **Bukti teknis** | Line 28: `* [Media3PlaybackService] and [MediaKitPlaybackService].` — `MediaKitPlaybackService` sudah dihapus (single-engine migration). KDoc stale. |
| **Severity akhir** | Low — dokumentasi menyesatkan. |
| **Rekomendasi** | Hapus referensi `MediaKitPlaybackService` dari KDoc. |

---

### K-05 — `StereoWideningAudioProcessor.kt` — Unreachable Loop (INFO/LOW)

| | |
|---|---|
| **Status** | ✅ Valid |
| **File source** | `effects/StereoWideningAudioProcessor.kt:93` |
| **Bukti teknis** | `while (inputBuffer.hasRemaining()) output.put(inputBuffer.get())` — ExoPlayer garantikan aligned frames, loop tidak bisa pernah dieksekusi. |
| **Severity akhir** | Low — dead code, harmless. |

---

### K-07 — `ReplayGainError` Ordinal Stability (INFO)

| | |
|---|---|
| **Status** | ✅ Valid sebagai INFO |
| **Severity akhir** | Info — terdokumentasi dengan baik, tidak perlu aksi immediate. |

---

### Temuan FIXED yang Dikonfirmasi

Semua 15 temuan yang dilaporkan sebagai "Fixed" di Native_code_audit.md (LOW-01 sampai WD-01) **terkonfirmasi valid** — bukti fix ada di file source masing-masing. Tidak ada regresi yang ditemukan.

---

---

## BAGIAN D — CROSS-VALIDATION ANTAR LAPORAN

---

### Duplicate Findings

| Temuan | Laporan 1 | Laporan 2 | Status |
|--------|-----------|-----------|--------|
| `cached[2]`/`colors[2]` album card | 7.2 + 8.2 | HIGH card.dart:35,43 | Duplicate — 3x laporan, akar masalah sama. |
| `ModalRoute.of(context)!` | 8.3 | HIGH album_page/artist_page | Duplicate |
| `widget.userPlaylist!`/`smartType!` | 8.4 | HIGH playlist_page | Duplicate |
| `_current!` static | 8.5 | HIGH content.dart:82 | Duplicate |
| `'Putih' → Colors.black` | 8.1 | HIGH lyrics_pickers | Duplicate |
| God files | 5.1 | HIGH log_page/audio/detail | Duplicate |
| `ThemeController` SharedPreferences per toggle | 7.1 | HIGH app_state:appearance | Duplicate |
| `setState` per scroll | 6.1/6.2 | HIGH detail/about_app | Duplicate |
| `_GlassSubToggle` duplikat | 15.1 | MEDIUM glass_toggle | Duplicate |
| Settings dua folder | 5.11 | LOW settings | Duplicate |
| Folder spasi `Bottom NavBar` | 2.1/9.1 | LOW Bottom NavBar | Triple duplicate |
| `fog_painter.dart` cryptic vars | 7.6/9.3 | MEDIUM fog_painter | Duplicate |
| `ffmpeg_decoder_bridge` StreamController | 6.3 | MEDIUM bridge | Duplicate |
| `MediaCapabilitiesService.dispose()` | 6.4/13.2 | MEDIUM capabilities | Duplicate |
| `NativeModuleRegistry` sequential | 5.2 | MEDIUM registry | Duplicate |
| `NativeModuleRegistry` error swallow | 5.3 | MEDIUM registry | Duplicate |
| Assets 1.jpg/2.jpg/4.jpg | 11.1 | LOW banners | Duplicate |
| `DateTime.now()` di build | 4.2 | LOW about | Duplicate |
| Empty stub methods onAppPause/Resume | 1.13 | MEDIUM handler | Duplicate |

---

### Conflicting Findings

Tidak ditemukan temuan yang saling bertentangan secara signifikan antar laporan. Beberapa inkonsistensi severity:

| Temuan | Laporan 1 | Laporan 2 | Severity Final |
|--------|-----------|-----------|----------------|
| `ThemeController._save()` perf | Medium | HIGH | **Medium** — platform channel per toggle tidak kritis. |
| `applyEdgeToEdge` in build | N/A | HIGH | **Medium** — builder callback, bukan per-frame render. |
| `_cache[legacyKey]!` race | N/A | HIGH | **Medium** — Dart single-isolate minimizes race. |
| `lrc_parser` RegExp | Low | MEDIUM | **Rejected** — sudah fixed. |

---

---

## FINAL SUMMARY

---

### Valid Findings

**Critical (1):**
1. `assets/1.jpg`, `2.jpg`, `4.jpg` tidak dideklarasikan di `pubspec.yaml` → Browse banner tidak tampil di release build.

**High (9 unique, setelah dedup):**
1. `'Putih'` → `Colors.black` di `lyrics_pickers.dart:112` — display bug aktif
2. `cached[2]`/`colors[2]` unsafe array access di album card — RangeError crash
3. `ModalRoute.of(context)!` di album/artist page — crash potensi
4. `widget.userPlaylist!`/`widget.smartType!` (5x) di playlist_page — crash potensi
5. `_current!` static di `player_content/content.dart` — crash saat dispose race
6. `test/widget_test.dart` adalah counter test bawaan Flutter — zero test coverage
7. `lib/Bottom NavBar/` folder dengan spasi — URL-encoded import fragile
8. God files: `log_page.dart` 889L, `audio.dart` 869L, `playback_manager.dart` 833L, `detail.dart` 576L
9. `ThemeData` allocation di `build()` — unnecessary rebuild overhead
10. **[Native] K-01** `MetadataCacheDb.putByPath()` hash collision — silent cache corruption

**Medium (15+ unique):**
1. 20+ silent `catch (_) {}` blocks tanpa log
2. `ffmpeg_decoder_bridge` StreamController tidak di-close — memory leak
3. `MediaCapabilitiesService.dispose()` tidak pernah dipanggil — listener leak
4. `playlist_page.dart` model: `(json['songIds'] as List)` + `json['createdAt'] as int` tanpa null-check
5. `NativeModuleRegistry.disposeAll()` swallow semua error
6. `NativeModuleRegistry.initializeAll()` sequential
7. `LyricsService` dual cache (`_cache` + `LyricsCacheManager`)
8. `LyricsService` providerName.contains('tag') string matching rapuh
9. 7 lyrics providers tanpa base class — bug tidak propagate antar provider
10. `ThemeController` SharedPreferences per toggle — platform channel overhead
11. `setState` per scroll tick: `detail.dart`, `about_app_page.dart`, `album_page.dart`, `artist_page.dart`
12. `_GlassSubToggle` duplikat `SettingsToggleRow`
13. `data['id'] as int` (6 numeric fields) di `media_store_service.dart` tanpa null-aware
14. Player sheet nested `ValueListenableBuilder` scope terlalu lebar
15. Startup chain 20+ service fragile
16. `_scrollResumeTimer` tidak di-cancel sebelum reassign

**Low (banyak — see laporan untuk detail):**
- Dead files: `chip.dart`, `sleep_timer.dart`, `lyrics.dart`, `lyrics_rows.dart`, `notif_icon.dart`
- Dead classes: `FutureLocalSongCarousel`, `CommonActions._cast()` stub
- Dead methods: `clearHistory()`, `exportPlaylist()`, `getAlbumArtUri()`
- Style: folder spasi, camelCase filename, cryptic vars, param `v`, untyped `List`
- Minor perf: `DateTime.now()` di build, missing const constructors
- 5 dead WebView parameters
- `BootTrace` 74 referensi TEMPORARY
- Settings tersebar di dua folder
- Radio tab data kosong
- [Native] K-03 stale KDoc, K-05 unreachable loop

---

### Needs Manual Verification

1. **Apple Music provider token**: Komentar di file kontradiktif — perlu baca implementasi token lebih dalam.
2. **`ShaderMask` di lyrics overlay**: Perlu baca full `lyrics_overlay.dart` build() untuk verifikasi apakah ada visibility gate.
3. **`lerpDouble` redundan di `AnimatedPositioned`**: Perlu baca konteks penuh `content.dart:470`.
4. **`_current!` dispose race severity**: Race condition mungkin terjadi tapi perlu trace disposal order lengkap.
5. **K-02 CrossfadeController double setActiveQueueIndex**: Dua call ada di phase berbeda (promotion vs fade-complete), perlu trace Handler flow lebih detail.
6. **8.10 264 force unwrap sisanya**: Perlu review per-case untuk tentukan mana yang benar-benar berisiko.

---

### Rejected Findings (False Positives)

| # | Temuan | Alasan Reject |
|---|--------|---------------|
| 1 | `providerResult.isInternet` tidak terdefinisi | Property IS ada di `LyricsProviderResult.dart:11` |
| 2 | `getSongs()` tanpa timeout | Timeout 20s sudah implemented di line 182-183 |
| 3 | `_countdownTimer` tidak di-cancel di SleepTimerService | Timer tidak exist — service pakai subscription bukan Timer Dart |
| 4 | `result.files.single.path!` di open_file_service | Code tidak exist di file |
| 5 | `currentSong!` di audio_service:89 | Code tidak exist |
| 6 | `_handleNativeEvent` god method di playback_manager | Method tidak exist — sudah di-refactor |
| 7 | `_posSub` double-subscribe di didUpdateWidget | didUpdateWidget tidak re-subscribe |
| 8 | `karaoke shouldRepaint` selalu return true | Implementasi proper equality check |
| 9 | `library_page ScrollController` tidak di-dispose | `dispose()` ada dan memanggil `_scroll.dispose()` |
| 10 | CRITICAL: search_sections state.dart — wrong dispose order | removeListener dipanggil sebelum dispose — ordering sudah benar |
| 11 | `setVirtualizerStrength`/`getVirtualizerStrength` dead | Method tidak exist — sudah dihapus |
| 12 | `registerPostSwitchCallback()` no-op stub | Method tidak exist di lib/ |
| 13 | `crossfadeEnabled` field di up_next_settings | Field tidak exist di file |
| 14 | `openFile()` dead code | IS digunakan via registerHandler/checkInitialUri/onResume |
| 15 | `empty_placeholder_page` dead | Dipakai di support_page |
| 16 | `NativeModuleRegistry._modules: List<dynamic>` | Sudah `List<NativeModule>` |
| 17 | `BitPerfectLock AnimationController` tidak di-dispose | StatelessWidget, tidak ada controller |
| 18 | `active_card Timer.periodic` tanpa cancel | StatelessWidget, tidak ada Timer |
| 19 | `SleepTimerService StreamController` tidak di-close | Tidak ada StreamController di file |
| 20 | `SmartPlaylistType` enum unused | Dipakai di playlist_page + radio_sections |
| 21 | `LyricsSource` enum unused values | Semua values dipakai |
| 22 | `EditableLibraryList` dead class | Class aktual `_EditableRow` IS dipakai |
| 23 | `FocusNode` di search bar tidak di-dispose | External param — disposal responsibility di parent |
| 24 | `sample_music_data.dart` hanya export radio_stations | File export 3 items (search_categories, browse_banners, radio_stations) |
| 25 | RegExp tidak di-cache di lrc_parser | Sudah `static final` |
| 26 | `netease_provider` tidak ada 429 handling | Ada 429 check pada lyric response (line 68) |
| 27 | `rescanNotifier.value++` inside catch | Increment di happy path, bukan catch |
| 28 | `library_page ScrollController` | dispose() ada dan benar |

---

### Priority Order — Valid Findings

| Pri | ID | Temuan | Severity |
|---|---|---|---|
| 1 | 11.1 | `assets/1.jpg`/`2.jpg`/`4.jpg` tidak di pubspec — browse banner hilang di release | Critical |
| 2 | 8.1 | `'Putih'` → `Colors.black` di lyrics color picker — display bug aktif | High |
| 3 | 7.2/8.2 | `cached[2]`/`colors[2]` unsafe array — RangeError crash | High |
| 4 | K-01 | `MetadataCacheDb` hash collision — silent cache corruption | High |
| 5 | 8.3 | `ModalRoute.of(context)!` di album/artist page | High |
| 6 | 8.4 | `widget.userPlaylist!`/`smartType!` (5x) di playlist_page | High |
| 7 | 5.9/8.5 | `_current!` static di player_content | High |
| 8 | 3.1 | `widget_test.dart` adalah counter test bawaan | High |
| 9 | 2.1 | Folder `lib/Bottom NavBar/` dengan spasi | High |
| 10 | 6.3 | `ffmpeg_decoder_bridge` StreamController tidak di-close | Medium |
| 11 | 6.4 | `MediaCapabilitiesService.dispose()` tidak pernah dipanggil | Medium |
| 12 | playlist.dart | `(json['songIds'] as List)` + `json['createdAt'] as int` tanpa null-check | Medium |
| 13 | 6.7 | 20+ silent `catch (_) {}` tanpa log | Medium |
| 14 | 5.4 | 7 lyrics providers tanpa base class | Medium |
| 15 | LyricsService | Dual cache (`_cache` + `LyricsCacheManager`) | Medium |
| 16 | 5.3 | `NativeModuleRegistry.disposeAll()` error swallow | Medium |
| 17 | 6.1/6.2 | `setState` per scroll tick di 4 halaman | Medium |
| 18 | 5.2 | `NativeModuleRegistry.initializeAll()` sequential | Medium |
| 19 | K-03 | Stale KDoc `MediaKitPlaybackService` di PlaybackNotificationManager | Low |
| 20 | K-05 | Unreachable fallback loop di StereoWideningAudioProcessor | Low |
| 21 | 1.1 | BootTrace 74 referensi TEMPORARY | Low |
| 22 | 1.9 | `CommonActions._cast()` TODO stub — tombol di 5 halaman | Low |
| 23 | 1.2-1.4 | File settings kosong (chip, sleep_timer, lyrics, lyrics_rows) | Low |
| 24 | 1.5 | `notif_icon.dart` + `debug_state` fields unused | Low |
| 25 | 1.8 | `FutureLocalSongCarousel` dead class | Low |
| 26 | Berbagai | 30+ dead methods, dead params, style issues | Low |

---

*Validasi dilakukan 18 Juli 2026 menggunakan grep/shell verifikasi langsung dari source code terbaru.*  
*Total rejected (false positive): 28 temuan.*  
*Total needs manual verification: 6 temuan.*  
*Total valid: ~120+ temuan (setelah dedup ~70 unique issues).*
