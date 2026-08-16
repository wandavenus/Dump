import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/models/playlist.dart';

void main() {
  group('Playlist edge cases', () {
    test('fromJson handles explicit null values with fallbacks', () {
      final result = Playlist.fromJson({
        'id': null,
        'name': null,
        'songIds': null,
        'createdAt': null,
      });

      expect(result.id, equals(''));
      expect(result.name, equals(''));
      expect(result.songIds, isEmpty);
      expect(
        result.createdAt,
        equals(DateTime.fromMillisecondsSinceEpoch(0)),
      );
    });

    test('fromJson preserves song ID order and duplicates', () {
      final result = Playlist.fromJson({
        'id': 'x',
        'name': 'X',
        'songIds': [7, 3, 7, 1],
        'createdAt': 0,
      });

      expect(result.songIds, equals([7, 3, 7, 1]));
    });

    test('fromJson accepts integer millisecond timestamps', () {
      final timestamp = 1712345678901;
      final result = Playlist.fromJson({
        'id': 'x',
        'name': 'X',
        'songIds': <int>[],
        'createdAt': timestamp,
      });

      expect(
        result.createdAt,
        equals(DateTime.fromMillisecondsSinceEpoch(timestamp)),
      );
    });

    test('encodeList and decodeList preserve playlist order', () {
      final playlists = [
        Playlist(
          id: 'first',
          name: 'First',
          songIds: [1],
          createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        ),
        Playlist(
          id: 'second',
          name: 'Second',
          songIds: [2],
          createdAt: DateTime.fromMillisecondsSinceEpoch(2),
        ),
        Playlist(
          id: 'third',
          name: 'Third',
          songIds: [3],
          createdAt: DateTime.fromMillisecondsSinceEpoch(3),
        ),
      ];

      final decoded = Playlist.decodeList(Playlist.encodeList(playlists));

      expect(decoded.map((playlist) => playlist.id).toList(),
          equals(['first', 'second', 'third']));
    });

    test('copyWith does not mutate the original playlist song IDs', () {
      final original = Playlist(
        id: 'pl-001',
        name: 'Original',
        songIds: [1, 2, 3],
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      );

      final copy = original.copyWith(songIds: [99]);

      expect(original.songIds, equals([1, 2, 3]));
      expect(copy.songIds, equals([99]));
    });
  });
}
