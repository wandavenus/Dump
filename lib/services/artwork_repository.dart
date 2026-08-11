import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

import 'media_store_service.dart';

/// Two-layer persistent artwork cache.
class ArtworkRepository {
  ArtworkRepository._();
  static final ArtworkRepository instance = ArtworkRepository._();

  static const int _maxEntries = 300;

  final LinkedHashMap<int, String> _paths = LinkedHashMap();
  final LinkedHashMap<int, FileImage> _providers = LinkedHashMap();
  final Map<int, Future<String?>> _inFlight = {};

  // Generation is incremented on explicit eviction. A result started before
  // that eviction belongs to the old generation and must never be published.
  final Map<int, int> _cacheGeneration = {};

  // New lookups wait for the invalidation delete to finish before probing disk.
  final Map<int, Future<void>> _pendingDeletes = {};

  String? _cacheDirPath;
  final Set<int> _diskCachedIds = {};
  double? _cachedDpr;

  int resolveTargetPx(double size) {
    final dpr = _cachedDpr ??=
        SchedulerBinding.instance.platformDispatcher.views.firstOrNull?.devicePixelRatio ??
        3.0;
    var target = (size * dpr).round();
    if (size < 80) return target < 460 ? 460 : target;
    if (size >= 170 && size < 250) target = (target * 1.75).round();
    return target;
  }

  Future<String> _resolvedCacheDir() async {
    if (_cacheDirPath != null) return _cacheDirPath!;
    final base = (await getApplicationSupportDirectory()).path;
    _cacheDirPath = base;
    return base;
  }

  Future<void> warmUp() async {
    if (kIsWeb) return;
    try {
      final base = await _resolvedCacheDir();
      final artworkDir = Directory('$base/artwork');
      if (!artworkDir.existsSync()) return;
      await for (final entity in artworkDir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.endsWith('.webp')) continue;
        final id = int.tryParse(name.substring(0, name.length - 5));
        if (id != null && id > 0) _diskCachedIds.add(id);
      }
    } on Exception catch (_) {}
  }

  Future<String> diskPath(int songId) async {
    final base = await _resolvedCacheDir();
    return '$base/artwork/$songId.webp';
  }

  ImageProvider? getProviderSync(int songId, {int? targetSizePx}) {
    if (songId <= 0) return null;
    final memorized = _paths[songId];
    if (memorized != null) {
      _touchMemory(songId, memorized);
      return _wrapProvider(songId, memorized, targetSizePx);
    }
    final base = _cacheDirPath;
    if (base == null) return null;
    if (!_diskCachedIds.contains(songId)) return null;
    final expected = '$base/artwork/$songId.webp';
    _addToMemory(songId, expected);
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

  Future<String?> getPath(int songId) async {
    if (songId <= 0) return null;

    while (true) {
      final pendingDelete = _pendingDeletes[songId];
      if (pendingDelete != null) await pendingDelete;

      final memorized = _paths[songId];
      if (memorized != null) {
        _touchMemory(songId, memorized);
        return memorized;
      }

      final generation = _cacheGeneration[songId] ?? 0;
      final future = _inFlight[songId] ??= _resolvePath(songId);
      try {
        final path = await future;

        if ((_cacheGeneration[songId] ?? 0) != generation) {
          if (path != null) {
            await MediaStoreService.deleteArtworkCache(songId);
            _diskCachedIds.remove(songId);
          }
          continue;
        }

        return path;
      } finally {
        if (identical(_inFlight[songId], future)) {
          _inFlight.remove(songId);
        }
      }
    }
  }

  Future<ImageProvider?> getProvider(int songId, {int? targetSizePx}) async {
    final path = await getPath(songId);
    if (path == null) return null;
    return _wrapProvider(songId, path, targetSizePx);
  }

  Future<void> prewarmImageCache(
    List<int> songIds, {
    int? targetSizePx,
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    if (_cacheDirPath == null) return;
    final seen = <int>{};
    final warmups = <Future<void>>[];
    for (final id in songIds) {
      if (!seen.add(id)) continue;
      final provider = getProviderSync(id, targetSizePx: targetSizePx);
      if (provider == null) continue;
      warmups.add(_decodeIntoImageCache(provider).timeout(timeout, onTimeout: () {}));
    }
    if (warmups.isNotEmpty) await Future.wait(warmups);
  }

  Future<void> _decodeIntoImageCache(ImageProvider provider) {
    final completer = Completer<void>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      },
      onError: (_, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  bool _prefetching = false;
  bool get isPrefetching => _prefetching;

  Future<void> prefetch(
    List<int> songIds, {
    int limit = 8,
    int concurrency = 2,
  }) async {
    if (_prefetching || songIds.isEmpty) return;
    _prefetching = true;
    try {
      final uniqueIds = songIds.where((id) => id > 0).toSet().toList();
      final targets = uniqueIds.take(limit).toList(growable: false);
      for (var i = 0; i < targets.length; i += concurrency) {
        final batch = targets.sublist(
          i,
          i + concurrency > targets.length ? targets.length : i + concurrency,
        );
        await Future.wait([for (final id in batch) _prefetchOne(id)]);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    } finally {
      _prefetching = false;
    }
  }

  Future<void> _prefetchOne(int id) async {
    if (_paths.containsKey(id)) return;
    try {
      await getPath(id);
    } on Exception catch (_) {}
  }

  bool _predecoding = false;
  final Set<int> _decoding = {};

  Future<void> predecode(
    List<int> songIds, {
    int? targetSizePx,
    int concurrency = 2,
    int limit = 20,
  }) async {
    if (_predecoding || songIds.isEmpty) return;
    _predecoding = true;
    try {
      final uniqueIds = songIds.where((id) => id > 0).toSet().toList();
      final targets = uniqueIds.take(limit).toList(growable: false);
      for (var i = 0; i < targets.length; i += concurrency) {
        final batch = targets.sublist(
          i,
          i + concurrency > targets.length ? targets.length : i + concurrency,
        );
        await Future.wait([for (final id in batch) _predecodeOne(id, targetSizePx)]);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    } finally {
      _predecoding = false;
    }
  }

  Future<void> _predecodeOne(int id, int? targetSizePx) async {
    if (!_decoding.add(id)) return;
    try {
      final provider = await getProvider(id, targetSizePx: targetSizePx);
      if (provider == null) return;
      if (await _imageCached(provider)) return;
      await _decodeIntoImageCache(provider);
    } on Exception catch (_) {
    } finally {
      _decoding.remove(id);
    }
  }

  Future<bool> _imageCached(ImageProvider provider) async {
    try {
      final key = await provider.obtainKey(ImageConfiguration.empty);
      return PaintingBinding.instance.imageCache.containsKey(key);
    } on Exception catch (_) {
      return false;
    }
  }

  static Future<void> setActiveQueueIds(List<int> songIds) =>
      MediaStoreService.setActiveQueueIds(songIds);

  void evict(int songId) {
    if (songId <= 0) return;

    _cacheGeneration[songId] = (_cacheGeneration[songId] ?? 0) + 1;
    _paths.remove(songId);
    _providers.remove(songId);
    _diskCachedIds.remove(songId);

    final deleteFuture = MediaStoreService.deleteArtworkCache(songId);
    _pendingDeletes[songId] = deleteFuture;
    unawaited(deleteFuture.whenComplete(() {
      if (identical(_pendingDeletes[songId], deleteFuture)) {
        _pendingDeletes.remove(songId);
      }
    }));
  }

  void clearMemory() {
    _paths.clear();
    _providers.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  Future<String?> _resolvePath(int songId) async {
    final expected = await diskPath(songId);
    final file = File(expected);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.notFound && stat.size > 0) {
      _diskCachedIds.add(songId);
      _addToMemory(songId, expected);
      return expected;
    }

    final nativePath = await MediaStoreService.getArtworkPath(songId);
    if (nativePath != null) {
      _diskCachedIds.add(songId);
      _addToMemory(songId, nativePath);
    }
    return nativePath;
  }

  void _addToMemory(int songId, String path) {
    _paths.remove(songId);
    _paths[songId] = path;
    while (_paths.length > _maxEntries) {
      final oldest = _paths.keys.first;
      _paths.remove(oldest);
      _providers.remove(oldest);
    }
  }

  void _touchMemory(int songId, String path) {
    _paths.remove(songId);
    _paths[songId] = path;
  }
}
