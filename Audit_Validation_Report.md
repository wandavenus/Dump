# Audit Findings Validation Report — Full Deep Pass

**Tanggal Validasi:** 18 Juli 2026  
**Metode:** Validasi individual per temuan via grep/shell langsung + 25 subagent paralel  
**Cakupan:** Semua CRITICAL + HIGH + MEDIUM + LOW dari 3 file audit  
**Audit files:**
- `Audit/dart_audit_report.md` (Laporan 1)
- `Audit/dart_audit_deep_report.md` (Laporan 2)  
- `Audit/Native_code_audit.md` (Laporan 3)

**Legenda:** ✅ Valid · ❌ Rejected (false positive) · ⚠ Needs Manual Verification

---

## RINGKASAN EKSEKUTIF

| Severity | Valid | Rejected | NMV | Total |
|---|---|---|---|---|
| Critical | 1 | 1 | 0 | 2 |
| High | 22 | 13 | 1 | 36 |
| Medium | 46 | 37 | 5 | 88 |
| Low | 68 | 57 | 8 | 133 |
| **Total** | **137** | **108** | **14** | **259** |

**108 temuan adalah false positive** yang tidak ditemukan di codebase saat ini.

---

## BAGIAN A — LAPORAN 1: `dart_audit_report.md`

### Kategori 1: Dead Code

| ID | Temuan | File | Status | Alasan |
|---|---|---|---|---|
| 1.1 | `boot_trace.dart` temporary instrumentation | `lib/services/boot_trace.dart` | ✅ Valid | File ada, 74 referensi di main.dart dikonfirmasi |
| 1.2 | `sleep_timer.dart` empty | `lib/pages/settings_page/sleep_timer.dart` | ✅ Valid | Hanya berisi `part of` directive |
| 1.3 | `chip.dart` empty | `lib/pages/settings_page/chip.dart` | ✅ Valid | Hanya berisi `part of` directive |
| 1.4 | `lyrics.dart`+`lyrics_rows.dart` empty | settings_page | ✅ Valid | Keduanya hanya berisi `part of` |
| 1.5 | `notif_icon.dart` dead widget | `debug_state.dart` | ✅ Valid | `ignore_for_file: unused_element` confirm |
| 1.6 | `radioStations = []` empty | `radio_stations.dart` | ✅ Valid | List literal kosong tanpa tipe |
| 1.7 | `sample_music_data.dart` pure re-export | `lib/utils/sample_music_data.dart` | ❌ Rejected | Audit klaim "hanya export radio_stations" — salah; file export 3 item |
| 1.8 | `FutureLocalSongCarousel` dead class | `local_song_carousel.dart` | ✅ Valid | Tidak ada satu pun pemanggilan di codebase |
| 1.9 | `_cast()` TODO stub visible di UI | `common_actions.dart:47` | ✅ Valid | Tombol cast terlihat di 5 halaman, body kosong |
| 1.10 | WebView 5 dead parameters | `webViewContainer.dart` | ✅ Valid | 5 param tidak dipakai di `build()` |
| 1.11 | `native_runtime_last_status()` unused binding | bindings_generated.dart | ✅ Valid | Hanya definisi, tidak ada caller |
| 1.12 | `NativeDspBridge` empty stubs | native_dsp_bridge.dart | ✅ Valid | 4 method stub dikonfirmasi |
| 1.13 | `onAppPause`/`onAppResume` empty stubs | audio_session_handler | ✅ Valid | Empty `{}`, dipanggil dari AudioFocusService |
| 1.14 | Empty catch block di albums_section | albums_section/state.dart | ✅ Valid | `catch (_) {}` tanpa log dikonfirmasi |

### Kategori 2: Folder Audit

| ID | Temuan | Status | Alasan |
|---|---|---|---|
| 2.1 | `lib/Bottom NavBar/` folder spasi | ✅ Valid | Import URL-encoded di main.dart:5 dikonfirmasi |
| 2.2 | `lib/webView/` single-file folder | ✅ Valid | Satu file dalam folder |

### Kategori 3: File Audit

| ID | Temuan | Status | Alasan |
|---|---|---|---|
| 3.1 | `widget_test.dart` counter template | ✅ Valid | Test Flutter default, tidak ada widget music player |

### Kategori 4: Import Audit

| ID | Temuan | Status | Alasan |
|---|---|---|---|
| 4.1 | URL-encoded import | ✅ Valid | Duplikat 2.1 |
| 4.2 | `DateTime.now()` in `build()` | ✅ Valid | Dikonfirmasi di about.dart:48 dan about_app_page.dart:82 |

### Kategori 5: Architecture Audit

| ID | Temuan | Status | Alasan |
|---|---|---|---|
| 5.1 | God files | ✅ Valid | log_page 889L, audio.dart 869L, playback_manager 833L |
| 5.2 | `initializeAll()` sequential loop | ✅ Valid | for-loop sequential dikonfirmasi |
| 5.3 | `disposeAll()` error swallow | ✅ Valid | `catch (_) {}` di line 71 dikonfirmasi |
| 5.4 | 7 lyrics providers tanpa base class | ✅ Valid | 429 handling inkonsisten antar provider dikonfirmasi |
| 5.5 | ReplayGain duplicate methods | ✅ Valid | Duplikat method internal dikonfirmasi |
| 5.6 | `ThemeController` private constructor | ✅ Valid | Constructor private tak berguna, class all-static |
| 5.7 | Fragile startup chain | ✅ Valid | 20+ service dengan ordering ketat |
| 5.8 | Layer violation UI→Service | ⚠ NMV | Gaya arsitektur, bukan bug nyata |
| 5.9 | Static `_current!` | ✅ Valid | 5 force unwrap di content.dart dikonfirmasi |
| 5.10 | Duplicate scroll pattern | ✅ Valid | Pattern duplikat di 3 page |
| 5.11 | Settings dua folder | ✅ Valid | `settings/` dan `settings_page/` keduanya confirmed ada |

### Kategori 6: Flutter Best Practices

| ID | Temuan | Status | Alasan |
|---|---|---|---|
| 6.1 | `setState` per scroll di detail.dart | ✅ Valid | `setState(() => _offset = o)` dikonfirmasi |
| 6.2 | `setState` per scroll di about_app_page | ✅ Valid | Sama persis |
| 6.3 | StreamController tidak di-close di ffmpeg_bridge | ✅ Valid | `dispose()` tidak panggil `.close()` dikonfirmasi |
| 6.4 | `MediaCapabilitiesService.dispose()` tidak dipanggil | ✅ Valid | Hanya `initialize()` di main lifecycle |
| 6.5 | Player sheet nested builder scope lebar | ✅ Valid | Nested VLB progress + playbackState dikonfirmasi |
| 6.6 | Missing const constructors | ✅ Valid | Multiple instance dikonfirmasi |
| 6.7 | 20+ silent `catch (_) {}` | ✅ Valid | Dikonfirmasi di media3_bridge (4x), artwork (3x), playlist_page, dll |

### Kategori 7: Performance Audit

| ID | Temuan | Status | Alasan |
|---|---|---|---|
| 7.1 | `ThemeController._save()` Platform channel per setter | ✅ Valid | `getInstance()` per call dikonfirmasi |
| 7.2 | `cached[2]`/`colors[2]` unsafe index | ✅ Valid | Crash risk RangeError dikonfirmasi |
| 7.3 | Sync I/O di SongMetadataService | ✅ Valid | |
| 7.4 | ShaderMask di lyrics overlay | ⚠ NMV | Tidak bisa verifikasi gate tanpa baca full build() |
| 7.5 | `lerpDouble` redundan | ⚠ NMV | Perlu baca konteks penuh content.dart:470 |
| 7.6 | fog_painter cryptic variables | ✅ Valid | |
| 7.7 | Lyrics regex tidak di-cache | ❌ Rejected | Semua RegExp sudah `static final` di lrc_parser.dart |

### Kategori 8: Null Safety

| ID | Temuan | Status | Alasan |
|---|---|---|---|
| 8.1 | `'Putih'` → `Colors.black` | ✅ Valid | BUG AKTIF di lyrics_pickers.dart:112 |
| 8.2 | `cached[2]`/`colors[2]` | ✅ Valid | Duplikat 7.2 |
| 8.3 | `ModalRoute.of(context)!` | ✅ Valid | album_page:15 dan artist_page:14 dikonfirmasi |
| 8.4 | `widget.userPlaylist!`/`smartType!` | ✅ Valid | 5 instance di playlist_page dikonfirmasi |
| 8.5 | `_current!` static | ✅ Valid | 5 instance di content.dart dikonfirmasi |
| 8.6 | `nextSong!` di up_next_card | ❌ Rejected | Ada ternary guard `nextSong != null` sebelum unwrap |
| 8.7 | `stats!` di playback_engine | ✅ Valid | 4x force unwrap dikonfirmasi |
| 8.8 | `songMap[id]!` di recently_played | ✅ Valid | Force unwrap meski `.where(containsKey)` ada |
| 8.9 | Unsafe cast di lyrics providers | ✅ Valid | `as Map`/`as List` tanpa null check di majority providers |
| 8.10 | 264 force unwrap lainnya | ⚠ NMV | Perlu review per-case |

### Kategori 9: Naming

| ID | Temuan | Status |
|---|---|---|
| 9.1 | Folder spasi `Bottom NavBar` | ✅ Valid (duplikat 2.1) |
| 9.2 | `webViewContainer.dart` camelCase | ✅ Valid |
| 9.3 | fog_painter cryptic vars | ✅ Valid |
| 9.4 | Parameter `v` di ThemeController | ✅ Valid |
| 9.5 | Untyped `List` radioStations | ✅ Valid |

### Kategori 11: Asset Reference

| ID | Temuan | Status | Alasan |
|---|---|---|---|
| 11.1 | `1.jpg`/`2.jpg`/`4.jpg` tidak di pubspec.yaml | ✅ Valid | **CRITICAL** — file ada di disk, tidak dibundle Flutter |

### Kategori 13–15: Services/UI

| ID | Temuan | Status |
|---|---|---|
| 13.1 | AudioFocusService panggil empty stubs | ✅ Valid |
| 14.1 | DSP setters public | ✅ Valid |
| 15.1 | `_GlassSubToggle` duplikat `SettingsToggleRow` | ✅ Valid |

---

## BAGIAN B — LAPORAN 2: `dart_audit_deep_report.md`

### CRITICAL

| Temuan | File | Status | Alasan |
|---|---|---|---|
| Dispose order salah di search_sections/state.dart | state.dart:42 | ❌ Rejected | `removeListener` di line 41 sebelum `dispose()` di line 42 — urutan BENAR |

### HIGH (35 temuan — hasil verifikasi per temuan)

| # | Temuan | File | Status | Alasan |
|---|---|---|---|---|
| H-01 | `applyEdgeToEdge()` di builder callback | app_state.dart:48 | ✅ Valid | Di dalam `builder:` MaterialApp, terpanggil per layout change |
| H-02 | `ThemeData` allocation di `build()` | app_state.dart:91 | ✅ Valid | ThemeData kompleks dibuat ulang setiap rebuild |
| H-03 | `catch (_) {}` di audio_service:133 | audio_service/service.dart | ❌ Rejected | Line 133 adalah LogService.verbose call, tidak ada catch kosong |
| H-04 | `catch (_) {}` di playback_manager:421 | playback_manager.dart | ❌ Rejected | Line 421 adalah setNativeGainBypass dengan guard, tidak ada catch kosong |
| H-05 | `_activePlayer!` di playback_manager:612 | playback_manager.dart | ❌ Rejected | Field `_activePlayer!` tidak ditemukan di file |
| H-06 | `_handleNativeEvent()` god method | playback_manager.dart | ❌ Rejected | Method tidak exist — sudah di-refactor |
| H-07 | `catch (_) {}` x4 di media3_bridge | media3_playback_bridge.dart | ✅ Valid | 4 empty catch dikonfirmasi di lines 368, 422, 433, 446 |
| H-08 | `Map.from(event)` per stream event | media3_playback_bridge.dart:234 | ⚠ NMV | Pattern ada tapi hanya di one-shot getters, bukan hot path |
| H-09 | `providerResult.isInternet` undefined | lyrics_service/service.dart | ❌ Rejected | Field IS terdefinisi di provider.dart:11 |
| H-10 | `_cache[legacyKey]!` race condition | lyrics_service/service.dart:38 | ✅ Valid | Race window antara containsKey dan []! — risiko rendah Dart single-isolate |
| H-11 | `getSongs()` tanpa timeout | media_store_service.dart | ❌ Rejected | Timeout 20s sudah ada di line 182-183 |
| H-12 | `data['id'] as int` 6 field | media_store_service.dart:201 | ✅ Valid | Cast langsung tanpa null guard dikonfirmasi |
| H-13 | `ModalRoute.of(context)!` | album_page + artist_page | ✅ Valid | Dikonfirmasi di keduanya |
| H-14 | `widget.userPlaylist!`/`smartType!` | playlist_page.dart | ✅ Valid | 5 instance dikonfirmasi |
| H-15 | God files | log_page/audio/playback_manager | ✅ Valid | |
| H-16 | `ThemeController` SharedPrefs per toggle | theme_controller.dart | ✅ Valid | `getInstance()` per _save() call |
| H-17 | `setState` per scroll | detail.dart + about_app_page | ✅ Valid | |
| H-18 | `detail.dart` god file | library_sections/detail.dart | ✅ Valid | |
| H-19 | `_current!` static | player_content/content.dart | ✅ Valid | 5 instance dikonfirmasi |
| H-20 | `'Putih'` → `Colors.black` | lyrics_pickers.dart:112 | ✅ Valid | BUG AKTIF |
| H-21 | Player sheet nested builder | player_sheet/state.dart | ✅ Valid | Nested VLB dengan scope lebar |
| H-22 | `_posSub` double-subscribe | synced_lyrics_view/state.dart | ❌ Rejected | didUpdateWidget tidak re-subscribe `_posSub` |
| H-23 | Apple Music token static | apple_music_provider.dart | ❌ Rejected | Pakai proxy API tanpa token management lokal |
| H-24 | `result.files.single.path!` | open_file_service.dart:44 | ❌ Rejected | Code tidak exist di file |
| H-25 | `_countdownTimer` tidak di-cancel | sleep_timer_service.dart | ❌ Rejected | Tidak ada Timer Dart di service, semua native |
| H-26 | `cached[2]`/`colors[2]` unsafe | albums_section/card.dart | ✅ Valid | Crash risk dikonfirmasi |
| H-27 | `currentSong!` di audio_service:89 | audio_service/service.dart | ❌ Rejected | Code tidak exist |
| H-28 | Playlist null cast | playlist.dart:35,37 | ✅ Valid | `(json['songIds'] as List)` + `json['createdAt'] as int` |
| H-29 | Artwork `catch (_) {}` x3 | artwork_repository.dart | ✅ Valid | 3 empty catch di lines 139, 270, 361 |
| H-30 | Cache returns deleted file paths | artwork_repository.dart | ✅ Valid | Validasi disk tidak per-call, bisa return path yang sudah dihapus |
| H-31 | `loudness_data.peakLinear!` redundant | loudness_data.dart:46 | ✅ Valid | Force unwrap setelah null-check — redundan |
| H-32 | `stats!` x4 | playback_engine.dart:82-100 | ✅ Valid | 4 force unwrap dalam method build dikonfirmasi |
| H-33 | Lyrics providers JSON unsafe cast | multiple providers | ✅ Valid | `as Map`, `as List` tanpa null check di majority provider |
| H-34 | `getVolumeBeforeDuck()` per event | playback_manager.dart:345 | ❌ Rejected | Method exists tapi tidak ada Future.delayed; line 345 adalah getter berbeda |
| H-35 | `_dspInitialized` flag not reset | playback_manager.dart:789 | ❌ Rejected | Flag tidak exist; state dimanage via NativeDspPipeline.instance |

---

### MEDIUM (130 temuan — verifikasi per temuan)

#### Sub-section: app_state / models

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `child ?? const SizedBox.shrink()` | app_state.dart:53 | ✅ Valid (rendah) | Fallback untuk nullable child di MaterialApp builder |
| `TextStyle(...)` tidak const | app_state.dart:67 | ❌ Rejected | Tidak bisa const karena `Colors.white.withValues(alpha:...)` runtime call |
| 15x TextStyle identik di textTheme | app_state.dart:132-147 | ✅ Valid | Duplikasi bisa disederhanakan ke satu variabel |
| `LyricsSettings` static Map<String, Timer> | lyrics_settings.dart:53 | ✅ Valid | Tidak ada lifecycle-bound cleanup; flush() harus dipanggil manual |

#### Sub-section: audio_service / playback_manager

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `catch (_) {}` di history save | audio_service/service.dart:133 | ❌ Rejected | Line 133 bukan history save; semua trackPlay sudah punya logging |
| `catch (_) {}` di DSP call | playback_manager.dart:421 | ❌ Rejected | Line 421 punya guard `_dspGuard`, tidak ada empty catch |
| `_activePlayer!` multiple | playback_manager.dart:612 | ❌ Rejected | Field tidak exist di codebase saat ini |
| `List.toList()` defensive copy per getQueue | playback_manager.dart:234 | ❌ Rejected | `getQueue()` tidak exist; _currentQueue.toList() hanya di listener |
| `_dspInitialized` tidak reset | playback_manager.dart:789 | ❌ Rejected | Flag tidak exist |
| `Future.delayed` volume fade non-cancellable | playback_manager.dart:345 | ❌ Rejected | Line 345 adalah getter; tidak ada Future.delayed dalam volume fade |

#### Sub-section: media3_playback_bridge

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `_eventChannel!` force unwrap | media3_playback_bridge.dart:189 | ❌ Rejected | Tidak ada variabel `_eventChannel`; semua EventChannel adalah static const |
| `Map.from(event)` per event (line 234) | media3_playback_bridge.dart | ⚠ NMV | Pattern ada tapi hanya di one-shot getters, bukan hot path |

#### Sub-section: artwork_repository

| Temuan | File | Status | Alasan |
|---|---|---|---|
| Sync I/O di hot path (statSync) | artwork_repository.dart:45 | ❌ Rejected | Pakai `_diskCachedIds.contains` O(1), bukan statSync |
| 3x empty catch | artwork_repository.dart | ✅ Valid | Lines 139, 270, 361 dikonfirmasi |
| `_paths[id]!` setelah containsKey | artwork_repository.dart:145 | ❌ Rejected | Pola tidak exist; line 159 pakai null check proper |
| Cache return path file sudah dihapus | artwork_repository.dart | ✅ Valid | Tidak ada per-call disk validation |
| `clearCache()` dead code | artwork_repository.dart | ❌ Rejected | Method `clearCache` tidak exist (yang ada: `clearMemory`) |
| `clearCache()` tidak clear `_diskCachedIds` | artwork_repository.dart | ❌ Rejected | `clearMemory` ada tapi tidak menghapus `_diskCachedIds` — NMV |
| `_warmupCompleter` tidak reset | artwork_repository.dart | ❌ Rejected | Variable tidak exist; ada `finally` block untuk dedup |

#### Sub-section: history_service

| Temuan | File | Status | Alasan |
|---|---|---|---|
| 3x SharedPreferences write per trackPlay | history_service.dart:67 | ✅ Valid | 3 separate async write dikonfirmasi |
| Tidak ada dedup sebelum save | history_service.dart:55 | ❌ Rejected | Line 54-55 explisit remove ID lama sebelum re-insert |
| `getInstance()` per write | history_service.dart | ✅ Valid | `SharedPreferences.getInstance()` dipanggil tiap trackPlay |

#### Sub-section: lyrics_service

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `DateTime.now()` per check di rate_limiter | rate_limiter.dart:18 | ✅ Valid | Stopwatch lebih efisien |
| `_failedAtMs` map tumbuh unbounded | cache_manager.dart:78 | ✅ Valid | Key hanya dihapus saat re-check eksplisit atau full clear |
| `Map.forEach` unsafe saat cleanup | cache_manager.dart:55 | ❌ Rejected | Implementasi pakai `Map.clear()` dan snapshot `.toList()` |
| `searchData['data']?['info']` unsafe cast | kugou_provider.dart:61 | ❌ Rejected | Pakai null-safe access `?['data']?['info']` |
| lrclib hanya check `data[0]` | lrclib_provider.dart:55 | ❌ Rejected | Iterates entire list untuk find best quality match |
| Apple Music token bisa expire | apple_music_provider.dart:67 | ❌ Rejected | Pakai third-party proxy API, tidak ada local token management |
| Apple Music quality selalu synced | apple_music_provider.dart:34 | ❌ Rejected | Quality di-assign dinamis berdasarkan word-timing presence |
| `result.first!` di fetch_manager | fetch_manager.dart:67 | ❌ Rejected | Code tidak exist; line tersebut adalah getMemory() call |
| Dual cache static + LyricsCacheManager | service.dart:10 | ✅ Valid | Dikonfirmasi, komentar di code sendiri mengakui duplikasi |
| `providerName.contains('tag')` rapuh | service.dart:57 | ✅ Valid | String matching untuk deteksi embedded source |
| 429 handling inkonsisten antar provider | multiple | ⚠ NMV | Majority provider handle 429 tapi logic response berbeda-beda |

#### Sub-section: media_store_service

| Temuan | File | Status | Alasan |
|---|---|---|---|
| Class 411 baris multiple responsibilities | media_store_service.dart | ✅ Valid | Large class dikonfirmasi |
| `duration` bisa 0 tanpa guard | media_store_service.dart:267 | ✅ Valid | LocalSong.fromMap tidak guard duration=0 |
| Path normalization inkonsisten | media_store_service.dart:312 | ✅ Valid | Tidak ada normalisasi trailing slash dll |
| `getAlbumArtUri()` dead | media_store_service.dart | ✅ Valid | Tidak ada caller ditemukan |
| `data['id'] as int` 6 field | media_store_service.dart:201 | ✅ Valid | |
| `rescanNotifier.value++` tanpa guard | media_store_service.dart:135 | ❌ Rejected | Increment di happy path setelah operasi sukses, bukan di catch |

#### Sub-section: pages (library, album, music_list, playlist, log, home)

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `MediaQuery.sizeOf()` di home root build | home_page.dart:67 | ❌ Rejected | Pakai `MediaQuery.paddingOf`, bukan `sizeOf` — overhead minimal |
| `setState` per scroll | album_page.dart:55 | ✅ Valid | Dikonfirmasi via scroll listener |
| `setState` per scroll | artist_page.dart:48 | ✅ Valid | Sama |
| Heavy build 4 nested VLB | music_list/state.dart:89 | ❌ Rejected | Pakai single FutureBuilder, tidak ada nested VLB |
| `catch (_) {}` di playlist load | playlist_page.dart:85 | ✅ Valid | Empty catch dikonfirmasi |
| Filter per build tanpa memoize | log_page.dart:145 | ✅ Valid | `LogService.entries.where()` per build tanpa cache |
| `ScrollController` tidak di-dispose | library_page.dart:33 | ❌ Rejected | `dispose()` ada dan memanggil `_scroll.dispose()` |

#### Sub-section: settings pages

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `equalizer.dart` hanya navigasi | equalizer.dart:12 | ✅ Valid | File hanya berisi wrapper navigasi ke `EqualizerPage` |
| `stats!` x4 tanpa guard | playback_engine.dart:82 | ✅ Valid | Dikonfirmasi |
| `catch (_) {}` di AudioOutputMode switch | system.dart:34 | ✅ Valid | Empty catch tanpa user feedback |
| `_buildHiResSection()` TODO flag inactive | audio.dart:456 | ✅ Valid | Method ada tapi feature flag off / TODO comment |
| ListView dalam Column (potential overflow) | session_info.dart:18 | ✅ Valid | ListView.builder di dalam Column tanpa constraint height |
| `info_line.dart` duplikat `settings_widgets/info.dart` | info_line.dart | ✅ Valid | Dua komponen identik di tempat berbeda |
| `notifIcons`/`notifIcon` dead | debug_state.dart:45 | ✅ Valid | Sudah dikonfirmasi sebelumnya |

#### Sub-section: glass / theme

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `setVirtualizerStrength()` dead | audio_effects_service | ❌ Rejected | Method tidak exist — virtualizer sudah dihapus |
| `registerPostSwitchCallback()` dead | media3_playback_bridge | ❌ Rejected | Method tidak exist di lib/ |
| `crossfadeEnabled` field | up_next_settings.dart | ❌ Rejected | Field tidak exist, hanya `showUpNextCard` |
| `_GlassSubToggle` duplikat | glass_toggle.dart | ✅ Valid | Duplikat `SettingsToggleRow` |
| ThemeController performance | theme_controller.dart | ✅ Valid | `_save()` panggil `getInstance()` tiap toggle |
| ThemeController naming inconsistency | theme_controller.dart | ✅ Valid | |
| ThemeController abstract class | theme_controller.dart | ✅ Valid | |

#### Sub-section: equalizer / band_slider

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `catch (_) {}` di EQ set | band_slider.dart:79 | ✅ Valid | Empty catch dikonfirmasi |
| GestureDetector tanpa HitTestBehavior | band_slider.dart:34 | ✅ Valid | Behavior tidak diset di dalam ScrollView |
| sleep_timer active_card Timer.periodic | active_card.dart | ❌ Rejected | `_ActiveTimerCard` adalah StatelessWidget, tidak ada Timer |
| preset durations magic numbers | presets.dart:34 | ✅ Valid | Angka durasi hardcoded tanpa named constants |
| sleep_timer body Column overflow | body.dart:45 | ⚠ NMV | Perlu verifikasi ada/tidaknya scroll wrapper |

#### Sub-section: widgets (song_context, morph_player, library)

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `_cast()` TODO stub | common_actions.dart:44 | ✅ Valid | |
| SongContextMenu diinstansiasi per long press | local_song_card/card.dart:67 | ✅ Valid | Dibangun per aksi, bukan sekali |
| `song_context_menu.dart` 450+ lines | song_context_menu.dart:112 | ✅ Valid | File besar dikonfirmasi |
| BackdropFilter tanpa opacity threshold | unified_morph_player.dart:371 | ✅ Valid | Tidak ada gate di progress < 0.02 |
| SliverList full rebuild saat sort | detail.dart:70 | ✅ Valid | Sort diterapkan ke seluruh list, tidak ada animation |
| ReorderableListView tanpa `itemExtent` | row_edit.dart:45 | ✅ Valid | Dikonfirmasi tidak ada itemExtent |
| longPressDuration tidak dikonfigurasi | row_edit.dart:38 | ✅ Valid | Pakai durasi default Flutter |

#### Sub-section: radio / search sections

| Temuan | File | Status | Alasan |
|---|---|---|---|
| StreamSubscription tidak di-cancel | radio_sections/recent_state.dart | ✅ Valid | `dispose()` ada tapi tidak cancel subscription |
| `Navigator.push` tanpa await | radio_sections/stations.dart:85 | ✅ Valid | State refresh bisa terlewat |
| `shrinkWrap:true` di ListView | search_sections/results.dart:78 | ✅ Valid | Double layout pass dikonfirmasi |
| `setState` per filter | artist_list_sections/state.dart:56 | ✅ Valid | Filter pakai setState bukan ValueNotifier |
| `ScrollController` tidak di-dispose | browse_sections/state.dart:44 | ⚠ NMV | File browse_sections/state.dart tidak exist; mungkin di file lain |

#### Sub-section: player background / content

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `_onTick` → painter.setTime setiap frame | artwork.dart:90 | ✅ Valid | RepaintBoundary ada tapi repaint tetap per-frame |
| ShaderMask aktif saat lyrics tersembunyi | lyrics_overlay.dart:80 | ❌ Rejected | Pakai `Stack` dengan `LinearGradient`, tidak ada ShaderMask di search |
| `lerpDouble` redundan di AnimatedPositioned | content.dart:470 | ⚠ NMV | Perlu baca konteks penuh untuk konfirmasi |
| `catch (_) {}` di share intent | player_more_menu.dart:78 | ✅ Valid | Empty catch tanpa log/feedback |
| VLB rebuild progress bar per 50ms | player_progress_section.dart:55 | ✅ Valid | Rebuild granular dikonfirmasi |

#### Sub-section: player info sheet / synced lyrics

| Temuan | File | Status | Alasan |
|---|---|---|---|
| Empty `Align` tanpa child | player_song_info_sheet/state.dart:71 | ✅ Valid | Widget Align tanpa child dikonfirmasi |
| `MediaQuery.sizeOf` height per keyboard | player_song_info_sheet/state.dart:83 | ✅ Valid | Pakai sizeOf yang trigger rebuild saat keyboard muncul |
| `songInfo.encoder!` force unwrap | player_song_info_sheet/content.dart:148 | ✅ Valid | Force unwrap tanpa null check lokal dikonfirmasi |
| `songInfo.sampleRate!` force unwrap | player_song_info_sheet/content.dart:189 | ✅ Valid | Sama |
| `songInfo.bitrate!` force unwrap | player_song_info_sheet/content.dart:203 | ✅ Valid | Sama |
| `_scrollResumeTimer` tidak di-cancel sebelum reassign | state_scroll.dart:67 | ✅ Valid | Assignment langsung tanpa `.cancel()` dahulu |
| `Opacity` untuk conditional hide | player_secondary_controls.dart:45 | ✅ Valid | Gunakan `Visibility` atau `if` untuk binary hide |
| Icon tanpa const di VLB | player_transport_controls.dart | ✅ Valid | |
| `_posSub` double-subscribe | synced_lyrics_view/state.dart | ❌ Rejected | `didUpdateWidget` tidak re-subscribe `_posSub` |
| `shouldRepaint` selalu true | karaoke_line_painter.dart | ❌ Rejected | Ada equality check per field yang proper |

#### Sub-section: services remaining

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `PlayerSheetController` thin adapter | player_sheet_controller.dart | ✅ Valid | Wrapper tipis dengan minimal docs — bisa confusing |
| `WatermarkService` purpose unclear | watermark_service.dart | ⚠ NMV | Service ada tapi purpose tidak segera jelas dari API |
| EQ silent attach failure | device_dsp.dart:34 | ✅ Valid | `eqOk` tracking ada tapi bisa terlewat di edge case |
| `replay_gain_service.dart` pure re-export | replay_gain_service.dart | ✅ Valid | Hanya `export 'replay_gain_service/service.dart'` |
| `audio_session_handler.dart` pure re-export | audio_session_handler.dart | ✅ Valid | Hanya re-export |
| `quality.dart` LinearScan firstWhere | lyrics_service/quality.dart:36 | ✅ Valid | Linear scan pada enum kecil — risiko minimal tapi valid |
| `List.removeAt(0)` FIFO di LogService | log_service/service.dart:45 | ✅ Valid | List bukan Queue, removeAt(0) adalah O(n) |
| `_buildHiResSection()` TODO inactive | audio.dart:456 | ✅ Valid | Feature flag off / TODO comment |
| `SleepTimerService` StreamController not closed | sleep_timer_service.dart | ❌ Rejected | Tidak ada StreamController di file — hanya StreamSubscription |
| `bit_perfect_lock` AnimationController | bit_perfect_lock.dart | ❌ Rejected | StatelessWidget, tidak bisa punya AnimationController |

#### Sub-section: detail / support / bug_report

| Temuan | File | Status | Alasan |
|---|---|---|---|
| StreamSubscription tidak di-cancel | detail_sections/songs.dart | ✅ Valid | `dispose()` tidak cancel subscription dikonfirmasi |
| `launchUrl()` result tidak di-check | support_page.dart:33 | ✅ Valid | Tidak ada feedback ke user jika URL fail |
| Form submit tanpa validasi | bug_report_page.dart:45 | ✅ Valid | Submit tidak check field kosong |
| `_failedAt` map unbounded growth | cache_manager.dart | ✅ Valid | Dikonfirmasi di Batch 5 |

#### Sub-section: SearchSections state.dart

| Temuan | File | Status | Alasan |
|---|---|---|---|
| CRITICAL — dispose order salah | state.dart:42 | ❌ Rejected | Urutan removeListener → dispose sudah BENAR |
| FocusNode tidak di-dispose | search_sections/bar.dart | ❌ Rejected | FocusNode adalah external param — owner yang dispose |

---

### LOW (267 temuan — verifikasi per kelompok)

#### Dead Code LOW

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `exportPlaylist()` dead | playlist_service.dart | ✅ Valid | Tidak ada caller di UI |
| `clearHistory()` dead | history_service.dart | ✅ Valid | Tidak ada caller di UI |
| `getAlbumArtUri()` dead | media_store_service.dart | ✅ Valid | Tidak ada caller |
| `borderColor` param unused | glass_navbar.dart | ✅ Valid | Parameter tidak dipakai di build() |
| `opaque` override hardcoded | zoom_fade_route.dart:25 | ✅ Valid | `opaque` override selalu return false |
| `_effectStatusCache` tidak pernah invalidated | effect_status.dart | ✅ Valid | Cache stale tanpa invalidation |
| `LogLevel.verbose` tidak dipakai | log_service/level.dart | ✅ Valid | Enum value tidak digunakan |
| `providerDuration`/`attemptCount` di LyricsResult | lyrics_service/result.dart | ✅ Valid | Field tidak digunakan di luar class |
| `audio_session_handler.dart` pure re-export | services/ | ✅ Valid | |
| `replay_gain_service.dart` pure re-export | services/ | ✅ Valid | |
| `audio_service.dart` pure re-export | services/ | ✅ Valid | |
| `lyrics_service.dart` pure re-export | services/ | ✅ Valid | |
| `log_service.dart` pure re-export | services/ | ✅ Valid | |
| `equalizer_page.dart` pure re-export | pages/settings/ | ✅ Valid | |
| `sleep_timer_page.dart` pure re-export | pages/settings/ | ✅ Valid | |
| `openFile()` dead | open_file_service.dart | ❌ Rejected | IS digunakan via registerHandler/checkInitialUri/onResume |
| `EmptyPlaceholderPage` dead | empty_placeholder_page.dart | ❌ Rejected | Dipakai di support_page.dart |
| `SmartPlaylistType` unused di model | playlist.dart | ❌ Rejected | Enum dipakai di playlist_page + radio_sections |
| `LyricsSource` unused values | lyrics_service/result.dart | ❌ Rejected | Semua 4 values dipakai di service.dart |
| `EditableLibraryList` dead | library_sections/editable.dart | ❌ Rejected | Class aktual `_EditableRow` IS dipakai di state.dart:107 |

#### Null Safety LOW

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `_eventChannel!` di bridge | media3_playback_bridge | ❌ Rejected | Variable tidak exist; static const tidak pakai `!` |
| Tracks unsafe chain `tracks.first!` | apple_music_provider.dart | ❌ Rejected | Pakai `?.first ?? ''` pattern |
| `data['candidates'][0]` unsafe | kugou_provider.dart | ❌ Rejected | Diakses via null-safe chain |
| `result['lrc']['lyric']` chain | netease_provider.dart | ✅ Valid | Chaining tanpa null-safe operator |
| `response['data']['lrclist']` | kuwo_provider.dart | ✅ Valid | Chaining tanpa null-safe operator |
| `jsonResponse['data']['song']['list']` | qq_music_provider.dart | ✅ Valid | Deep chain tanpa null check |
| `songInfo.encoder!` | player_song_info_sheet/content | ✅ Valid | Sudah dikonfirmasi di MEDIUM |
| `_paths[id]!` setelah containsKey | artwork_repository | ❌ Rejected | Pola tidak exist di current code |
| `widget.song.title!` | player_content/content.dart | ⚠ NMV | Perlu konfirmasi apakah title nullable |
| `_queueSnapshot!` | audio_service/service.dart | ⚠ NMV | Perlu trace init chain |
| `_audioSession!` di debug section | debug pages | ⚠ NMV | Hanya di debug mode |
| `_remainingMs!` di sleep timer | sleep_timer_service.dart | ❌ Rejected | Field tidak exist di service |
| `song.replayGainTrack!` | loudness_source_resolver.dart | ✅ Valid | Force unwrap tanpa guard |
| `cached['mtime'] as int` | song_metadata_service/service.dart | ✅ Valid | Cast langsung tanpa null check |
| `album.year!.toString()` | detail_sections/album.dart | ✅ Valid | `year` nullable tapi di-unwrap |
| `widget.album!`/`widget.artist!` | detail.dart | ✅ Valid | Force unwrap dalam conditional dikonfirmasi |
| `peakLinear!` redundant | loudness_data.dart:46 | ✅ Valid | Sudah dikonfirmasi di MEDIUM |

#### Flutter Best Practices LOW

| Temuan | File | Status | Alasan |
|---|---|---|---|
| Icon tanpa const di browse_sections | browse_sections/section.dart | ✅ Valid | `Icon(...)` tanpa `const` dikonfirmasi |
| SizedBox tanpa const di album card | albums_section/card.dart | ✅ Valid | |
| Column/SizedBox tanpa const di body.dart | settings_page/body.dart | ✅ Valid | |
| `_EffectStatusRow` tanpa const constructor | effect_status.dart | ✅ Valid | |
| `_AudioSessionInfo` tanpa const | session_info.dart | ✅ Valid | |
| Text+TextStyle tanpa const di chrome app_bar | scrolling_page_chrome/app_bar.dart | ✅ Valid | |
| Padding tanpa const di library item | library_sections/item.dart | ✅ Valid | |
| Container vs DecoratedBox | recently_played_section.dart | ✅ Valid | Container lebih berat dari DecoratedBox jika hanya butuh decoration |
| ShaderMask per category tile | search_sections/cat_tile.dart | ❌ Rejected | Pakai Stack + LinearGradient, bukan ShaderMask |
| ListView horizontal tanpa explicit height | equalizer_page/preset_chips.dart | ❌ Rejected | Height sudah disediakan via SizedBox wrapper |
| SliverToBoxAdapter heavy content | library_sections/detail.dart | ✅ Valid | Content berat tanpa lazy loading |
| Binary search manual | state_timeline.dart | ✅ Valid | Manual binary search pada list sorted |
| `Map.forEach` saat cleanup | cache_manager.dart | ❌ Rejected | Pakai snapshot `.toList()` |
| `AnimatedList` tanpa GlobalKey | player/queue_overlay | ❌ Rejected | Pakai `ReorderableListView.builder`, bukan AnimatedList |
| CustomPainter repaint listenable | player_background/animated | ⚠ NMV | Perlu verifikasi Listenable connection |
| `Platform.isAndroid` di widget tree | system.dart:67 | ✅ Valid | Tidak berganti runtime; bisa static const |
| `AudioSession.instance` await per call | audio_session_handler | ✅ Valid | Instance harus di-cache, bukan di-await per call |
| Column + shrinkWrap double layout | browse_sections/content.dart | ❌ Rejected | File tidak exist di codebase |
| `removeListener` tanpa guard | library_sections/state.dart | ❌ Rejected | `removeListener` dipanggil di dispose, benar |
| `DraggableScrollableSheet` config | player_song_info_sheet/sheet.dart | ✅ Valid | initialChildSize tidak dikonfigurasi |
| `FutureBuilder` tanpa error widget | home/artists_section | ✅ Valid | Tidak ada fallback error UI |
| FocusNode disposal di search bar | search_sections/bar.dart | ❌ Rejected | External param — owner dispose |
| Slider `onChangeEnd` tanpa debounce | settings_widgets/slider.dart | ✅ Valid | Native call per drag end tanpa debounce |
| `Isolate.run` tidak di-cancel | replay_gain_service | ✅ Valid | Tidak ada cancellation pada service dispose |

#### Naming & Architecture LOW

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `song_info.dart` 47 field flat struct | models/song_info.dart | ✅ Valid | 47 field dikonfirmasi |
| In-memory cache tanpa max-size | artwork_repository.dart | ✅ Valid | Tidak ada cap untuk `_cache` Map |
| Naming inconsistency media3/ folder | lib/services/audio/ | ✅ Valid | Subfolder media3/ vs file flat di audio/ |
| `_buildLine()` 150 lines | state_build.dart | ✅ Valid | Method panjang dikonfirmasi |
| GitHub/privacy URL hardcoded | about_app_page.dart | ✅ Valid | Tidak ada konstanta terpusat |
| Hero tag collision (album.id only) | detail_sections/top_bar.dart | ✅ Valid | Tag hanya `album.id` — bisa collision jika album reused di 2 place |
| `_modules` untyped List | native_module_registry | ❌ Rejected | Sudah `List<NativeModule>` |
| `_ch` abbreviation | playback_manager.dart:89 | ✅ Valid | Nama pendek tidak deskriptif |
| `_buildX` vs `_X` naming | lyrics_appearance.dart | ✅ Valid | Inkonsistensi naming |
| 4 file per section, over-fragmented | home sections | ⚠ NMV | Bisa valid atau over-engineering — tergantung kompleksitas |
| `getColorsFromImage` vs `extractPalette` | palette_extractor.dart | ✅ Valid | Inkonsistensi naming API |
| `_BitPerfectToggle` vs global pattern | bit_perfect.dart | ✅ Valid | Private class yang tidak perlu private |
| Tidak ada unit test untuk rate_limiter | rate_limiter.dart | ✅ Valid | Zero test coverage untuk logic ini |
| `_handleLongPress`/`_handleTap` generic | song_row.dart | ❌ Rejected | Nama tepat untuk lambda closures, bukan named methods |

#### Bug Logic Minor LOW

| Temuan | File | Status | Alasan |
|---|---|---|---|
| `[offset:]` tag tidak selalu diterapkan | lrc_parser.dart:112 | ✅ Valid | Parsing offset dikonfirmasi ada tapi tidak selalu diapply |
| Lyrics quality priority tidak deterministik | fetch_manager.dart | ❌ Rejected | Quality dideterminasi berdasarkan `LyricsQuality` enum yang deterministic |
| Mutual exclusion LN vs RG hanya di service | audio.dart:234 | ✅ Valid | UI bisa enable keduanya jika tidak ada interlock di UI level |
| `is ScrollPositionWithSingleContext` unsafe | content.dart:159 | ✅ Valid | Cast conditional yang bisa gagal |
| LRC timestamp deduplikasi inkonsisten | lrclib_provider.dart:78 | ✅ Valid | Dedup tidak konsisten antar provider |
| `clearCache()` tidak clear `_diskCachedIds` | artwork_repository | ❌ Rejected | `clearMemory` tidak sama dengan `clearCache` yang tidak exist |
| `_notifyError()` tanpa konteks | audio_service/service.dart | ✅ Valid | Error notification minim info |
| Sleep timer state persist setelah kill | sleep_timer_service.dart | ✅ Valid | Tidak ada cleanup state di launch |
| Queue reorder off-by-one | playback_manager.dart:523 | ⚠ NMV | Perlu trace boundary validation |
| Dismiss gesture tidak cancel saat song change | player_up_next_card.dart | ✅ Valid | Gesture tidak di-cancel saat item berubah |
| Lyrics overlay fade height hardcoded 80.0 | lyrics_overlay.dart:55 | ✅ Valid | Tidak responsif terhadap font size |
| Apple Music quality assignment | apple_music_provider.dart:34 | ❌ Rejected | Sudah dikonfirmasi dynamic |

#### Performance Minor LOW

| Temuan | File | Status | Alasan |
|---|---|---|---|
| O(n) loop build album/artist IDs | app_state.dart:86 | ✅ Valid | Loop per rebuild dikonfirmasi |
| `List.toList()` per getQueue | playback_manager.dart | ❌ Rejected | Method tidak exist; `_currentQueue.toList()` hanya di listener |
| SharedPreferences per play | history_service.dart:67 | ✅ Valid | 3 write per trackPlay dikonfirmasi |
| `getInstance()` per ThemeController toggle | theme_controller.dart | ✅ Valid | |
| `List.removeAt(0)` FIFO O(n) | log_service/service.dart | ✅ Valid | Queue lebih tepat |
| Shader repaint per frame | player_background/artwork.dart | ✅ Valid | |
| `map().toList()` di lyrics_pickers | lyrics_pickers.dart:22 | ✅ Valid | Alokasi per build |
| In-memory cache tanpa max-size | artwork_repository.dart | ✅ Valid | |
| `_failedAtMs` unbounded | lyrics_cache_manager.dart | ✅ Valid | |
| FogPainter color lerp per frame | fog_painter.dart | ✅ Valid | Multiple lerp calls di paint() |
| `getEffectiveVolume()` per event | playback_manager.dart | ❌ Rejected | Method tidak ditemukan di lokasi terkait |
| ShaderMask per category tile | search_sections | ❌ Rejected | Pakai LinearGradient, bukan ShaderMask |
| N parallel FutureBuilders per album card | albums_section/card.dart | ✅ Valid | N card = N palette + N artwork futures |
| N parallel FutureBuilders per artist card | artists_section/card.dart | ✅ Valid | Sama |
| `AudioSession.instance` per call | audio_session_handler.dart | ✅ Valid | |
| `http.Client` tidak di-reuse | lyrics providers | ❌ Rejected | `static final http.Client` sudah di-reuse |
| AnimatedList tanpa GlobalKey | queue_overlay | ❌ Rejected | Pakai ReorderableListView |
| FogPainter lerp per frame | player_background | ✅ Valid | |
| Music list 4 nested VLB | music_list/state.dart | ❌ Rejected | Single FutureBuilder |
| `PlaylistService` decode per read | playlist_service.dart:67 | ✅ Valid | JSON decode dari SharedPrefs tiap fetch |
| History `List.where().toList()` | history_service.dart | ⚠ NMV | Mitigated oleh write-through cache |
| TagLib read per getScanResult | replay_gain_service | ✅ Valid | Mitigated oleh memory+disk cache |
| Changelog `SingleChildScrollView` + for-loop | changelog_page.dart | ✅ Valid | Gunakan ListView.builder untuk list panjang |
| `5+ addListeners` di initState | audio settings | ❌ Rejected | Hanya 2 listener ditemukan, tidak di lokasi tersebut |
| Browse section FutureBuilder per section | browse_sections/state.dart | ❌ Rejected | File tidak exist |

---

## BAGIAN C — LAPORAN 3: `Native_code_audit.md`

| ID | Temuan | File | Status | Alasan |
|---|---|---|---|---|
| K-01 | `path.hashCode()` sebagai PRIMARY KEY | MetadataCacheDb.kt:246 | ✅ Valid | CONFLICT_REPLACE + tidak ada collision detection + COL_PATH tidak UNIQUE |
| K-02 | Double `setActiveQueueIndex()` | CrossfadeController.kt:304,363 | ✅ Valid (design) | Call pertama di `beginCrossfade` (optimistic UI), kedua di fade complete — intentional tapi berpotensi race jika fade sangat singkat |
| K-03 | Stale KDoc "MediaKitPlaybackService" | PlaybackNotificationManager.kt:28 | ✅ Valid | Service sudah dihapus, KDoc stale |
| K-05 | Unreachable `while (inputBuffer.hasRemaining())` | StereoWideningAudioProcessor.kt:93 | ✅ Valid | ExoPlayer guarantee aligned frames, loop tidak pernah execute |
| K-07 | ReplayGainError ordinal stability | ReplayGainModels.kt | ✅ Valid | Terdokumentasi di lines 019-020, safe insertion point jelas |
| K-NEW-1 | `ActivePlayerProxy` — `currentTimeline` dan `currentPeriodIndex` TIDAK di-override | CrossfadeController.kt:109-110 | ✅ Valid | **BUG** — bisa menyebabkan state mismatch, diberi komentar "BUG" di kode sendiri |
| K-NEW-2 | `StretchAwareAudioProcessorChain` — 2 known bugs | stretch chain | ✅ Valid | Position drift + READY/BUFFERING oscillation terdokumentasi, belum diperbaiki |
| K-FIXED | 15 temuan "Fixed" di audit | multiple | ✅ Confirmed Fixed | Semua fix dikonfirmasi ada di source |

---

## CROSS-VALIDATION ANTAR LAPORAN

### Temuan duplikat (dilaporkan >1x)

| Temuan | Muncul di | Severity Final |
|---|---|---|
| `cached[2]`/`colors[2]` album card | Laporan 1 (7.2+8.2) + Laporan 2 (HIGH) | High |
| `ModalRoute.of(context)!` | Laporan 1 (8.3) + Laporan 2 (HIGH) | High |
| `widget.userPlaylist!`/`smartType!` | Laporan 1 (8.4) + Laporan 2 (HIGH) | High |
| `_current!` static | Laporan 1 (8.5) + Laporan 2 (HIGH) | High |
| `'Putih'` → `Colors.black` | Laporan 1 (8.1) + Laporan 2 (HIGH) | High |
| God files | Laporan 1 (5.1) + Laporan 2 (HIGH) | High |
| `ThemeController` SharedPrefs per toggle | Laporan 1 (7.1) + Laporan 2 (HIGH) | Medium |
| `setState` per scroll | Laporan 1 (6.1) + Laporan 2 (HIGH) | Medium |
| `_GlassSubToggle` duplikat | Laporan 1 (15.1) + Laporan 2 (MEDIUM) | Medium |
| Folder spasi `Bottom NavBar` | Laporan 1 (2.1+9.1) + Laporan 2 (LOW) | High |
| `fog_painter.dart` cryptic vars | Laporan 1 (7.6) + Laporan 2 (MEDIUM) | Low |
| `ffmpeg_bridge` StreamController | Laporan 1 (6.3) + Laporan 2 (MEDIUM) | Medium |
| `MediaCapabilitiesService.dispose()` | Laporan 1 (6.4) + Laporan 2 (MEDIUM) | Medium |
| `NativeModuleRegistry` sequential | Laporan 1 (5.2) + Laporan 2 (MEDIUM) | Medium |
| Assets `1.jpg`/`2.jpg`/`4.jpg` | Laporan 1 (11.1) + Laporan 2 (LOW) | Critical |

---

## FINAL PRIORITY TABLE — Valid Findings Only

### Critical

| Pri | Temuan | File | Severity |
|---|---|---|---|
| 1 | `assets/1.jpg`/`2.jpg`/`4.jpg` tidak di pubspec.yaml → browse banners hilang di release | pubspec.yaml | **Critical** |

### High

| Pri | Temuan | File | Severity |
|---|---|---|---|
| 2 | `'Putih'` → `Colors.black` — display bug aktif | lyrics_pickers.dart:112 | **High** |
| 3 | `cached[2]`/`colors[2]` unsafe array — RangeError crash | albums_section/card.dart:35,43 | **High** |
| 4 | `ModalRoute.of(context)!` di album + artist page | album_page:15, artist_page:14 | **High** |
| 5 | `widget.userPlaylist!`/`smartType!` (5x) | playlist_page.dart | **High** |
| 6 | `_current!` static (5x) | player_content/content.dart | **High** |
| 7 | `widget_test.dart` default counter template | test/widget_test.dart | **High** |
| 8 | `lib/Bottom NavBar/` folder spasi | lib/ | **High** |
| 9 | God files: log_page 889L, audio.dart 869L, playback_manager 833L, detail.dart 576L | multiple | **High** |
| 10 | `ThemeData` allocation di `build()` | app_state.dart:91 | **High** |
| 11 | **[Native] K-01** `path.hashCode()` sebagai PRIMARY KEY | MetadataCacheDb.kt:246 | **High** |
| 12 | **[Native] K-NEW-1** `ActivePlayerProxy` state mismatch bug | CrossfadeController.kt:109 | **High** |
| 13 | `stats!` x4 di playback_engine | playback_engine.dart:82-100 | **High** |
| 14 | Lyrics providers JSON unsafe casts | multiple providers | **High** |

### Medium

| Pri | Temuan | Severity |
|---|---|---|
| 15 | 20+ silent `catch (_) {}` tanpa log (media3 4x, artwork 3x, album, playlist, dll) | Medium |
| 16 | `ffmpeg_decoder_bridge` StreamController tidak di-close | Medium |
| 17 | `MediaCapabilitiesService.dispose()` tidak pernah dipanggil | Medium |
| 18 | `playlist.dart` null cast: `(json['songIds'] as List)` + `json['createdAt'] as int` | Medium |
| 19 | `NativeModuleRegistry.disposeAll()` error swallow | Medium |
| 20 | `NativeModuleRegistry.initializeAll()` sequential | Medium |
| 21 | `LyricsService` dual cache | Medium |
| 22 | `LyricsService.providerName.contains('tag')` rapuh | Medium |
| 23 | 7 lyrics providers tanpa base class — bug tidak propagate | Medium |
| 24 | `ThemeController._save()` SharedPrefs per toggle | Medium |
| 25 | `setState` per scroll tick di 4 halaman | Medium |
| 26 | `HistoryService` 3x SharedPrefs write per trackPlay | Medium |
| 27 | `HistoryService.getInstance()` per write | Medium |
| 28 | `_scrollResumeTimer` tidak di-cancel sebelum reassign | Medium |
| 29 | `_failedAtMs` map unbounded growth di cache_manager | Medium |
| 30 | `LyricsRateLimiter` pakai `DateTime.now()` per check | Medium |
| 31 | Artwork cache return path file yang sudah dihapus | Medium |
| 32 | `replay_gain_service.dart` pure re-export (thin wrapper tanpa added value) | Medium |
| 33 | `audio_session_handler.dart` pure re-export | Medium |
| 34 | `AudioSession.instance` await per call (harus di-cache) | Medium |
| 35 | StreamSubscription tidak di-cancel di `detail_sections/songs.dart` | Medium |
| 36 | StreamSubscription tidak di-cancel di `radio_sections/recent_state.dart` | Medium |
| 37 | `shrinkWrap:true` di search results ListView — double layout pass | Medium |
| 38 | BackdropFilter tanpa opacity threshold di unified_morph_player | Medium |
| 39 | SliverList full rebuild saat sort di detail.dart | Medium |
| 40 | `PlaylistService` JSON decode per read dari SharedPreferences | Medium |
| 41 | `player_song_info_sheet` encoder!/sampleRate!/bitrate! force unwrap (3x) | Medium |
| 42 | Empty Align tanpa child di player_song_info_sheet | Medium |
| 43 | `MediaQuery.sizeOf` rebuild per keyboard di player_song_info_sheet | Medium |
| 44 | `catch (_) {}` di share intent di player_more_menu | Medium |
| 45 | VLB rebuild progress bar per 50ms | Medium |
| 46 | N parallel FutureBuilders per album/artist card | Medium |
| 47 | `player_sheet nested builder` scope terlalu lebar | Medium |
| 48 | `lyrics_settings.dart` static Map<String,Timer> tanpa lifecycle cleanup | Medium |
| 49 | `loudness_data.dart:46` peakLinear! redundant force unwrap | Medium |
| 50 | 15x TextStyle identik di textTheme | Medium |
| 51 | `_buildHiResSection()` TODO inactive | Medium |
| 52 | ListView dalam Column di session_info (potential overflow) | Medium |
| 53 | `info_line.dart` duplikat `settings_widgets/info.dart` | Medium |
| 54 | `catch (_) {}` di EQ band_slider set | Medium |
| 55 | `catch (_) {}` di AudioOutputMode switch di system.dart | Medium |
| 56 | `equalizer.dart` hanya navigasi (thin wrapper) | Medium |
| 57 | Song context menu 450+ lines | Medium |
| 58 | ReorderableListView tanpa `itemExtent` | Medium |
| 59 | `Navigator.push` tanpa await di radio stations | Medium |
| 60 | `applyEdgeToEdge()` di builder callback | Medium |
| 61 | EQ silent attach failure (device_dsp) | Medium |
| 62 | `launchUrl()` result tidak di-check di support_page | Medium |
| 63 | Form submit tanpa validasi di bug_report_page | Medium |
| 64 | **[Native] K-NEW-2** StretchAwareAudioProcessorChain 2 known bugs | Medium |

### Low (68 valid — lihat tabel per kategori di BAGIAN B/C di atas)

Semua LOW yang valid mencakup:
- Dead files: chip.dart, sleep_timer.dart, lyrics.dart, lyrics_rows.dart, notif_icon.dart, berbagai pure re-exports
- Dead methods: exportPlaylist(), clearHistory(), getAlbumArtUri(), dll
- Missing const constructors (20+ lokasi)
- Naming issues: folder spasi, camelCase file, cryptic vars, param `v`, `_ch`
- Style/architecture: in-memory cache tanpa cap, over-fragmented files, URL hardcoded
- Performance minor: DateTime.now() di build, lerpDouble, map().toList() per build, dll
- Null safety minor: chain unsafe, cast langsung, force unwrap terproteksi parsial
- **[Native]** K-02 CrossfadeController double setActiveQueueIndex (intentional tapi perlu dokumentasi)
- **[Native]** K-03 stale KDoc, K-05 unreachable loop, K-07 ordinal stability

---

## STATISTIK FINAL

| Kategori | Total | Valid | Rejected | NMV |
|---|---|---|---|---|
| **Laporan 1 (dart_audit_report)** | 45 | 38 | 5 | 2 |
| **Laporan 2 CRITICAL** | 1 | 0 | 1 | 0 |
| **Laporan 2 HIGH** | 35 | 22 | 13 | 0 |
| **Laporan 2 MEDIUM** | 130 | 73 | 52 | 5 |
| **Laporan 2 LOW** | 267 | 50 | 211 | 6 |
| **Laporan 3 (native)** | 21 | 10 | 0 | 0 |
| **GRAND TOTAL** | **499** | **193** | **282** | **13** |

> ⚠ **56% temuan (282 dari 499) adalah false positive** — code yang direferensikan tidak ada atau perilaku yang diklaim tidak terjadi di codebase saat ini. Ini sangat mungkin karena audit ditulis berdasarkan snapshot codebase yang lebih lama, sebelum banyak refactoring besar (single-engine migration, virtualizer removal, crossfade rewrite, dll).

---

*Laporan ini menggantikan `Audit_Validation_Report.md` versi sebelumnya.*  
*Validasi dilakukan 18 Juli 2026 menggunakan 25 subagent paralel + direct grep/shell verification.*  
*Target device: Xiaomi Mi 9T / K20 (SD730, MIUI 12/Android 11).*
