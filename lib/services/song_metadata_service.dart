import 'dart:async';

import 'package:flutter/services.dart';
import '../models/local_song.dart';

class SongMetadataService {
  static const MethodChannel _channel = MethodChannel('musicplayer/media_store');

  static Future<Map<String, dynamic>> getAudioMetadata(String? path, int id) async {
    final metadata = await _channel.invokeMethod<Map>('getAudioMetadata', {
      'path': path,
      'id': id,
    });
    return Map<String, dynamic>.from(metadata ?? {});
  }

  // Existing methods restored
  static Future<Map<String, dynamic>> getSongInfo(LocalSong song) async {
    return await getAudioMetadata(song.path, song.id);
  }

  static Future<String?> getLyrics(LocalSong song) async {
    final metadata = await getAudioMetadata(song.path, song.id);
    return metadata['lyrics'] as String?;
  }

  // Additional helper methods could be restored here if needed
}