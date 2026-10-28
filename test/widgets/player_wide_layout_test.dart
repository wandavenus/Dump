import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/l10n/app_localizations.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/themes/app_themes.dart';
import 'package:musicplayer/services/player_sheet_controller.dart';
import 'package:musicplayer/widgets/player/player_content.dart';

/// Landscape phone-ish window (logical px).
const Size _landscape = Size(800, 360);

/// Portrait phone window (logical px).
const Size _portrait = Size(393, 852);

const List<Locale> _locales = [Locale('en'), Locale('id')];

const List<LocalizationsDelegate<Object>> _delegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

final _song = LocalSong(
  id: 1,
  title: 'Test Song',
  artist: 'Test Artist',
  album: 'Test Album',
  albumId: 10,
  path: '',
  duration: const Duration(minutes: 3),
);

Future<void> _pumpPlayer(
  WidgetTester tester,
  Size size, {
  bool showLyrics = false,
  LocalSong? song,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  // Full player fully expanded.
  PlayerSheetController.progress.value = 1.0;
  addTearDown(() => PlayerSheetController.progress.value = 0.0);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemes.dark,
      localizationsDelegates: _delegates,
      supportedLocales: _locales,
      home: Scaffold(
        body: SizedBox.expand(
          child: PlayerContent(
            song: song ?? _song,
            formatTime: (d) => '${d.inSeconds}s',
            showLyrics: showLyrics,
            onLyricsToggle: () {},
            showQueue: false,
            onQueueToggle: () {},
            hideArtwork: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 450));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    const channel = MethodChannel('musicplayer/media_store');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getExplicitStatus') return false;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  testWidgets('landscape builds the two-column layout without overflow', (
    tester,
  ) async {
    await _pumpPlayer(tester, _landscape);

    expect(find.byKey(const ValueKey('wideControlsPanel')), findsOneWidget);
    expect(find.byKey(const ValueKey('wideAlbumCover')), findsOneWidget);
    // Stacked-layout-only pieces must be gone.
    expect(find.byKey(const ValueKey('songInfo')), findsNothing);
    expect(find.byKey(const ValueKey('albumCover')), findsNothing);
    // No RenderFlex overflow / layout assertion while building the wide tree.
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait keeps the original stacked layout', (tester) async {
    await _pumpPlayer(tester, _portrait);

    expect(find.byKey(const ValueKey('wideControlsPanel')), findsNothing);
    expect(find.byKey(const ValueKey('wideAlbumCover')), findsNothing);
    expect(find.byKey(const ValueKey('songInfo')), findsOneWidget);
    expect(find.byKey(const ValueKey('albumCover')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mini player uses the shared knockout explicit badge', (
    tester,
  ) async {
    const channel = MethodChannel('musicplayer/media_store');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getExplicitStatus') return true;
      return null;
    });

    final explicitSong = LocalSong(
      id: 811,
      title: 'Explicit Test Song',
      artist: 'Test Artist',
      album: 'Test Album',
      albumId: 10,
      path: '/music/explicit-mini-header.mp3',
      duration: const Duration(minutes: 3),
    );

    await _pumpPlayer(tester, _landscape, showLyrics: true, song: explicitSong);

    expect(find.text('[E]'), findsNothing);
    final miniHeader = find.byKey(const ValueKey('wideMiniSongHeader'));
    expect(
      find.descendant(
        of: miniHeader,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Explicit content advisory',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('vertical drag inside the wide panel does not scroll it', (
    tester,
  ) async {
    await _pumpPlayer(tester, _landscape);

    final panel = find.byKey(const ValueKey('wideControlsPanel'));
    final before = tester.getTopLeft(panel);

    // The panel wraps its contents in a NeverScrollableScrollPhysics viewport
    // as an overflow safety net; it must never claim vertical drags (the sheet
    // drag / collapse gesture has to keep working).
    await tester.drag(panel, const Offset(0, -80));
    // pumpAndSettle would hang on the mini-header marquee animation.
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.getTopLeft(panel), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape lyrics overlay keeps an exit path to the toggles', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = _landscape;
    addTearDown(tester.view.reset);
    PlayerSheetController.progress.value = 1.0;
    addTearDown(() => PlayerSheetController.progress.value = 0.0);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.dark,
        localizationsDelegates: _delegates,
        supportedLocales: _locales,
        home: Scaffold(
          body: SizedBox.expand(
            child: PlayerContent(
              song: _song,
              formatTime: (d) => '${d.inSeconds}s',
              showLyrics: true,
              onLyricsToggle: () {},
              showQueue: false,
              onQueueToggle: () {},
              hideArtwork: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byKey(const ValueKey('wideLyricsArea')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
