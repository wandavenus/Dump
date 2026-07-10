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

## `getProviderSync()` DOES call `_addToMemory()` for pre-scanned songs
The `_diskCachedIds` branch in `getProviderSync()` calls `_addToMemory(songId, expected)`.

**Why:** Keeping `_paths` empty would force every `getPath()` async call to go through `_resolvePath()` → async `file.stat()` even for songs already confirmed by the warmup scan. That always triggers `setState()` in `_SongArtworkState._load()`, causing a visual flicker.  The warmup pre-scan is an equivalent confirmation to the old per-call `statSync()`, so adding to `_paths` here is correct.

## `_SongArtworkState._load()` skips `setState` when provider is unchanged
```dart
if (provider != _provider) {
  setState(() => _provider = provider);
}
```
`ImageProvider.==` is value-based (FileImage: path+scale; ResizeImage: inner+dimensions), so equal-content providers from sync and async paths compare as equal and no rebuild fires.

## Migration note
On first launch after this change, old artwork in `cacheDir/artwork/` is abandoned (not deleted). The native layer re-extracts all artwork into `filesDir/artwork/` on demand — one-time cost, no data loss.
