import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

class AudioService {
  static final AudioPlayer player = AudioPlayer();

  static SongModel? currentSong;
  static bool isPlaying = false;
}
