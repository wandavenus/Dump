import 'dart:collection';
import 'dart:typed_data';

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
}
