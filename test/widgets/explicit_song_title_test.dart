import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/widgets/explicit_song_title.dart';

LocalSong _song({required int id, required String title, required String path}) {
  return LocalSong(
    id: id,
    title: title,
    artist: 'Test Artist',
    album: 'Test Album',
    albumId: 1,
    path: path,
    duration: const Duration(minutes: 3),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    const channel = MethodChannel('musicplayer/media_store');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'getExplicitStatus') return null;
      final arguments = call.arguments as Map<Object?, Object?>;
      return arguments['path'] == '/music/explicit.mp3';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  testWidgets('shows the explicit glass badge for an explicit track', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExplicitSongTitle(
            song: _song(
              id: 901,
              title: 'Explicit Track',
              path: '/music/explicit.mp3',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Explicit Track'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);
    final badge = tester.widget<Container>(
      find.ancestor(
        of: find.text('E'),
        matching: find.byType(Container),
      ).first,
    );
    final decoration = badge.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white.withValues(alpha: 0.18));
    expect(decoration.borderRadius, BorderRadius.circular(3));
    expect(decoration.border, isNull);

    final glyph = tester.widget<Text>(find.text('E'));
    expect(glyph.style!.color, Colors.white.withValues(alpha: 0));
  });

  testWidgets('keeps the original title-only Text when not explicit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExplicitSongTitle(
            song: _song(
              id: 902,
              title: 'Clean Track',
              path: '/music/clean.mp3',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Clean Track'), findsOneWidget);
    expect(find.text('E'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ExplicitSongTitle),
        matching: find.byType(Text),
      ),
      findsOneWidget,
    );
  });
}
