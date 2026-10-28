# UI/UX Audit — `musicplayer`

**Audit date:** 2026-10-28  
**Repository:** Flutter local music player (`musicplayer`, Android app id `dev.wndavenz.music`)  
**Scope:** Entire Flutter UI/UX surface, player stack, navigation, shared widgets, and UI-adjacent state/lifecycle paths.  
**Change policy:** Audit only. No application source, assets, dependencies, or behavior were changed. The only repository change is this report.

---

## 1. Executive Summary

This audit reviewed the application's UI architecture, all primary navigation destinations, the mini/full player, detail pages, playlists, settings, logs, and the shared widgets that compose them. It combined code-level tracing with static analysis and repository-wide reference checks. No emulator, physical device, or release APK was used, so runtime rendering, measured frame time, battery cost, TalkBack behavior, and gesture-arena outcomes remain unverified.

**Overall assessment:** The app has a coherent, deliberately designed visual language and several strong performance foundations: Media3 owns playback state, artwork has an LRU/prefetch pipeline, blurred artwork is cached rather than recomputed, and the morph player deliberately avoids rebuilding its outer shell on position ticks. However, several high-visibility affordances are non-functional, a destructive action has no in-app confirmation, two core overlays perform work while invisible, and the player's portrait layout does not respect the bottom system inset.

### Most significant findings

| ID | Severity | Finding |
|---|---|---|
| BUG-01 | **High** | “Delete from device” deletes immediately after the menu closes; there is no in-app confirmation dialog. |
| UX-02 | **High** | Every tile in the Search category grid is inert, and its labels are hardcoded English. |
| UX-01 | **High** | The “Radio” tab contains Favorites and playlists, not radio; the radio data source is empty and unused. |
| PERF-01 | **High** | The lyrics karaoke ticker and the queue overlay remain live while the full player is open, even when both overlays are hidden. |
| UX-06 | Medium | The portrait full player disables the bottom safe area and places controls under the 3-button navigation bar. |
| PERF-02 | Medium | The entire full-player content subtree rebuilds on every playback position tick (~5–10 times per second). |
| A11Y-01 | Medium | Core player controls are 28–35 dp and several have no accessible name; the favorite label is English-only. |

### Severity distribution

| Severity | Count |
|---|---:|
| Critical | 0 |
| High | 4 |
| Medium | 9 |
| Low | 11 |
| **Total** | **24** |

No Critical finding was identified. “High” means either a data-loss risk or a large, visible portion of a primary destination/player that does not do what it presents. Medium and Low findings are listed in Sections 3–8 with explicit evidence and verification steps.

### What is working well

- Playback ownership is correctly centralized: Kotlin Media3 owns queue, shuffle, repeat, and effects; Dart mirrors state over streams rather than reimplementing queue logic.
- `ArtworkRepository` uses bounded caching, target-size resolution, prefetching, and invalidation on deletion. Cover blur is cached as an image, avoiding a full-screen `ImageFilter` on every player frame (`lib/widgets/player/player_background/cover_blur.dart`, `lib/services/artwork_blur_cache.dart`).
- The outer morph player absorbs position ticks deliberately (`lib/widgets/unified_morph_player.dart:390-394`), even though the inner content does not yet do the same.
- Responsive geometry has a single source of truth for the two-column player (`lib/widgets/player/now_playing_layout.dart`), including safe-area-aware panel height.
- `dart analyze lib test` reported no issues at audit time.

---

## 2. UI/UX Architecture and Coverage

### 2.1 Layered UI map

| Layer | Main locations | Responsibility |
|---|---|---|
| App shell | `lib/main.dart`, `lib/main/app_state.dart`, `lib/main/edge.dart` | `MaterialApp`, locale/theme controllers, watermark overlay, edge-to-edge setup. |
| Navigation | `lib/bottom_nav_bar/bottom_nav.dart`, `bottom_nav/state.dart`, `lib/themes/glass_navbar.dart` | Five destinations, standard and floating-pill navigation, mini-player placement, nav clearances. |
| Pages | `lib/pages/*`, `lib/widgets/pages/*` | Home, Browse, Radio, Search, Library, Music List, Album, Artist, Playlist, Settings, Logs. |
| Player shell | `lib/widgets/unified_morph_player.dart` | Mini player → full player morph, dock transitions, background, artwork geometry. |
| Full-player content | `lib/widgets/player/player_content/*` | Song header, progress, transport, lyrics/queue overlays, lyrics settings. |
| Player services | `lib/services/player_sheet_controller.dart`, `audio_playback_state.dart` | Sheet progress and playback state notifiers consumed by the UI. |
| Theming | `lib/themes/app_themes.dart`, `app_theme_extension.dart`, `theme_controller.dart` | Color/text theme, glass tokens, light/dark and background-style selection. |
| Shared UI | `lib/widgets/common/*`, `lib/widgets/pages/*_sections` | App bars, page chrome, responsive body, artwork, song rows, menus, dialogs. |

The app uses `ValueNotifier` + `Stream` + `setState`; there is no Provider/Bloc/Riverpod layer. The audit therefore focused on notifier fan-out, widget rebuild scope, and imperative route/state transitions rather than framework-level state composition.

### 2.2 Coverage

| Area | Entry points reviewed | Result |
|---|---|---|
| App shell / startup | `main.dart`, `main/main.dart`, `main/app_state.dart`, `main/edge.dart`, `main/scroll_behavior.dart` | No material UI defect confirmed. Status-bar icon brightness is a suspected issue (A11Y-03). |
| Navigation | `bottom_nav_bar/*`, `themes/glass_navbar.dart`, `scrolling_page_chrome/app_bar.dart` | Navigation mechanics work; destination-level content issues captured in UX-01, UX-02, UX-03. |
| Home | `pages/home_page.dart`, `widgets/pages/home_sections.dart`, `home/*` | No material standalone defect. First-frame cache warm-up avoids spinners when caches are ready. |
| Browse | `pages/browse_page.dart`, `widgets/pages/browse_sections/*` | UX-04, UX-05, UX-08. |
| Radio | `pages/radio.dart`, `widgets/pages/radio_sections/*` | UX-01. |
| Search | `pages/search_page.dart`, `widgets/pages/search_sections/*` | UX-02. |
| Library | `pages/library_page.dart`, `widgets/pages/library_sections/*` | A11Y-01 (edit control); otherwise no material issue. |
| Music list | `pages/music_list.dart`, `pages/music_list/*` | No material UI defect confirmed. |
| Album / Artist detail | `pages/album_page.dart`, `pages/artist_page.dart`, `detail_sections/*`, `*_sections.dart` | DEAD-05 (unmatched artist Hero); layout itself is coherent. |
| Playlist | `pages/playlist_page.dart` | DEAD-01 (orphaned components); delete confirmation for playlists is implemented. |
| Player | `unified_morph_player.dart`, `player_content/*`, `player_*`, `synced_lyrics_view/*`, `player_background/*` | UX-06, UX-07, PERF-01/02/03, A11Y-01/02/03. |
| Song info / context menu | `player_song_info_sheet*`, `song_context_menu*`, `swipe_to_dismiss_sheet.dart` | BUG-02, UX-07; swipe/scroll interaction is a suspected issue recorded in Section 10. |
| Settings | `settings_page.dart`, `settings_page/*`, `settings/*` | No material functional defect confirmed; MAINT-01 token drift applies. |
| Logs / debug | `pages/log_page.dart`, `log_page/*` | No material defect confirmed. |
| Theming / artwork | `themes/*`, `song_artwork.dart`, `artwork_repository.dart`, `artwork_blur_cache.dart` | Positive caching architecture; MAINT-01. GPU cost of shader/blur is an unverified hypothesis (Section 7). |
| Responsive behavior | `utils/responsive.dart`, `common/responsive_page_body.dart`, `now_playing_layout.dart` | Good use of width constraints; bottom-inset and context-menu overflow are exceptions. |
| Tests | `test/widgets/*`, `test/ui_reference_golden_test.dart` | Existing responsive/layout coverage; no semantics or no-op-affordance tests. |

### 2.3 Audit status by area

| Status | Areas |
|---|---|
| Material issues found | Radio, Search, Browse, full player layout, player overlays, song info/context menu, accessibility. |
| No material issue found | Home loading/caching, Music List, Album/Artist layout, Logs, Settings functional flows, playlist delete/rename confirmation, artwork cache/prefetch, theme switching. |
| Not verified at runtime | All visual styling, gesture conflicts, measured performance, TalkBack, 3-button navigation, landscape/text-scale rendering. |

### 2.4 Method and evidence quality

- Enumerated 296 Dart files under `lib` (49,806 lines), 185 widget/page files, and 27 test files; deep-traced the navigation, player, primary pages, and shared widget call paths.
- Used `rg` for every claim of “unused” or “no matching tag,” and `nl` for exact source lines.
- Ran `dart analyze lib test`; result: **no issues**.
- Attempted a responsive widget-test run; the command hit its 120-second timeout (exit 124). This is **not** a passing test result and is recorded as a limitation.
- Did not build an APK, per the repository's permanent directive. No screenshots or GPU traces were produced.

**Finding status legend**

- **Confirmed** — execution path or reference absence verified in source.
- **Confirmed (static layout)** — layout math and widget composition verified, but the failure was not rendered on a device.
- **Suspected** — code evidence indicates a likely runtime problem; a device/gesture/rendering check is still required.
- **Unverified hypothesis** — plausible optimization with no measured profile attached.

---

## 3. Confirmed Bugs and Functional Issues

| ID | Severity | Category | Issue | Status |
|---|---|---|---|---|
| BUG-01 | High | Bug | Device deletion has no confirmation. | Confirmed |
| UX-01 | High | UX | Radio tab is not radio. | Confirmed |
| UX-02 | High | UX | Search category grid is non-interactive. | Confirmed |
| UX-03 | Medium | UX | Cast button is a global no-op. | Confirmed |
| UX-04 | Medium | UX | Browse section chevrons do nothing. | Confirmed |
| UX-05 | Medium | UX | Curated Browse labels show random, unstable content. | Confirmed |
| UX-06 | Medium | UX | Portrait player ignores bottom system inset. | Confirmed |
| UX-07 | Medium | UX | Song context menu cannot scroll; overflow risk. | Confirmed (static layout) |
| BUG-02 | Low | Bug | Song Info has no error branch; spinner can persist forever. | Confirmed (latent) |
| UX-08 | Low | UX | Browse has no empty/loading state. | Confirmed |

### BUG-01 — “Delete from device” commits without confirmation

- **Severity / Category:** High / Bug (destructive UX)
- **Status:** Confirmed
- **Location:** `lib/widgets/song_context_menu.dart:245-253`, `lib/widgets/song_context_menu.dart:267-301`; invocation from every song row/context menu via `showSongContextMenu` (`lib/widgets/song_context_menu.dart:30-51`).
- **Evidence:** The menu item calls `_confirmDelete(context)`. Despite the name, `_confirmDelete` does not show a dialog: it immediately calls `navigator.pop()`, then awaits `MediaStoreService.deleteSong(widget.song.id)`. The only user feedback is a success or failure SnackBar after the file operation. There is no cancel path and no “Are you sure?” step in the app UI.
- **Impact:** A single tap on a destructive action can irreversibly remove a local audio file from the device. Users who tap the row expecting a confirmation (the common Android pattern for destructive actions) have no opportunity to back out. Depending on Android version, MediaStore permissions, and whether the file is app-owned, the platform may or may not add a system prompt; the app cannot rely on one.
- **Recommendation:** Insert an `AlertDialog` (or a bottom-sheet confirmation with the song title and file path) before calling `deleteSong`. Use a clearly destructive action label, default focus on Cancel, and dismiss without deleting. Consider an “Undo” SnackBar only if the file can be retained safely; do not promise undo for a MediaStore delete that cannot be reversed.
- **Verification:** Long-press a disposable test file → tap “Delete from device” → confirm that the menu closes into a confirmation state and the file still exists after Cancel. On the fixed build, confirm that cancel preserves the file and only the explicit destructive action deletes it. Add a widget test asserting that the delete service is not called until confirmation.

### UX-01 — The “Radio” tab exposes Favorites and playlists, not radio

- **Severity / Category:** High / UX (information architecture)
- **Status:** Confirmed
- **Location:** `lib/pages/radio.dart:58-80`, `lib/widgets/pages/radio_sections/content.dart:13-20`, `lib/widgets/pages/radio_sections/stations.dart:7-10`, `lib/utils/data/radio_stations.dart:4`.
- **Evidence:** The destination is labeled “Radio” (`context.l10n.navRadio`) with a radio-waves icon in the navigation (`bottom_nav/state.dart:230-243`). Its body is `RadioPageContent`, which composes `_SmartPlaylistCardWidget(index: 0)` and `_UserPlaylistsSection`. `_SmartType` has exactly one value, `favorites` (`stations.dart:8-10`), so the card is the Favorites playlist. The `radioStations` constant is an empty list and has no code references outside its declaration and a changelog entry.
- **Impact:** One of five primary navigation destinations does not deliver its label. Users looking for radio cannot find stations, and the tab substantially duplicates the Library/playlist surface. This is more than an empty state: the data model and UI for radio are absent.
- **Recommendation:** Make a product decision and make the UI honest. Either (a) rename the destination to “Favorites”/“Playlists” and change its icon, or (b) implement a real radio/streaming source and populate `radioStations`. Do not ship an empty radio data file merely to satisfy the label. If radio is deferred, remove the empty source and document the feature as unavailable.
- **Verification:** Open the tab and enumerate every visible section; there should be no “Radio” label unless a station/stream control is present. Compare with the navigation label and icon. After renaming/implementing, verify TalkBack reads a destination name that matches its content.

### UX-02 — Every Search category tile is inert and English-only

- **Severity / Category:** High / UX (dead affordance + localization)
- **Status:** Confirmed
- **Location:** `lib/widgets/pages/search_sections/cat_tile.dart:3-46`, `lib/widgets/pages/search_sections/cat_grid.dart:12-14`, `lib/utils/data/search_categories.dart:3-20`, `lib/widgets/pages/search_sections/state.dart:99-127`.
- **Evidence:** `_SearchCategoryTile` renders an image, a gradient, and a title, but has no `GestureDetector`, `InkWell`, `onTap`, route, or callback. `SearchCategoryGrid` passes 16 entries whose titles are literal English strings (“Apple Music Radio”, “Concerts”, “Hits”, “K-Pop”, …). The only interactive search input is the text field; the category grid is shown whenever the query is empty and cannot filter or navigate.
- **Impact:** Sixteen large, image-led tiles advertise genres and categories but do nothing when tapped. This is the dominant empty-query state of a primary destination, so it reads as a broken screen rather than a placeholder. In Indonesian locale, the tiles remain English while the rest of the page is localized, breaking language consistency.
- **Recommendation:** Either wire each tile to a real filtered result (genre/artist/title matching, or a curated destination) with an `InkWell`/`Semantics(button: true, label: ...)`, or remove the grid until the destinations exist. Move titles to the ARB files (`app_en.arb`, `app_id.arb`) and resolve them through `context.l10n`; avoid hardcoded demo labels.
- **Verification:** Tap each tile and assert a visible result/navigation occurs; run in both `en` and `id` and confirm no English literals remain. Add a widget test that the tile exposes a button semantic and invokes its callback.

### UX-03 — The Cast icon is a global no-op on eight surfaces

- **Severity / Category:** Medium / UX
- **Status:** Confirmed
- **Location:** `lib/widgets/common_actions.dart:54-72` (`_cast` is an empty TODO), `lib/widgets/common_actions.dart:59-105` (icon rendered), `lib/widgets/common/scrolling_page_chrome/app_bar.dart:10` (default action), plus usage in `lib/pages/album_page.dart:40`, `artist_page.dart:39`, `library_page.dart:53`, `artist_list.dart:58`, `music_list/state.dart:61`, `playlist_page.dart:290`, and `library_sections/detail.dart:272`.
- **Evidence:** `_cast(BuildContext context) { // TODO: Cast function }` is bound to an always-visible `IconButton` with a Cast icon. No `onPressed` guard, disabled state, tooltip, SnackBar, or route exists. Every page that uses the default `CommonActions` shows the icon.
- **Impact:** A familiar Android media affordance is shown on nearly every library/detail page and silently does nothing. Users may repeatedly tap it or assume cast/device output is broken. The icon also adds visual noise to app bars where no cast target exists.
- **Recommendation:** Remove the Cast action until a cast implementation is available, or render it disabled with an explanatory tooltip/SnackBar (“Casting isn’t available yet”). If cast is implemented, route through a single service and show connection state; do not leave a permanent TODO-bound button.
- **Verification:** Tap Cast on each listed surface; before the fix there must be no route/state change. After the fix, either the icon is absent/disabled with an accessible explanation, or a cast picker opens and reports device state.

### UX-04 — Browse section headers show a chevron but are not tappable

- **Severity / Category:** Medium / UX
- **Status:** Confirmed
- **Location:** `lib/widgets/pages/browse_sections/section.dart:17-33`, `lib/widgets/pages/browse_sections/new_music_grid.dart:53-69`.
- **Evidence:** `_BrowseSection` renders a section title row with `Icons.chevron_right_rounded`, but the row is a plain `Row` with no `InkWell`, `GestureDetector`, or route. `_NewMusicSection` repeats the same pattern. The chevron is the conventional “see all” affordance, especially beside “We Recommend” and “Daily Top 100”.
- **Impact:** Users tap the headers expecting a full list and get no response. The affordance makes the page feel unfinished and makes the carousels’ truncation (top 30/new music, partial daily remainder) undiscoverable.
- **Recommendation:** Wrap the header row in an `InkWell` with a 48 dp minimum target and navigate to a full, filtered list; or remove the chevron and present the section as a non-navigating carousel. Avoid using the chevron purely as decoration.
- **Verification:** Tap each section header; assert that a route opens (or that no navigation chevron is present). Check the tap target bounds and TalkBack button semantics.

### UX-05 — “Daily Top 100” and “We Recommend” are random, unstable content

- **Severity / Category:** Medium / UX (content trust)
- **Status:** Confirmed
- **Location:** `lib/widgets/pages/browse_sections/state.dart:26-59`, rendered at `browse_sections/state.dart:72-75`.
- **Evidence:** Only the three banner songs use a date-seeded RNG (`dailyRng`). The rest of the page uses `List<LocalSong>.from(songs)..shuffle()` with no seed on every page load. `_recommend` is `shuffled.take(third)`, `_daily` is `shuffled.skip(third * 2)`; there is no play-count sort, no period window, and no 100-item cap. The “Daily Top 100” label therefore describes an arbitrary random remainder that changes every time the page is built.
- **Impact:** The page presents editorial/algorithmic labels that the data does not support. Users cannot form expectations, cannot return to the same “Daily Top 100”, and may interpret random tracks as personalized recommendations. The instability also causes unnecessary visual churn on each visit.
- **Recommendation:** Choose one contract and enforce it. For a real “Daily Top 100”, compute a stable daily ranking (play counts/history, recency) and cap it at 100; persist the seed/ranking for the day. If no ranking exists, relabel to “Shuffle”/“More to explore” and make clear it is random. Cache the computed lists so tab re-entry does not reshuffle.
- **Verification:** Open Browse repeatedly on the same day; the “Daily Top 100” and “We Recommend” order should be stable. Cross-check the ranking against play counts/history. After relabeling, verify the copy no longer promises curation that is not implemented.

### UX-06 — Portrait full player places controls under the bottom navigation bar

- **Severity / Category:** Medium / UX (safe area / edge-to-edge)
- **Status:** Confirmed (code path; visual overlap not captured)
- **Location:** `lib/widgets/unified_morph_player.dart:734-744` (`SafeArea(bottom: false)`), `lib/widgets/player/player_content/content.dart:469-520` (portrait column ending with `SizedBox(height: 25)` and a divider with `bottom: 15`), `lib/main/edge.dart:3-11` (edge-to-edge with transparent navigation bar).
- **Evidence:** The full-player content is mounted inside `SafeArea(bottom: false)`. The portrait layout's bottom controls are placed at a fixed 25 dp + 15 dp above the physical bottom; there is no `MediaQuery.viewPadding.bottom`/`viewPadding` compensation. On a 3-button navigation bar (~48 dp), the secondary controls and divider fall inside the system navigation area. The two-column layout, by contrast, subtracts `safeBottom` in `now_playing_layout.dart:75-79`, showing the intended pattern.
- **Impact:** The queue/lyrics toggles and the bottom divider can be partially hidden or untappable behind the navigation bar when the user selects 3-button navigation. This is a direct accessibility/navigation-mode regression, not merely cosmetic.
- **Recommendation:** Remove `bottom: false` from the full-player `SafeArea`, or add `MediaQuery.viewPaddingOf(context).bottom` to the portrait bottom padding. If the morph transform makes a full `SafeArea` awkward, apply `padding.bottom` to the controls container and keep the background edge-to-edge.
- **Verification:** On a 3-button-navigation emulator, open a song → full player; screenshot and tap the queue/lyrics toggles. Repeat with gesture navigation to ensure no double inset. Add a widget test with `viewPadding.bottom = 48` asserting the controls' bottom is at least 48 dp above the screen edge.

### UX-07 — Song context menu has no scroll container and can overflow

- **Severity / Category:** Medium / UX (responsive layout)
- **Status:** Confirmed (static layout; runtime render not captured)
- **Location:** `lib/widgets/song_context_menu.dart:38-47` (`isScrollControlled: true`), `lib/widgets/song_context_menu.dart:96-104` (SafeArea → Column), `lib/widgets/song_context_menu.dart:159-255` (nine action rows), `lib/widgets/song_context_menu/menu_item.dart:27-48` (13 dp vertical padding per row).
- **Evidence:** The sheet is a non-scrollable `Column` with a drag handle, a 48 dp artwork header, separators, and nine action rows (Play, Play Next, Add to Queue, Favorite, Add to Playlist, Open Album, Open Artist, Song Info, Delete). Each row is roughly 48 dp at default text scale; the handle and header add ~88 dp. That places the content around 530–600 dp before text scaling. On a 393 dp-high landscape window, or with large accessibility text, the `Column` exceeds the available height and the lower actions (including Delete) are clipped with no way to scroll.
- **Impact:** In landscape or at large text sizes, users cannot reach all actions, and Flutter will report a RenderFlex overflow. The destructive action is at the bottom, so the failure is especially likely to hide or misplace it.
- **Recommendation:** Wrap the menu body in a `SingleChildScrollView` (or use a `DraggableScrollableSheet`) with a bounded max height, and set `useSafeArea: true` on the modal. If swipe-to-dismiss must remain, attach it to the drag handle/header only rather than the entire scrollable body to avoid gesture competition. Ensure the bottom `SizedBox` and SafeArea are inside the scroll extent.
- **Verification:** Render at 852×393 and at 393×852 with `textScaleFactor` 2.0; open the menu and scroll to Delete. Assert no RenderFlex overflow in the test console and that every row is reachable. Repeat on a physical device in landscape.

### BUG-02 — Song Info shows an infinite spinner when metadata loading fails

- **Severity / Category:** Low / Bug (missing error state)
- **Status:** Confirmed (latent; trigger is uncommon)
- **Location:** `lib/widgets/player/player_song_info_sheet/state.dart:82-95`, `lib/widgets/player/player_song_info_sheet/loading.dart:4-14`, `lib/services/song_metadata_service/service.dart:72-87`.
- **Evidence:** The `FutureBuilder<SongInfo>` ignores `snapshot.hasError` and only checks `snapshot.data`: any null data, including a failed future, renders `_LoadingSongInfo` forever. `SongMetadataService` catches most channel/file errors internally, so the common path is resilient; however, the `Future.wait` in `_fetchSongInfo` and any unexpected future error still have no UI error branch. The loading widget is a fixed 360 dp spinner with no message or retry.
- **Impact:** If metadata loading does fail, the sheet is permanently stuck on a spinner and offers no explanation or retry. The user cannot distinguish “still loading” from “broken”, and must dismiss and reopen the sheet.
- **Recommendation:** Branch on `snapshot.hasError` and render a concise error state with a Retry action that recreates the future. Consider showing whatever fields are already available from `LocalSong` (title/artist/album/duration) instead of blocking the entire sheet on extended metadata.
- **Verification:** Inject a failing `Future<SongInfo>` in a widget test and assert an error message + Retry are visible; simulate an unreadable file path on device and confirm the sheet does not spin indefinitely. After retry, assert the future is recreated.

### UX-08 — Browse has no empty or loading state on a library with no songs

- **Severity / Category:** Low / UX
- **Status:** Confirmed
- **Location:** `lib/widgets/pages/browse_sections/state.dart:26-30`, `lib/widgets/pages/browse_sections/state.dart:62-77`, `lib/widgets/pages/browse_sections/banners.dart:17-22`.
- **Evidence:** `_load()` returns immediately when `songs.isEmpty`; the build path always renders `LargePageTitle`, `HeaderDivider`, and `BrowseBannerCarousel(songs: _bannerSongs)`. The banner widget deliberately reserves its full section height even for an empty list (`SizedBox(height: sectionHeight, child: Center(child: SizedBox.shrink()))`). All other sections hide themselves when empty. There is no empty state or permission/scan CTA and no loading indicator while the asynchronous load is in flight.
- **Impact:** On a fresh install, denied media permission, or a device with no local audio, Browse is a large blank region under a title. Users receive no explanation and no path to fix the library. On slower scans, content pops in after an empty-looking first frame.
- **Recommendation:** Add an explicit empty/error state shared with Home/Library: explain that no local songs were found, offer a Rescan action, and link to permission settings when permission is denied. Avoid reserving banner height when there are no banners; show a lightweight skeleton or nothing until data is ready.
- **Verification:** Install with no media / deny audio permission and open Browse; assert an explanatory empty state and a working Rescan/permission action. Use a delayed fake `getSongs()` to confirm a loading state rather than a blank banner area.

---

## 4. Performance and Rendering Bottlenecks

No frame timings, GPU traces, or battery measurements were captured. The findings below are structural costs confirmed by code paths; their visible impact must be measured on the target device.

| ID | Severity | Finding | Measured? |
|---|---|---|---|
| PERF-01 | High | Hidden lyrics ticker + hidden queue overlay stay live while the player is open. | No; 60 fps ticker and rebuild path confirmed in source |
| PERF-02 | Medium | Full `PlayerContent` rebuilds on every playback tick. | No; subscription scope confirmed |
| PERF-03 | Medium | Morph progress rebuilds the stable full-player content during every sheet animation/drag. | No; widget construction path confirmed |

### PERF-01 — Hidden lyrics and queue overlays still run while the player is open

- **Severity / Category:** High / Performance
- **Status:** Confirmed (structural; runtime impact unmeasured)
- **Location:** `lib/widgets/player/player_content/content.dart:229-271` and `:806-844` (both overlays are constructed unconditionally inside `TweenAnimationBuilder` children), `lib/widgets/player/player_content/content.dart:869-902` (`_buildLyricsContent` → `_LyricsOverlayBody`), `lib/widgets/player/player_content/lyrics_overlay.dart:105-118`, `lib/widgets/player/synced_lyrics_view/state.dart:105-143`, `lib/widgets/player/synced_lyrics_view/state_playback.dart:11-20`, `lib/widgets/player/player_content/queue_overlay.dart:48-65`.
- **Evidence:** The lyrics and queue areas are wrapped in `Opacity` + `IgnorePointer` with an animated value of 0 when hidden, but their children are still built and laid out. When lyrics resolve, `SyncedLyricsView` creates and starts `_frameTicker` whenever playback is active (`state.dart:140`, `state_playback.dart:17`), subscribes to `AudioService.positionStream`, and rebuilds karaoke content at display refresh rate. The flag passed to it (`isVisible`) is only used to trigger a scroll-to-current when it becomes visible (`state.dart:197-202`); it does not stop the ticker. Separately, `_QueueOverlayBody` always builds and subscribes to the entire `AudioService.playbackState`, so the hidden queue list rebuilds on every playback notification.
- **Impact:** Opening the player and never touching lyrics or queue still runs lyric interpolation, karaoke painting, and queue list rebuilds. On a mid-range device this is avoidable CPU/GPU work, battery drain, and a competing source of frame work while the player is visible. It can also make the open-player animation less smooth and keep the device warm during paused playback (the ticker stops when paused, but the queue listener remains).
- **Recommendation:** Lazily mount each overlay the first time it is opened, and after the closing animation ends either unmount it or pass an `active` flag that stops the lyric ticker and pauses the position subscription. Keep the 400 ms fade by mounting before the fade-in and delaying unmount until after the fade-out. Make the queue body subscribe only while visible (or move its subscription behind an `isActive` gate). Avoid using `Opacity(0)` as a “hidden” state for expensive subtrees.
- **Verification:** In profile mode, open the full player with lyrics available but never open the lyrics/queue modes. Record CPU/GPU frame time and ticker activity before and after the change. Add a debug build counter (or DevTools rebuild stats) showing `_QueueOverlayBody` and `SyncedLyricsView` are not rebuilding while hidden. On device, compare battery/thermal behavior during a 10-minute paused vs playing session.

### PERF-02 — The full player subtree rebuilds on every playback position tick

- **Severity / Category:** Medium / Performance
- **Status:** Confirmed (structural; jank unmeasured)
- **Location:** `lib/widgets/unified_morph_player/playback_content.dart:3-7` and `:29-41`, `lib/widgets/player/player_content/content.dart:5-25` and `:148-154`, `lib/widgets/player/player_progress_section.dart:204-208`.
- **Evidence:** `_PlaybackContent` is a `ValueListenableBuilder<AudioPlaybackState>` over `AudioService.playbackState`; it constructs a new `PlayerContent` for every notification, passing the full state. The comment claims this “isolat[es] position-tick rebuilds to this subtree,” but the subtree is the entire 904-line player. `PlayerContent` itself does not need the full state except to pass `playbackState` to `PlayerTransportControls` (only `isPlaying`/`currentPlaylist` are used there), and `PlayerProgressSection` already has its own `ValueListenableBuilder` on the same notifier. Native position events are documented at ~200 ms (`synced_lyrics_view/state_playback.dart:47`), with comments elsewhere citing ~100 ms, so this is roughly 5–10 full-player rebuilds per second.
- **Impact:** Repeatedly rebuilding headers, artwork slots, hidden overlays, transport rows, and gesture wrappers consumes main-isolate time and increases the chance of missed frames during scrolling, animation, or low-end-device playback. The outer morph shell is protected, but the expensive inner subtree is not.
- **Recommendation:** Remove `AudioPlaybackState` from `PlayerContent`'s constructor. Pass only the derived values it needs (for example `isPlaying` and `hasPlaylist`) through a narrow notifier, or let `PlayerTransportControls` subscribe directly. Keep position-only consumers (`PlayerProgressSection`, lyrics) on their own subscriptions. If a single state object is retained, use a selector that only notifies on identity/`isPlaying` changes rather than every position update.
- **Verification:** Add a temporary build counter around `PlayerContent` during a profile run; it should not increment on each position event after the change. Use DevTools “Track widget builds” or a timeline trace while the player is open and idle. Confirm transport play/pause still updates immediately and progress still advances.

### PERF-03 — Sheet-progress rebuilds reconstruct the stable player content

- **Severity / Category:** Medium / Performance
- **Status:** Confirmed (structural; frame impact unmeasured)
- **Location:** `lib/widgets/unified_morph_player.dart:389-441` (progress → `_buildMorph`), `lib/widgets/unified_morph_player.dart:734-755` (`_PlaybackContent` constructed inside the morph), `lib/widgets/player/player_content/content.dart:148-154` (reads sheet progress for opacity), `unified_morph_player.dart:477-514` (progress-derived geometry/alpha).
- **Evidence:** The morph geometry genuinely depends on `PlayerSheetController.progress`, so the morph shell must rebuild. However, `_PlaybackContent` is also reconstructed on every progress tick, even though its own parameters (`song`, callbacks, flags) are stable; its children then recompute opacities from the current progress. During a drag/release at 60 fps this means repeated construction and reconciliation of the full player subtree in addition to the geometry work.
- **Impact:** Adds avoidable build/layout work to the most animation-sensitive interaction in the app; on a mid-range device it can contribute to sheet-opening jank and dropped frames, especially while artwork/blur is also changing.
- **Recommendation:** Hoist the stable content subtree out of the progress builder and animate only the progress-dependent wrappers. For example, keep a stable `_PlaybackContent` child and wrap the specific `Opacity`/transform values that need progress in a small `ValueListenableBuilder` or `AnimatedBuilder`. The two-column and portrait layouts will need slightly different wrappers, but the expensive child tree should not be recreated per tick.
- **Verification:** Profile a slow drag and a tap-to-open at 60/120 Hz; count `PlayerContent` builds per frame. After the change, only the opacity/transform wrappers should rebuild on progress, while `PlayerContent` builds only when song/flags change. Confirm the visual morph is unchanged with side-by-side screen recordings.

### Performance note on GPU effects (unverified)

The full-player background uses a full-screen fragment shader (`assets/shaders/fluid.frag`) driven by a 30-minute repeating `AnimationController` (`lib/widgets/player/player_background/artwork.dart:59-63`), plus layered blur/glass surfaces. This may be expensive on the target Snapdragon 730, but no GPU trace was captured. It is treated as an optimization hypothesis in Section 7, not as a confirmed bottleneck.

---

## 5. Dead and Redundant Code

All items below were checked with repository-wide reference search. “Zero references” means no imported, constructed, or named usage outside the declaration (and, where noted, the barrel export itself).

| ID | Severity | Category | Item | Evidence |
|---|---|---|---|---|
| DEAD-01 | Low | Dead Code | Four orphaned playlist widgets + `LibraryRow` wrapper | Zero references; inline equivalents in `playlist_page.dart` |
| DEAD-02 | Low | Dead Code | `lib/themes/theme_builder.dart` | `AppThemeConfig` never referenced |
| DEAD-03 | Low | Dead Code | `DetailTopBar` | Defined but never constructed |
| DEAD-04 | Low | Dead Code | Empty `radioStations` / `browseBanners` data | Exported but unused |
| DEAD-05 | Low | Dead Code | Unmatched artist-detail `Hero` | No sibling tag exists |

### DEAD-01 — Orphaned playlist components duplicate inline implementations

- **Severity / Category:** Low / Dead Code (maintainability)
- **Status:** Confirmed
- **Location:** `lib/widgets/pages/playlist_dialogs.dart`, `lib/widgets/pages/playlist_empty_state.dart`, `lib/widgets/pages/playlist_play_all_button.dart`, `lib/widgets/pages/playlist_song_tile.dart`, `lib/widgets/pages/library_sections/row.dart:3-19`.
- **Evidence:** `showRenamePlaylistDialog`, `showDeletePlaylistDialog`, `PlaylistEmptyState`, `PlaylistPlayAllButton`, and `PlaylistSongTile` have zero references outside their files. `PlaylistPage` implements its own rename dialog (`_rename`, lines ~166-196), delete dialog (`_delete`, lines 198-237), inline empty state (`_EmptyState`, line 409), inline play-all button (`_PlayAllButton`, line 318), and inline song rows. `LibraryRow` is a public wrapper around private `_LibraryRow`; only `_LibraryRow` is used (`library_sections/state.dart:93`).
- **Impact:** Two implementations of the same UI can drift; a future edit to the “playlist empty state” component will have no visible effect, and readers may waste time tracing dead code. This also increases APK/code size marginally and makes review harder.
- **Recommendation:** Remove the unused components (or replace the inline `PlaylistPage` implementations with the extracted components, add tests, and delete the duplicates). For `LibraryRow`, either make it the used public API or remove the wrapper. Do not keep both forms “just in case.”
- **Verification:** After removal, `rg` must show zero remaining references; run `dart analyze lib test` and the playlist/detail widget tests. Manually verify rename/delete/empty/play-all still behave identically.

### DEAD-02 — `theme_builder.dart` is an unused indirection

- **Severity / Category:** Low / Dead Code
- **Status:** Confirmed
- **Location:** `lib/themes/theme_builder.dart:4-11`.
- **Evidence:** `AppThemeConfig` only exposes `light`/`dark` getters that return `AppThemes.light`/`AppThemes.dark`, plus an identity `resolve(ThemeMode mode) => mode`. Repository search finds no references to `AppThemeConfig` or `theme_builder.dart`.
- **Impact:** Dead abstraction suggests a theme-building layer that does not exist and can mislead future contributors. It has no runtime effect.
- **Recommendation:** Delete the file or use it as the single theme composition point if a real theme-building layer is planned. If deleted, remove any barrel export if one is added later.
- **Verification:** `rg -n "AppThemeConfig|theme_builder" lib test` returns no references; analyzer and app build remain clean.

### DEAD-03 — `DetailTopBar` is an obsolete, non-functional top bar

- **Severity / Category:** Low / Dead Code
- **Status:** Confirmed
- **Location:** `lib/widgets/pages/detail_sections/top_bar.dart:3-41`.
- **Evidence:** `DetailTopBar` is defined but never constructed. It contains an `InkWell` back button, plus bare Cast, Add, and More icons that have no `onTap` at all. Current album/artist pages use `FadingTitleAppBar` with `CommonActions` instead (`album_page.dart:29-40`, `artist_page.dart:28-39`).
- **Impact:** Dead UI code with additional dead affordances; a future contributor might mount it and ship non-functional Cast/Add/More icons. It also contradicts the current app-bar architecture.
- **Recommendation:** Delete `DetailTopBar` and its `part` directive. If a compact detail top bar is still desired, rebuild it on top of the shared app-bar/action components.
- **Verification:** Remove the part declaration; `dart analyze lib test` clean; album/artist pages unchanged.

### DEAD-04 — Empty radio/banner data is exported but unused

- **Severity / Category:** Low / Dead Code
- **Status:** Confirmed
- **Location:** `lib/utils/data/radio_stations.dart:4`, `lib/utils/data/browse_banners.dart:2`, `lib/utils/sample_music_data.dart:1-5`.
- **Evidence:** Both constants are empty lists. `radioStations` is referenced only by a changelog string; `browseBanners` has no references. The shared barrel exports them, but only `searchCategories` is actually consumed (`search_sections.dart:12`).
- **Impact:** The barrel suggests sample/demo data still powers browse/radio, while the real screens use MediaStore-derived lists. This obscures the actual data flow and leaves a misleading “radio data exists” artifact alongside UX-01.
- **Recommendation:** Remove the two unused files and their exports; keep `searchCategories` only if the category grid is retained (see UX-02). If radio is implemented later, introduce a typed station model rather than a `Map<String, String>` empty placeholder.
- **Verification:** `rg -n "radioStations|browseBanners" lib test` returns no live usage; analyzer clean.

### DEAD-05 — `ArtistHero` has a Hero tag with no matching destination

- **Severity / Category:** Low / Dead Code (also a missing transition)
- **Status:** Confirmed
- **Location:** `lib/widgets/pages/detail_sections/artist.dart:35-45`; artist cards at `lib/widgets/pages/artist_list_sections/row.dart:20-31`, `lib/widgets/pages/home/artists_section/card.dart`, `lib/widgets/pages/library_sections/detail/artists_grid_view.dart:47-49`.
- **Evidence:** `ArtistHero` wraps its artwork in `Hero(tag: 'artist-artwork-${songs.first.artist}')`. Repository search finds that tag only at this declaration; artist cards do not wrap their artwork in a matching `Hero`. Album cards and the player do have matching tags (`PlayerHeroTags`), so this is specific to artist detail.
- **Impact:** The artist artwork never performs a Hero flight; the wrapper is dead weight and the intended transition is missing. Users see an abrupt image swap from the artist grid to detail. No crash occurs.
- **Recommendation:** Either add the matching `Hero` around the artist card artwork with the same stable tag, or remove the `Hero` from `ArtistHero`. Use an artist identity key (id/name) that is unique and stable; avoid using a display name alone if duplicates are possible.
- **Verification:** Add a widget/navigation test that asserts a Hero flight pair exists; on device, open an artist and confirm the artwork animates from the card to the header. If removed, confirm no Hero warning is logged.

---

## 6. Best-Practice and Maintainability Violations

### MAINT-01 — Typography and accent colors bypass the theme tokens

- **Severity / Category:** Low / Maintainability (UI consistency)
- **Status:** Confirmed
- **Location:** Representative: `lib/widgets/common_actions.dart:68-70`, `lib/widgets/pages/library_sections/header.dart:34`, `lib/pages/settings_page/*`, `lib/pages/settings/equalizer_page/*`; shared theme at `lib/themes/app_themes.dart`, `lib/themes/app_theme_extension.dart`.
- **Evidence:** `0xFFF92D48` appears 60 times across 34 Dart files. There are 251 explicit `fontSize:` declarations in `lib/widgets` and `lib/pages`. Many pages use `TextStyle(fontSize: …, color: …)` directly instead of the theme's `TextTheme` or the extension's semantic tokens. The theme already defines the brand color in `ColorScheme.primary` and semantic labels in `AppThemeExtension`.
- **Impact:** A future brand, contrast, or type-scale change must be applied in dozens of places and will inevitably drift. Component-level typography is inconsistent by construction (17/18/20/22/26/34 px headings with ad-hoc weights), making accessibility tuning and dark/light parity harder. This is a maintainability/design-system issue, not a current visual break.
- **Recommendation:** Introduce a small set of typography tokens (page title, section title, row title, caption, control label) in the theme extension and migrate screens incrementally. Replace hardcoded accent literals with `Theme.of(context).colorScheme.primary` or a single `brandAccent` token. Do not perform a mass mechanical rewrite without visual regression coverage.
- **Verification:** Track token adoption with `rg` counts (target: zero raw `0xFFF92D48` outside the theme; explicit font sizes reduced to the token set). Run golden/screenshot tests for light/dark and both locales after each batch.

### MAINT-02 — Oversized player widgets mix layout, animation, data loading, and gestures

- **Severity / Category:** Low / Maintainability (widget-tree complexity)
- **Status:** Confirmed
- **Location:** `lib/widgets/unified_morph_player.dart` (1,172 lines), `lib/widgets/player/player_content/content.dart` (904 lines), with parts in `player_content/queue_overlay.dart`, `lyrics_overlay.dart`, `lyrics_appearance.dart`, `player_background/*`; other large screens: `playlist_page.dart` (424), `log_page.dart` (422), `equalizer_page/page.dart` (405).
- **Evidence:** `_UnifiedMorphPlayerState` owns entry/exit/release animation controllers, playback diffing, sheet progress, geometry, background selection, and three alternative layouts. `_PlayerContentState` owns lyrics fetching, explicit-status fetching, two scroll controllers, a drag handle, marquee timer, expansion state, and both overlay bodies. These are cohesive features but not independently testable units.
- **Impact:** Changes to one concern (for example, queue scrolling) can rebuild or destabilize unrelated concerns (artwork morph, lyrics animation). The size makes code review and targeted performance fixes (PERF-01/02/03) harder, and it encourages broad subscriptions because passing narrow state requires refactoring. This is a maintainability risk rather than a current user-visible bug.
- **Recommendation:** Extract independent units with explicit inputs: a `QueueOverlay` with its own controller/subscription, a `LyricsOverlay` that owns its ticker, a pure `PlayerMorphLayout` geometry widget, and a `PlayerTransport` that subscribes to only the state it needs. Keep the existing visual structure and test with golden/screenshot comparisons. Do this incrementally, starting with the overlay extraction that also fixes PERF-01.
- **Verification:** After each extraction, run the player wide-layout/device-matrix tests and compare screenshots at 393×852 and 852×393. Add build-count tests for the new units to ensure the extraction actually narrows rebuild scope.

### MAINT-03 — Architecture comments describe behavior the code no longer has

- **Severity / Category:** Low / Maintainability (documentation drift)
- **Status:** Confirmed
- **Location:** `lib/widgets/unified_morph_player/playback_content.dart:3-7`, `lib/widgets/player/player_content/content.dart:5-25`; `lib/widgets/player/player_song_info_sheet/state.dart:73-75` vs `lib/widgets/player/player_song_info_sheet/content.dart:51`.
- **Evidence:** The playback-content comment says position-tick rebuilds are isolated to the narrow wrapper, implying only that subtree rebuilds; in practice it rebuilds the entire `PlayerContent`. The song-info sheet comment says the body is “Not scrollable internally (fits within the constraint)”, but `_SongInfoContent` returns a `SingleChildScrollView` and explicitly supports overflow. These comments are the kind of guidance a future performance or gesture fix would rely on.
- **Impact:** Misleading comments hide PERF-02 and the swipe/scroll interaction, increasing the chance that a future change preserves the wrong behavior or “fixes” a non-problem. They also make onboarding slower.
- **Recommendation:** Update the comments as part of the corresponding fixes: state exactly which widgets rebuild and why, and describe the scroll/swipe division of labor. Prefer comments that link to the invariant (“PlayerContent must not subscribe to position”) over claims that are easy to invalidate.
- **Verification:** Review comments against DevTools build counts and the actual sheet gesture behavior; ensure the song-info comment matches the presence/absence of an internal scrollable after UX-07/section 10 work.

---

## 7. Optimization Opportunities

These are opportunities, not confirmed defects. Expected benefits are qualitative unless a measurement plan is included. Avoid implementing all of them blindly; prioritize the ones tied to confirmed costs (PERF-01/02/03) and measure on the target device.

| ID | Opportunity | Expected benefit | Trade-off / risk | Evidence status |
|---|---|---|---|---|
| OPT-01 | Lazily mount/pause lyrics and queue overlays. | Removes continuous karaoke ticker, position subscription, and hidden queue rebuilds; lower CPU/GPU/battery while player open. | Must preserve fade animations and state restoration (scroll position, active line). Medium implementation complexity. | Confirmed cost (PERF-01) |
| OPT-02 | Replace full `AudioPlaybackState` subscription in the player with narrow `isPlaying`/queue signals. | Removes 5–10 full-subtree rebuilds/s; smoother scrolling and animation. | Touches transport/queue wiring; risk of stale play/pause UI if a signal is missed. | Confirmed cost (PERF-02) |
| OPT-03 | Hoist stable content out of the sheet-progress builder; animate only opacity/transform wrappers. | Fewer builds during the most gesture-sensitive animation; less jank while artwork/blur changes. | Layout code is split across portrait/two-column; risk of visual mismatch. | Confirmed cost (PERF-03) |
| OPT-04 | Profile the full-screen fluid shader and glass blur; reduce resolution/frame rate when paused or when the player is idle. | Potentially meaningful GPU/battery savings on Snapdragon 730. | Visual identity depends on the animated background; reducing it may look worse. No data yet. | Hypothesis |
| OPT-05 | Gate the repeated `applyEdgeToEdge()` call in `MaterialApp.builder` so it runs on lifecycle/theme changes rather than every builder pass. | Removes redundant platform-channel calls during ordinary rebuilds. | Very small benefit; low risk. Do not prioritize over user-facing issues. | Code inspection; impact likely minor |
| OPT-06 | Add a shared empty/loading/error state component for library-backed sections. | Consistent recovery path, fewer blank screens, less duplicated layout code. | Requires product copy and permission-aware actions; moderate UI work. | Confirmed gaps (UX-08, BUG-02) |

**On OPT-04:** Before changing the effect, capture a GPU frame trace in profile mode while the full player is open, both paused and playing, on the target device. If the shader is not a meaningful contributor, leave it alone. If it is, consider rendering the background at a reduced resolution, pausing after a period of inactivity, or disabling the animated layer when `MediaQuery.disableAnimationsOf(context)` is true. Do not trade away the design without evidence.

**Positive optimizations already present (do not regress):**

- Pre-blurred artwork caching avoids a full-screen `ImageFilter` on every frame (`cover_blur.dart` comments and `artwork_blur_cache.dart`).
- The morph shell deliberately excludes `AudioService.playbackState` from its top-level VLB chain (`unified_morph_player.dart:390-394`).
- The bottom navigation caches its child across sheet-progress rebuilds (`bottom_nav/state.dart:249-275`).
- Artwork target sizes and prefetch limits are explicit (`ArtworkRepository.resolveTargetPx`, `prewarmImageCache`).
- The two-column player uses computed panel metrics to avoid overflow on short windows (`now_playing_layout.dart:129-157`).

---

## 8. Accessibility and Interaction Issues

### A11Y-01 — Core controls are below the 48 dp target and several are unnamed

- **Severity / Category:** Medium / Accessibility
- **Status:** Confirmed
- **Location:** `lib/widgets/player/player_favorite_button.dart:61-88` (28×28, label hardcoded English), `lib/widgets/player/player_more_menu.dart:74-92` (28×28, no Semantics/tooltip), `lib/widgets/player/player_secondary_controls/controls.dart:50-70` and `:85-105` (35×35, no Semantics/tooltip), `lib/widgets/pages/library_sections/header.dart:25-39` (text-only Edit/Done), `lib/widgets/play_shuffle_buttons.dart:93-97` (44 dp high).
- **Evidence:** The favorite button uses a `Semantics` wrapper but a hardcoded, non-localized label (“Add to Favorites”/“Remove from Favorites”). The more menu, lyrics toggle, and queue toggle are bare `GestureDetector`s with 28–35 dp hit boxes and no semantic label/tooltip. The Library header’s Edit/Done control is a `GestureDetector` around a 17 px `Text`, so its tap area is only the glyph bounds. Play/Shuffle are 44 dp, two dp below the Material/Android minimum.
- **Impact:** Users with motor impairments have a much smaller-than-standard target for frequent player actions, and TalkBack announces several icon controls without a meaningful name (or announces an English label in the Indonesian locale). The favorite state can be impossible to discover non-visually. This is a direct usability issue on the target phone, especially one-handed.
- **Recommendation:** Enforce a 48×48 dp minimum hit area with `IconButton`/`InkResponse`/`SizedBox` + `Semantics`, keeping the visual glyph size unchanged. Add localized `tooltip`/`semanticLabel` for Favorite, More, Lyrics, Queue, Cast (if retained), and the Library Edit/Done control. Use `Semantics(toggled: ...)` for the favorite/lyrics/queue states. Prefer Material `BackButton` (which supplies a localized tooltip) over a custom icon-only `CupertinoButton` in app bars.
- **Verification:** Run Flutter's `androidTapTargetGuideline` and `labeledTapTargetGuideline` in widget tests over the player and Library screens. On device, enable TalkBack and confirm every icon announces a localized name, role, and state; use “Switch Access” or a large-display setting to check focus order. Measure the actual hit rectangles in a widget test (minimum 48×48).

### A11Y-02 — Reduced-motion setting is ignored outside the lyrics view

- **Severity / Category:** Medium / Accessibility
- **Status:** Confirmed
- **Location:** `lib/widgets/player/player_background/artwork.dart:59-63` (30-minute repeating shader controller), `lib/widgets/unified_morph_player.dart:75-85` (entry/exit/release controllers), `lib/widgets/player/player_content/content.dart:210-246, 459-464, 560-565` (fade/slide tweens), and the only `MediaQuery.disableAnimationsOf` checks at `lib/widgets/player/synced_lyrics_view/state.dart:46,59`, `state_build.dart:32`, `state_indexing.dart:55`, `state_scroll.dart:44`.
- **Evidence:** The lyrics implementation explicitly respects the system animation preference, but the player morph, the continuously repeating background shader, page fades, and most `TweenAnimationBuilder` transitions do not. There is no global `disableAnimations` policy in the app shell.
- **Impact:** Users who enable “Remove animations” for vestibular sensitivity still get a full-screen animated shader, morphing sheet, and sliding/fading transitions. Continuous background motion can also waste battery when the user has deliberately reduced motion. The inconsistency is surprising because the lyrics view already sets a precedent.
- **Recommendation:** Read `MediaQuery.disableAnimationsOf(context)` (or `accessibleNavigation`) at the player shell and page-transition layers. When enabled, stop the shader/repeating controller, replace morph slides with short fades or instant state changes, and keep only essential progress feedback. Provide a separate “animated background” setting if the visual effect is considered core; do not override the OS preference silently.
- **Verification:** Enable “Remove animations” in Android accessibility settings, open/close the player, open lyrics/queue, and confirm there is no continuous shader motion or long slide. Compare with animations enabled. Add a widget test that injects `disableAnimations: true` and asserts the shader controller is not repeating.

### A11Y-03 — Status-bar icon contrast is not controlled for the dark full player (suspected)

- **Severity / Category:** Low / Accessibility (visual contrast)
- **Status:** Suspected — requires runtime verification
- **Location:** `lib/main/edge.dart:3-11`, `lib/main/app_state.dart:84-131`; absence of `AnnotatedRegion`/`SystemUiOverlayStyle` in the full-player subtree (`rg` finds none in `lib/widgets`, `lib/pages`).
- **Evidence:** The app sets transparent status/navigation bars and edge-to-edge mode, but never sets `statusBarIconBrightness` or wraps the player in an `AnnotatedRegion`. The full player uses a dark scrim and white content; in light theme, the underlying page's status-bar icons may remain dark. The exact result depends on the last route/app-bar style and the Android system behavior, so this cannot be confirmed statically.
- **Impact:** On a bright album cover or light theme, the clock/battery/notification icons can become low-contrast or invisible over the full player. This is a legibility failure for system status information, not just aesthetics.
- **Recommendation:** Wrap the full player (or the app shell per route) in an `AnnotatedRegion<SystemUiOverlayStyle>` that sets light icons over the dark player and restores the page-appropriate style on exit. Verify against both light and dark app themes and dynamic album colors.
- **Verification:** On the target device in light theme, open the full player with a bright cover and inspect the status bar in a screenshot; repeat in dark theme. After the fix, assert the icons remain legible on both. Do not claim this is fixed without an actual screenshot or device inspection.

### Accessibility strengths worth preserving

- `PlayerFavoriteButton` at least exposes a `Semantics(button: true)` wrapper, unlike many other custom controls.
- The app respects the system locale and ships both English and Indonesian ARB resources.
- Text uses the system text scaler rather than a fixed global scale; no override suppresses accessibility text size.
- The lyrics view checks `disableAnimationsOf` in its scroll/highlight paths, which is the right pattern to extend.
- `AppThemeExtension` provides semantic label/separator tokens that can support contrast work once adopted broadly.

---

## 9. Recommended Fixes and Prioritized Action Plan

Priorities are based on user harm first, then likelihood, then engineering risk. Effort estimates are relative, not calendar estimates.

### P0 — Fix before the next user-facing release

| Order | IDs | Action | Effort | Risk | Expected impact |
|---:|---|---|---|---|---|
| 1 | BUG-01 | Add an explicit confirmation before device deletion; default to Cancel. | Low | Low | Prevents irreversible accidental data loss. |
| 2 | UX-01, UX-02, UX-03, UX-04 | Make every visible affordance honest: rename/implement Radio, wire or remove Search categories, remove/disable Cast, remove or wire Browse chevrons. | Medium | Low–Medium | Eliminates the largest cluster of “tap does nothing” experiences across primary navigation. |
| 3 | UX-06 | Respect `viewPadding.bottom` in the portrait full player. | Low | Low | Restores tappability under 3-button navigation; low regression risk. |

### P1 — Next iteration (performance and core interaction quality)

| Order | IDs | Action | Effort | Risk | Expected impact |
|---:|---|---|---|---|---|
| 4 | PERF-01 | Lazily mount/pause lyrics and queue overlays; stop the hidden ticker and queue subscription. | Medium | Medium | Largest measurable CPU/GPU/battery win; helps player smoothness. |
| 5 | PERF-02 | Narrow the player's playback subscription to `isPlaying`/queue identity. | Medium | Medium | Removes full-subtree rebuilds on every position tick. |
| 6 | A11Y-01 | Enforce 48 dp targets and localized semantics/tooltips for player and Library controls. | Low–Medium | Low | Directly improves one-handed and TalkBack usability. |
| 7 | BUG-02, UX-07, UX-08 | Add error/retry to Song Info, make the context menu scrollable, add a Browse empty/loading state. | Medium | Low | Removes dead-end states and landscape/large-text clipping. |

### P2 — Product and architecture decisions

| Order | IDs | Action | Effort | Risk | Expected impact |
|---:|---|---|---|---|---|
| 8 | UX-05 | Decide whether Browse is curated or random; implement stable ranking or relabel. | Medium | Low | Restores trust in “Daily Top 100”/“We Recommend”. |
| 9 | PERF-03 | Isolate progress-dependent wrappers from stable player content. | Medium | Medium | Smoother sheet animation on mid-range hardware. |
| 10 | A11Y-02 | Honor reduced-motion for morph/shader/transitions. | Medium | Low | Accessibility and battery improvement. |
| 11 | A11Y-03 | Add route-aware status-bar icon styling. | Low | Low | Prevents low-contrast system icons over the player. |

### P3 — Cleanup and design-system work

| Order | IDs | Action | Effort | Risk | Expected impact |
|---:|---|---|---|---|---|
| 12 | DEAD-01…05 | Remove orphaned playlist/top-bar/theme/data code and fix or remove the unmatched artist Hero. | Low | Low | Less misleading code; smaller surface for future drift. |
| 13 | MAINT-01, MAINT-02, MAINT-03 | Adopt type/color tokens incrementally, split the player's concerns, correct stale architecture comments. | High (incremental) | Medium | Long-term maintainability and safer performance work; no immediate user-visible change. |
| 14 | OPT-04 | Profile GPU cost of the fluid shader/glass blur before changing it. | Low (measurement) | N/A | Evidence-based decision; avoids optimizing the wrong thing. |

### Suggested validation gates

1. **Widget tests:** Add tests for destructive confirmation, category tap callbacks, 48 dp targets, and error states before or alongside the fixes.
2. **Layout tests:** Render full player/context menu at 393×852 and 852×393, with `textScaleFactor` 1.0 and 2.0, and assert no overflow. Extend the existing `test/widgets/device_matrix_test.dart` patterns.
3. **Semantics:** Run `androidTapTargetGuideline` and `labeledTapTargetGuideline`; do one TalkBack pass on device.
4. **Performance:** Profile before/after PERF-01/02/03 with DevTools; record frame times, build counts, and battery/thermal observations on the target phone. Do not report a speedup without these measurements.
5. **Visual regression:** Capture light/dark and English/Indonesian screenshots for Home, Browse, Search, Library, album/artist, playlist, and the full player. Use the existing golden setup where practical, but do not treat a temporarily committed reference test as permanent coverage.

---

## 10. Audit Limitations and Items Requiring Runtime Verification

### Limitations of this audit

- **No runtime device/emulator inspection.** No screenshots, no touch testing, no TalkBack, no 3-button navigation check, no landscape test, and no measured frame time, GPU time, memory, or battery use.
- **No APK build.** Per the repository's permanent directive, APK builds belong to CI/devcontainer/Replit; none was attempted.
- **Static analysis only.** `dart analyze lib test` was clean, but analyzer cleanliness does not prove visual or interaction correctness.
- **Responsive test attempt failed to complete.** The responsive widget-test run was stopped by the command's 120-second limit (exit 124). It is not reported as a pass and does not establish layout correctness.
- **Shallow repository metadata.** Git history was not available to this host, so repository history was not used as evidence.
- **No web-runtime test.** The web preview is a secondary surface and cannot exercise Android MediaStore/FFI.

### Items requiring runtime verification

| Item | Why static evidence is insufficient | Suggested check |
|---|---|---|
| UX-06 bottom inset | Actual overlap depends on the device's navigation mode and insets. | 3-button and gesture navigation screenshots; tap the bottom toggles. |
| UX-07 context menu overflow | Height depends on font metrics, text scale, and sheet constraints. | Render at 852×393 and text scale 2.0; inspect the overflow console and scroll to Delete. |
| PERF-01 hidden ticker | The code confirms the ticker, but the user-visible cost needs profiling. | DevTools CPU/GPU trace with player open, lyrics/queue never opened; compare before/after gating. |
| PERF-02/03 rebuild scope | Build counts are inferred from widget composition, not measured. | DevTools “Track widget builds”; add temporary counters in a profiling branch. |
| A11Y-01 target size/semantics | Layout and semantics can differ under text scaling and device density. | Flutter accessibility guidelines + TalkBack on device. |
| A11Y-02 reduced motion | Android's animation setting propagation can vary. | Enable “Remove animations”; observe shader/morph behavior. |
| A11Y-03 status-bar icons | Depends on route/app-bar style, theme, and Android system behavior. | Light/dark screenshots over a bright cover. |
| UX-01 Radio | Product intent is not documented; the tab could be intentionally repurposed. | Product decision/design review before renaming or implementing. |
| UX-05 Browse ranking | “Daily Top 100” may be a placeholder label, not a promised ranking. | Confirm intended product semantics with the owner. |
| BUG-02 metadata error | Normal metadata paths catch errors; the failure trigger is narrow. | Inject a failing future/widget test and an unreadable file; confirm error UI. |
| Swipe-to-dismiss vs scroll | Gesture arena behavior requires a real drag on a scrollable sheet. | Open Song Info, drag from the middle vs the handle; verify whether the sheet dismisses or the list scrolls. |
| Web Search loading | `MediaStoreService.getSongs()` throws by design on web; `search_sections/state.dart:47-55` has no catch, so `_loading` may stay true. | Run the web preview, open Search, and inspect console/loading state. This is web-only and outside the Android target. |

### Explicitly unverified optimization hypotheses

- The full-screen fluid shader and layered glass blur may be costly on the target Snapdragon 730, but no GPU trace was captured. Do not cite a speedup without a before/after profile.
- Decoding the 16 Search category images at source resolution may be a memory cost, but source dimensions were not available in this environment; no claim is made.
- `applyEdgeToEdge()` inside `MaterialApp.builder` may cause redundant platform-channel calls, but the cost is likely small relative to the confirmed rebuild issues; it is listed only as a low-priority cleanup.

### Closing statement

This audit found no Critical issue, but it found four high-impact problems that directly affect trust and core usability: unconfirmed device deletion, two primary surfaces with dead affordances, a mislabeled Radio destination, and hidden player work that continues every frame. The next highest-value work is not a broad redesign; it is to make existing affordances truthful, respect system insets and accessibility settings, and stop doing hidden work in the player. All findings above are documented with source evidence and a concrete verification path so fixes can be validated rather than assumed.
