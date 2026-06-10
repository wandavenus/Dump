import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/local_song.dart';

class AudioService {
  static final AudioPlayer player = AudioPlayer();

  static LocalSong? currentSong;
  static bool isPlaying = false;

  static int currentIndex = 0;
  static List<LocalSong> currentPlaylist = [];

  static AudioSource createSource(LocalSong song) {
    final contentUri = song.contentUri;
    final tag = createMediaItem(song);

    if (contentUri != null && contentUri.isNotEmpty) {
      return AudioSource.uri(
        Uri.parse(contentUri),
        tag: tag,
      );
    }

    return AudioSource.file(
      song.path,
      tag: tag,
    );
  }

  static MediaItem createMediaItem(LocalSong song) {
    final artworkUri = song.artworkUri;

    return MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist,
      album: song.album,
      artUri: artworkUri == null || artworkUri.isEmpty
          ? null
          : Uri.parse(artworkUri),
    );
  }
}
