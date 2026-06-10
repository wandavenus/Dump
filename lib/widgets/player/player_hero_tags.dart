import '../../models/local_song.dart';

class PlayerHeroTags {
  const PlayerHeroTags._();

  static String artwork(LocalSong song) =>
      'player-artwork-${song.id}-${song.path}';
  static String title(LocalSong song) => 'player-title-${song.id}-${song.path}';
}
