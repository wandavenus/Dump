import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/l10n/app_localizations.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/themes/app_themes.dart';
import 'package:musicplayer/widgets/common_actions.dart';
import 'package:musicplayer/widgets/player/player_favorite_button.dart';
import 'package:musicplayer/widgets/player/player_more_menu.dart';
import 'package:musicplayer/widgets/player/player_secondary_controls.dart';
import 'package:musicplayer/widgets/song_context_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _song = LocalSong(
  id: 81,
  title: 'Confirmation Test Song',
  artist: 'Test Artist',
  album: 'Test Album',
  albumId: 8,
  path: '/music/test.mp3',
  duration: Duration(minutes: 3),
);

const List<Locale> _locales = [Locale('en'), Locale('id')];
const List<LocalizationsDelegate<Object>> _delegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void main() {
  testWidgets('player actions expose 48dp targets and accessible labels', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemes.dark,
          localizationsDelegates: _delegates,
          supportedLocales: _locales,
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PlayerFavoriteButton(song: _song),
                      PlayerMoreMenu(song: _song),
                    ],
                  ),
                  PlayerSecondaryControls(
                    song: _song,
                    showLyrics: true,
                    onLyricsToggle: () {},
                    showQueue: false,
                    onQueueToggle: () {},
                    spacing: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final buttons = find.byType(InkWell);
      expect(buttons, findsNWidgets(4));
      for (var index = 0; index < 4; index++) {
        expect(tester.getSize(buttons.at(index)), const Size(48, 48));
      }
      expect(find.bySemanticsLabel('Add to Favorites'), findsOneWidget);
      expect(find.bySemanticsLabel('More options'), findsOneWidget);
      expect(find.bySemanticsLabel('Lyrics'), findsOneWidget);
      expect(find.bySemanticsLabel('Queue'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('player overlay toggles honor reduced-motion preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.dark,
        localizationsDelegates: _delegates,
        supportedLocales: _locales,
        home: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: PlayerSecondaryControls(
                song: _song,
                showLyrics: true,
                onLyricsToggle: () {},
                showQueue: false,
                onQueueToggle: () {},
                spacing: 8,
              ),
            ),
          ),
        ),
      ),
    );

    final animations = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .toList();
    expect(animations, hasLength(2));
    expect(
      animations.map((animation) => animation.duration),
      everyElement(Duration.zero),
    );
  });

  testWidgets('Cast action explains when casting is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.dark,
        localizationsDelegates: _delegates,
        supportedLocales: _locales,
        home: const Scaffold(body: CommonActions()),
      ),
    );
    await tester.tap(find.byIcon(Icons.cast_outlined));
    await tester.pump();

    expect(find.text('Casting is not available yet.'), findsOneWidget);
  });

  testWidgets('song deletion waits for explicit confirmation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 320);
    addTearDown(tester.view.reset);

    var deleteCalls = 0;
    const mediaStoreChannel = MethodChannel('musicplayer/media_store');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(mediaStoreChannel, (call) async {
      if (call.method == 'deleteSong') {
        deleteCalls++;
        return false;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(mediaStoreChannel, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.dark,
        localizationsDelegates: _delegates,
        supportedLocales: _locales,
        home: Scaffold(
          body: Builder(
            builder: (context) => SongContextMenu(
              song: _song,
              playlist: const [_song],
              index: 0,
              tabNavigator: Navigator.of(context),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete from Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete from Device'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text(
        'Delete "Confirmation Test Song" from your device? This cannot be undone.',
      ),
      findsOneWidget,
    );
    expect(deleteCalls, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(deleteCalls, 0);

    await tester.tap(find.text('Delete from Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(deleteCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
