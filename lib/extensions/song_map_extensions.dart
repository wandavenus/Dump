import '../models/local_song.dart';

extension SongMapListX on List {
  List<LocalSong> toLocalSongs() {
    return asMap().entries.map((entry) {
      final i = entry.key;
      final song = entry.value as Map;
      return LocalSong(
        id: i + 1,
        title: song['title'] ?? song['song'] ?? 'Unknown Title',
        artist: song['artist'] ?? 'Unknown Artist',
        path: song['source'] ?? '',
        album: song['album'] ?? 'Unknown Album',
        albumId: 0,
        duration: Duration(seconds: (song['duration'] as num?)?.toInt() ?? 0),
      );
    }).toList();
  }
}
