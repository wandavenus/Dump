# Flutter & Dart Architecture Audit — 2026-07-22

Skills digunakan:
- `flutter/skills@flutter-apply-architecture-best-practices`
- `kevmoo/dash_skills@dart-best-practices`

---

## Ringkasan Eksekutif

| Kategori | Temuan | Status |
|---|---|---|
| Async tanpa error handling | 3 tempat | ✅ Diperbaiki sesi ini |
| Indentasi inkonsisten | 1 file | ✅ Diperbaiki sesi ini |
| Direct service calls dari UI | 4 tempat | ⚠️ Perlu diskusi (refactor besar) |
| Business logic dalam build() | 4 tempat | ⚠️ Perlu diskusi (refactor besar) |
| File terlalu besar (>300 baris) | 5 file | ⚠️ Dokumentasi saja |
| `Map<dynamic, dynamic>` di platform channel | 8 tempat | ✅ False positive — benar secara teknis |
| String concatenation `+\n` | 0 tempat | ✅ False positive — semua single-line interpolation |
| `const` constructor hilang | 0 tempat | ✅ False positive — semua sudah `const` |

---

## Temuan A — Diperbaiki Sesi Ini

### A1. Async onTap tanpa try/catch

**File:** `lib/widgets/play_shuffle_buttons.dart` (baris 28, 37)  
**File:** `lib/widgets/local_song_card/card.dart` (baris 20)

Ketiga `onTap` memanggil `AudioService` secara async tanpa `try/catch`.
Jika native channel melempar exception (service belum siap, queue error, dll),
exception meluncur ke Flutter framework dan muncul sebagai red-screen di debug
atau silent crash di release.

**Rule yang dilanggar:** Dart/Flutter — setiap `async` callback UI harus
menangkap exception agar UI tetap stabil.

**Fix:** ditambahkan `try/catch` dengan `LogService.log()` di ketiga tempat.

---

### A2. Indentasi inkonsisten

**File:** `lib/widgets/local_song_card/card.dart` (baris 49–61)

Widget `SizedBox` untuk artist text menggunakan indentasi 2-space alih-alih
4-space yang dipakai di seluruh file. Menyebabkan ketidakkonsistenan visual
yang menyulitkan review.

**Fix:** distandarkan ke 4-space.

---

## Temuan B — Perlu Diskusi (Refactor Besar)

### B1. Direct service calls dari UI layer

Beberapa widget memanggil service secara langsung dari `build()` atau callback,
melanggar prinsip MVVM dari skill Flutter Architecture.

| File | Service yang dipanggil |
|---|---|
| `lib/widgets/local_song_card/card.dart` | `AudioService.playSongAt` |
| `lib/widgets/play_shuffle_buttons.dart` | `AudioService.playSongAt`, `AudioService.toggleShuffle` |
| `lib/widgets/common_actions.dart` | `MediaStoreService.refreshSongs()` |
| `lib/widgets/pages/browse_sections/state.dart` | `MediaStoreService.getSongs()` |
| `lib/widgets/song_context_menu.dart` | `PlaylistService.isFavorite` |

**Rule yang dilanggar:** skill Flutter Architecture — Views tidak boleh
memanggil Services langsung; harus melalui ViewModel/Repository layer.

**Catatan konteks:** App ini menggunakan static service facades
(`AudioService`, `MediaStoreService`) sebagai pengganti ViewModel pattern.
Ini adalah trade-off yang disengaja agar state sharing antar widget lebih
sederhana. Refactor ke MVVM penuh akan membutuhkan pengenalan Provider/get_it
dan perombakan besar di semua halaman.

**Rekomendasi:** Pertimbangkan sebagai long-term goal, bukan fix segera.

---

### B2. Business logic dalam build()

| File | Deskripsi |
|---|---|
| `lib/widgets/common/swipe_to_dismiss_sheet.dart:42` | Kalkulasi `dragFraction` (clamp, pembagian) |
| `lib/widgets/unified_morph_player.dart:230` | Early-return guards berdasarkan state lagu |
| `lib/pages/album_page.dart:38` | Extract argumen dari `ModalRoute` |
| `lib/pages/home_page.dart` | Kalkulasi padding berdasarkan glass theme state |

**Rule yang dilanggar:** skill Flutter Architecture — logic di View hanya
boleh untuk UI-specific (animasi, layout constraints).

**Catatan:** sebagian (swipe drag fraction, padding kalkulasi) adalah
UI-specific logic yang masih dalam batas wajar. Yang benar-benar perlu
dipindah adalah `album_page.dart` — extract argumen sebaiknya di `initState`
atau constructor, bukan `build()`.

---

### B3. File terlalu besar

| File | Baris |
|---|---|
| `lib/services/audio/audio_effects_service/service.dart` | 872 |
| `lib/services/audio/playback_manager.dart` | 850 |
| `lib/widgets/unified_morph_player.dart` | 760 |
| `lib/services/audio_service/service.dart` | 737 |
| `lib/widgets/player/player_content/content.dart` | 706 |

**Rekomendasi:** pemecahan file bisa dilakukan per fitur saat ada
kesempatan refactor — tidak perlu dilakukan sekarang.

---

## Temuan C — False Positives (Tidak Perlu Aksi)

### C1. `Map<dynamic, dynamic>` di platform channel

`lib/models/local_song.dart` dan `lib/services/audio/media3/media3_playback_bridge.dart`
menggunakan `Map<dynamic, dynamic>` untuk hasil EventChannel/MethodChannel.
Ini **benar secara teknis** — Dart platform channel selalu mengembalikan
`Map<dynamic, dynamic>` dan harus di-cast secara eksplisit setelahnya.
Menggantinya dengan `Map<String, dynamic>` langsung akan runtime error.

### C2. String concatenation dengan `+`

Semua kasus yang ditemukan adalah single-line string interpolation untuk
format tanda (`${g > 0 ? '+' : ''}`) — bukan concatenation multi-baris
dengan `\n` yang dimaksud oleh Dart skill. Tidak ada aksi diperlukan.

### C3. Missing `const` constructor

`MyApp` dan `FirstPage` sudah memiliki `const` constructor. Laporan
subagent merupakan false positive.

---

## TODO/FIXME yang Ada di Codebase

| File | Komentar |
|---|---|
| `lib/main/app_state.dart:7` | `TODO(refactor)` — ThemeData constants |
| `lib/widgets/common_actions.dart:51` | `TODO: Cast function` |
| `lib/pages/settings_page/info_line.dart:3` | `TODO(cleanup)` — duplicate widgets |

Tidak blocking, bisa dikerjakan kapan saja.

---

*Audit dihasilkan oleh flutter/skills@flutter-apply-architecture-best-practices
dan kevmoo/dash_skills@dart-best-practices.*
