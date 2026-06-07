import 'package:just_audio/just_audio.dart';
import '../models/local_song.dart';

class AudioService {
  static final AudioPlayer player = AudioPlayer();

  static LocalSong? currentSong;
  static bool isPlaying = false;

  static int currentIndex = 0;
  static List<LocalSong> currentPlaylist = [];
}