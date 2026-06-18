import '../models/local_song.dart';
import 'audio/media3/media3_audio_player.dart';

/// Builds a local Media3-backed audio source descriptor.
AudioSource buildAudioSource(LocalSong song) => AudioSource(song);
