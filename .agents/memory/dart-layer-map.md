---
name: Dart Layer Map
description: Every file in lib/models/, lib/services/, lib/pages/, lib/widgets/ with class name and role.
---

# Dart Layer Map

## lib/models/

| File | Class(es) | Role |
|------|-----------|------|
| `local_song.dart` | `LocalSong` | Data model for a local device song file |
| `loudness_data.dart` | `LoudnessSource` (enum), `LoudnessData` | Loudness / ReplayGain metadata container |
| `lyric_line.dart` | `LyricLine` | Single lyrics line with timestamp |
| `lyrics_settings.dart` | `LyricsSettings` | Singleton: fontSize, textAlign, bgDim, blurStrength, activeColor, showSource, karaokeMode |
| `playlist.dart` | `SmartPlaylistType` (enum), `Playlist` | User-defined and smart playlists |
| `replay_gain_mode.dart` | `ReplayGainMode` (enum) | Off / Track / Album |
| `song_info.dart` | `SongInfo` | Technical metadata: bitrate, sample rate, format |

## lib/services/ (root)

| File | Class(es) | Role |
|------|-----------|------|
| `artwork_repository.dart` | `ArtworkRepository` | Fetch + cache album artwork; filesDir/supportDir storage |
| `audio_focus_service.dart` | `AudioFocusService` | OS audio focus requests/responses |
| `audio_playback_state.dart` | `AudioPlaybackState` | Current playback status (playing/paused/buffering) |
| `audio_service.dart` | — | Entry point for audio service subsystem |
| `boot_trace.dart` | `BootTrace` | Startup performance measurement; rethrows on error (web-unsafe) |
| `history_service.dart` | `HistoryService` | Recently played tracking |
| `log_service.dart` | — | Entry point for logging (max 500 FIFO entries, persistent) |
| `loudness_source_resolver.dart` | `LoudnessSourceResolver` | Picks best loudness data source per song |
| `lyrics_service.dart` | — | Entry point for lyrics retrieval |
| `media_capabilities_service.dart` | — | Device media hardware capability queries |
| `media_store_service.dart` | `MediaStoreService` | System MediaStore → audio file discovery (throws MissingPluginException on web — handle gracefully) |
| `open_file_service.dart` | `OpenFileService` | External intent file opening |
| `palette_extractor.dart` | `PaletteExtractor` | Dominant color extraction from artwork for theming |
| `player_sheet_controller.dart` | `PlayerSheetController` | Thin adapter over `PlayerSheetController`; MiniPlayer + PlayerSheet still use old controller |
| `playlist_service.dart` | `PlaylistService` | Playlist CRUD + favorites |
| `replay_gain_service.dart` | — | ReplayGain processing entry point |
| `scroll_to_top_service.dart` | `ScrollToTopService` | Cross-tab scroll-to-top event coordination |
| `sleep_timer_service.dart` | `SleepTimerMode` (enum), `SleepTimerService` | Delegates to native Handler; subscribes sleepTimerStream for UI ValueNotifiers |
| `song_metadata_service.dart` | — | Read/write file tags entry point |
| `up_next_settings.dart` | `UpNextSettings` | "Up Next" queue visualisation settings |
| `watermark_service.dart` | `WatermarkService` | UI watermark visibility/content |

## lib/services/audio/

| File | Class(es) | Role |
|------|-----------|------|
| `audio_effects_service.dart` | — | Library entry for audio effects |
| `audio_effects_service/service.dart` | `AudioEffectsService` | DSP effects management: EQ, compressor, etc. |
| `audio_session_handler.dart` | — | Library entry for audio session |
| `audio_session_handler/handler.dart` | `AudioSessionHandler` | OS audio session configuration |
| `device_dsp.dart` | `DeviceDsp` | Native Android/iOS global DSP effects interface |
| `media3/media3_playback_bridge.dart` | `Media3PlaybackBridge` | Android Media3/ExoPlayer MethodChannel bridge |
| `playback_manager.dart` | `PlaybackManager` | High-level playback coordinator; root owner of NativeModuleRegistry + AudioService |

## lib/services/log_service/

| File | Class(es) | Role |
|------|-----------|------|
| `entry.dart` | `LogEntry` | Single log message model |
| `level.dart` | `LogLevel` (enum) | Log severity levels |
| `native_log_bridge.dart` | `NativeLogBridge` | Routes Dart logs → Logcat |

## lib/services/lyrics_service/

Multi-provider system: `LyricsFetchManager` orchestrates local (Embedded, LocalFile) + 6 online providers (LRCLIB, NetEase, Kugou, Kuwo, QQMusic, Musixmatch-removed) in parallel. `LyricsQuality` enum drives priority. Public API unchanged.

| File | Role |
|------|------|
| `lyrics_cache_manager.dart` | Single cache (LyricsCacheManager only); failed-TTL = 1h |
| `lyrics_fetch_manager.dart` | Parallel provider orchestration |
| `providers/` | Individual provider implementations |

## lib/services/replay_gain_service/

| File | Role |
|------|------|
| `service.dart` | `ReplayGainService` — volume normalization logic |

## lib/services/song_metadata_service/

| File | Role |
|------|------|
| `service.dart` | `SongMetadataService` — read/write media tags (ExoMetadataReader + MetadataCacheDb SQLite, mtime-keyed) |

---

## lib/pages/

| File | Main Widget | Role |
|------|-------------|------|
| `album_page.dart` | `AlbumPage` | Album detail + tracklist |
| `artist_list.dart` | `ArtistList` | All artists list |
| `artist_page.dart` | `ArtistPage` | Artist profile + albums/songs |
| `browse_page.dart` | `BrowsePage` | Discovery / recommendations |
| `home_page.dart` | `HomePage` | Main dashboard |
| `library_page.dart` | `LibraryPage` | Local/saved music collection; ReorderableListView in edit mode; order in SharedPrefs |
| `log_page.dart` | `LogPage` | App event log viewer |
| `playlist_page.dart` | `PlaylistPage` | Playlist view + management |
| `radio.dart` | `RadioPage` | Radio-style playback |
| `search_page.dart` | `SearchPage` | Track/artist/album search |
| `settings_page.dart` | `SettingsPage` | Main settings; debug section via 3× version tap |

### lib/pages/log_page/
`_AppBarBadge`, `_BarBtn`, `_LogEntryTile`, `_LogFilterBar`, `_LogLevelSelector`

### lib/pages/settings/
| File | Role |
|------|------|
| `equalizer_page/page.dart` | `EqualizerPage` — 32-band graphic EQ (system Equalizer, sole Band EQ backend) |
| `settings_widgets/action.dart` | `SettingsActionRow` |
| `sleep_timer_page/page.dart` | `SleepTimerPage` |
| `changelog_data.dart` | `_changelogEntries` list — version history shown in Settings |

---

## lib/widgets/

| File | Widget | Role |
|------|--------|------|
| `common_actions.dart` | multiple | Shared action buttons |
| `local_song_card.dart` | `LocalSongCard` | Song card tile |
| `local_song_carousel.dart` | `LocalSongCarousel` | Horizontal song card scroller |
| `song_artwork.dart` | `SongArtwork` | Album art display |
| `song_context_menu.dart` | `SongContextMenu` | Track popup menu |
| `unified_morph_player.dart` | `UnifiedMorphPlayer` | Main persistent + expanded player UI |

### lib/widgets/player/
| File | Widget | Role |
|------|--------|------|
| `player_sheet.dart` | `PlayerSheet` | Expandable bottom sheet player |
| `player_progress_section.dart` | `PlayerProgressSection` | Seek bar + time indicators |
| `synced_lyrics_view/view.dart` | `SyncedLyricsView` | Auto-scrolling synced lyrics; rawLrc param; ELRC word-level support |
| `player_transport_controls.dart` | `PlayerTransportControls` | Play/pause/skip/repeat controls |
| `player_up_next_card.dart` | `PlayerUpNextCard` | Next track preview |

### lib/widgets/pages/
| File | Widget | Role |
|------|--------|------|
| `home_sections.dart` | `HomePageContent` | Home screen section layout; uses `part` to home/albums_section.dart etc. |
| `detail_sections/album.dart` | `AlbumHero` | Hero animation for album transitions |
| `browse_sections/banners.dart` | `BrowseBanners` | Featured content sliders |

---

## Init Order (main.dart)
`ThemeController → LogService → LyricsSettings → AudioEngine → AudioEffectsService → LyricsService.init() → SleepTimerService.initialize() → AudioService`
