import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/models/local_song.dart';

void main() {
  group('LocalSong', () {
    late LocalSong song;

    setUp(() {
      song = const LocalSong(
        id: 1,
        title: 'Test Song',
        artist: 'Test Artist',
        path: '/music/test.mp3',
        album: 'Test Album',
        albumId: 10,
        duration: Duration(seconds: 180),
        year: 2024,
        trackNumber: 3,
        discNumber: 1,
        genre: 'Rock',
        bitrate: 320000,
        sampleRate: 44100,
        dateAdded: 1700000000,
      );
    });

    group('fromMap', () {
      test('parses all fields from a complete map', () {
        final map = {
          'id': 1,
          'title': 'Test Song',
          'artist': 'Test Artist',
          'path': '/music/test.mp3',
          'album': 'Test Album',
          'albumId': 10,
          'duration': 180000,
          'year': 2024,
          'trackNumber': 3,
          'discNumber': 1,
          'genre': 'Rock',
          'bitrate': 320000,
          'sampleRate': 44100,
          'dateAdded': 1700000000,
        };

        final result = LocalSong.fromMap(map);

        expect(result.id, equals(1));
        expect(result.title, equals('Test Song'));
        expect(result.artist, equals('Test Artist'));
        expect(result.path, equals('/music/test.mp3'));
        expect(result.album, equals('Test Album'));
        expect(result.albumId, equals(10));
        expect(result.duration, equals(const Duration(seconds: 180)));
        expect(result.year, equals(2024));
        expect(result.trackNumber, equals(3));
        expect(result.discNumber, equals(1));
        expect(result.genre, equals('Rock'));
        expect(result.bitrate, equals(320000));
        expect(result.sampleRate, equals(44100));
        expect(result.dateAdded, equals(1700000000));
      });

      test('uses fallback values when fields are null', () {
        final result = LocalSong.fromMap({});

        expect(result.id, equals(0));
        expect(result.title, equals('Unknown Title'));
        expect(result.artist, equals('Unknown Artist'));
        expect(result.path, equals(''));
        expect(result.album, equals('Unknown Album'));
        expect(result.albumId, equals(0));
        expect(result.duration, equals(Duration.zero));
        expect(result.year, isNull);
        expect(result.trackNumber, isNull);
        expect(result.artworkUri, isNull);
      });

      test('handles num types correctly (int and double)', () {
        final map = {
          'id': 42.0,
          'albumId': 7.0,
          'duration': 60500.0,
        };
        final result = LocalSong.fromMap(map);
        expect(result.id, equals(42));
        expect(result.albumId, equals(7));
        expect(result.duration, equals(const Duration(milliseconds: 60500)));
      });
    });

    group('toMap', () {
      test('round-trips via fromMap → toMap', () {
        final map = song.toMap();
        final restored = LocalSong.fromMap(map);

        expect(restored.id, equals(song.id));
        expect(restored.title, equals(song.title));
        expect(restored.artist, equals(song.artist));
        expect(restored.duration, equals(song.duration));
        expect(restored.year, equals(song.year));
        expect(restored.trackNumber, equals(song.trackNumber));
        expect(restored.genre, equals(song.genre));
      });

      test('omits null optional fields from map', () {
        const minimal = LocalSong(
          id: 1,
          title: 'Minimal',
          artist: 'Artist',
          path: '/x.mp3',
          album: 'Album',
          albumId: 1,
          duration: Duration(seconds: 60),
        );
        final map = minimal.toMap();

        expect(map.containsKey('year'), isFalse);
        expect(map.containsKey('trackNumber'), isFalse);
        expect(map.containsKey('discNumber'), isFalse);
        expect(map.containsKey('genre'), isFalse);
        expect(map.containsKey('bitrate'), isFalse);
        expect(map.containsKey('sampleRate'), isFalse);
      });

      test('duration is stored as milliseconds', () {
        final map = song.toMap();
        expect(map['duration'], equals(180000));
      });
    });

    group('copyWith', () {
      test('overrides only the specified fields', () {
        final copy = song.copyWith(title: 'New Title', year: 2025);

        expect(copy.title, equals('New Title'));
        expect(copy.year, equals(2025));
        // Unchanged fields preserved
        expect(copy.id, equals(song.id));
        expect(copy.artist, equals(song.artist));
        expect(copy.duration, equals(song.duration));
        expect(copy.genre, equals(song.genre));
      });

      test('returns equal object when no fields overridden', () {
        final copy = song.copyWith();

        expect(copy.id, equals(song.id));
        expect(copy.title, equals(song.title));
        expect(copy.duration, equals(song.duration));
      });
    });
  });
}
