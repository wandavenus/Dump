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

  static Future<List<LocalSong>> getSongs() async {
    try {
      final List<dynamic>? songs = await _channel.invokeListMethod('getSongs');

      return (songs ?? const <dynamic>[])
          .map((song) => LocalSong.fromMap(Map<dynamic, dynamic>.from(song)))
          .where((song) => song.path.isNotEmpty)
          .toList(growable: false);
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Failed to load songs from MediaStore: $error\n$stackTrace');
      return const <LocalSong>[];
    } catch (error, stackTrace) {
      debugPrint('Invalid song payload from MediaStore: $error\n$stackTrace');
      return const <LocalSong>[];
    }
  }

  static Future<Uint8List?> getArtwork(int albumId) {
    if (albumId <= 0) return Future<Uint8List?>.value();

    final cachedArtwork = _artworkCache.remove(albumId);
    if (cachedArtwork != null) {
      _artworkCache[albumId] = cachedArtwork;
      return cachedArtwork;
    }

    final artworkFuture = _loadArtwork(albumId);
    _artworkCache[albumId] = artworkFuture;
    _trimArtworkCache();
    return artworkFuture;
  }

  static Future<Uint8List?> _loadArtwork(int albumId) async {
    try {
      return _channel.invokeMethod<Uint8List>(
        'getArtwork',
        {'albumId': albumId},
      );
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Failed to load artwork for album $albumId: $error\n$stackTrace');
      return null;
    } catch (error, stackTrace) {
      debugPrint('Invalid artwork payload for album $albumId: $error\n$stackTrace');
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
