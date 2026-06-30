---
name: ELRC word renderer
description: Architecture of the true word-timestamp karaoke renderer for Enhanced LRC files.
---

## Data flow (rawLrc pipeline)
- `LyricsProviderResult.rawLrc: String?` — all 8 providers populate this
- `LyricsCacheManager.getDisk()` — returns rawLrc from stored JSON 'lrc' key
- `LyricsFetchManager._saveToDisk()` — saves `result.rawLrc ?? _reconstructLrc(lines)` (preserves ELRC word data in disk cache)
- `LyricsResult.rawLrc: String?` — threaded from provider result → service → public result
- Call sites pass `rawLrc: result.rawLrc` to `SyncedLyricsView`

## Renderer files
- `elrc_word.dart` — `ElrcWord(text, start)` model + `ElrcWordExtractor.extractAll(rawLrc)`
- `view.dart` — added `rawLrc: String?` param (null default, backward compat)
- `state.dart` — `_elrcWordLines`, `_currentLineElrcWords` pre-computed per line; `_buildElrcText()` for ELRC, `_buildKaraokeText()` for standard

## ElrcWordExtractor contract
- Must produce exactly the same line count and order as `LrcParser.parseLrc()` on the same input
- Same offset extraction, same metadata skip, same leading-timestamp logic, same sort+deduplicate
- Returns `List<List<ElrcWord>>` — one entry per line, empty list for lines with no word timestamps

## Rendering algorithm (_buildElrcText)
- Binary search: last word with `word.start <= position` = currentWordIdx
- Fill fraction: `(position - wordStart) / (nextWordStart - wordStart)`
- Colors: past words → activeColor, current → lerp(dim, active, easeOut(fill)), future → dimColor
- Spaces between words inherit left neighbour's color

## Fallback behavior
- If `rawLrc == null`: standard char-fill renderer (unchanged)
- If line has no word timestamps (`_currentLineElrcWords.isEmpty`): standard char-fill renderer
- Mixed files (some lines ELRC, some plain): works per-line

## Key constraint
- `ElrcWordExtractor` is in the RENDERER LAYER (part of synced_lyrics_view.dart barrel)
- LrcParser, LyricLine, ParsedLyrics NOT modified
- rawLrc fields added with null defaults → all existing call sites backward-compatible

**Why:** Existing char-fill renderer estimated timing from character count / line duration — inaccurate for word-timed ELRC files. True ELRC needs actual word timestamps stored through the pipeline.
