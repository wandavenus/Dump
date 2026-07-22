# Flutter & Dart Architecture — Revalidasi Audit 2026-07-22

Skills yang digunakan untuk revalidasi ini:
- `kevmoo/dash_skills@dart-modern-features` (Dart 3.x modern idioms)
- `alinaqi/claude-bootstrap@android-kotlin` (Kotlin coroutines & anti-patterns)
- SDK target: `>=3.12.2` — semua fitur Dart 3.0–3.7 tersedia penuh

> Ini adalah revalidasi dari `Flutter_Dart_Architecture_Audit_2026-07-22.md`.
> Status temuan lama dikonfirmasi ulang, dan temuan baru dari skill ditambahkan.

---

## Ringkasan Eksekutif

| Kategori | Sumber | Temuan | Aksi |
|---|---|---|---|
| Switch statement kuno (bisa jadi switch expression) | Dart modern skill | 2 tempat valid | ⚠️ Modernisasi opsional |
| Switch statement tidak bisa dimodernisasi | Dart modern skill | 3 tempat | ✅ False positive — terlalu kompleks |
| `sealed class` candidate | Dart modern skill | 0 tempat valid | ✅ False positive — `LyricsProvider` butuh extensibility |
| Null-aware element `?` candidate (List) | Dart modern skill | 1 tempat valid | ⚠️ Modernisasi opsional |
| Null-aware element `?` di Map | Dart modern skill | 0 tempat valid | ✅ False positive — Map butuh `if (x!=null)` |
| Digit separator angka besar | Dart + Kotlin skill | 4 angka | ⚠️ Fix kecil, readability |
| Kotlin GlobalScope / runBlocking | Android-Kotlin skill | 0 | ✅ Tidak ada pelanggaran |
| Kotlin MutableStateFlow publik | Android-Kotlin skill | 0 | ✅ Tidak ada pelanggaran |
| Temuan audit lama (A1, A2) | Audit sebelumnya | Diperbaiki sesi lalu | ✅ Masih berlaku |
| Temuan audit lama (B1, B2, B3) | Audit sebelumnya | Masih ada | ⚠️ Tidak berubah |

---

## Bagian 1 — Revalidasi Temuan Audit Sebelumnya

### ✅ A1 (Async tanpa try/catch) — Masih valid, sudah diperbaiki
`play_shuffle_buttons.dart`, `local_song_card/card.dart` — fix dari sesi sebelumnya masih berlaku.

### ✅ A2 (Indentasi inkonsisten) — Masih valid, sudah diperbaiki
`local_song_card/card.dart` — fix dari sesi sebelumnya masih berlaku.

### ⚠️ B1 (Direct service calls dari UI) — Masih ada, belum diubah
Pattern static service facade (`AudioService`, `MediaStoreService`) masih digunakan.
Keputusan sebelumnya tetap berlaku: ini trade-off yang disengaja, refactor ke MVVM adalah long-term goal.

### ⚠️ B2 (Business logic dalam build()) — Masih ada, belum diubah
`album_page.dart:38`, `unified_morph_player.dart:230` masih perlu perhatian.

### ⚠️ B3 (File terlalu besar) — Masih ada
Kelima file besar tidak berubah ukurannya.

### ✅ C1–C3 (False positives lama) — Dikonfirmasi ulang masih false positive
`Map<dynamic, dynamic>` channel, string interpolation, const constructor — semua masih benar.

---

## Bagian 2 — Temuan Baru dari Dart Modern Features Skill

### D1. Switch Statement yang Bisa Dimodernisasi ke Switch Expression

Dua switch statement valid sebagai kandidat modernisasi Dart 3:

---

#### D1a. `lib/services/native/bridges/native_dsp_bridge.dart:100`

**Kode saat ini:**
```dart
switch (regStatus) {
  case NativeRuntimeStatus.ok:
  case NativeRuntimeStatus.duplicateModule:
    _status = NativeModuleStatus.available;
  default:
    _status = NativeModuleStatus.unavailable;
}
```

**Seharusnya (Dart 3 — switch expression + OR pattern):**
```dart
_status = switch (regStatus) {
  NativeRuntimeStatus.ok || NativeRuntimeStatus.duplicateModule
      => NativeModuleStatus.available,
  _ => NativeModuleStatus.unavailable,
};
```

**Manfaat:** lebih ringkas, exhausiveness checker aktif jika `NativeRuntimeStatus` adalah enum.

---

#### D1b. `lib/bottom_nav_bar/bottom_nav/state.dart:92`

**Kode saat ini:**
```dart
Widget? page;
switch (settings.name) {
  case '/album':
    page = const WebView(child: AlbumPage());
  case '/artist':
    page = const WebView(child: ArtistPage());
  case '/artistlist':
    page = const WebView(child: ArtistList());
  case '/musiclist':
    page = const WebView(child: MusicList());
  default:
    return null;
}
return ZoomFadeRoute(page: page!, settings: settings);
```

**Seharusnya (Dart 3 — switch expression):**
```dart
final Widget? page = switch (settings.name) {
  '/album'     => const WebView(child: AlbumPage()),
  '/artist'    => const WebView(child: ArtistPage()),
  '/artistlist' => const WebView(child: ArtistList()),
  '/musiclist'  => const WebView(child: MusicList()),
  _            => null,
};
if (page == null) return null;
return ZoomFadeRoute(page: page, settings: settings);
```

**Manfaat:** `page` jadi `final` (immutable), tidak ada `!` bang operator.

---

### D2. False Positive — Switch Statement Terlalu Kompleks untuk Switch Expression

Tiga switch lain yang dilaporkan subagent **tidak bisa** dimodernisasi:

| File | Alasan |
|---|---|
| `lib/pages/playlist_page.dart:100` (`_smartIds`) | Case `mostPlayed` mengandung 4 statement async — switch expression hanya bisa 1 ekspresi per arm |
| `lib/widgets/pages/radio_sections/stations.dart:57` | Setiap case assign ke beberapa variabel (`ids`, `_count`) — bukan single expression |
| `lib/pages/settings_page/debug.dart:158` | Sudah campuran: switch statement lama di atas, switch expression modern di bawah (baris 172, 177) — bagian atas kompleks (fall-through ke string conditional), biarkan |

**Kesimpulan:** Tidak perlu aksi untuk ketiga file ini.

---

### D3. False Positive — `LyricsProvider` Tidak Cocok untuk `sealed class`

Subagent melaporkan `abstract class LyricsProvider` (8 subclass) sebagai kandidat `sealed class`.

**Ini false positive.** Alasan:

`fetch_manager.dart:69` mengandung:
```dart
void registerOnlineProvider(LyricsProvider provider) { ... }
```

Method ini memungkinkan provider baru didaftarkan secara runtime dari luar library. `sealed` melarang subclassing di luar file yang sama — mengubah ke `sealed` akan **memecah** extensibility ini. `abstract class` adalah pilihan yang benar untuk plugin-style provider system.

---

### D4. Null-Aware Element `?` — 1 Kandidat Valid, Rest False Positive

**Kandidat valid (List literal):**

`lib/widgets/pages/detail_sections/album.dart:12`:
```dart
// Kode saat ini:
if (album.year != null) album.year.toString(),

// Versi Dart 3.7+:
?album.year?.toString(),
```
`album.year` bertipe `int?`. `album.year?.toString()` menghasilkan `String?`.
Prefix `?` di list literal menyertakan elemen hanya jika non-null. ✅ Valid.

---

**False positive — Map literal (`lib/models/local_song.dart:74–81`):**
```dart
if (year != null) 'year': year,
```
Key `'year'` adalah string literal (non-nullable). Null-aware element `?` di Map hanya bekerja ketika KEY-nya nullable (`?nullableKey: value`). Kasus ini: VALUE yang nullable dengan KEY yang fixed — sintaks `?` tidak berlaku. **Pattern `if (x != null) 'key': x` di Map literal adalah idiom yang benar di Dart, tidak perlu diubah.**

**False positive — spread kompleks (`toggle.dart:31`, `content.dart:159`):**
```dart
if (subtitle != null) ...[
  const SizedBox(height: 4),
  Text(subtitle!),
],
```
Ini adalah spread multi-elemen bersyarat, bukan single-element null-aware. `?` hanya untuk satu elemen tunggal. **`if (x != null) ...[...]` adalah pola yang benar.**

---

## Bagian 3 — Temuan Baru dari Dart Modern Features Skill (Readability)

### D5. Digit Separator pada Angka Besar

Dart 3 dan Kotlin mendukung `_` sebagai pemisah digit untuk readability.

| File | Baris | Sekarang | Seharusnya |
|---|---|---|---|
| `lib/widgets/player/synced_lyrics_view/elrc_word.dart` | 79, 114 | `.clamp(0, 9999999)` | `.clamp(0, 9_999_999)` |
| `lib/services/lyrics_service/lrc_parser.dart` | 145 | `.clamp(0, 9999999)` | `.clamp(0, 9_999_999)` |
| `android/.../metadata/MetadataCacheDb.kt` | 63 | `1099511628211L` | `1_099_511_628_211L` |

**Prioritas:** sangat rendah — hanya readability, tidak ada dampak fungsional.

---

## Bagian 4 — Hasil Audit Kotlin (Android-Kotlin Skill)

### ✅ Tidak Ada Anti-Pattern Kotlin yang Ditemukan

| Anti-pattern | Status |
|---|---|
| `GlobalScope` usage | ✅ Tidak ditemukan |
| `runBlocking` di main thread | ✅ Tidak ditemukan |
| `MutableStateFlow` / `MutableSharedFlow` publik | ✅ Tidak ditemukan |
| Flow tanpa `catch` operator | ✅ Flow di Kotlin dikelola via EventChannel ke Dart |
| Hardcoded dispatcher | ✅ Dispatcher diinjeksi atau digunakan via `Dispatchers.IO` scoped |

Kode Kotlin di `android/app/src/main/kotlin/` sudah mengikuti best practice dari Android-Kotlin skill.

---

## Ringkasan Aksi yang Direkomendasikan

### Bisa dikerjakan sekarang (minor, aman):

| # | Aksi | File | Effort |
|---|---|---|---|
| 1 | Modernisasi switch → switch expression | `native_dsp_bridge.dart:100` | 5 menit |
| 2 | Modernisasi switch → switch expression | `bottom_nav/state.dart:92` | 5 menit |
| 3 | Null-aware element `?` | `detail_sections/album.dart:12` | 2 menit |
| 4 | Digit separator `9_999_999` | `elrc_word.dart`, `lrc_parser.dart` | 2 menit |
| 5 | Digit separator Kotlin | `MetadataCacheDb.kt:63` | 1 menit |

### Long-term (refactor besar, perlu diskusi):

- B1: MVVM / Repository pattern untuk menghilangkan direct service calls dari UI
- B2: Pindahkan logic `album_page.dart` keluar dari `build()`
- B3: Pecah file-file besar (>700 baris)

---

*Audit dihasilkan menggunakan:*
- *`kevmoo/dash_skills@dart-modern-features` — Dart 3.0–3.7 idioms*
- *`alinaqi/claude-bootstrap@android-kotlin` — Kotlin coroutines & anti-patterns*
- *SDK: Dart `>=3.12.2`, target device: Xiaomi Mi 9T/K20 (Android 11 / MIUI 12)*
