import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/l10n/app_localizations.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/themes/app_themes.dart';
import 'package:musicplayer/widgets/pages/browse_sections.dart';
import 'package:musicplayer/widgets/pages/radio_sections.dart';
import 'package:musicplayer/widgets/song_artwork.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<Locale> _locales = [Locale('en'), Locale('id')];

const List<LocalizationsDelegate<Object>> _delegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

final List<LocalSong> _songs = List.generate(
  6,
  (i) => LocalSong(
    id: i + 1,
    title: 'Song $i',
    artist: 'Artist $i',
    album: 'Album $i',
    albumId: 100 + i,
    path: '',
    duration: const Duration(minutes: 3),
  ),
);

void _mockMediaStore() {
  const channel = MethodChannel('musicplayer/media_store');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async => null);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

Future<void> _pump(WidgetTester tester, Size size, Widget child) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemes.dark,
      localizationsDelegates: _delegates,
      supportedLocales: _locales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: size.width, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mockMediaStore();
  });

  group('browse banner carousel', () {
    testWidgets('portrait keeps the full-height banner without overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        const Size(393, 852),
        BrowseBannerCarousel(songs: _songs),
      );
      final height = tester.getSize(find.byType(BrowseBannerCarousel)).height;
      expect(height, 350);
      expect(tester.takeException(), isNull);
    });

    testWidgets('landscape shrinks the banner but keeps it usable', (
      tester,
    ) async {
      await _pump(
        tester,
        const Size(800, 360),
        BrowseBannerCarousel(songs: _songs),
      );
      final height = tester.getSize(find.byType(BrowseBannerCarousel)).height;
      expect(height, lessThan(350));
      // Tetap cukup tinggi untuk teks (artis + judul + album) di atas artwork.
      expect(height, greaterThanOrEqualTo(200));
      expect(tester.takeException(), isNull);
    });
  });

  group('radio smart playlist grid', () {
    /// Number of distinct rows = number of distinct top edges of the cells.
    int rowCount(WidgetTester tester) {
      final finder = find.byType(ArtworkHairlineBorder);
      final tops = <double>{};
      for (var i = 0; i < finder.evaluate().length; i++) {
        tops.add((tester.getTopLeft(finder.at(i)).dy * 2).round() / 2);
      }
      return tops.length;
    }

    double cellWidth(WidgetTester tester) =>
        tester.getSize(find.byType(ArtworkHairlineBorder).first).width;

    testWidgets('portrait keeps the 3-column (2-row) grid', (tester) async {
      await _pump(
        tester,
        const Size(393, 852),
        Builder(
          builder: (context) => MediaQuery(
            // The test font has wider glyph metrics than the app font. Scale
            // only this test's text so the unchanged page header does not
            // create a false overflow unrelated to the responsive grid.
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(0.8)),
            child: const RadioPageContent(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ArtworkHairlineBorder), findsNWidgets(6));
      expect(rowCount(tester), 2);
      expect(cellWidth(tester), greaterThan(100));
      expect(cellWidth(tester), lessThan(140));
      expect(tester.takeException(), isNull);
    });

    testWidgets('landscape lays the six cells out in a single row', (
      tester,
    ) async {
      await _pump(tester, const Size(800, 360), const RadioPageContent());
      await tester.pump();
      expect(find.byType(ArtworkHairlineBorder), findsNWidgets(6));
      expect(rowCount(tester), 1);
      // Cell tetap dekat ukuran desain, tidak meregang memenuhi layar.
      expect(cellWidth(tester), lessThan(150));
      expect(tester.takeException(), isNull);
    });
  });
}
