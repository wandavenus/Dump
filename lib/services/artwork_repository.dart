import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import 'media_store_service.dart';

/// Two-layer persistent artwork cache.
///
/// Layer 1 — Memory:  [LinkedHashMap] of up to [_maxEntries] (songId → file path).
///                    Evicts the LRU entry when full.
/// Layer 2 — Disk:    `{supportDir}/artwork/{songId}.webp` written by the native
///                    [ArtworkCacheManager].  A Dart-side pre-scanned ID set skips
///                    the MethodChannel entirely on subsequent app launches.
/// Layer 3 — Native:  [MediaStoreService.getArtworkPath] → MethodChannel →
///                    native extraction + WebP encode + atomic save.
///
/// Disk storage uses [getApplicationSupportDirectory] (not the system cache dir)
/// so files persist across app restarts and are never cleared by MIUI/Android's
/// storage-free mechanisms.
///
/// All async methods are safe to call concurrently: in-flight deduplication
/// prevents double-extraction of the same song.
class ArtworkRepository {
  ArtworkRepository._();
  static final ArtworkRepository instance = ArtworkRepository._();

  static const int _maxEntries = 300;

  // ── Memory caches ──────────────────────────────────────────────────────────

  // LRU map: insertion-order, move-to-back on hit.
  final LinkedHashMap<int, String>    _paths     = LinkedHashMap();
  // Reuse FileImage objects to avoid repeated object allocation.
  final LinkedHashMap<int, FileImage> _providers = LinkedHashMap();
  // Reuse artwork bytes to avoid repeated disk reads.
  final LinkedHashMap<int, Uint8List> _bytes = LinkedHashMap();
  // Deduplicate concurrent requests for the same songId.
  final Map<int, Future<String?>> _inFlight = {};

  // ── Disk cache directory + pre-scanned ID set ──────────────────────────────

  // Cached once; null until first call to [_resolvedCacheDir].
  String? _cacheDirPath;

  // Song IDs that are known to have a WebP file on disk, populated during
  // [warmUp] by scanning the artwork directory once.  Used by [getProviderSync]
  // to skip per-call File.statSync() — a Set.contains() O(1) lookup instead.
  //
  // This set can have stale entries if the native LRU eviction removes a file
  // mid-session; in that case FileImage will fail to load and the widget falls
  // back to its async path automatically, which is an acceptable trade-off for
  // the elimination of hundreds of statSync() calls on every scroll.
  final Set<int> _diskCachedIds = {};

  Future<String> _resolvedCacheDir() async {
    if (_cacheDirPath != null) return _cacheDirPath!;
    // Use app support directory — unlike the system cache dir this is never
    // cleared by MIUI or Android's automatic storage-free mechanisms.
    final base = (await getApplicationSupportDirectory()).path;
    _cacheDirPath = base;
    return base;
  }

  /// Resolves the support-directory path and pre-scans the artwork sub-directory
  /// to populate [_diskCachedIds].  Call once during app startup (awaited, before
  /// [runApp]) so [getProviderSync] can return immediately on the very first frame
  /// without any File I/O — this is what eliminates the placeholder flash on cold
  /// start (app killed / removed from recents).
  Future<void> warmUp() async {
    final base = await _resolvedCacheDir();
    final artworkDir = Directory('$base/artwork');
    if (!artworkDir.existsSync()) return;

    try {
      await for (final entity in artworkDir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.endsWith('.webp')) continue;
        final id = int.tryParse(name.substring(0, name.length - 5));
        if (id != null && id > 0) _diskCachedIds.add(id);
      }
    } catch (_) {
      // Non-fatal: if scan fails, getProviderSync falls back to async lookup.
    }
  }

  /// Expected disk path for a song's artwork (without checking existence).
  Future<String> diskPath(int songId) async {
    final base = await _resolvedCacheDir();
    return '$base/artwork/$songId.webp';
  }

  /// Synchronous best-effort lookup: returns a [FileImage] immediately if the
  /// artwork is already known (memory cache) or already on disk, without any
  /// `await` — so callers can populate their first frame with zero flash.
  ///
  /// Requires [warmUp] to have completed first; returns null otherwise (falls
  /// back to the async path, e.g. this is the very first extraction ever).
  ImageProvider? getProviderSync(int songId, {int? targetSizePx}) {
    if (songId <= 0) return null;

    final memorized = _paths[songId];
    if (memorized != null) {
      _touchMemory(songId, memorized);
      return _wrapProvider(songId, memorized, targetSizePx);
    }

    final base = _cacheDirPath;
    if (base == null) return null; // warmUp() hasn't resolved yet.

    // Use the pre-scanned set for an O(1) lookup — no File.statSync() per call.
    if (!_diskCachedIds.contains(songId)) return null;

    // Return the FileImage directly WITHOUT adding to _paths.
    //
    // _paths only holds async-validated entries (confirmed by disk stat or native
    // extraction in _resolvePath).  If we added here and native LRU later deleted
    // the file, a subsequent getPath() call would short-circuit on _paths and
    // return the stale path, skipping re-extraction.  By keeping _paths clean,
    // getPath() will run _resolvePath() → properly verify/re-extract, then add
    // to _paths with a confirmed path.
    //
    // _providers IS still used so we don't re-allocate FileImage objects on every
    // synchronous call for the same song.
    final expected = '$base/artwork/$songId.webp';
    return _wrapProvider(songId, expected, targetSizePx);
  }

  ImageProvider _wrapProvider(int songId, String path, int? targetSizePx) {
    final img = _providers.remove(songId) ?? FileImage(File(path));
    _providers[songId] = img;
    while (_providers.length > _maxEntries) {
      _providers.remove(_providers.keys.first);
    }
    if (targetSizePx != null && targetSizePx > 0) {
      return ResizeImage(img, width: targetSizePx, height: targetSizePx);
    }
    return img;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the absolute file path for [songId]'s cached WebP artwork.
  ///
  /// Load order: memory → disk → native extraction.
  /// Returns null when the song has no embedded artwork.
  Future<String?> getPath(int songId) async {
    if (songId <= 0) return null;

    // Layer 1: memory cache hit.
    final memorized = _paths[songId];
    if (memorized != null) {
      _touchMemory(songId, memorized);
      return memorized;
    }

    // Deduplicate: return the in-flight future if one already exists.
    if (_inFlight.containsKey(songId)) {
      return _inFlight[songId];
    }

    final future = _resolvePath(songId);
    _inFlight[songId] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(songId); // ignore: unawaited_futures
    }
  }

  /// Returns a [FileImage] provider backed by the cached WebP file.
  ///
  /// The returned provider is wrapped in [ResizeImage] at [targetSizePx] so
  /// Flutter's image cache only holds a downscaled decoded bitmap — not the
  /// full-resolution original.  Pass null to skip resizing.
  ///
  /// Returns null when the song has no artwork.
  Future<ImageProvider?> getProvider(
    int songId, {
    int? targetSizePx,
  }) async {
    final path = await getPath(songId);
    if (path == null) return null;

    return _wrapProvider(songId, path, targetSizePx);
  }

  /// Returns raw bytes for [songId]'s artwork, reading from the cached WebP
  /// file.  Use this for image-processing pipelines that require a
  /// [Uint8List] (e.g. [PaletteExtractor]).
  ///
  /// Returns null when the song has no artwork or the file cannot be read.
  Future<Uint8List?> getBytes(int songId) async {
  final cached = _bytes.remove(songId);
  if (cached != null) {
    _bytes[songId] = cached;
    return cached;
  }

  final path = await getPath(songId);
  if (path == null) return null;

  try {
    final bytes = await File(path).readAsBytes();

    _bytes[songId] = bytes;

    while (_bytes.length > _maxEntries) {
      _bytes.remove(_bytes.keys.first);
    }

    return bytes;
  } catch (_) {
    return null;
  }
}

  // ── Background prefetch (cache warm-up) ────────────────────────────────────

  // Guards against overlapping prefetch batches stepping on each other.
  bool _prefetching = false;

  /// Warms the disk cache for [songIds] so artwork is likely already on disk
  /// by the time the user scrolls to it, reducing how often the fallback
  /// icon is visible.
  ///
  /// Deliberately conservative for mid-range devices (e.g. Snapdragon 730,
  /// 6 GB RAM): only resolves [getPath] (disk path), never decodes bitmaps
  /// into memory via [getProvider]. Runs sequentially, one song at a time,
  /// with a small delay between each so it never competes with the UI
  /// thread or saturates storage I/O. Silently skips songs already cached.
  Future<void> prefetch(List<int> songIds, {int limit = 8}) async {
    if (_prefetching || songIds.isEmpty) return;
    _prefetching = true;
    try {
      for (final id in songIds.take(limit)) {
        if (id <= 0 || _paths.containsKey(id)) continue;
        try {
          await getPath(id);
        } catch (_) {
          // Never let a single failed extraction abort the batch.
        }
        // Yield back to the event loop between items so scrolling/animation
        // frames are never blocked by this low-priority background work.
        await Future.delayed(const Duration(milliseconds: 120));
      }
    } finally {
      _prefetching = false;
    }
  }

  // ── Active-queue registration ──────────────────────────────────────────────

  /// Tells the native cache manager which song IDs are currently in the
  /// playback queue.  These songs are never evicted by LRU cleanup, even when
  /// the cache exceeds the 500 MB limit.
  ///
  /// Call this whenever the playback queue changes (set, shuffle, add/remove).
  /// The call is fire-and-forget: it returns immediately after the MethodChannel
  /// invoke.  Errors are swallowed so a failure here never crashes the app.
  static Future<void> setActiveQueueIds(List<int> songIds) =>
      MediaStoreService.setActiveQueueIds(songIds);

  // ── Memory cache management ────────────────────────────────────────────────

  /// Remove [songId] from memory caches (e.g. after a library change).
  /// The disk file is NOT deleted; call native cleanupIfNeeded for that.
  void evict(int songId) {
  _paths.remove(songId);
  _providers.remove(songId);
  _bytes.remove(songId);
  _inFlight.remove(songId);
}

  /// Flush the entire memory cache (e.g. in response to a low-memory callback).
  void clearMemory() {
  _paths.clear();
  _providers.clear();
  _bytes.clear();

  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
}

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<String?> _resolvePath(int songId) async {
    // Layer 2: disk probe — skip MethodChannel if file already on disk.
    final expected = await diskPath(songId);
    final file = File(expected);
    final stat = await file.stat(); // ignore: avoid_slow_async_io
    if (stat.type != FileSystemEntityType.notFound && stat.size > 0) {
      _diskCachedIds.add(songId);
      _addToMemory(songId, expected);
      return expected;
    }

    // Layer 3: native extraction via MethodChannel.
    final nativePath = await MediaStoreService.getArtworkPath(songId);
    if (nativePath != null) {
      _diskCachedIds.add(songId);
      _addToMemory(songId, nativePath);
    }
    return nativePath;
  }

  void _addToMemory(int songId, String path) {
    // Move to back (MRU position) in the insertion-order LinkedHashMap.
    _paths.remove(songId);
    _paths[songId] = path;

    // Trim to max entries (removes from the front = LRU).
    while (_paths.length > _maxEntries) {
      final oldest = _paths.keys.first;
      _paths.remove(oldest);
      _providers.remove(oldest);
    }
  }

  void _touchMemory(int songId, String path) {
    // Re-insert at the back so the entry is treated as recently used.
    _paths.remove(songId);
    _paths[songId] = path;
  }
}
