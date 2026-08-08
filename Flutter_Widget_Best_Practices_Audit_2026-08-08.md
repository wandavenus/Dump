# Flutter Widget Best Practices Audit — 2026-08-08

## Scope

Audit seluruh widget dan UI Flutter di `lib/` (277 file Dart, ~37k baris) terhadap
best practices Flutter: state management, lifecycle/dispose, async/context safety,
l10n, performa rebuild, const-ness, dan kualitas kode. Target device: Xiaomi Mi 9T
(SD730 / Android 11 / MIUI 12) — baseline sama dengan audit sebelumnya.

**Metode:** `flutter analyze` penuh (Flutter 3.44.9 stable) + grep anti-pattern
terarah + baca kode manual pada file terbesar (unified_morph_player.dart 807 baris,
player_content/content.dart 632 baris, bottom_nav/state.dart).

## Executive summary

**Kode sudah mengikuti best practices Flutter dengan sangat baik.** `flutter analyze`
→ **No issues found** di atas lint ketat (strict-casts, strict-inference,
strict-raw-types, unawaited_futures, discarded_futures, close_sinks,
cancel_subscriptions, dll). Tidak ditemukan satu pun anti-pattern berat:
tidak ada `setState` setelah dispose, tidak ada BuildContext async gap yang tidak
terjaga (`use_build_context_synchronously` bersih), tidak ada `print()` debug,
tidak ada API deprecated (`withOpacity` → sudah `withValues`), dan Timer/Stream
semua di-cancel/dispose. Hanya ditemukan **2 temuan kecil** (rendah severity) dan
beberapa catatan informasional.

## Stats

| Metrik | Nilai |
|---|---|
| File Dart di lib/ | 277 |
| Total baris | 37.247 |
| `flutter analyze` | **No issues found** |
| File pakai `context.l10n` | 77 |
| `if (!mounted)` guard | 23 |
| File pakai `ValueListenableBuilder` | 36 |
| File pakai `setState` | 42 |
| `GlobalKey` | 2 (keduanya tepat guna: per-tab Navigator) |
| `print(` debug | 0 |
| `withOpacity` (deprecated) | 0 |
| TODO/FIXME di lib/ | 3 (semua beralasan) |

## Findings

### F-1 (LOW) — Tombol Cast no-op di 8 halaman

| Field | Isi |
|---|---|
| Severity | LOW (UX, bukan bug teknis) |
| File | `lib/widgets/common_actions.dart:54-67` |
| Deskripsi | `_cast(BuildContext context)` isi-nya hanya `// TODO: Cast function` — tombol `Icons.cast_outlined` (merah) yang menempel di `CommonActions` **tidak melakukan apa pun** saat ditekan. `CommonActions` dipasang di **8 halaman**: album_page, artist_list, artist_page, library_page, music_list, playlist_page, scrolling_page_chrome/app_bar, library_sections/detail. |
| Root cause | Fitur cast direncanakan tapi belum diimplementasikan; tombol ditinggalkan live. |
| Dampak | User menekan tombol yang terlihat aktif → tidak ada respons. Persepsi bug di 8 halaman. |
| Confidence | High (fungsi kosong, analyzer tidak menangkapnya) |
| Rekomendasi | **Pilih salah satu**: (a) hapus tombol sampai fitur cast benar-benar dibangun (nol trade-off, ukuran widget mengecil), atau (b) implementasikan fitur cast. Opsi (a) paling aman. |
| Risiko jika diabaikan | Rendah secara teknis; tetap menurunkan kualitas UX. |

### F-2 (LOW) — 4 string hardcoded di about.dart (luput l10n)

| Field | Isi |
|---|---|
| Severity | LOW |
| File | `lib/pages/settings_page/about.dart:73-83` |
| Deskripsi | Dialog konfirmasi simpan QRIS memakai string literal: `'Simpan QR Code'`, `'Simpan gambar QRIS ke galeri?'`, `'Batal'`, `'Simpan'`. File yang sama sudah memakai `context.l10n` (baris 8 & 191) — ini satu-satunya titik di seluruh lib/ yang memakai `Text('...')` tanpa l10n. |
| Root cause | Dialog QRIS ditambahkan sebelum pola l10n merata; lolos review. |
| Dampak | Inkonsistensi i18n: string ini tidak akan ikut swap bahasa EN/ID (dan hanya ada dalam bahasa Indonesia). |
| Confidence | High |
| Rekomendasi | Pindahkan 4 string ke ARB EN/ID + pakai `context.l10n`. Nol trade-off; butuh entry di `lib/l10n/app_*.arb`. |
| Risiko jika diabaikan | Sangat rendah (dialog jarang terbuka), tapi melanggar konvensi l10n repo. |

## Informational (sudah baik — tidak diubah)

- **`_GlassSubToggle` & `_InfoLine`** (`lib/pages/settings_page/`) — duplikasi
  konseptual dari `SettingsToggleRow`/`SettingsInfoRow`, sudah ditandai
  `TODO(cleanup)` dengan alasan jelas (beda padding/icon/onChanged signature).
  Konsolidasi disarankan setelah API glass-theme stabil — bukan sekarang.
- **`_formatTime`** di-pass sebagai callback dari `_UnifiedMorphPlayerState` →
  `PlayerContent` → `PlayerProgressSection` — pola injection yang konsisten,
  bukan duplikasi. Tidak perlu refactor.
- **`// ignore_for_file: prefer_const_literals_to_create_immutables`** di
  `bottom_nav/bottom_nav.dart` — ignore yang sah untuk daftar item navbar.
- Widget besar (807 & 632 baris) memakai `part` files dengan seksi berkomentar —
  struktur dapat dibaca; bukan pelanggaran best practice.

## Positive findings (yang sudah benar)

1. **Rebuild isolation / performa 60 FPS** — `_UnifiedMorphPlayerState`
   memakai listener yang **mengabaikan position tick** (~100ms) dan hanya
   `setState` saat identitas lagu/`isPlaying` berubah; `_PlaybackContent`
   adalah VLB sempit yang mengisolasi rebuild posisi; `BackdropFilter` dibungkus
   `RepaintBoundary` + threshold `progress < 0.02` sehingga tidak pernah jalan
   saat morph; shader pakai `TickerMode` + target render 256×512 (konsisten
   dengan Fluid_Shader_Performance_Audit).
2. **Async/context safety** — 23 `if (!mounted)` guard + `unawaited()` untuk
   fire-and-forget (sesuai memory `async-fire-and-forget.md`); analyzer bersih
   terhadap `use_build_context_synchronously`.
3. **Lifecycle lengkap** — semua `AnimationController`, `ScrollController`,
   `Timer`, dan listener di-`dispose`; debounce timer SharedPreferences punya
   `flush()` eksplisit saat halaman ditutup.
4. **State management konsisten tanpa dependency eksternal** — 36 file
   `ValueListenableBuilder` + `ValueNotifier` singleton (ThemeController,
   PlayerSheetController, AudioService.playbackState); `setState` hanya untuk
   state lokal ephemeral. Tidak ada package state-management yang tidak perlu.
5. **l10n terpenuhi luas** — 77 file memakai `context.l10n` (EN/ID ARB),
   termasuk snackbar error/scan.
6. **StreamController broadcast** di-playback_manager & ffmpeg_decoder_bridge
   di-close dengan benar (lint `close_sinks` aktif).
7. **API modern** — `withValues(alpha:)` (bukan `withOpacity` yang deprecated),
   `PopScope.onPopInvokedWithResult` (bukan `WillPopScope`), `MediaQuery.sizeOf`.
8. **Konvensi repo terpelihara** — `part` files, komentar bahasa Indonesia,
   seksi visual dengan box-drawing, konstanta magic-number diberi nama.

## Recommended order of work

1. F-1: putuskan nasib tombol Cast (hapus ↔ implementasi) — satu keputusan UX.
2. F-2: pindahkan 4 string QRIS ke ARB + l10n (perubahan < 10 baris).
3. Jika keduanya disetujui: bump versi + changelog per konvensi repo, `flutter
   analyze lib test` untuk validasi.

## Verification

- `flutter analyze --no-fatal-infos --fatal-warnings lib` → **No issues found** (10.5s).
- Grep `withOpacity`/`print(`/hardcoded `Text('` di lib → hasil di atas.
- Tidak ada perubahan kode yang dilakukan dalam audit ini (hanya laporan).
