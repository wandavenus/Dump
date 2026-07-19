---
name: Lyrics Service Deep Map
description: Every file in lib/services/lyrics_service/ with class, role, and full fetch pipeline data flow.
---

# Lyrics Service — Deep Map

## Core Files (`lib/services/lyrics_service/`)

| File | Class(es) | Role |
|------|-----------|------|
| `service.dart` | `LyricsService` | Public facade; simplified `fetchLyrics` API + cache/cancel controls |
| `fetch_manager.dart` | `LyricsFetchManager` | Orchestrates full pipeline: memory cache → disk cache → local → online parallel |
| `cache_manager.dart` | `LyricsCacheManager`, `_CacheEntry` | Two-layer cache (memory + SharedPrefs disk); 30-day TTL; failed-search suppression 1h TTL |
| `provider.dart` | `LyricsProvider` (abstract), `LyricsProviderResult`, `LyricsQuery` | Standardizes search params + provider outputs |
| `quality.dart` | `LyricsQuality` (enum), `LyricsQualityX` | Ranks: `wordTimedLrc` > `syncedLrc` > `plainText` > `none` |
| `lrc_parser.dart` | `LrcParser`, `ParsedLyrics` | Parses LRC/Enhanced-LRC; handles metadata/offsets; auto-detects `LyricsQuality`; applies `[offset:]`; deduplicates timestamps |
| `result.dart` | `LyricsResult` | Final structure to UI: lines, source info, raw LRC |
| `source.dart` | `LyricsSource` (enum) | `embedded / localFile / internet / none` — for UI display |
| `cancellation.dart` | `CancellationToken`, `CancelledException` | Cancels previous request when song changes; providers abort HTTP ops |
| `rate_limiter.dart` | `ProviderRateLimiter` | Cooldown periods (default 60s) per provider on HTTP 429 |

## Providers (`lib/services/lyrics_service/providers/`)

| File | Provider | Notes |
|------|----------|-------|
| `embedded_provider.dart` | `EmbeddedProvider` | Extracts USLT/SYLT tags from audio file |
| `local_file_provider.dart` | `LocalFileProvider` | Searches `.lrc` files in configured local directory |
| `lrclib_provider.dart` | `LrclibProvider` | LRCLIB API; scans all results (not just data[0]) |
| `netease_provider.dart` | `NeteaseProvider` | NetEase Music |
| `kugou_provider.dart` | `KugouProvider` | Kugou Music |
| `kuwo_provider.dart` | `KuwoProvider` | Kuwo Music |
| `qq_music_provider.dart` | `QQMusicProvider` | QQ Music |
| `apple_music_provider.dart` | `AppleMusicProvider` | Apple Music (needs real subscriber token — not anonymous) |
| `provider_http.dart` | `ProviderHttp` | Shared resilient HTTP: timeouts + exponential backoff (2 retries) + rate-limiting + cancellation; 429 centralized here |

> **Removed:** Musixmatch (dead API, no token source)

## Fetch Pipeline Data Flow

```
LyricsService.fetchLyrics(metadata)
  → LyricsQuery created
  → LyricsFetchManager.fetch()
      → CancellationToken generated (previous token cancelled)
      → LyricsCacheManager: memory hit? → return
      → LyricsCacheManager: disk hit?   → return
      → EmbeddedProvider (sequential)
      → LocalFileProvider (sequential)
      → All online providers in parallel (Future.wait)
          ↓ results stream in as each provider resolves
      → Quality selection: best LyricsQuality wins
          • "upgrade window" 2s: wait for higher quality unless wordTimedLrc found immediately
      → Best result saved to memory + disk cache
  → LyricsResult returned to UI (SyncedLyricsView)
```

## Important Parsing Rules
- `[offset:]` tag applied during parse (shifts all timestamps)
- Duplicate timestamps deduplicated
- Plain-text (no timestamps) gets proportional timing over 210s default duration
- LRC encoding: UTF-8 with Latin-1 fallback
- ELRC word-level: `ElrcWordExtractor` in renderer; binary search on `word.start`; falls back to char-fill for lines without word data
