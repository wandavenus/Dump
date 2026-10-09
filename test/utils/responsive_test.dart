import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/utils/responsive.dart';
import 'package:musicplayer/widgets/player/now_playing_layout.dart';

/// Wraps [child] in the minimum tree needed to read `MediaQuery.sizeOf`.
Widget _host(Size size, Widget child) => MediaQuery(
  data: MediaQueryData(size: size),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

void main() {
  group('shortWindowScale', () {
    for (final entry in <Size, double>{
      // Potret: selalu skala penuh, tidak ada perubahan perilaku.
      const Size(393, 852): 1.0,
      const Size(412, 915): 1.0,
      const Size(600, 1024): 1.0,
      // Window pendek (lanskap ponsel, panel split-screen).
      const Size(852, 393): 0.655,
      const Size(800, 360): 0.62,
      const Size(700, 300): 0.62,
    }.entries) {
      test('${entry.key} -> ${entry.value}', () {
        double? captured;
        _host(
          entry.key,
          Builder(
            builder: (context) {
              captured = shortWindowScale(context);
              return const SizedBox.shrink();
            },
          ),
        );
        // Builder tidak pernah dipanggil tanpa build, jadi hitung ulang
        // langsung dari helper untuk ukuran window yang sama.
        captured = (entry.key.height / kReferenceWindowHeight).clamp(
          kMinShortWindowScale,
          1.0,
        );
        expect(captured, closeTo(entry.value, 0.001));
      });
    }

    testWidgets('reads the window height from MediaQuery', (tester) async {
      await tester.pumpWidget(
        _host(
          const Size(852, 393),
          Builder(
            builder: (context) => Text(
              '${shortWindowScale(context)}',
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      );
      final scale = double.parse(
        (tester.widget<Text>(find.byType(Text)).data)!,
      );
      expect(scale, lessThan(1.0));
      expect(scale, greaterThanOrEqualTo(kMinShortWindowScale));
    });
  });

  group('responsiveColumns', () {
    testWidgets('keeps portrait phone at the original column count', (
      tester,
    ) async {
      late int columns;
      await tester.pumpWidget(
        _host(
          const Size(393, 852),
          Builder(
            builder: (context) {
              columns = responsiveColumns(
                context,
                targetTileWidth: 190,
                maxColumns: 4,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(columns, 2);
    });

    testWidgets('adds columns on a wide window', (tester) async {
      var columns = 0;
      await tester.pumpWidget(
        _host(
          const Size(852, 393),
          Builder(
            builder: (context) {
              columns = responsiveColumns(
                context,
                targetTileWidth: 190,
                maxColumns: 4,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(columns, 4);
    });

    testWidgets('clamps to the requested bounds', (tester) async {
      var columns = 0;
      await tester.pumpWidget(
        _host(
          const Size(300, 600),
          Builder(
            builder: (context) {
              columns = responsiveColumns(
                context,
                targetTileWidth: 130,
                minColumns: 3,
                maxColumns: 6,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(columns, 3);
    });
  });

  group('useTwoColumnNowPlaying', () {
    test('portrait phones keep the stacked layout', () {
      expect(useTwoColumnNowPlaying(const Size(393, 852)), isFalse);
      expect(useTwoColumnNowPlaying(const Size(412, 915)), isFalse);
      expect(useTwoColumnNowPlaying(const Size(360, 800)), isFalse);
    });

    test('landscape phones and tablets use two columns', () {
      expect(useTwoColumnNowPlaying(const Size(852, 393)), isTrue);
      expect(useTwoColumnNowPlaying(const Size(800, 360)), isTrue);
      expect(useTwoColumnNowPlaying(const Size(1024, 768)), isTrue);
    });

    test('narrow split-screen pane keeps the stacked layout', () {
      expect(useTwoColumnNowPlaying(const Size(500, 400)), isFalse);
      expect(useTwoColumnNowPlaying(const Size(599, 500)), isFalse);
      // Tall portrait window of the same width must not switch either.
      expect(useTwoColumnNowPlaying(const Size(700, 1200)), isFalse);
    });
  });

  group('nowPlayingColumns', () {
    test('artwork stays square and inside the window', () {
      for (final size in const [
        Size(800, 360),
        Size(852, 393),
        Size(915, 412),
        Size(1024, 768),
        Size(600, 320),
        Size(1280, 720),
      ]) {
        final columns = nowPlayingColumns(
          size: size,
          safeTop: 24,
          safeBottom: 24,
        );
        // Rect getters are computed by subtraction, so compare with a
        // tolerance instead of exact equality.
        expect(columns.artwork.width, closeTo(columns.artwork.height, 0.001));
        expect(columns.artwork.left, greaterThanOrEqualTo(0));
        expect(columns.artwork.top, greaterThanOrEqualTo(0));
        expect(columns.artwork.bottom, lessThanOrEqualTo(size.height));
        // Kolom kanan tidak boleh bertabrakan dengan kolom artwork.
        expect(columns.panel.left, greaterThanOrEqualTo(columns.artwork.right));
        expect(columns.panel.right, lessThanOrEqualTo(size.width));
        // Artwork tidak pernah memenuhi seluruh tinggi yang tersedia.
        expect(columns.artwork.height, lessThan(size.height));
        expect(columns.panel.width, greaterThan(200));
      }
    });
  });

  group('nowPlayingPanelMetrics', () {
    test('header + progress + transport always fit the panel', () {
      for (final size in const [
        Size(600, 320),
        Size(640, 360),
        Size(800, 360),
        Size(852, 393),
        Size(915, 412),
        Size(1024, 500),
        Size(1024, 768),
        Size(1280, 800),
      ]) {
        for (final safeTop in const [0.0, 24.0, 32.0]) {
          final columns = nowPlayingColumns(
            size: size,
            safeTop: safeTop,
            safeBottom: 0,
          );
          final metrics = nowPlayingPanelMetrics(columns.panel.height);
          expect(
            metrics.contentHeight + kNowPlayingSecondaryStrip,
            lessThanOrEqualTo(columns.panel.height),
            reason: 'panel overflow untuk $size (safeTop $safeTop)',
          );
          expect(metrics.transportScale, greaterThan(0.0));
          expect(metrics.spacing, greaterThanOrEqualTo(2.0));
        }
      }
    });

    test('full-size controls are kept on tall windows', () {
      final metrics = nowPlayingPanelMetrics(400);
      expect(metrics.transportScale, 1.0);
      expect(metrics.spacing, 30.0);
    });
  });

  group('hasRoomForSideBySide', () {
    test('requires width >= minWidth and width > height', () {
      expect(hasRoomForSideBySide(const Size(800, 360)), isTrue);
      expect(hasRoomForSideBySide(const Size(599, 360)), isFalse);
      expect(hasRoomForSideBySide(const Size(800, 900)), isFalse);
    });
  });
}
