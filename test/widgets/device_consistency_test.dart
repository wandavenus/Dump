import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/l10n/app_localizations.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/themes/app_themes.dart';
import 'package:musicplayer/widgets/pages/browse_sections.dart';
import 'package:musicplayer/widgets/pages/radio_sections.dart';
import 'package:musicplayer/themes/artwork_hairline_border.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _locales = [Locale('en'), Locale('id')];
const List<LocalizationsDelegate<Object>> _delegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

final _songs = List.generate(
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

Future<void> _pumpAtDevicePixelRatio(
  WidgetTester tester, {
  required Size logicalSize,
  required double devicePixelRatio,
  required Widget child,
}) async {
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = Size(
    logicalSize.width * devicePixelRatio,
    logicalSize.height * devicePixelRatio,
  );
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemes.dark,
      localizationsDelegates: _delegates,
      supportedLocales: _locales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: logicalSize.width, child: child),
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

  group('logical layout consistency across display densities', () {
    for (final dpr in const [1.0, 2.0, 2.75, 3.0]) {
      testWidgets('radio grid remains valid at DPR $dpr', (tester) async {
        await _pumpAtDevicePixelRatio(
          tester,
          logicalSize: const Size(393, 852),
          devicePixelRatio: dpr,
          child: const RadioPageContent(),
        );

        expect(find.byType(ArtworkHairlineBorder), findsNWidgets(6));
        expect(tester.takeException(), isNull);

        final firstCell = tester.getSize(
          find.byType(ArtworkHairlineBorder).first,
        );
        expect(firstCell.width, greaterThan(100));
        expect(firstCell.width, lessThan(140));
      });
    }

    testWidgets('browse banner keeps its portrait reference size at DPR 3', (
      tester,
    ) async {
      await _pumpAtDevicePixelRatio(
        tester,
        logicalSize: const Size(393, 852),
        devicePixelRatio: 3.0,
        child: BrowseBannerCarousel(songs: _songs),
      );

      expect(
        tester.getSize(find.byType(BrowseBannerCarousel)).height,
        350,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
