import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/local_song.dart';

/// Builds a plain [AudioSource] with no [MediaItem] tag.
///
/// Notification metadata is now pushed separately to [BackgroundAudioHandler]
/// via [AudioService] — it no longer lives on the [AudioSource].  This allows
/// the secondary (preload-only) player to call [setAudioSource] without
/// triggering [audio_service]'s single-handler constraint.
AudioSource buildAudioSource(LocalSong song) {
  if (kIsWeb) return AudioSource.uri(Uri.parse(song.path));
  return AudioSource.file(song.path);
}
