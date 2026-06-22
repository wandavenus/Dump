import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/local_song.dart';

class MediaStoreService {
  static const MethodChannel _channel = MethodChannel('musicplayer/media_store');
  static const int _maxArtworkCacheEntries = 80;

  static final LinkedHashMap<int, Future<Uint8List?>> _artworkCache =
      LinkedHashMap<int, Future<Uint8List?>>();

  static List<LocalSong>? _songsCache;

  static Future<List<LocalSong>> getSongs() async {
    final cachedSongs = _songsCache;
    if (cachedSongs != null) {
      return cachedSongs;
    }

    return refreshSongs();
  }

  static Future<List<LocalSong>> refreshSongs() async {
    try {
      final List<dynamic>? songs =
          await _channel.invokeListMethod('getSongs');

      final parsedSongs = (songs ?? const <dynamic>[])
          .map((song) =>
              LocalSong.fromMap(Map<dynamic, dynamic>.from(song)))
          .where((song) => song.path.isNotEmpty)
          .toList(growable: false);

      _songsCache = parsedSongs;
      return parsedSongs;
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Failed to load songs from MediaStore: $error\n$stackTrace');
      return const <LocalSong>[];
    } catch (error, stackTrace) {
      debugPrint('Invalid song payload from MediaStore: $error\n$stackTrace');
      return const <LocalSong>[];
    }
  }

  static void clearSongsCache() {
    _songsCache = null;
  }

  static Future<Uint8List?> getArtwork(int songId) {
    if (songId <= 0) return Future<Uint8List?>.value();

    final cachedArtwork = _artworkCache.remove(songId);
    if (cachedArtwork != null) {
      _artworkCache[songId] = cachedArtwork;
      return cachedArtwork;
    }

    final artworkFuture = _loadArtwork(songId);
    _artworkCache[songId] = artworkFuture;
    _trimArtworkCache();
    return artworkFuture;
  }

  static Future<Uint8List?> _loadArtwork(int songId) async {
    try {
      return _channel.invokeMethod<Uint8List>(
        'getArtwork',
        {'songId': songId},
      );
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Failed to load artwork for song $songId: $error\n$stackTrace');
      return null;
    } catch (error, stackTrace) {
      debugPrint('Invalid artwork payload for song $songId: $error\n$stackTrace');
      return null;
    }
  }

  static void _trimArtworkCache() {
    while (_artworkCache.length > _maxArtworkCacheEntries) {
      _artworkCache.remove(_artworkCache.keys.first);
    }
  }

  static void clearArtworkCache() {
    _artworkCache.clear();
  }

  // ── Artwork path (persistent cache) ────────────────────────────────────────

  /// Calls the native [ArtworkCacheManager] via MethodChannel.
  /// Returns the absolute path to `{cacheDir}/artwork/{songId}.webp`.
  ///
  /// On a cache hit the native side returns immediately (file-exist check only).
  /// On a miss it extracts from MediaStore, encodes WebP, saves atomically,
  /// then returns the path.  The call runs on a native background thread so
  /// the Flutter UI thread is never blocked.
  ///
  /// Prefer [ArtworkRepository.instance.getPath] which adds a Dart-side memory
  /// cache and disk probe on top of this method.
  static Future<String?> getArtworkPath(int songId) async {
    if (songId <= 0) return null;
    try {
      return await _channel.invokeMethod<String>(
        'getArtworkPath',
        {'songId': songId},
      );
    } on PlatformException catch (e) {
      debugPrint('getArtworkPath error songId=$songId: $e');
      return null;
    } catch (e) {
      debugPrint('getArtworkPath unexpected error songId=$songId: $e');
      return null;
    }
  }
}
