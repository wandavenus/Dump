import 'package:flutter/services.dart';
import '../models/local_song.dart';

class MediaStoreService {
  static const MethodChannel _channel =
      MethodChannel('musicplayer/media_store');

  static Future<List<LocalSong>> getSongs() async {
    final List<dynamic> songs =
        await _channel.invokeMethod('getSongs');

    return songs
        .map((e) => LocalSong.fromMap(
              Map<dynamic, dynamic>.from(e),
            ))
        .toList();
  }
}
