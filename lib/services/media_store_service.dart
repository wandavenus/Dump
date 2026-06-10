import 'dart:typed_data';

import 'package:flutter/services.dart';
import '../models/local_song.dart';

class MediaStoreService {
  static const MethodChannel _channel =
      MethodChannel('musicplayer/media_store');
  static final Map<String, Future<Uint8List?>> _artworkCache = {};

  static Future<List<LocalSong>> getSongs() async {
    final List<dynamic> songs = await _channel.invokeMethod('getSongs');

    return songs
        .map((e) => LocalSong.fromMap(
              Map<dynamic, dynamic>.from(e),
            ))
        .toList();
  }

  static Future<Uint8List?> getArtwork(
    int albumId, {
    int? songId,
    String? path,
  }) {
    final cacheKey = [
      albumId.toString(),
      songId?.toString() ?? '',
      path ?? '',
    ].join('|');

    return _artworkCache.putIfAbsent(
      cacheKey,
      () => _fetchArtwork(
        albumId: albumId,
        songId: songId,
        path: path,
      ),
    );
  }

  static Future<Uint8List?> _fetchArtwork({
    required int albumId,
    int? songId,
    String? path,
  }) async {
    final Uint8List? artwork = await _channel.invokeMethod(
      'getArtwork',
      {
        'albumId': albumId,
        'songId': songId,
        'path': path,
      },
    );

    if (artwork == null || artwork.isEmpty) {
      return null;
    }

    return artwork;
  }
}
