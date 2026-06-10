import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/local_song.dart';

AudioSource buildAudioSource(LocalSong song) {
  if (kIsWeb) {
    return AudioSource.uri(Uri.parse(song.path));
  }
  return AudioSource.file(
    song.path,
    tag: MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration,
      artUri: song.albumId > 0
          ? Uri.parse('content://media/external/audio/albumart/${song.albumId}')
          : null,
    ),
  );
}
