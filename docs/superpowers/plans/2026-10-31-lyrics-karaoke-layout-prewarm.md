# Lyrics Karaoke Layout Prewarming — Implementation Plan

## Goal
Eliminate cold `TextPainter.layout()` and `getBoxesForSelection()` work from normal active-line transitions by retaining line layouts and prewarming the nearby timeline.

## Files and interfaces
- Add `lib/widgets/player/synced_lyrics_view/karaoke_layout_cache.dart`: bounded `KaraokeLayoutCache`, `KaraokeLineLayout`, and immutable word timing/box values.
- Add it as an import in `synced_lyrics_view.dart`.
- Add cache ownership, configuration tracking, and an idle-task generation counter to `state.dart`; implement scheduling in a dedicated `state_karaoke.dart` part.
- Change `state_build.dart` to derive the actual content width with `LayoutBuilder`, prepare the active line before paint, and pass the shared cache + line index to the active karaoke widget.
- Change `karaoke_line.dart` and `karaoke_line_painter.dart` so painters read cached TextPainters/word boxes instead of building and disposing their own layouts.
- Clear the cache when lyric data changes and dispose it with the state.
- Add cache-focused tests under `test/widgets/player/synced_lyrics_view/`.
- Follow repo rules: bump app version, add the top changelog entry, and update the player-widgets memory note + MEMORY index.

## Steps
1. Write tests for identical-key reuse, key changes, LRU capacity/eviction, and disposal; run them only if verification policy permits.
2. Implement the standalone bounded cache and make the tests target real cache behavior.
3. Integrate the cache with the karaoke painter and keep the existing paint algorithm/animations unchanged.
4. Add visibility-aware idle prewarming: active line first when visible, then current+1..current+8 and current-1..current-2 at `Priority.idle`; invalidate queued tasks with a generation token.
5. Add version/changelog/memory updates and format the changed Dart files.
6. Review the complete diff and run `flutter analyze` only. No APK build.

## Review focus
- No `TextPainter` is disposed while still referenced by a live painter.
- Width/style changes cannot reuse stale geometry.
- Old scheduled tasks cannot insert entries for a previous track or configuration.
- Cache remains bounded and releases native paragraph resources on eviction/disposal.
- A normal next-line transition should find the next line already prepared; cold seeks show the normal active `Text` row until the animation-priority prewarm completes, then activate karaoke painting.
