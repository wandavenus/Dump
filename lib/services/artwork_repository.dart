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
/// Layer 2 — Disk:    `{cacheDir}/artwork/{songId}.webp` written by the native
///                    [ArtworkCacheManager].  A Dart-side existence check skips
///                    the MethodChannel entirely on subsequent app launches.
/// Layer 3 — Native:  [MediaStoreService.getArtworkPath] → MethodChannel →
///                    native extraction + WebP encode + atomic save.
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

  // Deduplicate concurrent requests for the same songId.
  final Map<int, Future<String?>> _inFlight = {};

  // ── Cache directory ────────────────────────────────────────────────────────

  // Cached once; null until first call to [_resolvedCacheDir].
  String? _cacheDirPath;

  Future<String> _resolvedCacheDir() async {
    return _cacheDirPath ??= (await getApplicationCacheDirectory()).path;
  }

  /// Expected disk path for a song's artwork (without checking existence).
  Future<String> diskPath(int songId) async {
    final base = await _resolvedCacheDir();
    return '$base/artwork/$songId.webp';
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

    // Reuse existing FileImage to avoid allocating duplicate objects.
    final img = _providers.remove(songId) ?? FileImage(File(path));
    _providers[songId] = img;

    // Trim provider cache in sync with path cache.
    while (_providers.length > _maxEntries) {
      _providers.remove(_providers.keys.first);
    }

    if (targetSizePx != null && targetSizePx > 0) {
      return ResizeImage(img, width: targetSizePx, height: targetSizePx);
    }
    return img;
  }

  /// Returns raw bytes for [songId]'s artwork, reading from the cached WebP
  /// file.  Use this for blur / image-processing pipelines that require a
  /// [Uint8List] (e.g. [BlurredImageCache]).
  ///
  /// Returns null when the song has no artwork or the file cannot be read.
  Future<Uint8List?> getBytes(int songId) async {
    final path = await getPath(songId);
    if (path == null) return null;
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
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
    _inFlight.remove(songId);
  }

  /// Flush the entire memory cache (e.g. in response to a low-memory callback).
  void clearMemory() {
  _paths.clear();
  _providers.clear();

  PaintingBinding.instance.imageCache.clear();
}

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<String?> _resolvePath(int songId) async {
    // Layer 2: disk probe — skip MethodChannel if file already on disk.
    final expected = await diskPath(songId);
    final file = File(expected);
    final stat = await file.stat(); // ignore: avoid_slow_async_io
    if (stat.type != FileSystemEntityType.notFound && stat.size > 0) {
      _addToMemory(songId, expected);
      return expected;
    }

    // Layer 3: native extraction via MethodChannel.
    final nativePath = await MediaStoreService.getArtworkPath(songId);
    if (nativePath != null) {
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
