---
name: Pages — Browse, Search, Album, Artist, Playlist, Radio
description: Detail on all content pages outside Home/Settings/Player.
---

# Pages: Browse, Search, Album, Artist, Playlist, Radio

## BrowsePage (`lib/pages/browse_page.dart`)

- Title: "Baru"
- State: `_scrollOffsetNotifier` (ValueNotifier for app bar fade), `_scroll` (ScrollController)
- Listens to `ScrollToTopService` (signal index 1)
- Uses `FadingTitleAppBar` + `BrowsePageContent` (from `browse_sections/content.dart`)

### BrowsePageContent (`lib/widgets/pages/browse_sections/`)

| File | Widget | Role |
|------|--------|------|
| `content.dart` / `state.dart` | `BrowsePageContent` | Orchestrates data loading via `MediaStoreService.getSongs()`; seeds `Random` with current date → 3 "Daily" banner songs; shuffles others into "We Recommend", "New Music", "Daily Top 100" |
| `banners.dart` | `BrowseBannerCarousel`, `_BannerArtwork` | Horizontal ListView; 370px-wide banner cards; shows artist (uppercase), song title, album; artwork via `ArtworkRepository` |
| `section.dart` | `_BrowseSection` | Reusable vertical block: title + chevron + `LocalSongCarousel` |

## RadioPage (`lib/pages/radio.dart`)

- Title: "Radio"
- State: `_scrollOffset` (double), `_scroll` (ScrollController)
- Listens to `ScrollToTopService` (signal index 2)
- Uses `RadioPageContent` from `radio_sections.dart`
- Data: static radio station data from `lib/utils/sample_music_data.dart`

## PlaylistPage (`lib/pages/playlist_page.dart`)

- State: `_songs` (List<LocalSong>), `_loading` (bool), `_offsetNotifier`
- `_load()`: fetches via `MediaStoreService`
- `_smartIds()`: logic for Favorites, Recently Played, Most Played (via `PlaylistService`, `HistoryService`)
- Actions: play all, `_removeSong`, `_rename`, `_delete`
- UI: `ListView.separated` with `SongArtwork` + `ListTile`

## SearchPage (`lib/pages/search_page.dart`)

- Searches across: tracks, albums, artists (local library)
- No network search — local-only filtered from `MediaStoreService` song list
- Result types: `LocalSong`, album groups, artist groups
- Uses `TextEditingController`; debounced search

## AlbumPage (`lib/pages/album_page.dart`)

- Shows: album details, play/shuffle buttons, song tracklist, footer metadata, "More by Artist" section
- Tracklist: `SongListSection` inside `AlbumPageContent`
- Hero: `AlbumHero` — centered 220px artwork, title, artist (red), metadata (genre, year, Lossless tag)
- Opens from: `LocalSongCard` album tap or home albums section

## ArtistPage (`lib/pages/artist_page.dart`)

- Shows: artist name, song/album count, albums grid, all-songs list
- Uses: `ArtistHero` widget

## ArtistList (`lib/pages/artist_list.dart`)

- All artists listed; sorted alphabetically
- Each artist → `ArtistPage`

## Detail Section Widgets (`lib/widgets/pages/detail_sections/`)

| File | Widget | Role |
|------|--------|------|
| `album.dart` | `AlbumHero` | 220px artwork + title + artist (red) + genre/year/Lossless |
| `artist.dart` | `ArtistHero` | Artist name + song/album count |
| `songs.dart` | `SongListSection` | `ListView.builder` of `SongListRow` |
| `song_row.dart` | `SongListRow` | Track number + title + 3-dot menu; tap → `AudioService.playSongAt` |
| `top_bar.dart` | `DetailTopBar` | Back button + cast/add/more icons |
| `circle_icon.dart` | `CircleIcon` | Icon helper |

## Shared Widgets

### LocalSongCard (`lib/widgets/local_song_card.dart`)
Individual song tile with artwork, title, artist, 3-dot context menu.

### LocalSongCarousel (`lib/widgets/local_song_carousel.dart`)
Horizontal scrollable list of `LocalSongCard`s.

### SongContextMenu (`lib/widgets/song_context_menu.dart`)
Popup menu actions:
- Play next
- Add to queue
- Add to playlist / favorites
- Go to album / artist
- Share
- Song info
- Edit tags (opens `SongMetadataService`)

### SongArtwork (`lib/widgets/song_artwork.dart`)
Props: `songId`, `width`, `height`, optional border radius.
Loads via `ArtworkRepository`; shows placeholder on miss.

### CommonActions (`lib/widgets/common_actions.dart`)
Multiple small reusable action button widgets (play, shuffle, cast, add to queue, etc.).
