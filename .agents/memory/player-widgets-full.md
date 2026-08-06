---
name: Player Widgets Full Map
description: All files in lib/widgets/player/ — UnifiedMorphPlayer, SyncedLyricsView, progress, transport controls.
---

# Player Widgets — Full Map

## UnifiedMorphPlayer (`lib/widgets/unified_morph_player.dart`)

The main persistent player component is `UnifiedMorphPlayer`, which morphs between
collapsed mini-player and expanded full-player states.
- Handles glass morphing logic via `ThemeController` values
- `TickerMode` pauses player background shader when player collapsed (performance)
- Player background: `lib/widgets/player/player_background/fog_painter.dart` + `artwork.dart` render `fluid.frag` GLSL shader
- Pre-computed `_c0r…_c2b` color values; `paint()` zero arithmetic; 256×512 canvas + `RepaintBoundary` isolation
- Shader pauses when collapsed to save CPU

## Legacy PlayerSheet

The old `PlayerSheet` widget and its part files were removed after the active
navigation tree was verified to use `UnifiedMorphPlayer`. `PlayerSheetController`
remains because it is still the state/control backend for MorphPlayer.

## SyncedLyricsView (`lib/widgets/player/synced_lyrics_view/view.dart`)

Auto-scrolling lyrics display synchronized with audio position.
- `rawLrc` param for raw LRC string input
- ELRC word-level: `ElrcWordExtractor` parses word timestamps; binary search on `word.start`; falls back to char-fill for lines without word data
- Auto-scroll suppression: 3s grace period after user manual scroll before resuming auto-follow
- Bottom controls: hide ONLY on genuine user swipe-up (`ScrollUpdateNotification.dragDetails != null`); never on programmatic/auto-follow scrolls
- Drag updates from the active list use the real scroll position; programmatic
  auto-follow must not be treated as a genuine user swipe
- State: pre-computes karaoke values (no per-frame allocation); `Listenable.merge` replaces 3 nested `ValueListenableBuilder`s
- KaraokeMode: connected to renderer + toggle UI

## PlayerProgressSection (`lib/widgets/player/player_progress_section.dart`)

Seek bar + time indicators.
- Vertical slider vs scroll conflict: `Listener`-based multitouch sliders don't join gesture arena; lock ancestor `ScrollView` via shared active-pointer-count `ValueNotifier`

## PlayerTransportControls (`lib/widgets/player/player_transport_controls.dart`)

Play/pause, skip prev/next, repeat, shuffle controls.
- All actions delegate to `AudioService` / `PlaybackManager`
- Repeat and shuffle state come from native EventChannel stream

## PlayerUpNextCard (`lib/widgets/player/player_up_next_card.dart`)

Preview of next track in queue.
- Subscribes to queue EventChannel; refreshes on track change visibility

## Player Background (`lib/widgets/player/player_background/`)

| File | Role |
|------|------|
| `fog_painter.dart` | CustomPainter that renders `fluid.frag` GLSL shader |
| `artwork.dart` | Blurred/dimmed artwork layer behind controls |

## lib/widgets/pages/home_sections.dart

`HomePageContent` (composition hub via `part`):
- `SingleChildScrollView` → `LargePageTitle` + `HeaderDivider` + 3 sections
- Data models: `_AlbumGroup`, `_ArtistGroup` (group songs by metadata)

### lib/widgets/pages/home/ (part files)

| File | Widget | Data Shown |
|------|--------|-----------|
| `albums_section.dart` | `_LocalAlbumsSection` | Album cards grouped by album name; horizontal carousel |
| `recently_played_section.dart` | `_RecentlyPlayedSection` | Last-played songs from `HistoryService`; horizontal carousel |
| `artists_section.dart` | `_LocalArtistsSection` | Artist cards; horizontal carousel |

Artwork prewarm: shared 3s timeout + `Future.wait` concurrent decode to prevent cold-start flicker.
