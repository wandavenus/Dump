---
name: Full Localization Implementation
description: Detail keputusan dan pola yang dipakai saat mengimplementasikan l10n lengkap (ID+EN) di seluruh app.
---

## Keputusan arsitektur

- `flutter gen-l10n` menghasilkan `app_localizations.dart` di `lib/l10n/` — ini adalah source of truth.
- Flutter 3.44 tidak mengekspos hasil generate melalui `package:flutter_gen/gen_l10n`; `context.l10n` mengimpor `package:musicplayer/l10n/app_localizations.dart`.
- Build web release pada toolchain Replit ini perlu `--no-wasm-dry-run`; tanpa opsi itu, dry-run WASM dapat gagal pada URI yang tidak dapat diterjemahkan meskipun kompilasi JS valid.

## Pola penggantian string

- Setiap `part` file tidak butuh import tambahan — import di parent library mencukupi.
- `const Text('...')` → `Text(l.key)` (harus hapus `const`).
- `const SliverToBoxAdapter(child: Column(children: [LargePageTitle(title: context.l10n.x)]))` → hapus `const` dari SliverToBoxAdapter.
- `const CupertinoButton(child: Text(context.l10n.x))` → hapus `const` dari CupertinoButton.
- `const SingleChildScrollView(child: Column(children: [SectionTitle(title: context.l10n.x)]))` → hapus `const` dari ScrollView, pindahkan `const` ke child yang tidak pakai l10n.

## Library items (library_sections/state.dart)

- `_defaultItems` tetap const (untuk ordering logic by id).
- Tambah method `_resolveItemTitle(BuildContext context, String id)` di State class dengan switch on id.
- `_buildStaticList()` dan `_buildReorderable()` diberi parameter `BuildContext context`, dipanggil dari `build(context)`.
- id values: 'playlist', 'artist', 'album', 'songs', 'tv'.

## Smart playlist cards (radio_sections/stations.dart)

- `_smartCards` sudah tidak ada — diganti `_resolveType()` dan `_resolveName(BuildContext context)` di State class.
- `_resolveType()` maps `_SmartType` enum → `SmartPlaylistType`.
- `_resolveName()` maps `_SmartType` enum → l10n keys: `favoritesLabel`, `recentlyPlayed`, `mostPlayedLabel`.

## ARB parametrik baru

- `logCopiedEntries`: `{count}` (int)
- `songsFoundMsg`: `{count}` (int)
- `deletePlaylistBody`: `{name}` (String) — sudah ada sebelumnya
- `appVersion`: `{version}` (String) — sudah ada sebelumnya

## Files yang butuh import ditambahkan

bottom_nav_bar/bottom_nav.dart, pages/music_list.dart, pages/log_page.dart,
widgets/common_actions.dart, pages/artist_list.dart, widgets/pages/playlist_dialogs.dart,
pages/settings/equalizer_page.dart, pages/settings/settings_widgets.dart,
pages/settings/sleep_timer_page.dart.

**Why:** File-file ini bukan `part of` library yang sudah import l10n, jadi harus import sendiri.

## Version bump

Versi di pubspec.yaml + changelog_data.dart dinaikkan ke 1.4.5 setelah penyempurnaan lokalisasi.

**Why:** Jalur `flutter_gen` dan dry-run WASM default tidak kompatibel dengan Flutter 3.44 pada workspace ini, sedangkan file generated lokal dan target JS berhasil.

**How to apply:** Pertahankan import generated lokal dan gunakan `--no-wasm-dry-run` untuk build web manual, watcher, dan deployment.

## Current completion state

- ARB English dan Bahasa Indonesia memiliki 393 message key yang sama.
- `LanguageManager` menyimpan `system`, `en`, atau `id`; `null` pada locale berarti kembali mengikuti bahasa perangkat.
- Preset Sleep Timer membentuk label dari `context.l10n` saat UI dibuat, bukan menyimpan teks bahasa tertentu di service.
- String literal yang tersisa di UI adalah nilai teknis, simbol, nama akun/artis, email, atau data lagu demo—bukan copy yang perlu diterjemahkan.

**Why:** Menjaga sumber terjemahan tetap lengkap dan mencegah service/domain layer bergantung pada bahasa tampilan.

**How to apply:** Tambahkan string baru ke kedua ARB, jalankan `flutter gen-l10n`, lalu gunakan `context.l10n` di widget; jangan memasukkan label terjemahan ke service.
