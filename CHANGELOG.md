# Changelog

## [1.2.6] — 2026-07-18

### Refactor — Phase 8A God Files Refactor (structural only, zero behavior change)

**`lib/pages/log_page.dart`** (820 → 265 lines)
- Extracted `_LogEntryTile` StatelessWidget → `log_page/entry_tile.dart`
- Extracted `_LogFilterBar` StatelessWidget (search field + filter chips) → `log_page/filter_bar.dart`
- Extracted `_LogLevelSelector` StatelessWidget (AppBar level button + bottom sheet picker) → `log_page/log_level_selector.dart`

**`lib/pages/settings_page/audio.dart`** (876 → 78 lines)
- Extracted `_ReplayGainSection`, `_ReplayGainModePicker`, `_ModeOption`, `_ModeChip` → `settings_page/audio/replaygain_section.dart`
- Extracted `_LoudnessNormSection` → `settings_page/audio/loudness_section.dart`
- Extracted `_CrossfeedSection` → `settings_page/audio/crossfeed_section.dart`
- Extracted `_CrossfadePicker` → `settings_page/audio/crossfade_picker.dart`
- Extracted `_BatchScanSection`, `_ScanIdleRow`, `_ScanProgressRow`, `_ScanResultRow` → `settings_page/audio/batch_scan_section.dart`
- Added 5 new `part` directives to `settings_page.dart`

**`lib/widgets/pages/library_sections/detail.dart`** (606 → 255 lines)
- Extracted `_PlaylistBannerCard` → `library_sections/detail/playlist_banner_card.dart`
- Extracted `_StickyLibraryControlsDelegate` + `_kLibraryControlsHeight` → `library_sections/detail/sticky_controls_delegate.dart`
- Extracted `_SongsListView` StatelessWidget → `library_sections/detail/songs_list_view.dart`
- Extracted `_AlbumsListView` StatelessWidget → `library_sections/detail/albums_list_view.dart`
- Extracted `_ArtistsGridView` StatelessWidget → `library_sections/detail/artists_grid_view.dart`
- Extracted `_FrequentSongsView` StatelessWidget → `library_sections/detail/frequent_songs_view.dart`
- Added 6 new `part` directives to `library_sections.dart`

**`lib/services/audio/playback_manager.dart`** — not split
- File assessed: all DSP controls are static methods on a single class; Dart cannot split a class body across files; splitting would create files of <50 lines each with no reduction in coupling. Existing file comment confirmed this decision.

### Validation
- `flutter analyze`: **0 issues found** ✓
- All public APIs unchanged ✓
- All `part`/`part of` chains verified ✓
- No logic, UI, or behavior changes ✓
