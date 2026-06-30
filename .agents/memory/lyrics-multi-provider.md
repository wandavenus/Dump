---
name: LyricsMultiProvider system
description: Architecture of the refactored multi-provider lyrics system with parallel online fetching and quality-priority selection.
---

## Overview
`LyricsService` (public API unchanged) now delegates to `LyricsFetchManager` which orchestrates multiple providers.

## File layout
```
lib/services/lyrics_service/
  quality.dart          — LyricsQuality enum (wordTimedLrc > charTimedLrc > lineTimedLrc > plainLrc > unsyncedLyrics > none)
  cancellation.dart     — CancellationToken (cancel all requests when song changes)
  provider.dart         — LyricsProvider abstract + LyricsQuery + LyricsProviderResult
  lrc_parser.dart       — LrcParser.parse() / parseLrc() / detectQuality() (extracted from old service.dart)
  cache_manager.dart    — LyricsCacheManager: memory cache + disk cache (SharedPrefs, 30-day TTL, key=artist|title|album|dur)
  rate_limiter.dart     — ProviderRateLimiter singleton (per-provider cooldown on 429)
  fetch_manager.dart    — LyricsFetchManager: orchestration logic
  providers/
    embedded_provider.dart    — Android MethodChannel getEmbeddedLyrics
    local_file_provider.dart  — .lrc / .elrc / .lrcx files (same dir + configured folder)
    lrclib_provider.dart      — lrclib.net (Enhanced LRC detection)
    netease_provider.dart     — NetEase Music (klyric = word-timed)
    kugou_provider.dart       — Kugou (base64 LRC, Enhanced LRC)
    kuwo_provider.dart        — Kuwo (lrclist array → LRC)
    qq_music_provider.dart    — QQ Music (base64, needs Referer header)
    musixmatch_provider.dart  — Musixmatch (needs userToken, Rich Sync)
    provider_http.dart        — shared HTTP helper: 5s connect / 15s read, 2 retries, exponential backoff
```

## Fetch pipeline
1. Memory cache (instant)
2. Failure TTL check (1h, skip if recently failed)
3. Disk cache (SharedPrefs, 30 days)
4. Local providers: Embedded → LocalFile (sequential, fast)
5. **All online providers run in PARALLEL**
6. Mark failure TTL if nothing found

## Parallel quality selection
- Global deadline: 15 seconds
- Once first result arrives: start 2-second upgrade window
- If wordTimedLrc arrives: return immediately (best possible)
- After 2s window or all done: return best quality found
- Each provider failure is isolated (others continue)

## Key design decisions
- `LyricsProviderResult` (provider output) is separate from `LyricsResult` (public API) to avoid circular imports
- `LyricsResult` extended with `quality: LyricsQuality` and `providerName: String` (named params with defaults → backward compat)
- `parseLrc` stays public static on `LyricsService` (backward compat) — delegates to `LrcParser.parseLrc()`
- `lyricsQualityFromJson()` is a top-level function (not extension static) due to Dart extension static accessibility rules
- `LyricsService.init()` must be called after `AudioEffectsService.init()` in main()

**Why:** Old system was sequential (embedded → file → internet/lrclib only). New system prioritizes word-timed karaoke from multiple sources without breaking any existing call sites.
