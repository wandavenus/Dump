# Dart/Flutter Best Practices Audit Report

**Project:** musicplayer (Flutter music player app)  
**Files audited:** 281 Dart files (~33k lines under `lib/`, `test/`, etc.)  
**Date:** 2026-07-20  
**Scope:** Read-only audit. No source files modified.

---

## Executive Summary

The codebase is a mature, well-structured Flutter music player with a service-oriented architecture, heavy async initialization, and tight native (Media3/FFI) integration. The team demonstrates strong awareness of Flutter lifecycle and async pitfalls in many places (e.g., `mounted` checks, timeout-wrapped MethodChannel calls, fail-open native DSP guards).

However, the audit identified **15 HIGH-severity** findings (mostly unsafe `!` force-unwraps and bare `catch` blocks that swallow exceptions without logging), **20+ MEDIUM-severity** findings (lifecycle leaks, excessive `unawaited` fire-and-forget, oversized god files, `Column`+`shrinkWrap` performance anti-patterns), and **20+ LOW-severity** findings (magic numbers, hardcoded strings, missing `const`, import ordering).

The most impactful risk is **null-safety correctness**: several widgets force-unwrap values from native-backed models or `lerpDouble` results, which will crash on edge-case data.

---

## HIGH Severity

### 1. Unsafe `!` force-unwraps on `lerpDouble()` in morph player
**Files/Lines:**
- `lib/widgets/unified_morph_player.dart:345-348`
- `lib/widgets/unified_morph_player.dart:373-376`
- `lib/widgets/unified_morph_player.dart:514-520`
- `lib/widgets/player/player_content/content.dart:471,475,489,498,502`

`lerpDouble()` returns `double?`. The code force-unwraps with `!` after every call. If `t` is ever slightly outside `[0.0, 1.0]` (e.g., due to a gesture overshoot or animation fraction precision), this throws a `NullThrownError`.

**Fix:** Replace `lerpDouble(a, b, t)!` with a local helper that clamps `t` and asserts non-null, or use `??` fallback:
```dart
double _lerp(double a, double b, double t) =>
    lerpDouble(a, b, t.clamp(0.0, 1.0)) ?? a;
```

---

### 2. Unsafe `!` force-unwraps on optional song metadata in player info sheet
**File/Lines:** `lib/widgets/player/player_song_info_sheet/content.dart:148,171,215,217,226,229,232,234,239,242,245,248,251,254`

Fields like `encoder`, `loudnessSource`, `dateAdded`, `modified`, `composer`, `publisher`, `copyright`, `isrc`, `comment`, `rgTrackGain`, `rgTrackPeak`, `rgAlbumGain`, `rgAlbumPeak`, `r128Track`, `r128Album` are force-unwrapped. These come from native metadata which may be missing for many files.

**Fix:** Use null-aware access with fallback text:
```dart
value: songInfo.encoder ?? 'Unknown',
```

---

### 3. Unsafe `!` force-unwrap in playlist song lookup
**File/Line:** `lib/pages/playlist_page.dart:82`

```dart
ids.where(songMap.containsKey).map((id) => songMap[id]!).toList();
```
The `where` + `map(id)!` pattern is redundant — if `containsKey` is true, the value exists. But if the map is mutated between the `where` and `map` (unlikely here but possible in concurrent scenarios), this crashes. More importantly, this pattern is repeated elsewhere.

**Fix:** Use `map((id) => songMap[id]!).toList()` only after confirming the key exists, or use `Iterable.map` with a safe lookup:
```dart
return ids.where(songMap.containsKey).map((id) => songMap[id]!).toList();
```
This specific instance is safe because `where` and `map` run on the same iterator, but the pattern is fragile. Prefer `List<LocalSong>.generate` or a for-loop.

---

### 4. Same unsafe `!` pattern in recently-played section
**File/Line:** `lib/widgets/pages/home/recently_played_section.dart:44`

```dart
.map((id) => songMap[id]!)
```
Same pattern as above.

**Fix:** Same as finding #3.

---

### 5. Same unsafe `!` pattern in radio recent state
**File/Line:** `lib/widgets/pages/radio_sections/recent_state.dart:31`

```dart
.map((id) => songMap[id]!)
```
Same pattern.

**Fix:** Same as finding #3.

---

### 6. Force-unwrap of `_entry!` in player more menu
**File/Line:** `lib/widgets/player/player_more_menu.dart:55`

```dart
Overlay.of(context, rootOverlay: true).insert(_entry!);
```
If `_entry` is null (e.g., widget disposed before insert), this crashes.

**Fix:** Add a null guard:
```dart
if (_entry == null) return;
Overlay.of(context, rootOverlay: true).insert(_entry);
```

---

### 7. Force-unwrap of `_prefs!` in theme controller
**File/Line:** `lib/themes/theme_controller.dart:47`

```dart
final prefs = _prefs!;
```
If `_prefs` is accessed before `init()` completes, this crashes.

**Fix:** Add an assertion or guard:
```dart
assert(_prefs != null, 'ThemeController not initialized');
final prefs = _prefs!;
```

---

### 8. Force-unwrap of playlist/favorite caches
**File/Lines:** `lib/services/playlist_service.dart:19,28,90,100`

```dart
if (_cachedPlaylists != null) return List.of(_cachedPlaylists!);
```
The null-check makes the `!` technically safe, but it's still a code-smell. More importantly, the caches are not thread-safe — concurrent `getPlaylists()` + `createPlaylist()` can cause lost updates.

**Fix:** Use a `Completer` or mutex for cache writes, or move to a proper state manager.

---

### 9. Force-unwrap of regex capture group
**File/Line:** `lib/services/replay_gain_service/service.dart:198`

```dart
return double.tryParse(match.group(1)!);
```
If the regex doesn't match group 1, this crashes.

**Fix:** Return a default on null:
```dart
final g = match.group(1);
return g == null ? null : double.tryParse(g);
```

---

### 10. Unsafe `!` on `songInfo` optional fields (summary of ~14 instances)
**File:** `lib/widgets/player/player_song_info_sheet/content.dart`

Multiple optional fields from native metadata are force-unwrapped. When files lack embedded tags (common for MP3s without ID3 or streaming sources), this crashes.

**Fix:** Replace each `songInfo.field!` with `songInfo.field ?? '—'` or a localized fallback.

---

### 11. Force-unwrap of `_countsFuture!` in library detail
**File/Line:** `lib/widgets/pages/library_sections/detail.dart:151`

```dart
countsFuture: _countsFuture!,
```
If the widget rebuilds before `_countsFuture` is assigned, this crashes.

**Fix:** Use a null-aware fallback or ensure initialization in `initState`.

---

### 12. Force-unwrap of widget properties in settings
**Files/Lines:**
- `lib/pages/settings/settings_widgets/slider.dart:127,199` — `widget.description!`
- `lib/pages/settings/settings_widgets/toggle.dart:34` — `subtitle!`
- `lib/pages/settings/equalizer_page/page.dart:390` — `trailing!`
- `lib/pages/settings/sleep_timer_page/presets.dart:73` — `preset.duration!`

These assume required fields are always provided, but widget reconstruction or incorrect usage can violate that.

**Fix:** Add `assert(description != null)` in constructor, or use `??` fallback in build.

---

### 13. Force-unwrap of `nextSong!` in up-next card
**File/Line:** `lib/widgets/player/player_up_next_card.dart:69`

```dart
child: _UpNextCardContent(song: nextSong!),
```
If the queue is empty or the next track is null, this crashes.

**Fix:** Guard with null check and render placeholder:
```dart
if (nextSong == null) return const SizedBox.shrink();
```

---

### 14. Force-unwrap of `_basePainter!` in karaoke painter
**File/Line:** `lib/widgets/player/synced_lyrics_view/karaoke_line_painter.dart:159`

```dart
final painter = _basePainter!;
```
If the painter hasn't been set yet, this crashes.

**Fix:** Add null guard or make the field non-nullable with proper initialization.

---

### 15. Force-unwrap of `_pendingSeekPos!` in lyrics playback state
**File/Line:** `lib/widgets/player/synced_lyrics_view/state_playback.dart:31`

```dart
final delta = (position - _pendingSeekPos!).inMilliseconds.abs();
```
If `_pendingSeekPos` is null (no pending seek), this crashes.

**Fix:** Guard with `if (_pendingSeekPos == null) return;`.

---

## MEDIUM Severity

### 1. Silent exception swallowing via bare `catch (_)` or `catch (_) {}`
**Files (representative sample):**
- `lib/widgets/song_context_menu.dart:318,336`
- `lib/widgets/pages/radio_sections/stations.dart:78`
- `lib/widgets/pages/radio_sections/station_card.dart:160`
- `lib/widgets/pages/radio_sections/recent_state.dart:34`
- `lib/widgets/pages/home/recently_played_section.dart:59`
- `lib/widgets/pages/browse_sections/banners.dart:121`
- `lib/widgets/common_actions.dart:31`
- `lib/services/open_file_service.dart:61`
- `lib/services/lyrics_service/providers/local_file_provider.dart:77,109,112`
- `lib/services/lyrics_service/providers/qq_music_provider.dart:83`
- `lib/services/lyrics_service/cancellation.dart:34`
- `lib/services/lyrics_service/cache_manager.dart:82,103,141`

Bare `catch (_)` or empty catch blocks swallow all exceptions including `OutOfMemoryError`, `StackOverflowError`, and platform channel errors. This makes debugging impossible in production.

**Fix:** At minimum, log the exception:
```dart
} catch (e, st) {
  LogService.warn('Widget', 'Operation failed: $e', stackTrace: st.toString());
}
```

---

### 2. Excessive `unawaited` fire-and-forget without error handling
**Files:**
- `lib/main/main.dart:141-162` (prewarm batches)
- `lib/main/main.dart:238,253`
- `lib/services/audio_service/service.dart:346,419,486,487,528,539,573`
- `lib/services/audio/audio_effects_service/service.dart:222,245,246,249,253,333,334,547,553,571,600,616,651,662,692,719,728,729,805,806`
- `lib/services/media_store_service.dart:117,194`
- `lib/services/playback_manager.dart:188,204`

`unawaited` is used pervasively for fire-and-forget. While many calls are intentionally best-effort (prewarm, history logging, native DSP), errors are silently dropped. This is acceptable for non-critical operations but risky for operations that should never fail silently (e.g., queue mutations, settings writes).

**Fix:** For critical operations, add `.catchError()`:
```dart
unawaited(PlaybackManager.insertNext(song).catchError((e) {
  LogService.warn('AudioService', 'insertNext failed: $e');
}));
```

---

### 3. Missing `dispose()` on `_lyricsOffsetController` (ScrollOffsetController)
**File/Line:** `lib/widgets/player/player_content/content.dart:68,177-183`

`_lyricsOffsetController` is a `ScrollOffsetController` that is created in `initState` but **never disposed**. While `ScrollOffsetController` doesn't hold a native resource, it registers with the scrollable and should be disposed.

**Fix:** Add `_lyricsOffsetController.dispose();` in the `dispose()` method.

---

### 4. `_staticSubs` in `AudioService` never cancelled
**File/Line:** `lib/services/audio_service/service.dart:46,90-183`

`AudioService._staticSubs` accumulates `StreamSubscription`s in `initialize()` but there is no `dispose()` method to cancel them. Since `AudioService` is a static singleton that lives for the app lifetime, this is not a leak in practice, but it prevents clean shutdown (e.g., in tests or hot-restart).

**Fix:** Add a static `dispose()` method that cancels all subscriptions, and call it from `MediaCapabilitiesService.dispose()` or app shutdown.

---

### 5. Same `_subs` pattern in `PlaybackManager`
**File/Line:** `lib/services/audio/playback_manager.dart:104,178-207`

`PlaybackManager._subs` accumulates subscriptions in `initialize()` and does cancel them in `dispose()`. However, `dispose()` is never called from the app lifecycle. Same observation as above — not a leak in production but prevents clean test teardown.

**Fix:** Call `PlaybackManager.dispose()` from `_MyAppState.dispose()`.

---

### 6. `_MyAppState.didChangeAppLifecycleState` uses `BuildContext` after async gap without `mounted` check
**File/Line:** `lib/main/app_state.dart:76-93`

```dart
unawaited(AudioService.syncFromNative().catchError(...));
unawaited(OpenFileService.onResume());
unawaited(LyricsSettings.flush().catchError(...));
```
These are fire-and-forget and don't use `context` after await, so they're safe. However, `AudioService.syncFromNative()` internally calls `setState` on `AudioPlaybackState` ValueNotifier, which is fine. The pattern is acceptable but worth noting that any future change that captures `context` here would be a bug.

**Fix:** No immediate fix needed, but add a comment warning future maintainers.

---

### 7. `Column` + `shrinkWrap: true` + `ListView` anti-pattern
**Files (representative):**
- `lib/widgets/pages/detail_sections/songs.dart:15-37` — `Column` containing `ListView.builder` with `shrinkWrap: true`
- `lib/widgets/pages/library_sections/detail/songs_list_view.dart:79` — `Column` wrapping `ListTile` + `Divider` inside `SliverList`
- `lib/widgets/player/player_content/content.dart:237,388,593,602` — multiple nested `Column`s
- `lib/widgets/song_context_menu.dart:89,116,351`
- `lib/widgets/player/player_song_info_sheet/content.dart:31,38`
- `lib/widgets/player/player_up_next_card.dart:113`

Using `Column` with many children inside scrollable contexts forces O(n²) layout cost. For lists that can grow, prefer `ListView.builder` or `SliverList`.

**Fix:** Replace `Column(children: [...])` with `ListView.builder` or `SliverList` for lists with > 3-4 children or dynamic length.

---

### 8. `ListView.separated` with `Column` as header item
**File/Line:** `lib/pages/playlist_page.dart:255-280`

The first item in `ListView.separated` is a `Column` containing title, divider, and play-all button. This mixes layout concerns inside the list delegate.

**Fix:** Use a `SliverList` with `SliverToBoxAdapter` for the header, or wrap the `ListView` in a `Column` with a separate header widget.

---

### 9. `PlayerContent` static `_current` global mutable state
**File/Line:** `lib/widgets/player/player_content/content.dart:78`

```dart
static _PlayerContentState? _current;
```
This is used to forward external drag events from outside the widget tree (gesture inset area). It's a global mutable reference that can leak if the widget is disposed while gestures are active.

**Fix:** Use a `GlobalKey<_PlayerContentState>` or pass the callback through the widget tree instead of a static field.

---

### 10. `late final` fields initialized in `initState` without null-safety guarantee
**Files:**
- `lib/widgets/player/synced_lyrics_view/state.dart:13` — `late final Ticker _frameTicker`
- `lib/widgets/player/synced_lyrics_view/state.dart:30` — `late final Listenable _settingsListenable`
- `lib/widgets/player/synced_lyrics_view/karaoke_line.dart:36` — `late _KaraokeLinePainter _painter`
- `lib/widgets/player/player_song_info_sheet/state.dart:4` — `late final Future<SongInfo> _songInfoFuture`
- `lib/pages/settings_page/audio/replaygain_section.dart:15-16` — `late final AnimationController _ctrl`, `late final Animation<double> _fade`
- `lib/pages/settings_page/audio/crossfade_picker.dart:15-16` — same pattern
- `lib/pages/settings/settings_widgets/slider.dart:45-46` — same pattern
- `lib/pages/settings/equalizer_page/band_slider.dart:219` — `late final AnimationController _pressCtrl`
- `lib/widgets/pages/library_sections/detail.dart:22` — `late Future<List<LocalSong>> _songsFuture`
- `lib/widgets/pages/album_sections.dart:104` — `late Future<List<_AlbumGroup>> _future`
- `lib/widgets/song_context_menu/add_to_playlist_sheet.dart:21` — `late Future<List<Playlist>> _future`
- `lib/bottom_nav_bar/bottom_nav/state.dart:38` — `late final List<_TabNavObserver> _tabObservers`

While these are initialized in `initState()` (which runs before `build`), they are not compile-time constants. If `initState` throws or is interrupted, the `late` field will throw at access time with a less informative error.

**Fix:** Use field initializers where possible, or convert to nullable fields with proper null checks.

---

### 11. `AudioService` static singleton — no way to reset between tests
**File:** `lib/services/audio_service/service.dart`

The static `_initialized`, `_isLoading`, `_playlist`, `_currentIndex`, `_previousSong`, `_staticSubs`, and `playbackState` ValueNotifier persist across tests. There's no `reset()` or `dispose()` method.

**Fix:** Add a test-only `reset()` method or make the class instantiable for testability.

---

### 12. `PlaybackManager` monolithic static facade (850 lines)
**File:** `lib/services/audio/playback_manager.dart`

The file is 850 lines and mixes equalizer, volume, DSP pipeline, queue, ReplayGain, Loudness Normalization, Crossfeed, Compressor, Limiter, and Soft Clipper. The comment acknowledges this but it hurts maintainability.

**Fix:** Split into `playback_manager/equalizer.dart`, `playback_manager/volume.dart`, `playback_manager/dsp.dart`, `playback_manager/queue.dart` as suggested in the file's own TODO.

---

### 13. `AudioEffectsService` oversized (872 lines)
**File:** `lib/services/audio/audio_effects_service/service.dart`

872 lines managing all DSP settings. Similar splitting recommendation applies.

**Fix:** Split by feature domain (EQ, ReplayGain, Crossfeed, Compressor/Limiter, Bit-Perfect).

---

### 14. `AudioService` oversized (829 lines)
**File:** `lib/services/audio_service/service.dart`

829 lines. Same splitting recommendation.

**Fix:** Extract `AudioService._applyReplayGain`, `AudioService._syncCurrentTrackFromNative`, and queue mutations into separate files.

---

### 15. Hardcoded strings — no localization framework
**Files (representative):**
- `lib/pages/settings_page/audio/replaygain_section.dart:64` — `'Audio Normalize'`
- `lib/pages/playlist_page.dart:345` — `'$count lagu'`, `'Putar Semua'`
- `lib/pages/playlist_page.dart:386` — `'Belum ada lagu'`
- `lib/widgets/pages/home/recently_played_section.dart:79` — `'No recently played songs'`
- `lib/widgets/player/player_sheet/state.dart:235` — `'No song selected'`
- `lib/main/app_state.dart:33` — `fontFamily: 'SF Pro Text'`

The app mixes Indonesian and English strings inline. No `l10n`/`arb` files found.

**Fix:** Migrate to Flutter's `intl` package with `.arb` localization files.

---

### 16. Magic numbers
**Files (representative):**
- `lib/main/app_state.dart:33` — `fontFamily: 'SF Pro Text'` (hardcoded font)
- `lib/widgets/player/player_sheet/state.dart:93` — `h * 0.35` drag threshold
- `lib/widgets/player/player_content/content.dart:226` — `(width - 44).clamp(260.0, 390.0)`
- `lib/widgets/unified_morph_player.dart:59,63,67` — `Duration(milliseconds: 420/380)`
- `lib/services/artwork_repository.dart:90` — `3.0` DPR fallback
- `lib/services/palette_extractor.dart:131` — `_quantizeTargetSize = 112`
- `lib/widgets/player/player_progress_section.dart:50` — `_throttleMs = 100`

**Fix:** Extract to named constants in a `constants.dart` or class-level `static const`.

---

### 17. Import ordering inconsistency
**Files (representative):**
- `lib/main.dart` — `dart:async` then `package:flutter/...` then `package:musicplayer/...` then `utils/...` (relative import mixed at end)
- `lib/widgets/player/player_content.dart:4-6` — `package:flutter/cupertino.dart`, `package:flutter/gestures.dart`, `package:text_scroll/text_scroll.dart` interleaved
- `lib/pages/settings_page.dart:1-22` — mixed `dart:async`, `package:flutter/...`, `package:...`, `settings/...`

Effective Dart style recommends: `dart:` → `package:` → `relative` with blank lines between groups.

**Fix:** Run `dart format` or `flutter format` and verify import ordering.

---

### 18. `SingleChildScrollView` + `Column` where `ListView` is more appropriate
**File:** `lib/widgets/pages/home_sections.dart:35-51`

```dart
return SingleChildScrollView(
  physics: const ClampingScrollPhysics(),
  child: Column(...),
);
```
This forces all children to be built at once. If the home screen grows, this will jank.

**Fix:** Use `CustomScrollView` with `SliverList`/`SliverToBoxAdapter` for better lazy loading.

---

### 19. `_reconcileInBackground` in `MediaStoreService` could race with `_persist`
**File/Lines:** `lib/services/media_store_service.dart:126-137,194`

`_reconcileInBackground` calls `refreshSongs()` which calls `_persist()` at the end. Meanwhile, `getSongs()` also calls `_reconcileInBackground` via `unawaited`. Multiple concurrent callers can trigger overlapping reconciles, though `_inFlightRefresh` dedup prevents duplicate queries.

**Fix:** The `_inFlightRefresh` dedup already mitigates this. Document the dedup invariant more explicitly.

---

### 20. `_sendRoomPresetEq` in `AudioEffectsService` uses `.then()` instead of `async/await`
**File/Line:** `lib/services/audio/audio_effects_service/service.dart:602-606`

```dart
SharedPreferences.getInstance().then((prefs) {
  for (var b = 0; b < gains.length; b++) {
    prefs.setDouble('eqBand_$b', gains[b]);
  }
});
```
This fire-and-forget `.then()` is inconsistent with the rest of the file which uses `async/await`. If the widget is disposed before this completes, it writes stale data.

**Fix:** Convert to `async` and `await`:
```dart
final prefs = await SharedPreferences.getInstance();
for (var b = 0; b < gains.length; b++) {
  await prefs.setDouble('eqBand_$b', gains[b]);
}
```

---

## LOW Severity

### 1. `unified_morph_player.dart` is 760 lines
**File:** `lib/widgets/unified_morph_player.dart`

One of the largest widgets in the app. The `build()` method contains deeply nested `Stack`/`Positioned`/`AnimatedOpacity` trees.

**Fix:** Extract sub-trees into separate widgets: `_AlbumCoverTransition`, `_ControlsOverlay`, `_SongInfoOverlay`.

---

### 2. `playlist_page.dart` is 391 lines
**File:** `lib/pages/playlist_page.dart`

Combines UI, state management, dialog presentation, and playlist CRUD in one file.

**Fix:** Extract `_RenameDialog`, `_DeleteDialog`, and playlist operations into a controller.

---

### 3. `song_context_menu.dart` is 388 lines
**File:** `lib/widgets/song_context_menu.dart`

**Fix:** Extract menu item builders into separate files.

---

### 4. `log_page.dart` is 346 lines
**File:** `lib/pages/log_page.dart`

**Fix:** Extract filter bar, log entry tile, and log list into separate widgets.

---

### 5. `playback_manager.dart` comment acknowledges god-file status but doesn't act
**File/Lines:** `lib/services/audio/playback_manager.dart:18-33`

The file has a detailed split plan but it's marked as "intentionally kept monolithic." This is technical debt.

**Fix:** Execute the split plan; each section is independently cohesive.

---

### 6. `main.dart` uses `part`/`part-of` for 5 files
**File:** `lib/main.dart`

While `part`/`part-of` is valid Dart, it's uncommon in Flutter and makes IDE navigation harder. The `app.dart` and `app_state.dart` parts are tiny.

**Fix:** Consider merging `app.dart`, `app_state.dart`, `edge.dart`, `scroll_behavior.dart` into a single `app.dart` file (they total ~220 lines).

---

### 7. `settings_page.dart` uses 25+ `part` files
**File:** `lib/pages/settings_page.dart`

The settings page is split across many `part` files. This is approaching the complexity where a proper nested navigator or separate page classes would be cleaner.

**Fix:** Convert the largest parts (`debug.dart`, `about.dart`, `changelog_page.dart`, `bug_report_page.dart`) into separate route pages.

---

### 8. `PlayerContent` rebuilds on every position tick via `ValueListenableBuilder`
**File/Line:** `lib/widgets/player/player_content/content.dart:132-189`

`ValueListenableBuilder<AudioPlaybackState>` rebuilds the entire `PlayerContent` tree every ~100 ms (position tick). While the team already optimized `_PlayerSheetState` to ignore position ticks, the inner `PlayerContent` still receives them.

**Fix:** Split the `ValueListenableBuilder` so only the progress section rebuilds on position ticks, not the entire content tree.

---

### 9. `player_progress_section.dart` rebuilds on every position tick
**File/Line:** `lib/widgets/player/player_progress_section.dart:132-189`

Same issue — `ValueListenableBuilder<AudioPlaybackState>` rebuilds the slider every ~100 ms.

**Fix:** Use a separate `ValueListenableBuilder<Duration>` for position only, or throttle rebuilds with `ValueListenableBuilder` + `buildWhen` equivalent.

---

### 10. `MediaStoreService.getSongs` MethodChannel timeout is 20 seconds
**File/Line:** `lib/services/media_store_service.dart:181-183`

```dart
final List<dynamic>? songs = await _channel
    .invokeListMethod('getSongs')
    .timeout(const Duration(seconds: 20));
```
A 20s timeout on a MethodChannel is very generous. If the native side hangs, the UI waits up to 20s before showing an error.

**Fix:** Reduce to 5-8s and show a retry UI if it times out.

---

### 11. `PaletteExtractor` hardcodes `maximumColorCount: 24`
**File/Line:** `lib/services/palette_extractor.dart:171`

The comment says "sweet spot is 16" but the code uses 24. This is a minor inconsistency.

**Fix:** Align the code with the comment or update the comment.

---

### 12. `ArtworkRepository.resolveTargetPx` has magic fallback `3.0`
**File/Line:** `lib/services/artwork_repository.dart:90`

```dart
?.devicePixelRatio ?? 3.0; // 3.0 = Mi 9T DPR; fallback sebelum view terpasang
```
Hardcoded device-specific fallback.

**Fix:** Use `MediaQuery.devicePixelRatioOf(context)` with a fallback, or document why 3.0 is the chosen universal default.

---

### 13. `PlaylistService` has no cache invalidation on external changes
**File:** `lib/services/playlist_service.dart`

If playlists are modified outside the app (e.g., by a content provider), the in-memory cache stays stale until the app restarts.

**Fix:** Add a broadcast receiver or periodic cache refresh, or accept that this is a single-device cache.

---

### 14. `HistoryService.trackPlay` decodes JSON on every call
**File/Lines:** `lib/services/history_service.dart:68-85`

Every `trackPlay` call decodes `_playCountKey` and `_artistPlayCountKey` from JSON, modifies the maps, then re-encodes. This is O(n) per call and happens on every track change.

**Fix:** Keep the in-memory `Map` as the source of truth and serialize only on write, or batch writes.

---

### 15. `LocalSong.copyWith` has 14 optional parameters
**File:** `lib/models/local_song.dart:85-121`

A 14-parameter `copyWith` is unwieldy and error-prone (it's easy to pass two conflicting parameters).

**Fix:** Use `freezed` package or a builder pattern for complex data classes.

---

### 16. `_MyAppState` builds `ThemeData` as a static field
**File/Line:** `lib/main/app_state.dart:9-51`

The `_appTheme` is `static final` on the state class, which works but is unconventional. The TODO correctly notes it should be top-level when `ThemeData` gains a `const` constructor.

**Fix:** Move to `lib/themes/app_theme.dart` as a top-level `final` when possible.

---

### 17. `ScrollController` + `PrimaryScrollController` redundancy
**File/Line:** `lib/pages/home_page.dart:16,73`

`_scroll` is created and passed to `PrimaryScrollController`. The `ScrollingPageChrome` and `FadingTitleAppBar` likely read from the primary scroll controller, but having a named controller is redundant.

**Fix:** Use `PrimaryScrollController.of(context)` in descendant widgets instead of passing a controller.

---

### 18. `_BannerArtwork` in browse sections creates async work without cancellation
**File/Line:** `lib/widgets/pages/browse_sections/banners.dart:117-122`

```dart
Future<void> _load() async {
  try {
    final p = await ArtworkRepository.instance.getProvider(widget.songId);
    if (mounted) setState(() => _provider = p);
  } catch (_) {}
}
```
If the widget is removed from tree during the await, `mounted` check prevents the `setState`, but the `getProvider` future still runs to completion (wasting I/O).

**Fix:** Use a `CancelableOperation` or check `mounted` more frequently.

---

### 19. `bottom_nav/state.dart` hardcodes 5 tabs
**File/Line:** `lib/bottom_nav_bar/bottom_nav/state.dart:32-35,59-65`

`_tabNavKeys` and `_tabRoots` are hardcoded to length 5. Adding/removing a tab requires changes in multiple places.

**Fix:** Extract a `TabConfig` list and generate keys/roots from it.

---

### 20. `AudioEffectsService._pushEngineSettingsWhenReady` has no timeout
**File/Line:** `lib/services/audio/audio_effects_service/service.dart:237-238`

```dart
await PlaybackManager.waitForServiceReady();
```
If the native service never becomes ready, this hangs forever. Other startup paths (e.g., `syncFromNative`) use 5s timeouts, but this one doesn't.

**Fix:** Add a timeout:
```dart
await PlaybackManager.waitForServiceReady()
    .timeout(const Duration(seconds: 5), onTimeout: () {
  LogService.warn('AudioEffects', 'Service not ready after 5s');
});
```

---

## Summary by Category

| Category | HIGH | MEDIUM | LOW |
|----------|------|--------|-----|
| Null safety (`!`) | 15 | 3 | 0 |
| Error handling (bare catch) | 0 | 1 | 0 |
| Async / unawaited | 0 | 2 | 0 |
| Lifecycle / dispose leaks | 0 | 3 | 0 |
| Performance (Column/ListView, rebuilds) | 0 | 3 | 2 |
| File size / god objects | 0 | 4 | 3 |
| Magic numbers / hardcoded strings | 0 | 1 | 3 |
| Import ordering / style | 0 | 1 | 1 |
| Architecture / testability | 0 | 2 | 0 |
| Late without init guarantee | 0 | 1 | 0 |

---

## Top 5 Recommendations

1. **Replace all `!` force-unwraps on nullable values** with null-aware access or assertions with messages. The crash risk in `unified_morph_player.dart` and `player_song_info_sheet/content.dart` is the highest-priority fix.

2. **Add logging to bare `catch (_)` blocks** or justify each with a comment explaining why the exception is truly ignorable.

3. **Split `playback_manager.dart`, `audio_service.dart`, and `audio_effects_service.dart`** into domain-specific files. Each is >800 lines.

4. **Replace `Column` + `shrinkWrap: true` inside scrollables** with `ListView.builder` or `SliverList` for any list that can exceed 3-4 items.

5. **Migrate hardcoded strings to `intl`/`.arb`** for localization. The app already mixes Indonesian and English UI text.

---

*End of report.*
