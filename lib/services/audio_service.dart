import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

class AudioService {
  static final AudioPlayer player = AudioPlayer();

  static SongModel? currentSong;
  static bool isPlaying = false;

  static int currentIndex = 0;
  static List<SongModel> currentPlaylist = [];
}