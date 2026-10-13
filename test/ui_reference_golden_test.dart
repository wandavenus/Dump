// SEMENTARA — dipakai untuk membuktikan tampilan acuan ponsel tidak berubah,
// dengan cara membandingkan hasil render terhadap revisi sebelum perubahan.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/l10n/app_localizations.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/themes/app_themes.dart';
import 'package:musicplayer/widgets/pages/browse_sections.dart';
import 'package:musicplayer/widgets/pages/detail_sections.dart';
import 'package:musicplayer/widgets/common/scrolling_page_chrome.dart';
import 'package:musicplayer/widgets/pages/radio_sections.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _locales = [Locale('en'), Locale('id')];
const _delegates = <LocalizationsDelegate<Object>>[
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
      home: Builder(
        builder: (context) => Scaffold(
          body: MediaQuery(
            // Kompensasi font test yang lebih lebar dari font aplikasi.
            // Dipakai sama persis di kedua revisi, jadi perbandingan tetap sah.
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(0.8)),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mockMediaStore();
  });

  final cases = <String, Widget>{
    'radio_page': const RadioPageContent(),
    'browse_banner': BrowseBannerCarousel(songs: _songs),
    'song_list_row': SongListRow(song: _songs[0], index: 0, playlist: _songs),
    'page_chrome': const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LargePageTitle(title: 'Judul Halaman'),
        HeaderDivider(),
      ],
    ),
  };

  // Ukuran acuan ponsel: di sini tampilan HARUS identik dengan revisi lama.
  for (final entry in cases.entries) {
    testWidgets('golden acuan 393x852 ${entry.key}', (tester) async {
      await _pump(tester, const Size(393, 852), entry.value);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/ref_${entry.key}_393x852.png'),
      );
    });
  }
}
