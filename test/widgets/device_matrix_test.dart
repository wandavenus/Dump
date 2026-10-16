import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/l10n/app_localizations.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/themes/app_themes.dart';
import 'package:musicplayer/utils/responsive.dart';
import 'package:musicplayer/widgets/common/responsive_page_body.dart';
import 'package:musicplayer/widgets/pages/browse_sections.dart';
import 'package:musicplayer/widgets/pages/radio_sections.dart';
import 'package:musicplayer/widgets/song_artwork.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Konsistensi UI lintas layar dan perangkat.
///
/// Dua hal yang dijaga berkas ini:
///
/// 1. **Ponsel potret tidak berubah.** Ukuran acuan (393x852) harus tetap
///    menghasilkan angka yang persis sama seperti sebelum aturan lebar konten
///    ditambahkan: banner browse 350 px, sel grid radio 100–140 px.
/// 2. **Aturan lebar konten sama di semua halaman.** Lebar isi halaman harus
///    `min(lebar window, kMaxContentWidth)` di setiap kombinasi ukuran layar
///    dan kerapatan piksel, dan di layar lebar isinya dipusatkan — bukan
///    melebar mengikuti layar.

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

/// Ukuran layar yang mewakili perangkat yang harus didukung.
const Map<String, Size> _devices = {
  // Ponsel potret — acuan desain, tidak boleh berubah.
  'ponsel kecil 360x800': Size(360, 800),
  'ponsel acuan 393x852': Size(393, 852),
  'ponsel besar 412x915': Size(412, 915),
  // Window sempit (split-screen / panel samping).
  'split-screen 320x600': Size(320, 600),
  // Tablet & layar lebar (>= kWideLayoutMinWidth).
  'tablet potret 600x1024': Size(600, 1024),
  'tablet lanskap 1024x768': Size(1024, 768),
  'desktop 1440x900': Size(1440, 900),
  // Ponsel lanskap — window pendek.
  'ponsel lanskap 800x360': Size(800, 360),
};

/// Kerapatan piksel perangkat nyata (mdpi … xxhdpi).
const List<double> _densities = [1.0, 2.0, 2.75, 3.0];

void _mockMediaStore() {
  const channel = MethodChannel('musicplayer/media_store');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async => null);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

/// Font bawaan lingkungan test punya metrik glyph lebih lebar daripada font
/// aplikasi, sehingga baris teks di lebar ponsel bisa terlihat overflow padahal
/// di aplikasi tidak. [responsive_sections_test] yang sudah ada memakai
/// penyesuaian yang sama untuk alasan yang sama.
///
/// Penyusutan ini HANYA dipakai di lebar ponsel. Di tablet/lanskap teks dibiarkan
/// apa adanya supaya tes tetap ketat menangkap overflow yang sebenarnya.
const TextScaler _testFontCompensation = TextScaler.linear(0.8);

/// Menjalankan [child] seolah-olah berada di perangkat [size] dengan
/// kerapatan [dpr]. Anak menerima lebar body yang sebenarnya, sehingga aturan
/// lebar konten diuji apa adanya — bukan lebar yang dipaksakan oleh tes.
Future<void> _pumpOnDevice(
  WidgetTester tester, {
  required Size size,
  required double dpr,
  required Widget child,
}) async {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(size.width * dpr, size.height * dpr);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemes.dark,
      localizationsDelegates: _delegates,
      supportedLocales: _locales,
      home: Builder(
        builder: (context) => Scaffold(
          body: size.width <= 500
              ? MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: _testFontCompensation),
                  child: child,
                )
              : child,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Lebar isi halaman = lebar root scroll view milik halaman tersebut.
double _contentWidth(WidgetTester tester) =>
    tester.getSize(find.byType(SingleChildScrollView).first).width;

/// Ukuran logis yang diharapkan untuk isi halaman: lebar window di ponsel,
/// dijepit ke kolom baca bersama di layar lebar.
double _expectedContentWidth(double windowWidth) =>
    windowWidth < kMaxContentWidth ? windowWidth : kMaxContentWidth;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mockMediaStore();
  });

  group('aturan lebar konten bersama', () {
    testWidgets(
      'contentMaxWidth: lebar window di ponsel, dijepit di layar lebar',
      (tester) async {
        final cases = <Size, double>{
          // Ponsel: lebar apa adanya → tidak ada perubahan perilaku.
          const Size(320, 600): 320,
          const Size(393, 852): 393,
          const Size(412, 915): 412,
          const Size(600, 1024): 600,
          const Size(719, 900): 719,
          // Layar lebar: kolom baca yang sama untuk semua halaman.
          const Size(720, 900): 720,
          const Size(1024, 768): kMaxContentWidth,
          const Size(1440, 900): kMaxContentWidth,
        };

        for (final entry in cases.entries) {
          double? captured;
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = entry.key;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Builder(
                builder: (context) {
                  captured = contentMaxWidth(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          );

          expect(
            captured,
            entry.value,
            reason: 'contentMaxWidth di ${entry.key}',
          );
        }
      },
    );

    test('ambang tata letak lebar cuma satu angka: $kWideLayoutMinWidth', () {
      expect(kWideLayoutMinWidth, 600.0);
      // 599 tidak lebar; 600 lebar tapi wajib lebih lebar daripada tinggi.
      expect(hasRoomForSideBySide(const Size(599, 400)), isFalse);
      expect(hasRoomForSideBySide(const Size(600, 400)), isTrue);
      expect(hasRoomForSideBySide(const Size(600, 900)), isFalse);
    });
  });

  group('ResponsivePageBody', () {
    /// Probe yang mengambil seluruh lebar yang diizinkan, sehingga lebar yang
    /// terukur adalah lebar yang benar-benar tersedia bagi konten halaman.
    const probe = SizedBox(
      key: ValueKey('probe'),
      width: double.infinity,
      height: 40,
    );

    testWidgets(
      'window sempit: anak diteruskan apa adanya, mulai dari tepi kiri',
      (tester) async {
        await _pumpOnDevice(
          tester,
          size: const Size(393, 852),
          dpr: 2.0,
          child: const ResponsivePageBody(child: probe),
        );

        expect(tester.getSize(find.byKey(const ValueKey('probe'))).width, 393);
        expect(tester.getTopLeft(find.byKey(const ValueKey('probe'))).dx, 0);
      },
    );

    testWidgets('window lebar: konten dijepit dan dipusatkan, bukan melebar', (
      tester,
    ) async {
      const size = Size(1024, 768);
      await _pumpOnDevice(
        tester,
        size: size,
        dpr: 1.0,
        child: const ResponsivePageBody(child: probe),
      );

      expect(
        tester.getSize(find.byKey(const ValueKey('probe'))).width,
        kMaxContentWidth,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('probe'))).dx,
        (size.width - kMaxContentWidth) / 2,
      );
    });
  });

  group('halaman di seluruh kombinasi layar x kerapatan', () {
    for (final device in _devices.entries) {
      for (final dpr in _densities) {
        testWidgets('${device.key} @ DPR $dpr', (tester) async {
          final size = device.value;
          await _pumpOnDevice(
            tester,
            size: size,
            dpr: dpr,
            child: const RadioPageContent(),
          );

          // Tidak ada overflow/exception di ukuran mana pun.
          expect(tester.takeException(), isNull);

          // Isi halaman memakai satu aturan lebar yang sama di semua halaman.
          expect(
            _contentWidth(tester),
            closeTo(_expectedContentWidth(size.width), 0.5),
            reason: 'lebar isi halaman di ${device.key}',
          );

          // Konten tetap utuh: enam kartu smart playlist.
          expect(find.byType(ArtworkHairlineBorder), findsNWidgets(6));
        });
      }
    }
  });

  group('tampilan acuan ponsel tidak berubah', () {
    testWidgets('potret 393x852: banner tetap 350 px', (tester) async {
      await _pumpOnDevice(
        tester,
        size: const Size(393, 852),
        dpr: 1.0,
        child: BrowseBannerCarousel(songs: _songs),
      );
      expect(tester.getSize(find.byType(BrowseBannerCarousel)).height, 350);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lanskap 800x360: banner menyusut tapi tetap terpakai', (
      tester,
    ) async {
      await _pumpOnDevice(
        tester,
        size: const Size(800, 360),
        dpr: 1.0,
        child: BrowseBannerCarousel(songs: _songs),
      );
      final height = tester.getSize(find.byType(BrowseBannerCarousel)).height;
      expect(height, lessThan(350));
      expect(height, greaterThanOrEqualTo(200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ukuran sel radio tidak berubah karena kerapatan piksel', (
      tester,
    ) async {
      for (final dpr in _densities) {
        await _pumpOnDevice(
          tester,
          size: const Size(393, 852),
          dpr: dpr,
          child: const RadioPageContent(),
        );
        final cell = tester.getSize(find.byType(ArtworkHairlineBorder).first);
        expect(
          cell.width,
          inInclusiveRange(100, 140),
          reason: 'lebar sel di DPR $dpr harus ikut ukuran logis, bukan fisik',
        );
      }
    });
  });
}
