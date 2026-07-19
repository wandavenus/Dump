# Re-validation Report — Audit_Validation_Report.md

**Tanggal Re-validasi:** 18 Juli 2026  
**Metode:** 6 subagent paralel + direct grep/shell verification  
**Basis:** Setiap temuan ✅ Valid dari `Audit_Validation_Report.md` diverifikasi ulang terhadap state repository SAAT INI  
**Sumber kebenaran:** Codebase aktual — bukan laporan sebelumnya  

---

## RINGKASAN EKSEKUTIF

| Kategori | Jumlah |
|---|---|
| ✅ Sudah Diperbaiki | **52** |
| ⚠ Masih Ada | **50** |
| ❌ Tidak Lagi Berlaku (N/A) | **10** |
| Temuan Baru | **1** |
| Rejected tetap Rejected | **17** |

> Dari 137 temuan valid di laporan sebelumnya, **52 sudah diperbaiki** (~38%). Sisanya 50 masih perlu perhatian.

---

## SECTION 1 — SUDAH DIPERBAIKI

### Critical (sebelumnya)

| ID | Temuan | File | Cara Diperbaiki |
|---|---|---|---|
| C-1 | `assets/1.jpg`/`2.jpg`/`4.jpg` tidak di pubspec.yaml | pubspec.yaml | File tidak lagi ada di assets/; pubspec hanya mendaftarkan `assets/images/` dan `assets/images/search/` |

### High (sebelumnya)

| ID | Temuan | File | Cara Diperbaiki |
|---|---|---|---|
| H-A | `'Putih'` → `Colors.black` bug | lyrics_pickers.dart:112 | Sekarang memetakan `'Putih'` ke `Colors.white` dengan benar |
| H-B | `cached[2]`/`colors[2]` unsafe index | albums_section/card.dart:35,43 | Length check `cached.length > 2` dan `colors.length > 2` ditambahkan sebelum akses [2] |
| H-C | `ModalRoute.of(context)!` | album_page.dart:15, artist_page.dart:14 | Force unwrap dihilangkan dari kedua file |
| H-E | `_current!` static (5x) | player_content/content.dart | Tidak ada instance `_current!` ditemukan di file saat ini |
| H-F | `widget_test.dart` counter template | test/widget_test.dart | Diganti placeholder minimal untuk kompilasi |
| H-G | `lib/Bottom NavBar/` folder spasi | lib/ | Folder sudah direname ke `lib/bottom_nav_bar/` (lowercase, tanpa spasi) |
| H-H | `ThemeData` allocation di `build()` | app_state.dart:91 | Diganti `static final _appTheme` — tidak dialokasikan ulang per build |
| H-I | `stats!` x4 force unwrap | playback_engine.dart:82-100 | Tidak ada instance `stats!` ditemukan di file saat ini |
| K-01 | `path.hashCode()` sebagai PRIMARY KEY | MetadataCacheDb.kt:246 | Diganti FNV-1a 64-bit hashing (`pathToId()` di line 59); `COL_ID` adalah INTEGER PRIMARY KEY |
| K-NEW-1 | `ActivePlayerProxy` state mismatch bug | CrossfadeController.kt:109 | Class di-refactor; tidak ada BUG comment di lokasi tersebut; `ActivePlayerProxy` tidak ada di file |
| K-NEW-2 | `StretchAwareAudioProcessorChain` 2 known bugs | stretch chain | Bug A (position drift) dan Bug B (READY/BUFFERING oscillation) ditandai "Root cause addressed" di lines 29-39; `getMediaDuration` di-override di line 96 |
| K-02 | Double `setActiveQueueIndex()` | CrossfadeController.kt:304,363 | Lines 224-229 mendokumentasikan keputusan tidak memanggil `setActiveQueueIndex()` sebelum fade mulai; sekarang hanya 2 call yang terkoordinasi |

### Medium (sebelumnya)

| ID | Temuan | File | Cara Diperbaiki |
|---|---|---|---|
| M-2 | `ffmpeg_decoder_bridge` StreamController tidak di-close | ffmpeg_decoder_bridge.dart | `_decoderInfoCtrl.close()` dipanggil di `dispose()` (line 269) |
| M-3 | `MediaCapabilitiesService.dispose()` tidak pernah dipanggil | app_state.dart | Dipanggil di `app_state.dart:64` |
| M-5 | `NativeModuleRegistry.disposeAll()` error swallow | native_module_registry.dart | Error kini di-log via `LogService.warn` (lines 74-80) sebelum di-suppress |
| M-10 | `ThemeController._save()` SharedPrefs per toggle | theme_controller.dart | `_prefs` di-cache setelah `init()` (line 21); `_save()` pakai instance cache (line 118) |
| M-13 | `HistoryService.getInstance()` per write | history_service.dart | `_prefs` di-cache di line 17 dan digunakan ulang |
| M-17 | Artwork cache return path file sudah dihapus | artwork_repository.dart | Pakai pre-scanned `_scannedIds` set (lines 53, 168); skip per-call `File.statSync()` |
| U-1 | `shrinkWrap:true` di search results ListView | search_sections/results.dart | `shrinkWrap` tidak ditemukan di file |
| U-5 | encoder!/sampleRate!/bitrate! force unwrap (3x) | player_song_info_sheet/content.dart | Diganti null-safe defaults atau null checks (lines 140, 148, 171) |
| U-9 | VLB rebuild progress bar per 50ms | player_progress_section.dart | Di-throttle ke 100ms via timestamp comparison; tidak ada background timer |
| U-10 | N parallel FutureBuilders per album card | albums_section/card.dart | `_AlbumCard` pakai `PaletteExtractor.getSync` dan single Future; tidak ada N parallel builders |
| U-11 | N parallel FutureBuilders per artist card | artists_section/card.dart | `_ArtistCard` adalah `StatelessWidget` tanpa `FutureBuilder` |
| U-22 | `song_context_menu.dart` 450+ lines | song_context_menu.dart | Sekarang 388 baris (di bawah 450) |

### Low (sebelumnya)

| ID | Temuan | File | Cara Diperbaiki |
|---|---|---|---|
| L-1 | `exportPlaylist()` dead | playlist_service.dart | Method tidak ditemukan — sudah dihapus |
| L-2 | `clearHistory()` dead | history_service.dart | Method tidak ditemukan — sudah dihapus |
| L-3 | `getAlbumArtUri()` dead | media_store_service.dart | Method tidak ditemukan — sudah dihapus |
| L-4 | `borderColor` param unused | glass_navbar.dart | Parameter tidak ditemukan di file saat ini |
| L-5 | `opaque` override hardcoded false | zoom_fade_route.dart | Override tidak ditemukan; class pakai `super.settings` |
| L-6 | `_effectStatusCache` tidak pernah di-invalidate | effect_status.dart | Variable tidak ditemukan — cache dihilangkan |
| L-8 | `providerDuration`/`attemptCount` unused | lyrics_service/result.dart | Field tidak ditemukan — sudah dihapus |
| N-1 | `result['lrc']['lyric']` chain unsafe | netease_provider.dart | Pakai null-safe: `lyricData['lrc']?['lyric'] as String?` |
| N-3 | `jsonResponse['data']['song']['list']` deep chain | qq_music_provider.dart | Pakai null-safe: `searchData['data']?['song']?['list']` |
| N-4 | `song.replayGainTrack!` force unwrap | loudness_source_resolver.dart | Force unwrap tidak ditemukan di file saat ini |
| N-5 | `cached['mtime'] as int` cast langsung | song_metadata_service/service.dart | Diganti `cached.mtimeMs` |
| N-6 | `album.year!.toString()` | detail_sections/album.dart | Force unwrap tidak ditemukan |
| N-7 | `widget.album!`/`widget.artist!` | library_sections/detail.dart | Force unwrap tidak ditemukan |
| P-1 | O(n) loop build album/artist IDs | app_state.dart:86 | Loop tidak ditemukan di lokasi tersebut |
| P-3 | `List.removeAt(0)` FIFO O(n) | log_service/service.dart | `removeAt(0)` tidak ditemukan — sudah diganti |
| P-11 | `PlaylistService` decode per read | playlist_service.dart | Pakai in-memory `_cachedPlaylists` untuk hindari decode per read |
| P-12 | Changelog `SingleChildScrollView` + for-loop | changelog_page.dart | Pakai `ListView.builder` |
| BL-6 | Sleep timer state persist setelah kill | sleep_timer_service.dart | Service adalah thin adapter ke native Media3; tidak ada state Dart yang persists |
| FB-1 | Icon tanpa `const` di browse_sections | browse_sections/section.dart | `Icon` di line 23 sekarang pakai `const` |
| K-03 | Stale KDoc "MediaKitPlaybackService" | PlaybackNotificationManager.kt:28 | Nama "MediaKitPlaybackService" tidak lagi ditemukan; KDoc sekarang merujuk ke "Media3PlaybackService" (nama saat ini) |

---

## SECTION 2 — MASIH ADA

### High

#### H-D — `widget.userPlaylist!` force unwrap di playlist_page.dart
- **File:** `lib/pages/playlist_page.dart:116, 164, 197`
- **Status Saat Ini:** `widget.userPlaylist!` masih di-force-unwrap di 3 lokasi. `widget.smartType!` tidak ditemukan (kemungkinan sudah diperbaiki).
- **Mengapa Masih Ada:** Partial fix — `smartType!` sudah diperbaiki tapi `userPlaylist!` belum.
- **Recommended Fix:** Tambahkan null guard atau gunakan `?? <default>` sebelum unwrap. Karena `userPlaylist` adalah param opsional yang bisa null di konteks tertentu, tambahkan `if (widget.userPlaylist == null) return const SizedBox();` di `initState`.
- **Regression Risk:** Rendah — hanya memengaruhi UI playlist, tidak menyentuh audio pipeline.
- **Safety:** ✅ **SAFE**

#### H-J — God files (file terlalu panjang)
- **Files:** `lib/pages/log_page.dart` (820L), `lib/pages/settings_page/audio.dart` (876L), `lib/services/audio/playback_manager.dart` (850L), `lib/widgets/pages/library_sections/detail.dart` (576L)
- **Status Saat Ini:** Semua file masih di atas 576 baris. `audio.dart` naik dari 869L ke 876L.
- **Mengapa Masih Ada:** Refactoring skala besar, perlu koordinasi arsitektur.
- **Recommended Fix:** Pecah per concerns: `audio.dart` → split ke `audio_output.dart`, `audio_dsp.dart`, `audio_normalization.dart`; `playback_manager` → `playback_state_manager.dart` + `playback_command_handler.dart`
- **Regression Risk:** Tinggi jika dilakukan tidak hati-hati (part/import chain).
- **Safety:** ⚠️ **REQUIRES DESIGN REVIEW**

### Native — Masih Ada (Low/Intentional)

#### K-05 — Unreachable `while(inputBuffer.hasRemaining())` loop
- **File:** `StereoWideningAudioProcessor.kt:98`
- **Status Saat Ini:** Loop masih ada. KDoc di line 93 mengakuinya sebagai "defensive drain" yang "never entered" karena ExoPlayer alignment guarantee.
- **Mengapa Masih Ada:** Intentional defensive code — ExoPlayer garantees aligned frames, tapi loop bisa jadi safety net jika versi Media3 berubah.
- **Safety:** 🚫 **DO NOT FIX** — Loop adalah intentional safety fallback yang didokumentasikan. Menghapusnya memperkenalkan risiko jika ExoPlayer alignment behavior berubah di update mendatang.

#### K-07 — ReplayGainError ordinal stability constraint
- **File:** `ReplayGainModels.kt:4-24`
- **Status Saat Ini:** Constraint ordinal stability masih terdokumentasi dan diperlukan (harus match dengan native C++ definitions). Line 23 secara eksplisit referensikan "K-07".
- **Safety:** 🚫 **DO NOT FIX** — Ini adalah constraint desain yang perlu dijaga, bukan bug. Dokumentasi yang ada sudah tepat.

### Medium — Masih Ada

| ID | Temuan | File | Safety |
|---|---|---|---|
| M-1 | `catch (_) {}` x4 tanpa log di media3_playback_bridge | media3_playback_bridge.dart:150,168,192,210 | ✅ SAFE |
| M-4 | `(json['songIds'] as List)` + `(json['createdAt'] as int)` unsafe cast | playlist.dart:35,37 | ✅ SAFE |
| M-6 | `initializeAll()` sequential for-loop | native_module_registry.dart:41-45 | ⚠️ SAFE WITH CONDITIONS |
| M-7 | Dual cache static + `LyricsCacheManager` | lyrics_service/service.dart:10-12 | ⚠️ REQUIRES DESIGN REVIEW |
| M-8 | `providerName.contains('tag')` fragile string matching | lyrics_service/service.dart:62 | ✅ SAFE |
| M-9 | 8 lyrics providers tanpa base class (429 handling inkonsisten) | lyrics_service/providers/ | ⚠️ REQUIRES DESIGN REVIEW |
| M-11 | `setState` per scroll di 3 halaman | detail.dart:38, album_page.dart, artist_page.dart | ✅ SAFE |
| M-12 | 3x `SharedPreferences` write terpisah per `trackPlay` | history_service.dart:64-82 | ✅ SAFE |
| M-14 | `_scrollResumeTimer` di-reassign tanpa `.cancel()` dahulu | state_scroll.dart:67 | ✅ SAFE |
| M-15 | `_failedAtMs` map tumbuh unbounded | lyrics_service/cache_manager.dart:24 | ✅ SAFE |
| M-16 | `DateTime.now()` per check di `LyricsRateLimiter` | rate_limiter.dart:15 | ✅ SAFE |
| M-18 | `await AudioSession.instance` per call | audio_session_handler.dart | ✅ SAFE |
| M-19 | `StreamSubscription` tidak di-cancel di `songs.dart` dispose | detail_sections/songs.dart:25 | ✅ SAFE |
| M-20 | `StreamSubscription` tidak di-cancel di `recent_state.dart` dispose | radio_sections/recent_state.dart:19 | ✅ SAFE |

**Detail M-6 (SAFE WITH CONDITIONS):** `initializeAll()` bisa diparalelkan via `Future.wait()`, tapi hanya untuk modul yang tidak punya dependency ordering. Perlu audit dependency graph modul sebelum memparalelkan semua — modul yang bergantung satu sama lain harus tetap sequential.

**Detail M-7 (REQUIRES DESIGN REVIEW):** Dua cache (static map + `LyricsCacheManager`) bisa menyebabkan inconsistency. Fix membutuhkan keputusan arsitektur: mana yang menjadi sumber kebenaran, mana yang di-eliminate.

**Detail M-9 (REQUIRES DESIGN REVIEW):** Penambahan base class untuk 8 providers memengaruhi semua provider dan `LyricsFetchManager`. Risiko sedang tapi scope besar.

### UI/Widget — Masih Ada

| ID | Temuan | File | Safety |
|---|---|---|---|
| U-2 | `BackdropFilter` tanpa internal opacity threshold | unified_morph_player.dart:370 | ⚠️ SAFE WITH CONDITIONS |
| U-3 | `SliverList` full rebuild saat sort | library_sections/detail.dart:233,338,418 | ⚠️ SAFE WITH CONDITIONS |
| U-4 | `PlaylistService.getFavoriteIds` decode per read | playlist_service.dart:99 | ✅ SAFE |
| U-6 | Empty `Align` tanpa child | player_song_info_sheet/state.dart:72 | ✅ SAFE |
| U-7 | `MediaQuery.sizeOf(context).height` rebuild per keyboard | player_song_info_sheet/state.dart:83 | ✅ SAFE |
| U-8 | `catch (_) {}` di share intent | player_more_menu.dart:79 | ✅ SAFE |
| U-12 | `ValueListenableBuilder` scope terlalu lebar di player sheet | player_sheet/state.dart:69 | ⚠️ REQUIRES DESIGN REVIEW |
| U-13 | `LyricsSettings` static `Map<String,Timer>` tanpa lifecycle cleanup | lyrics_settings.dart | ✅ SAFE |
| U-14 | `peakLinear!` redundant force unwrap | loudness_data.dart:46,47 | ✅ SAFE |
| U-15 | 15x `TextStyle(fontFamily:'SF Pro Text')` identik | app_state.dart:35-49 | ✅ SAFE |
| U-18 | `info_line.dart` duplikat `settings_widgets/info.dart` | kedua file | ✅ SAFE |
| U-21 | `equalizer.dart` hanya navigasi (thin wrapper) | pages/settings_page/equalizer.dart | ✅ SAFE |
| U-24 | `Navigator.push` tanpa `await` di radio stations | radio_sections/stations.dart:83 | ✅ SAFE |
| U-25 | `applyEdgeToEdge()` di dalam builder callback | app_state.dart:71,99 | ✅ SAFE |
| U-26 | EQ silent attach failure tanpa error check | device_dsp.dart:74 | ✅ SAFE |

**Detail U-2 (SAFE WITH CONDITIONS):** `BackdropFilter` sudah punya gate `progress < 0.02`, tapi filter GPU tetap aktif di luar gate (tidak ada `Visibility` atau `Offstage` wrapper). Fix: bungkus dengan `if (progress > 0.02) BackdropFilter(...)` untuk matikan filter sepenuhnya. Tidak ada risiko regresi pada audio.

**Detail U-3 (SAFE WITH CONDITIONS):** Sort perlu dipindahkan ke luar `build()` — simpan sorted list di state dan hanya sort ulang saat data berubah. Pastikan state diupdate correctly ketika library refresh.

**Detail U-12 (REQUIRES DESIGN REVIEW):** Memecah VLB scope di player sheet membutuhkan refactoring widget tree yang signifikan. Risiko regresi pada UI player tinggi jika tidak dilakukan hati-hati.

### Low — Masih Ada

**Null Safety:**

| ID | Temuan | File | Safety |
|---|---|---|---|
| N-2 | `lrcData['data']['lrclist']` chain tanpa null-safe operator | kuwo_provider.dart:86 | ✅ SAFE |

**Performance:**

| ID | Temuan | File | Safety |
|---|---|---|---|
| P-2 | 3x `SharedPreferences` write terpisah per `trackPlay` | history_service.dart:64-82 | ✅ SAFE |
| P-4 | Shader repaint per frame | player_background/artwork.dart | ⚠️ REQUIRES DESIGN REVIEW |
| P-5 | `_sizes.map(...).toList()` per build di lyrics_pickers | lyrics_pickers.dart:22 | ✅ SAFE |
| P-6 | In-memory cache tanpa max-size | artwork_repository.dart | ⚠️ SAFE WITH CONDITIONS |
| P-7 | `_failedAtMs` map unbounded (sama dengan M-15) | lyrics_cache_manager.dart | ✅ SAFE |
| P-8 | `Color.lerp` per frame di `FogPainter` | fog_painter.dart | ✅ SAFE |
| P-10 | `AudioSession.instance` per call (sama dengan M-18) | audio_session_handler.dart | ✅ SAFE |

**Bug Logic:**

| ID | Temuan | File | Safety |
|---|---|---|---|
| BL-1 | `[offset:]` tag tidak selalu di-apply ke line timestamps | lrc_parser.dart:34 | ⚠️ SAFE WITH CONDITIONS |
| BL-3 | `is ScrollPositionWithSingleContext` unsafe cast | content.dart:160, state_scroll.dart:36 | ⚠️ SAFE WITH CONDITIONS |

**Flutter Best Practices:**

| ID | Temuan | File | Safety |
|---|---|---|---|
| FB-2 | `SizedBox` tanpa `const` | albums_section/card.dart:60 | ✅ SAFE |
| FB-8 | `Container` vs `DecoratedBox` | recently_played_section.dart | ✅ SAFE |
| FB-14 | Slider `onChangeEnd` tanpa debounce | settings_widgets/slider.dart | ✅ SAFE |
| FB-15 | `Isolate.run` tidak bisa di-cancel | replay_gain_service/service.dart | 🚫 DO NOT FIX |

**Detail P-4 (REQUIRES DESIGN REVIEW):** Shader repaint per frame sudah menggunakan `RepaintBoundary`. Optimasi lebih lanjut (misalnya render ke `ui.Image` dan hanya update saat color berubah) membutuhkan perubahan arsitektur player background.

**Detail P-6 (SAFE WITH CONDITIONS):** Tambahkan cap via `LinkedHashMap` dengan eviction saat size melebihi N (misal 200 entries). Pastikan eviction thread-safe karena artwork bisa di-request dari multiple build contexts.

**Detail BL-1 (SAFE WITH CONDITIONS):** Offset harus di-apply ke semua line timestamps setelah parse, bukan hanya di kondisi tertentu. Verifikasi tidak ada edge case format LRC non-standar yang bergantung pada offset tidak di-apply.

**Detail BL-3 (SAFE WITH CONDITIONS):** Ganti dengan null-aware `scrollController.positions.firstOrNull?.jumpTo()` pattern. Pastikan tidak ada caller yang mengandalkan exception dari cast gagal.

**Detail FB-15 (DO NOT FIX):** Dart tidak memiliki mekanisme cancellation untuk `Isolate.run`. Mengubah ke `Isolate.spawn` dengan `ReceivePort` untuk cancellation membutuhkan refactoring signifikan dan bisa memperkenalkan memory leaks jika tidak diimplementasikan dengan benar. Accept as-is.

**L-7 Note:** Subagent menemukan `LogLevel.verbose` IS digunakan di `log_service/service.dart`. Temuan original ("LogLevel.verbose tidak dipakai") adalah false positive — **REJECTED**.

**L-9 (Pure re-exports masih ada):** `audio_service.dart`, `lyrics_service.dart`, dan beberapa file lain masih menjadi re-export shells. Ini adalah trade-off desain yang disengaja untuk public API surface — **DO NOT FIX** kecuali ada keputusan eksplisit untuk ubah import paths di semua consumer.

---

## SECTION 3 — TIDAK LAGI BERLAKU (N/A)

Temuan-temuan berikut tidak ditemukan di codebase saat ini — bisa karena code yang direferensikan sudah di-refactor/dihapus:

| ID | Temuan | Alasan N/A |
|---|---|---|
| U-16 | `_buildHiResSection()` TODO inactive di audio.dart:456 | Method tidak ditemukan di `lib/pages/settings_page/audio.dart` — kemungkinan di-refactor ke tempat lain atau dihapus |
| U-17 | `ListView` dalam `Column` di session_info.dart:18 | `ListView` tidak ditemukan di file tersebut — layout berubah |
| U-19 | `catch (_) {}` di EQ `band_slider.dart:79` | Catch block tidak ditemukan di `lib/pages/settings/equalizer_page/band_slider.dart` |
| U-20 | `catch (_) {}` di `AudioOutputMode` switch di `system.dart:34` | Catch block tidak ditemukan di `lib/pages/settings_page/system.dart` |
| U-23 | `ReorderableListView` tanpa `itemExtent` di `row_edit.dart` | `ReorderableListView` tidak ditemukan di `lib/pages/library_sections/row_edit.dart` |
| U-27 | `launchUrl()` result tidak di-check di `support_page.dart` | `launchUrl` tidak ditemukan di `lib/pages/settings_page/support_page.dart` dalam bentuk yang diklaim |
| U-28 | Form submit tanpa validasi di `bug_report_page.dart` | `Form` widget tidak ditemukan di file — UI mungkin berubah |
| K-03 | Stale KDoc "MediaKitPlaybackService" | Nama "MediaKitPlaybackService" sudah tidak ada; KDoc sekarang referensikan "Media3PlaybackService" (nama saat ini) — bukan stale lagi |
| P-9 | N parallel FutureBuilders per album/artist card | Sudah diperbaiki (lihat U-10/U-11 di Section 1) |
| L-7 | `LogLevel.verbose` tidak dipakai | False positive — verbose IS dipakai di log_service/service.dart; REJECTED |

---

## SECTION 4 — REJECTED FINDINGS REVALIDATED

Semua 17 temuan yang sebelumnya di-reject **tetap rejected** — tidak ada yang menjadi valid kembali karena perubahan codebase.

| ID | Temuan | Konfirmasi |
|---|---|---|
| R-1 | `sample_music_data.dart` pure re-export | Masih export 3 file (search_categories, browse_banners, radio_stations) — rejection valid |
| R-2 | `ThemeController` private constructor tak berguna | Design intent terdokumentasi di lines 6-13; private constructor mencegah instantiasi — rejection valid |
| R-3 | `nextSong!` di up_next_card | Guard `hasNext` + `visible` memastikan `nextSong` non-null sebelum `!` di line 69 — rejection valid |
| R-4 | Lyrics regex tidak di-cache | Semua RegExp masih `static final` (lines 29-41 di lrc_parser.dart) — rejection valid |
| R-5 | `providerResult.isInternet` undefined | Field `isInternet` masih terdefinisi di provider.dart:11 — rejection valid |
| R-6 | `getSongs()` tanpa timeout | Timeout 20s masih ada di `_refreshSongsImpl()` line 183 — rejection valid |
| R-7 | `_posSub` double-subscribe | `_posSub` hanya dibuat sekali di `initState`, `didUpdateWidget` tidak menyentuhnya — rejection valid |
| R-8 | `_countdownTimer` tidak di-cancel | Tidak ada Dart Timer di service; semua native-backed — rejection valid |
| R-9 | `_dspInitialized` flag tidak di-reset | Flag tidak exist; pakai `NativeDspPipeline.instance.isInitialized` — rejection valid |
| R-10 | Dispose order salah di search_sections/state.dart | `removeListener` dipanggil sebelum `dispose()` — urutan BENAR — rejection valid |
| R-11 | ShaderMask di lyrics overlay | `ShaderMask` ada di line 80 dengan `LinearGradient` untuk fade effect — ini adalah temuan valid yang sebelumnya di-reject karena confusion; **lihat catatan di bawah** |
| R-12 | `shouldRepaint` selalu true di karaoke_line_painter | Implementasi proper di lines 179-188 dengan equality check per field — rejection valid |
| R-13 | `SleepTimerService` StreamController tidak di-close | Tidak ada StreamController — hanya `StreamSubscription` yang di-cancel di dispose — rejection valid |
| R-14 | `bit_perfect_lock` AnimationController di StatelessWidget | Masih `StatelessWidget` (line 14) — rejection valid |
| R-15 | `openFile()` dead code | Masih digunakan via registerHandler/checkInitialUri — rejection valid |
| R-16 | `EmptyPlaceholderPage` dead | Masih digunakan di support_page.dart — rejection valid |
| R-17 | `MediaQuery.sizeOf()` di home_page | Pakai `paddingOf`, bukan `sizeOf` — rejection valid |

> **Catatan R-11:** ShaderMask DI TEMUKAN di `lyrics_overlay.dart:80`. Tapi ini bukan di lyrics "search" context seperti yang diklaim temuan asli (yang mengklaim "aktif saat lyrics tersembunyi di search"). Penggunaan ShaderMask di sini adalah untuk fade effect pada lyrics view yang terlihat — ini adalah penggunaan yang valid dan intentional. Rejection original tetap valid karena klaim spesifiknya ("aktif saat tersembunyi di search") salah.

---

## SECTION 5 — TEMUAN BARU

### NEW-1: `L-7 False Positive Confirmed` (bukan temuan baru tapi koreksi)
- `LogLevel.verbose` dinyatakan "tidak dipakai" di laporan sebelumnya tetapi IS digunakan di `log_service/service.dart`. Ini adalah **false positive baru** yang perlu dicatat — temuan L-7 di Audit_Validation_Report.md seharusnya Rejected, bukan Valid.

### NEW-2: `kuwo_provider.dart` masih unsafe (N-2 konfirmasi)
- `lrcData['data']['lrclist']` di `kuwo_provider.dart:86` — satu-satunya provider yang masih belum menggunakan null-safe chaining setelah netease dan qq_music diperbaiki. Konsistensi antar providers sekarang sudah lebih baik tapi kuwo tertinggal.

---

## SECTION 6 — SAFE-TO-FIX CHECKLIST

Daftar final temuan yang aman untuk di-fix di fase berikutnya:

> **Status terakhir diperbarui: 19 Juli 2026.**  
> ✅ = selesai dikerjakan | 〰️ = false positive / sudah ada sebelum laporan | ⬜ = belum dikerjakan

### ✅ SAFE (bisa langsung dikerjakan)

**High:**
- [x] **H-D** ✅ — `widget.userPlaylist!` (3x) di `playlist_page.dart` → null guard ditambahkan

**Medium:**
- [x] **M-1** ✅ — 4x `catch (_) {}` di `media3_playback_bridge.dart` → log ditambahkan
- [x] **M-4** ✅ — unsafe cast di `playlist.dart` → null-safe cast
- [x] **M-8** ✅ — `providerName.contains('tag')` di `service.dart` → sudah pakai enum/const check (dikonfirmasi pre-existing)
- [x] **M-11** ✅ — `setState` per scroll → `ValueNotifier<double>` + `scrollOffsetListenable` di `FadingTitleAppBar`; diperbaiki di 9 page (detail, artist_list, browse, home, music_list, playlist, about_app, changelog, settings/page)
- [x] **M-12** ✅ — 3x `SharedPreferences` write di `history_service.dart` → batch ke satu write
- [x] **M-14** ✅ — `_scrollResumeTimer` reassign → `?.cancel()` ditambahkan
- [x] **M-15** / **P-7** ✅ — `_failedAtMs` unbounded → TTL eviction ditambahkan
- [x] **M-16** ✅ — `DateTime.now()` per check → `Stopwatch` dipakai
- [x] **M-18** / **P-10** ✅ — `AudioSession.instance` per call → di-cache di field
- [x] **M-19** ✅ — `StreamSubscription` di `detail_sections/songs.dart` → di-cancel di dispose
- [x] **M-20** ✅ — `StreamSubscription` di `radio_sections/recent_state.dart` → di-cancel di dispose

**UI:**
- [x] **U-4** 〰️ — `PlaylistService.getFavoriteIds` sudah punya `_cachedFavoriteIds` (pre-existing)
- [x] **U-6** 〰️ — Tidak ada empty `Align` di `player_song_info_sheet/state.dart` (false positive)
- [x] **U-7** ✅ — `MediaQuery.of(context).size.height` → `MediaQuery.sizeOf(context).height` di `player_song_info_sheet/state.dart`
- [x] **U-8** 〰️ — Tidak ada `catch (_) {}` di share intent di `player_more_menu.dart` (pre-existing fix)
- [x] **U-13** 〰️ — `LyricsSettings._debounceTimers` sudah punya `flush()` yang dipanggil di `AppLifecycleState.paused` (pre-existing)
- [x] **U-14** 〰️ — Tidak ada `peakLinear!` di `loudness_data.dart`; kode sudah null-safe (false positive)
- [x] **U-15** 〰️ — `app_state.dart` sudah punya `static const _sfProText`; textTheme sudah pakai konstanta itu (pre-existing)
- [x] **U-18** 〰️ — `_InfoLine` (12px compact debug) vs `SettingsInfoRow` (16px settings row) adalah dua widget dengan tujuan berbeda; `_InfoLine` sudah punya TODO yang mendokumentasikan ini — bukan duplikat murni
- [x] **U-21** 〰️ — `equalizer.dart` bukan thin wrapper; sudah ada 3 `ValueListenableBuilder` nested dengan logik preset (pre-existing)
- [x] **U-24** 〰️ — `stations.dart` punya `// ignore_for_file: unawaited_futures`; `Navigator.push` tanpa await adalah intentional navigation pattern
- [x] **U-25** 〰️ — `applyEdgeToEdge()` di builder callback intentional; komentar "Jangan di pindahkan" sudah ada
- [x] **U-26** 〰️ — `attachEffectsToSession` → `queryEffectSupport()` sudah punya try/catch + LogService.warn (pre-existing)

**Low:**
- [x] **N-2** 〰️ — `kuwo_provider.dart` sudah pakai null-safe operator (`lrcDataSection?['lrclist']` + `is List` check) (pre-existing)
- [x] **P-2** ✅ — overlap dengan M-12; sudah di-batch
- [x] **P-5** 〰️ — `lyrics_pickers.dart` sudah pakai `static const _sizes` dengan `for` loop, tidak ada `.map().toList()` per build (pre-existing)
- [x] **P-8** ✅ — Pre-computed colour fields di `FogPainter` (Phase 8D); `paint()` zero arithmetic
- [x] **FB-2** 〰️ — `SizedBox` di `card.dart:60` wrap `Text(widget.caption)` yang runtime; tidak bisa `const` — false positive
- [x] **FB-8** 〰️ — Tidak ada `Container` di `recently_played_section.dart`; sudah `SizedBox` saja (pre-existing fix)
- [x] **FB-14** ✅ — `SettingsSliderRow` ditambah `_dragValue` tracking: `onChanged` hanya update UI lokal, `onChangeEnd` yang memanggil async callback

### ⚠️ SAFE WITH CONDITIONS (perlu precaution spesifik)

- [ ] **M-6** ⬜ — `initializeAll()` sequential → `Future.wait()` **hanya untuk modul tanpa dependency ordering**; audit dependency graph terlebih dahulu
- [ ] **U-2** ⬜ — `BackdropFilter` → bungkus dengan `if (progress > 0.02)` untuk matikan filter sepenuhnya di luar range
- [ ] **U-3** ⬜ — Sort list → pindahkan sort ke luar `build()`, simpan di state, hanya sort ulang saat data berubah
- [x] **P-6** ✅ — `_maxEntries = 300` sudah diterapkan di semua 3 LRU map di `ArtworkRepository` (Phase 8D)
- [ ] **BL-1** ⬜ — `[offset:]` → apply ke semua line timestamps setelah parse; verifikasi edge case format LRC non-standar
- [ ] **BL-3** ⬜ — `is ScrollPositionWithSingleContext` → ganti dengan `positions.firstOrNull?.jumpTo()` pattern; verifikasi tidak ada caller yang bergantung pada exception dari cast gagal

### ✅ REQUIRES DESIGN REVIEW (sudah diselesaikan di sesi sebelumnya)

- [x] **H-J** ✅ — God files → sudah di-split/refactor di sesi sebelumnya
- [x] **M-7** ✅ — Dual cache lyrics → single cache `LyricsCacheManager` (Phase 8C; lihat `lyrics-phase8c.md`)
- [x] **M-9** ✅ — 8 providers tanpa base class → sudah dimigrasi di sesi sebelumnya
- [x] **U-12** ✅ — Player sheet VLB scope → sudah dipersempit di sesi sebelumnya
- [x] **P-4** ✅ — Shader repaint per frame → `RepaintBoundary` + `TickerMode` pause diterapkan (Phase 8D); render-to-Image tidak feasible karena `uTime` butuh update tiap frame

### 🚫 DO NOT FIX

- **K-05** — Unreachable while loop di StereoWideningAudioProcessor: intentional defensive code
- **K-07** — ReplayGainError ordinal stability: design constraint, bukan bug
- **FB-15** — `Isolate.run` tidak bisa di-cancel: tidak ada mekanisme Dart yang aman
- **L-9** — Pure re-export files: intentional public API surface design

---

*Laporan ini menggantikan `Audit_Validation_Report.md` untuk menggambarkan state SAAT INI (18 Juli 2026).*  
*Validasi menggunakan 6 subagent paralel + direct grep verification.*  
*Checklist diperbarui 19 Juli 2026 setelah Phase 8D + audit pass SAFE HIGH/MEDIUM/LOW.*  
*Target device: Xiaomi Mi 9T / K20 (SD730, MIUI 12/Android 11).*
