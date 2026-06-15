---
name: Part file architecture
description: How Dart part files are used for modularization throughout this codebase.
---

# Part File Modularization Pattern

**Rule:** All large service/widget files use Dart `part`/`part of` to split logic into focused sub-files without creating separate libraries.

## Structure
```
lib/services/audio_engine.dart          ← library (imports only)
lib/services/audio/audio_engine/
  output_mode.dart                      ← part of '../audio_engine.dart'
  player_slot.dart
  effects_control.dart                  ← library-level functions
  engine.dart                           ← class AudioEngine
```

## Key rules
1. Barrel file (`audio_engine.dart`) contains only `import` + `part` directives.
2. Part files begin with `part of '../audio_engine.dart';` (relative path).
3. Library-level functions in part files can access private (`_`) class members of any class in the same library — this is intentional and used throughout (e.g. `_engineSetSpatial` accesses `AudioEngine._effectsChannel`).
4. `compute()` requires a top-level or static function — library-level functions in part files qualify.
5. New part files must be added to the barrel **atomically** with any code that calls their functions, or the build will fail.

## Files modularized this way
- `audio_engine.dart` → output_mode, player_slot, effects_control, engine
- `audio_effects_service.dart` → presets, service
- `audio_service.dart` → service
- `crossfade_controller.dart` → fade_helpers, controller
- `loudness_analyzer.dart` → result, wav_parser, analyzer
- `lyrics_service.dart` → source, result, internet_fetch, service
- `song_metadata_service.dart` → formatters, service
- `settings_page.dart` → 20+ part files (debug, audio, lyrics, log_viewer, etc.)
- `local_song_card.dart` → card, menu, song_info_dialog, info, menu_item
- `player_secondary_controls.dart` → controls, queue_sheet
- `list.dart` → top_picks_data, page, state

**Why:** Keeps files ≤100 lines while sharing library scope (no need for public APIs between sub-files).

**How to apply:** When a file grows past ~100 lines, extract a logical section to a part file. Always add the `part` line to the barrel in the same edit as creating the part file.
