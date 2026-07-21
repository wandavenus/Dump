import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/models/playlist.dart';

void main() {
  group('Playlist', () {
    late Playlist playlist;

    setUp(() {
      playlist = Playlist(
        id: 'pl-001',
        name: 'My Favorites',
        songIds: [1, 2, 3],
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    group('toJson / fromJson', () {
      test('round-trips correctly', () {
        final json = playlist.toJson();
        final restored = Playlist.fromJson(json);

        expect(restored.id, equals(playlist.id));
        expect(restored.name, equals(playlist.name));
        expect(restored.songIds, equals(playlist.songIds));
        expect(restored.createdAt, equals(playlist.createdAt));
      });

      test('fromJson uses fallback values for missing keys', () {
        final result = Playlist.fromJson({});

        expect(result.id, equals(''));
        expect(result.name, equals(''));
        expect(result.songIds, isEmpty);
        expect(result.createdAt,
            equals(DateTime.fromMillisecondsSinceEpoch(0)));
      });

      test('songIds are parsed as int even when stored as double', () {
        final json = {'id': 'x', 'name': 'X', 'songIds': [1.0, 2.0], 'createdAt': 0};
        final result = Playlist.fromJson(json);
        expect(result.songIds, equals([1, 2]));
      });
    });

    group('encodeList / decodeList', () {
      test('encodes and decodes a list of playlists', () {
        final another = Playlist(
          id: 'pl-002',
          name: 'Workout',
          songIds: [10, 20],
          createdAt: DateTime.fromMillisecondsSinceEpoch(1710000000000),
        );
        final list = [playlist, another];
        final encoded = Playlist.encodeList(list);
        final decoded = Playlist.decodeList(encoded);

        expect(decoded.length, equals(2));
        expect(decoded[0].id, equals('pl-001'));
        expect(decoded[1].id, equals('pl-002'));
        expect(decoded[0].songIds, equals([1, 2, 3]));
        expect(decoded[1].songIds, equals([10, 20]));
      });

      test('encodes and decodes an empty list', () {
        final encoded = Playlist.encodeList([]);
        final decoded = Playlist.decodeList(encoded);
        expect(decoded, isEmpty);
      });
    });

    group('copyWith', () {
      test('overrides name and songIds only', () {
        final copy = playlist.copyWith(name: 'Renamed', songIds: [99]);

        expect(copy.name, equals('Renamed'));
        expect(copy.songIds, equals([99]));
        // Unchanged fields preserved
        expect(copy.id, equals(playlist.id));
        expect(copy.createdAt, equals(playlist.createdAt));
      });

      test('returns equivalent playlist when no fields overridden', () {
        final copy = playlist.copyWith();

        expect(copy.id, equals(playlist.id));
        expect(copy.name, equals(playlist.name));
        expect(copy.songIds, equals(playlist.songIds));
      });
    });
  });
}
