---
name: Artwork cache storage location
description: Where artwork WebP files are stored and how the pre-scan ID set works
---

# Artwork cache storage location

## The rule
- **Dart**: `ArtworkRepository` uses `getApplicationSupportDirectory()` (not `getApplicationCacheDirectory()`).
- **Kotlin**: `ArtworkCacheManager` uses `context.filesDir` (not `context.cacheDir`).
- Path: `{supportDir/filesDir}/artwork/{songId}.webp`

**Why:** `cacheDir` on Android (and its Dart equivalent) can be cleared by MIUI/system storage-free at any time, wiping all cached artwork. `filesDir` persists across restarts.

**How to apply:** Any new code that resolves or constructs artwork paths must use the same directories. Do not mix the two.

## Pre-scan ID set (`_diskCachedIds`)
- `warmUp()` scans `{supportDir}/artwork/` once at startup and populates `Set<int> _diskCachedIds`.
- `getProviderSync()` uses `_diskCachedIds.contains(songId)` (O(1)) instead of `File.statSync()` per call.
- `_resolvePath()` (async) adds to `_diskCachedIds` after confirming a file on disk or after native extraction.

## Critical invariant: `_paths` only holds async-validated entries
`getProviderSync()` must NOT call `_addToMemory()` for the `_diskCachedIds` branch.
It only calls `_wrapProvider()` directly (which still uses `_providers` cache for FileImage reuse).

**Why:** `_paths` is trusted by `getPath()` — a hit short-circuits all disk/native checks. If `getProviderSync()` added stale pre-scan entries into `_paths`, native LRU eviction post-warmup would leave `getPath()` returning deleted paths forever. Keeping `_paths` clean means the first async `getPath()` call will properly verify/re-extract and then correctly populate `_paths`.

## Migration note
On first launch after this change, old artwork in `cacheDir/artwork/` is abandoned (not deleted). The native layer re-extracts all artwork into `filesDir/artwork/` on demand — one-time cost, no data loss.
