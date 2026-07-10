import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/widgets/local_song_carousel.dart';
import 'package:musicplayer/widgets/song_artwork.dart';

void main() {
  testWidgets(
    'LocalSongCarousel forwards large artwork size for home sections',
    (tester) async {
      const song = LocalSong(
        id: 1,
        title: 'Song',
        artist: 'Artist',
        path: '/music/song.mp3',
        album: 'Album',
        albumId: 7,
        duration: Duration(minutes: 3),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LocalSongCarousel(
              songs: [song],
              artworkSize: 250,
              height: 330,
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      final artwork = tester.widget<SongArtwork>(find.byType(SongArtwork));

      expect(sizedBox.height, 330);
      expect(artwork.size, 250);
    },
  );
}
