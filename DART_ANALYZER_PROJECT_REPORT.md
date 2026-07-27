# Dart Analyzer Report — Project Scope

**Scope:** `dart analyze --format=json lib test`  
**Date:** 2026-07-27  
**Input:** `/tmp/project-dart-analyze.json`  
**Change policy:** No source code and no `analysis_options.yaml` changes were made.

## Summary

The analysis was explicitly limited to `lib/` and `test/`, so the local Flutter SDK under `flutter-ws/**` was not analyzed.

| Metric | Count |
|---|---:|
| Total diagnostics | 13,901 |
| Files with diagnostics | 288 |
| `lib/` diagnostics | 13,542 |
| `test/` diagnostics | 359 |
| Compile-time errors | 14 |
| Static warnings | 28 |
| Lint infos | 13,859 |

### Severity and analyzer type

| Severity | Analyzer type | Count |
|---|---|---:|
| ERROR | `COMPILE_TIME_ERROR` | 14 |
| WARNING | `STATIC_WARNING` | 28 |
| INFO | `LINT` | 13,859 |

## Top 100 files in `lib/`

| Rank | Count | File |
|---:|---:|---|
| 1 | 625 | `lib/services/audio/audio_effects_service/service.dart` |
| 2 | 431 | `lib/services/replay_gain_service/service.dart` |
| 3 | 397 | `lib/services/audio_service/service.dart` |
| 4 | 384 | `lib/widgets/unified_morph_player.dart` |
| 5 | 344 | `lib/services/audio/media3/media3_playback_bridge.dart` |
| 6 | 265 | `lib/services/audio/playback_manager.dart` |
| 7 | 252 | `lib/services/song_metadata_service/service.dart` |
| 8 | 240 | `lib/services/media_store_service.dart` |
| 9 | 238 | `lib/pages/settings_page/changelog_data.dart` |
| 10 | 222 | `lib/widgets/player/player_content/content.dart` |
| 11 | 219 | `lib/pages/settings/equalizer_page/band_slider.dart` |
| 12 | 209 | `lib/services/lyrics_service/providers/apple_music_provider.dart` |
| 13 | 187 | `lib/pages/playlist_page.dart` |
| 14 | 184 | `lib/services/artwork_repository.dart` |
| 15 | 161 | `lib/widgets/song_context_menu.dart` |
| 16 | 158 | `lib/services/lyrics_service/fetch_manager.dart` |
| 17 | 146 | `lib/widgets/player/player_song_info_sheet/content.dart` |
| 18 | 142 | `lib/services/lyrics_service/providers/kuwo_provider.dart` |
| 19 | 141 | `lib/services/lyrics_service/lrc_parser.dart` |
| 20 | 137 | `lib/widgets/pages/album_sections.dart` |
| 21 | 133 | `lib/widgets/player/player_more_menu.dart` |
| 22 | 133 | `lib/services/lyrics_service/providers/kugou_provider.dart` |
| 23 | 122 | `lib/pages/log_page.dart` |
| 24 | 121 | `lib/services/playlist_service.dart` |
| 25 | 118 | `lib/widgets/player/synced_lyrics_view/elrc_word.dart` |
| 26 | 113 | `lib/services/native/bridges/ffmpeg_decoder_bridge.dart` |
| 27 | 110 | `lib/widgets/player/player_progress_section.dart` |
| 28 | 107 | `lib/widgets/pages/library_sections/detail.dart` |
| 29 | 106 | `lib/services/lyrics_service/cache_manager.dart` |
| 30 | 106 | `lib/main/main.dart` |
| 31 | 105 | `lib/pages/settings/equalizer_page/page.dart` |
| 32 | 102 | `lib/services/lyrics_service/providers/netease_provider.dart` |
| 33 | 102 | `lib/services/native_palette_service.dart` |
| 34 | 100 | `lib/services/lyrics_service/providers/qq_music_provider.dart` |
| 35 | 98 | `lib/models/lyrics_settings.dart` |
| 36 | 95 | `lib/services/log_service/service.dart` |
| 37 | 94 | `lib/widgets/pages/radio_sections/stations.dart` |
| 38 | 93 | `lib/bottom_nav_bar/bottom_nav/state.dart` |
| 39 | 90 | `lib/themes/theme_controller.dart` |
| 40 | 85 | `lib/pages/settings_page.dart` |
| 41 | 84 | `lib/utils/data/search_categories.dart` |
| 42 | 83 | `lib/widgets/song_artwork.dart` |
| 43 | 81 | `lib/models/local_song.dart` |
| 44 | 80 | `lib/services/lyrics_service/providers/lrclib_provider.dart` |
| 45 | 80 | `lib/widgets/player/player_sheet/state.dart` |
| 46 | 76 | `lib/widgets/player/synced_lyrics_view/karaoke_line_painter.dart` |
| 47 | 76 | `lib/widgets/player/synced_lyrics_view/state_timeline.dart` |
| 48 | 75 | `lib/widgets/song_context_menu/add_to_playlist_sheet.dart` |
| 49 | 73 | `lib/services/lyrics_service/providers/local_file_provider.dart` |
| 50 | 70 | `lib/main.dart` |
| 51 | 69 | `lib/widgets/player/player_content/queue_overlay.dart` |
| 52 | 68 | `lib/widgets/player/player_up_next_card.dart` |
| 53 | 66 | `lib/widgets/pages/library_sections/state.dart` |
| 54 | 65 | `lib/services/history_service.dart` |
| 55 | 65 | `lib/pages/settings_page/audio/replaygain_section.dart` |
| 56 | 65 | `lib/widgets/player/synced_lyrics_view/state.dart` |
| 57 | 63 | `lib/pages/log_page/filter_bar.dart` |
| 58 | 62 | `lib/services/lyrics_service/providers/provider_http.dart` |
| 59 | 62 | `lib/widgets/player/player_content/lyrics_pickers.dart` |
| 60 | 59 | `lib/services/media_capabilities_service/service.dart` |
| 61 | 59 | `lib/widgets/pages/radio_sections/station_card.dart` |
| 62 | 59 | `lib/widgets/player/player_background/fog_painter.dart` |
| 63 | 58 | `lib/services/open_file_service.dart` |
| 64 | 56 | `lib/pages/settings_page/about_app_page.dart` |
| 65 | 55 | `lib/widgets/player/player_content.dart` |
| 66 | 54 | `lib/services/native/native_module_registry.dart` |
| 67 | 54 | `lib/widgets/pages/artist_sections.dart` |
| 68 | 53 | `lib/pages/settings/settings_widgets/slider.dart` |
| 69 | 53 | `lib/pages/settings_page/audio/batch_scan_section.dart` |
| 70 | 53 | `lib/pages/settings_page/playback_engine.dart` |
| 71 | 53 | `lib/services/audio_playback_state.dart` |
| 72 | 52 | `lib/themes/app_theme_extension.dart` |
| 73 | 51 | `lib/domain/app_router.dart` |
| 74 | 51 | `lib/models/song_info.dart` |
| 75 | 51 | `lib/pages/settings_page/language_section.dart` |
| 76 | 50 | `lib/pages/settings_page/debug.dart` |
| 77 | 50 | `lib/widgets/pages/home/artists_section/state.dart` |
| 78 | 47 | `lib/widgets/pages/home_sections.dart` |
| 79 | 46 | `lib/models/loudness_data.dart` |
| 80 | 46 | `lib/services/sleep_timer_service.dart` |
| 81 | 46 | `lib/widgets/player/player_background/artwork.dart` |
| 82 | 46 | `lib/widgets/player/player_content/lyrics_overlay.dart` |
| 83 | 45 | `lib/bottom_nav_bar/bottom_nav.dart` |
| 84 | 45 | `lib/services/audio/device_dsp.dart` |
| 85 | 45 | `lib/widgets/common/scrolling_page_chrome/app_bar.dart` |
| 86 | 45 | `lib/widgets/pages/library_sections.dart` |
| 87 | 44 | `lib/main/app_state.dart` |
| 88 | 43 | `lib/models/playlist.dart` |
| 89 | 43 | `lib/pages/music_list/state.dart` |
| 90 | 43 | `lib/services/lyrics_service/provider.dart` |
| 91 | 42 | `lib/pages/settings_page/audio/loudness_section.dart` |
| 92 | 42 | `lib/widgets/play_shuffle_buttons.dart` |
| 93 | 41 | `lib/widgets/common_actions.dart` |
| 94 | 41 | `lib/services/player_sheet_controller.dart` |
| 95 | 40 | `lib/pages/settings/sleep_timer_page.dart` |
| 96 | 40 | `lib/services/lyrics_service/providers/embedded_provider.dart` |
| 97 | 40 | `lib/widgets/pages/home/albums_section/state.dart` |
| 98 | 40 | `lib/widgets/player/synced_lyrics_view/state_scroll.dart` |
| 99 | 39 | `lib/pages/settings/sleep_timer_page/presets.dart` |
| 100 | 37 | `lib/services/native/bridges/native_dsp_bridge.dart` |

## Diagnostic codes

The following table includes every diagnostic code. For each code, the affected files are listed in descending order, with at most 10 files shown. A file entry is formatted as `count × path`.

| Code | Total | Top affected files |
|---|---:|---|
| `prefer_double_quotes` | 3,012 | 229 × `lib/services/audio/audio_effects_service/service.dart`; 145 × `lib/pages/settings_page/changelog_data.dart`; 115 × `lib/services/media_store_service.dart`; 102 × `lib/services/audio_service/service.dart`; 98 × `lib/services/audio/media3/media3_playback_bridge.dart`; 73 × `lib/services/replay_gain_service/service.dart`; 71 × `lib/widgets/player/player_song_info_sheet/content.dart`; 64 × `lib/services/song_metadata_service/service.dart`; 63 × `test/models/local_song_test.dart`; 61 × `test/services/lyrics_service/lrc_parser_test.dart` |
| `always_specify_types` | 2,715 | 128 × `lib/services/audio/audio_effects_service/service.dart`; 118 × `lib/services/replay_gain_service/service.dart`; 97 × `lib/widgets/unified_morph_player.dart`; 72 × `lib/services/audio/media3/media3_playback_bridge.dart`; 71 × `lib/services/audio_service/service.dart`; 70 × `lib/widgets/player/player_content/content.dart`; 60 × `lib/pages/settings/equalizer_page/band_slider.dart`; 54 × `lib/services/song_metadata_service/service.dart`; 51 × `lib/pages/playlist_page.dart`; 43 × `lib/services/playlist_service.dart` |
| `prefer_final_parameters` | 1,435 | 65 × `lib/services/audio/playback_manager.dart`; 63 × `lib/services/audio/media3/media3_playback_bridge.dart`; 52 × `lib/services/replay_gain_service/service.dart`; 43 × `lib/services/audio/audio_effects_service/service.dart`; 41 × `lib/widgets/player/player_content/content.dart`; 32 × `lib/services/audio_service/service.dart`; 27 × `lib/pages/settings/equalizer_page/band_slider.dart`; 26 × `lib/widgets/unified_morph_player.dart`; 25 × `lib/services/artwork_repository.dart`; 24 × `lib/bottom_nav_bar/bottom_nav/state.dart` |
| `unnecessary_final` | 1,367 | 69 × `lib/widgets/unified_morph_player.dart`; 66 × `lib/services/replay_gain_service/service.dart`; 54 × `lib/services/audio/audio_effects_service/service.dart`; 53 × `lib/services/audio_service/service.dart`; 44 × `lib/services/song_metadata_service/service.dart`; 35 × `lib/services/lyrics_service/providers/apple_music_provider.dart`; 34 × `lib/pages/settings/equalizer_page/band_slider.dart`; 32 × `lib/services/artwork_repository.dart`; 26 × `lib/pages/playlist_page.dart`; 25 × `lib/services/lyrics_service/lrc_parser.dart` |
| `specify_nonobvious_local_variable_types` | 1,174 | 68 × `lib/widgets/unified_morph_player.dart`; 60 × `lib/services/replay_gain_service/service.dart`; 51 × `lib/services/audio/audio_effects_service/service.dart`; 45 × `lib/services/audio_service/service.dart`; 35 × `lib/services/song_metadata_service/service.dart`; 31 × `lib/services/lyrics_service/providers/apple_music_provider.dart`; 26 × `lib/pages/settings/equalizer_page/band_slider.dart`; 25 × `lib/services/artwork_repository.dart`; 24 × `lib/pages/playlist_page.dart`; 20 × `lib/widgets/song_context_menu.dart` |
| `public_member_api_docs` | 820 | 51 × `lib/services/audio/playback_manager.dart`; 50 × `lib/services/audio/media3/media3_playback_bridge.dart`; 42 × `lib/services/audio/audio_effects_service/service.dart`; 37 × `lib/models/song_info.dart`; 26 × `lib/services/audio_playback_state.dart`; 25 × `lib/themes/theme_controller.dart`; 21 × `lib/models/local_song.dart`; 18 × `lib/models/loudness_data.dart`; 18 × `lib/services/log_service/service.dart`; 17 × `lib/services/audio_service/service.dart` |
| `lines_longer_than_80_chars` | 593 | 54 × `lib/pages/settings_page/changelog_data.dart`; 49 × `lib/widgets/unified_morph_player.dart`; 30 × `lib/services/audio_service/service.dart`; 21 × `lib/themes/app_theme_extension.dart`; 18 × `lib/widgets/player/player_content/content.dart`; 16 × `lib/pages/settings/equalizer_page/page.dart`; 16 × `lib/services/audio/audio_effects_service/service.dart`; 15 × `lib/pages/settings/equalizer_page/band_slider.dart`; 14 × `lib/themes/app_themes.dart`; 12 × `lib/main/main.dart` |
| `always_put_control_body_on_new_line` | 480 | 26 × `lib/services/replay_gain_service/service.dart`; 22 × `lib/services/lyrics_service/providers/apple_music_provider.dart`; 21 × `lib/services/audio/audio_effects_service/service.dart`; 20 × `lib/services/artwork_repository.dart`; 19 × `lib/services/audio_service/service.dart`; 17 × `lib/services/audio/playback_manager.dart`; 14 × `lib/pages/settings/equalizer_page/band_slider.dart`; 14 × `lib/widgets/player/synced_lyrics_view/state.dart`; 11 × `lib/pages/playlist_page.dart`; 11 × `lib/services/lyrics_service/lrc_parser.dart` |
| `always_use_package_imports` | 356 | 16 × `lib/widgets/player/player_content.dart`; 16 × `lib/widgets/song_context_menu.dart`; 15 × `lib/services/lyrics_service/fetch_manager.dart`; 14 × `lib/widgets/pages/radio_sections.dart`; 12 × `lib/services/audio_service.dart`; 11 × `lib/widgets/pages/home_sections.dart`; 11 × `lib/widgets/pages/library_sections.dart`; 10 × `lib/widgets/unified_morph_player.dart`; 9 × `lib/services/audio/playback_manager.dart`; 8 × `lib/widgets/pages/browse_sections.dart` |
| `diagnostic_describe_all_properties` | 330 | 15 × `lib/widgets/player/player_more_menu.dart`; 11 × `lib/pages/settings/settings_widgets/slider.dart`; 10 × `lib/pages/log_page/filter_bar.dart`; 9 × `lib/widgets/player/player_secondary_controls/controls.dart`; 9 × `lib/widgets/player/synced_lyrics_view/karaoke_line.dart`; 8 × `lib/pages/settings/equalizer_page/band_slider.dart`; 8 × `lib/widgets/player/player_content/content.dart`; 8 × `lib/widgets/player/player_sheet/state.dart`; 7 × `lib/widgets/pages/radio_sections/station_card.dart`; 7 × `lib/widgets/player/player_content/lyrics_overlay.dart` |
| `omit_obvious_property_types` | 164 | 15 × `lib/services/audio/media3/media3_playback_bridge.dart`; 8 × `lib/widgets/player/player_progress_section.dart`; 8 × `lib/widgets/player/synced_lyrics_view/state.dart`; 7 × `lib/widgets/unified_morph_player.dart`; 6 × `lib/services/audio/playback_manager.dart`; 5 × `lib/services/native/bridges/ffmpeg_decoder_bridge.dart`; 5 × `lib/services/player_sheet_controller.dart`; 4 × `lib/services/audio_service/service.dart`; 4 × `lib/services/media_store_service.dart`; 4 × `lib/widgets/pages/search_sections/state.dart` |
| `prefer_relative_imports` | 146 | 24 × `lib/main.dart`; 18 × `lib/bottom_nav_bar/bottom_nav.dart`; 16 × `lib/pages/settings_page.dart`; 11 × `lib/pages/playlist_page.dart`; 8 × `lib/domain/app_router.dart`; 5 × `lib/pages/log_page.dart`; 5 × `lib/widgets/player/player_up_next_card.dart`; 4 × `lib/pages/settings/settings_widgets.dart`; 4 × `lib/pages/settings/sleep_timer_page.dart`; 4 × `lib/services/open_file_service.dart` |
| `prefer_int_literals` | 137 | 28 × `lib/pages/settings/equalizer_page/page.dart`; 22 × `lib/services/audio/audio_effects_service/service.dart`; 9 × `lib/widgets/unified_morph_player.dart`; 9 × `test/models/loudness_data_test.dart`; 7 × `lib/pages/settings/equalizer_page/band_slider.dart`; 5 × `lib/services/player_sheet_controller.dart`; 4 × `lib/models/lyrics_settings.dart`; 4 × `lib/pages/settings_page/audio/loudness_section.dart`; 4 × `lib/widgets/player/player_background/artwork.dart`; 4 × `lib/widgets/player/player_progress_section.dart` |
| `discarded_futures` | 135 | 9 × `lib/widgets/unified_morph_player.dart`; 6 × `lib/pages/log_page.dart`; 6 × `lib/pages/settings/equalizer_page/band_slider.dart`; 6 × `lib/widgets/pages/radio_sections/stations.dart`; 5 × `lib/domain/app_router.dart`; 4 × `lib/pages/playlist_page.dart`; 4 × `lib/services/audio_service/service.dart`; 4 × `lib/widgets/player/player_progress_section.dart`; 4 × `lib/widgets/song_context_menu.dart`; 3 × `lib/pages/settings_page/audio/replaygain_section.dart` |
| `prefer_expression_function_bodies` | 124 | 5 × `lib/widgets/unified_morph_player.dart`; 4 × `lib/pages/settings/equalizer_page/band_slider.dart`; 4 × `lib/widgets/player/player_content/lyrics_pickers.dart`; 3 × `lib/models/local_song.dart`; 3 × `lib/pages/settings/equalizer_page/page.dart`; 3 × `lib/widgets/player/player_content/queue_overlay.dart`; 3 × `lib/widgets/player/player_secondary_controls/controls.dart`; 3 × `lib/widgets/player/player_up_next_card.dart`; 2 × `lib/bottom_nav_bar/bottom_nav/state.dart`; 2 × `lib/main/app_state.dart` |
| `sort_constructors_first` | 117 | 5 × `lib/widgets/player/player_more_menu.dart`; 4 × `lib/services/native/bridges/ffmpeg_decoder_bridge.dart`; 3 × `lib/pages/playlist_page.dart`; 3 × `lib/widgets/pages/radio_sections/station_card.dart`; 3 × `lib/widgets/player/player_secondary_controls/controls.dart`; 2 × `lib/models/local_song.dart`; 2 × `lib/models/loudness_data.dart`; 2 × `lib/models/playlist.dart`; 2 × `lib/services/audio/media3/media3_playback_bridge.dart`; 2 × `lib/services/lyrics_service/cache_manager.dart` |
| `always_put_required_named_parameters_first` | 116 | 9 × `lib/widgets/player/synced_lyrics_view/karaoke_line.dart`; 8 × `lib/models/song_info.dart`; 7 × `lib/widgets/player/player_content/content.dart`; 6 × `lib/pages/settings/settings_widgets/slider.dart`; 5 × `lib/widgets/pages/playlist_song_tile.dart`; 5 × `lib/widgets/player/player_secondary_controls/controls.dart`; 4 × `lib/widgets/pages/radio_sections/station_card.dart`; 4 × `lib/widgets/player/player_content/queue_overlay.dart`; 4 × `lib/widgets/song_context_menu.dart`; 3 × `lib/pages/playlist_page.dart` |
| `avoid_catches_without_on_clauses` | 90 | 7 × `lib/services/audio_service/service.dart`; 7 × `lib/services/media_store_service.dart`; 6 × `lib/services/replay_gain_service/service.dart`; 5 × `lib/services/song_metadata_service/service.dart`; 4 × `lib/services/audio/media3/media3_playback_bridge.dart`; 3 × `lib/services/artwork_repository.dart`; 3 × `lib/services/audio/playback_manager.dart`; 3 × `lib/services/lyrics_service/cache_manager.dart`; 3 × `lib/services/lyrics_service/providers/local_file_provider.dart`; 3 × `lib/services/native/native_module_registry.dart` |
| `directives_ordering` | 70 | 13 × `lib/pages/settings_page.dart`; 11 × `lib/main.dart`; 6 × `lib/widgets/player/player_content.dart`; 4 × `lib/bottom_nav_bar/bottom_nav.dart`; 4 × `lib/services/audio/playback_manager.dart`; 4 × `lib/services/audio_service.dart`; 3 × `lib/widgets/player/player_more_menu.dart`; 2 × `lib/domain/app_router.dart`; 2 × `lib/services/native/native_module_registry.dart`; 2 × `lib/widgets/player/player_up_next_card.dart` |
| `prefer_single_quotes` | 64 | 64 × `lib/utils/data/search_categories.dart` |
| `comment_references` | 53 | 7 × `lib/services/artwork_repository.dart`; 7 × `lib/services/native/models/native_module_status.dart`; 5 × `lib/services/lyrics_service/provider.dart`; 4 × `lib/services/audio/media3/media3_playback_bridge.dart`; 4 × `lib/services/media_capabilities_service/service.dart`; 3 × `lib/services/media_store_service.dart`; 3 × `lib/services/native/native_module_registry.dart`; 3 × `lib/widgets/player/synced_lyrics_view/elrc_word.dart`; 3 × `lib/widgets/song_artwork.dart`; 2 × `lib/services/replay_gain_service/service.dart` |
| `omit_local_variable_types` | 51 | 6 × `lib/widgets/player/synced_lyrics_view/state_build.dart`; 5 × `lib/services/lyrics_service/lrc_parser.dart`; 4 × `lib/services/lyrics_service/providers/apple_music_provider.dart`; 4 × `lib/widgets/player/synced_lyrics_view/elrc_word.dart`; 3 × `lib/services/audio_service/service.dart`; 3 × `lib/services/lyrics_service/fetch_manager.dart`; 3 × `lib/services/song_metadata_service/service.dart`; 2 × `lib/services/lyrics_service/cache_manager.dart`; 2 × `lib/services/lyrics_service/providers/provider_http.dart`; 2 × `lib/widgets/player/synced_lyrics_view/karaoke_line.dart` |
| `avoid_redundant_argument_values` | 49 | 4 × `lib/widgets/player/player_content/content.dart`; 3 × `lib/widgets/unified_morph_player.dart`; 2 × `lib/pages/music_list/state.dart`; 2 × `lib/pages/settings/equalizer_page/preset_chips.dart`; 2 × `lib/services/lyrics_service/providers/local_file_provider.dart`; 2 × `lib/themes/app_themes.dart`; 2 × `lib/widgets/pages/library_sections/detail.dart`; 2 × `lib/widgets/song_artwork.dart`; 2 × `lib/widgets/song_context_menu.dart`; 1 × `lib/pages/album_page.dart` |
| `avoid_positional_boolean_parameters` | 46 | 12 × `lib/services/audio/playback_manager.dart`; 10 × `lib/themes/theme_controller.dart`; 8 × `lib/services/audio/audio_effects_service/service.dart`; 6 × `lib/services/audio/media3/media3_playback_bridge.dart`; 3 × `lib/services/log_service/service.dart`; 2 × `lib/models/lyrics_settings.dart`; 1 × `lib/pages/settings/settings_widgets/toggle.dart`; 1 × `lib/pages/settings_page/glass_toggle.dart`; 1 × `lib/services/media_capabilities_service/service.dart`; 1 × `lib/services/up_next_settings.dart` |
| `avoid_dynamic_calls` | 44 | 10 × `lib/services/lyrics_service/providers/kuwo_provider.dart`; 8 × `lib/services/lyrics_service/providers/kugou_provider.dart`; 7 × `lib/services/lyrics_service/providers/netease_provider.dart`; 6 × `lib/widgets/player/player_song_info_sheet/content.dart`; 5 × `lib/services/lyrics_service/providers/qq_music_provider.dart`; 3 × `lib/widgets/player/player_more_menu.dart`; 2 × `lib/services/history_service.dart`; 2 × `lib/services/lyrics_service/providers/lrclib_provider.dart`; 1 × `lib/services/lyrics_service/providers/apple_music_provider.dart` |
| `cascade_invocations` | 26 | 7 × `lib/services/audio_service/service.dart`; 2 × `lib/services/history_service.dart`; 2 × `lib/widgets/pages/library_sections/detail.dart`; 2 × `lib/widgets/player/player_background/artwork.dart`; 2 × `lib/widgets/song_context_menu/add_to_playlist_sheet.dart`; 1 × `lib/pages/artist_list.dart`; 1 × `lib/pages/music_list/state.dart`; 1 × `lib/pages/playlist_page.dart`; 1 × `lib/pages/settings_page/changelog_page.dart`; 1 × `lib/pages/settings_page/page.dart` |
| `omit_obvious_local_variable_types` | 20 | 4 × `lib/services/lyrics_service/providers/apple_music_provider.dart`; 4 × `lib/widgets/player/synced_lyrics_view/elrc_word.dart`; 3 × `lib/services/lyrics_service/lrc_parser.dart`; 2 × `lib/services/lyrics_service/providers/provider_http.dart`; 2 × `lib/widgets/player/synced_lyrics_view/karaoke_line_painter.dart`; 2 × `lib/widgets/player/synced_lyrics_view/state_scroll.dart`; 1 × `lib/services/lyrics_service/providers/qq_music_provider.dart`; 1 × `lib/services/song_metadata_service/service.dart`; 1 × `test/services/lyrics_service/lrc_parser_test.dart` |
| `prefer_const_constructors` | 19 | 5 × `lib/pages/settings/settings_widgets/bit_perfect_lock.dart`; 3 × `lib/pages/log_page.dart`; 3 × `lib/pages/settings_page/debug.dart`; 2 × `lib/pages/settings/sleep_timer_page.dart`; 2 × `lib/pages/settings_page/about_app_page.dart`; 2 × `lib/widgets/pages/home/albums_section/state.dart`; 1 × `lib/pages/settings_page/language_section.dart`; 1 × `lib/widgets/player/player_sheet/state.dart` |
| `avoid_multiple_declarations_per_line` | 17 | 15 × `lib/widgets/player/player_background/fog_painter.dart`; 1 × `lib/widgets/player/synced_lyrics_view/karaoke_controller.dart`; 1 × `lib/widgets/player/synced_lyrics_view/state_indexing.dart` |
| `inference_failure_on_instance_creation` | 13 | 5 × `lib/domain/app_router.dart`; 2 × `lib/services/lyrics_service/providers/provider_http.dart`; 2 × `lib/widgets/pages/radio_sections/stations.dart`; 1 × `lib/pages/settings_page/system.dart`; 1 × `lib/services/artwork_repository.dart`; 1 × `lib/services/lyrics_service/fetch_manager.dart`; 1 × `lib/widgets/common_actions.dart` |
| `noop_primitive_operations` | 13 | 5 × `lib/services/audio/audio_effects_service/service.dart`; 2 × `lib/widgets/common/scrolling_page_chrome/app_bar.dart`; 2 × `lib/widgets/player/player_sheet/state.dart`; 1 × `lib/models/loudness_data.dart`; 1 × `lib/pages/settings/settings_widgets/slider.dart`; 1 × `lib/services/player_sheet_controller.dart`; 1 × `lib/widgets/player/player_content/content.dart` |
| `document_ignores` | 12 | 2 × `lib/services/artwork_repository.dart`; 1 × `lib/bottom_nav_bar/bottom_nav.dart`; 1 × `lib/pages/settings_page/audio/replaygain_section.dart`; 1 × `lib/services/audio/playback_manager.dart`; 1 × `lib/services/lyrics_service/fetch_manager.dart`; 1 × `lib/services/lyrics_service/providers/local_file_provider.dart`; 1 × `lib/services/media_capabilities_service/service.dart`; 1 × `lib/services/native_palette_service.dart`; 1 × `lib/services/replay_gain_service/service.dart`; 1 × `lib/services/song_metadata_service/service.dart` |
| `avoid_classes_with_only_static_members` | 11 | 1 × `lib/domain/app_router.dart`; 1 × `lib/pages/settings_page/debug_state.dart`; 1 × `lib/services/history_service.dart`; 1 × `lib/services/lyrics_service/lrc_parser.dart`; 1 × `lib/services/lyrics_service/providers/provider_http.dart`; 1 × `lib/services/lyrics_service/service.dart`; 1 × `lib/services/media_store_service.dart`; 1 × `lib/services/open_file_service.dart`; 1 × `lib/services/playlist_service.dart`; 1 × `lib/themes/app_themes.dart` |
| `argument_type_not_assignable` | 10 | 5 × `lib/services/history_service.dart`; 2 × `lib/widgets/pages/search_sections/cat_tile.dart`; 1 × `lib/services/lyrics_service/cancellation.dart`; 1 × `lib/services/media_store_service.dart`; 1 × `lib/widgets/pages/search_sections/cat_grid.dart` |
| `avoid_types_on_closure_parameters` | 7 | 5 × `lib/main/main.dart`; 1 × `lib/widgets/player/player_content/lyrics_overlay.dart`; 1 × `test/widget_test.dart` |
| `specify_nonobvious_property_types` | 7 | 2 × `lib/services/lyrics_service/cache_manager.dart`; 2 × `lib/widgets/player/player_content/lyrics_pickers.dart`; 1 × `lib/widgets/pages/radio_sections/stations.dart`; 1 × `lib/widgets/player/player_content/queue_control_button.dart`; 1 × `lib/widgets/player/player_more_menu.dart` |
| `avoid_annotating_with_dynamic` | 6 | 2 × `lib/widgets/player/player_song_info_sheet/content.dart`; 1 × `lib/services/audio_service/service.dart`; 1 × `lib/services/log_service/native_log_bridge.dart`; 1 × `lib/services/lyrics_service/providers/kuwo_provider.dart`; 1 × `lib/widgets/player/player_more_menu.dart` |
| `inference_failure_on_untyped_parameter` | 5 | 2 × `lib/main/app_state.dart`; 1 × `lib/services/audio/audio_effects_service/service.dart`; 1 × `lib/services/lyrics_service/cancellation.dart`; 1 × `lib/services/lyrics_service/fetch_manager.dart` |
| `strict_raw_type` | 5 | 2 × `lib/services/audio_service/service.dart`; 1 × `lib/services/audio/playback_manager.dart`; 1 × `lib/services/lyrics_service/providers/apple_music_provider.dart`; 1 × `lib/utils/data/search_categories.dart` |
| `inference_failure_on_function_invocation` | 5 | 3 × `lib/widgets/song_context_menu.dart`; 1 × `lib/services/media_store_service.dart`; 1 × `lib/widgets/pages/radio_sections/stations.dart` |
| `use_named_constants` | 5 | 2 × `lib/widgets/common_actions.dart`; 2 × `lib/widgets/song_context_menu.dart`; 1 × `lib/widgets/player/player_up_next_card.dart` |
| `return_of_invalid_type` | 3 | 2 × `lib/widgets/player/player_song_info_sheet/content.dart`; 1 × `lib/widgets/player/player_more_menu.dart` |
| `unnecessary_parenthesis` | 3 | 1 × `lib/pages/settings/equalizer_page/band_slider.dart`; 1 × `lib/services/lyrics_service/fetch_manager.dart`; 1 × `lib/services/lyrics_service/providers/apple_music_provider.dart` |
| `use_late_for_private_fields_and_variables` | 3 | 1 × `lib/services/audio/audio_session_handler/handler.dart`; 1 × `lib/widgets/pages/library_sections/detail.dart`; 1 × `lib/widgets/player/player_background/artwork.dart` |
| `use_setters_to_change_properties` | 3 | 1 × `lib/services/lyrics_service/fetch_manager.dart`; 1 × `lib/widgets/player/player_background/fog_painter.dart`; 1 × `lib/widgets/player/synced_lyrics_view.dart` |
| `unnecessary_ignore` | 2 | 1 × `lib/bottom_nav_bar/bottom_nav.dart`; 1 × `lib/services/audio/playback_manager.dart` |
| `cast_nullable_to_non_nullable` | 2 | 1 × `lib/pages/album_page.dart`; 1 × `lib/pages/artist_page.dart` |
| `use_if_null_to_convert_nulls_to_bools` | 2 | 1 × `lib/pages/log_page.dart`; 1 × `lib/pages/settings_page/bit_perfect.dart` |
| `prefer_if_elements_to_conditional_expressions` | 2 | 1 × `lib/pages/settings_page/debug.dart`; 1 × `lib/widgets/pages/library_sections/state.dart` |
| `prefer_final_locals` | 2 | 1 × `lib/services/lyrics_service/providers/kuwo_provider.dart`; 1 × `lib/services/lyrics_service/providers/qq_music_provider.dart` |
| `missing_code_block_language_in_doc_comment` | 2 | 1 × `lib/services/native/bridges/native_dsp_bridge.dart`; 1 × `lib/services/native/contracts/native_module.dart` |
| `flutter_style_todos` | 2 | 1 × `lib/widgets/common_actions.dart`; 1 × `test/widget_test.dart` |
| `use_build_context_synchronously` | 2 | 2 × `lib/widgets/song_context_menu/add_to_playlist_sheet.dart` |
| `invalid_assignment` | 1 | 1 × `lib/services/lyrics_service/cache_manager.dart` |
| `eol_at_end_of_file` | 1 | 1 × `lib/widgets/player/player_secondary_controls.dart` |
| `prefer_foreach` | 1 | 1 × `lib/widgets/player/synced_lyrics_view/karaoke_line_painter.dart` |
| `no_default_cases` | 1 | 1 × `lib/widgets/player/synced_lyrics_view/state.dart` |

## Non-lint diagnostics

### Compile-time errors — 14

| Code | Count | Main locations |
|---|---:|---|
| `argument_type_not_assignable` | 10 | `lib/services/history_service.dart` (5); `lib/services/lyrics_service/cancellation.dart`; `lib/services/media_store_service.dart`; `lib/widgets/pages/search_sections/cat_grid.dart`; `lib/widgets/pages/search_sections/cat_tile.dart` (2) |
| `return_of_invalid_type` | 3 | `lib/widgets/player/player_more_menu.dart`; `lib/widgets/player/player_song_info_sheet/content.dart` (2) |
| `invalid_assignment` | 1 | `lib/services/lyrics_service/cache_manager.dart` |

The error messages are primarily `dynamic` values being passed to or returned from typed APIs.

### Static warnings — 28

| Code | Count | Main locations |
|---|---:|---|
| `inference_failure_on_instance_creation` | 13 | `lib/domain/app_router.dart` (5); `lib/services/lyrics_service/providers/provider_http.dart` (2); `lib/widgets/pages/radio_sections/stations.dart` (2); five other files |
| `inference_failure_on_untyped_parameter` | 5 | `lib/main/app_state.dart` (2); three other files |
| `strict_raw_type` | 5 | `lib/services/audio_service/service.dart` (2); three other files |
| `inference_failure_on_function_invocation` | 5 | `lib/widgets/song_context_menu.dart` (3); two other files |

These warnings are strict type-inference issues, not missing imports or deprecated API warnings.

## Cause assessment

| Cause | Approx. count | Share | Assessment |
|---|---:|---:|---|
| Style and formatting lints | 13,834 | 99.52% | Dominant cause: quote style, explicit types, final parameters/locals, API docs, line length, formatting, and related style rules |
| Strict analyzer / type inference | 28 | 0.20% | `inference_failure_*` and `strict_raw_type` |
| Other compiler/analyzer diagnostics | 23 | 0.17% | Mostly the 14 compile-time type errors plus small analyzer-specific findings |
| Type/null-safety related lints | 16 | 0.12% | Assignment/return/cast-related findings |

### Main conclusion

The project-scoped total is driven overwhelmingly by the maximum lint set, not by broken imports, generated code, deprecated APIs, or null-safety failures. The 14 compile-time errors and 28 warnings are real type/inference findings, but together they represent only 42 of 13,901 diagnostics.

The earlier root-level total of 202,747 was inflated primarily because `flutter-ws/**` contained the local Flutter SDK and was included when analyzing from the repository root. This report excludes that directory by analyzing only `lib` and `test`.