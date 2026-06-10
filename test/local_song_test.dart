import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/models/local_song.dart';

void main() {
  group('LocalSong.fromMap', () {
    test('uses fallback values when optional payload values are missing', () {
      final song = LocalSong.fromMap(const <String, dynamic>{});

      expect(song.id, 0);
      expect(song.title, 'Unknown Title');
      expect(song.artist, 'Unknown Artist');
      expect(song.path, isEmpty);
      expect(song.album, 'Unknown Album');
      expect(song.albumId, 0);
      expect(song.artworkUri, isNull);
      expect(song.duration, Duration.zero);
    });

    test('converts a valid payload into a LocalSong and back to a map', () {
      final song = LocalSong.fromMap(const <String, dynamic>{
        'id': 7,
        'title': 'Song title',
        'artist': 'Artist name',
        'path': '/music/song.mp3',
        'album': 'Album name',
        'albumId': 11,
        'artworkUri': 'content://artwork/7',
        'duration': 123456,
      });

      expect(song.toMap(), <String, dynamic>{
        'id': 7,
        'title': 'Song title',
        'artist': 'Artist name',
        'path': '/music/song.mp3',
        'album': 'Album name',
        'albumId': 11,
        'artworkUri': 'content://artwork/7',
        'duration': 123456,
      });
    });
  });
}
