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

  testWidgets('renders a square knockout glass badge scaled down by 10%', (
    tester,
  ) async {
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
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Explicit content advisory',
      ),
      findsOneWidget,
    );

    final badgeFinder = find.descendant(
      of: find.byType(ExplicitSongTitle),
      matching: find.byType(CustomPaint),
    );
    expect(badgeFinder, findsOneWidget);
    final badge = tester.widget<CustomPaint>(badgeFinder);
    expect(badge.painter, isA<CustomPainter>());
    expect(badge.child, isA<SizedBox>());

    final badgeSize = tester.getSize(badgeFinder);
    expect(badgeSize.width, badgeSize.height);

    final titleContext = tester.element(find.text('Explicit Track'));
    final inheritedStyle = DefaultTextStyle.of(titleContext).style;
    final originalBadgeStyle = inheritedStyle.copyWith(
      fontSize: ((inheritedStyle.fontSize ?? 14) * 0.78),
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    );
    final originalGlyphStyle = TextStyle(
      inherit: false,
      fontFamily: originalBadgeStyle.fontFamily,
      fontFamilyFallback: originalBadgeStyle.fontFamilyFallback,
      fontSize: originalBadgeStyle.fontSize,
      fontWeight: originalBadgeStyle.fontWeight,
      fontStyle: originalBadgeStyle.fontStyle,
      letterSpacing: originalBadgeStyle.letterSpacing,
      wordSpacing: originalBadgeStyle.wordSpacing,
      height: originalBadgeStyle.height,
      textBaseline: originalBadgeStyle.textBaseline,
      locale: originalBadgeStyle.locale,
      foreground: Paint()..blendMode = BlendMode.dstOut,
    );
    final originalGlyph = TextPainter(
      text: TextSpan(text: 'E', style: originalGlyphStyle),
      textDirection: Directionality.of(titleContext),
    )..layout();
    final originalWidth = originalGlyph.width + 6;
    final originalHeight = originalGlyph.height + 4;
    final originalSide = originalWidth > originalHeight
        ? originalWidth
        : originalHeight;

    expect(badgeSize.width, closeTo(originalSide * 0.9, 0.05));
  });

  testWidgets('does not render a badge for a non-explicit track', (
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
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Explicit content advisory',
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(ExplicitSongTitle),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(ExplicitSongTitle),
        matching: find.byType(Text),
      ),
      findsOneWidget,
    );
  });
}
