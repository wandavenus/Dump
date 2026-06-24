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

  /// Cancels the native background metadata pre-scanner.
  ///
  /// Call this when the user starts playback so the pre-scanner yields all
  /// I/O bandwidth to ExoPlayer's audio decode pipeline.
  /// Fire-and-forget — result is not awaited.
  static void cancelMetadataPrescanner() {
    _channel.invokeMethod<void>('cancelMetadataPrescanner').catchError((_) {});
  }

  /// Restarts the native background metadata pre-scanner.
  ///
  /// Call this when the playback queue ends (idle window) so songs played
  /// for the first time still get pre-cached for their next play.
  /// Uses the cached song list from the last [getSongs] call — no extra
  /// MediaStore round-trip.
  /// Fire-and-forget — result is not awaited.
  static void startMetadataPrescanner() {
    _channel.invokeMethod<void>('startMetadataPrescanner').catchError((_) {});
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

  /// Updates the native [ArtworkCacheManager] with the current playback queue.
  /// Songs in this set are never evicted during LRU cleanup.
  /// Call whenever the queue is set, shuffled, or items are added/removed.
  static Future<void> setActiveQueueIds(List<int> songIds) async {
    try {
      await _channel.invokeMethod<void>(
        'setActiveQueueIds',
        {'ids': songIds},
      );
    } catch (e) {
      debugPrint('setActiveQueueIds error: $e');
    }
  }

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
