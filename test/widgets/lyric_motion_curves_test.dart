import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/widgets/player/lyric_motion_curves.dart';

void main() {
  group('lyric motion curves', () {
    test('scroll spring starts and ends at normalized positions', () {
      expect(lyricScrollSpringCurve.transform(0), closeTo(0, 1e-9));
      expect(lyricScrollSpringCurve.transform(1), closeTo(1, 1e-6));
    });

    test('scroll spring progresses smoothly toward its target', () {
      var previous = 0.0;
      for (var i = 1; i <= 20; i++) {
        final current = lyricScrollSpringCurve.transform(i / 20);
        expect(current, greaterThanOrEqualTo(previous - 1e-5));
        expect(current, inInclusiveRange(0.0, 1.0));
        previous = current;
      }
    });

    test('row staggering is bounded and settles to zero', () {
      expect(
        lyricStaggeredRowOffset(
          animationProgress: 0.4,
          distance: 120,
          rowsAfterFocus: 2,
        ).abs(),
        lessThanOrEqualTo(96),
      );
      expect(
        lyricStaggeredRowOffset(
          animationProgress: 1,
          distance: 32,
          rowsAfterFocus: 2,
        ),
        closeTo(0, 0.1),
      );
      expect(
        lyricStaggeredRowOffset(
          animationProgress: 0.4,
          distance: 32,
          rowsAfterFocus: 0,
        ),
        0,
      );
    });

    test('focus blur follows the three distance tiers', () {
      expect(lyricFocusBlurSigma(0), 0);
      expect(lyricFocusBlurSigma(1), 2.4);
      expect(lyricFocusBlurSigma(2), 3.6);
      expect(lyricFocusBlurSigma(3), 4.8);
      expect(lyricFocusBlurSigma(8), 4.8);
    });

    test('word lift is continuous at frame-sized intervals', () {
      final start = Duration(seconds: 12);
      final end = start + const Duration(milliseconds: 2600);
      var previous = lyricWordLift(
        position: start,
        start: start,
        end: end,
        fontSize: 34,
      );

      for (var ms = 16; ms <= 2600; ms += 16) {
        final current = lyricWordLift(
          position: start + Duration(milliseconds: ms),
          start: start,
          end: end,
          fontSize: 34,
        );
        expect(current, greaterThanOrEqualTo(0));
        expect((current - previous).abs(), lessThan(0.15));
        previous = current;
      }
    });

    test('word lift scales with font size and stays zero for invalid spans', () {
      final start = Duration(seconds: 3);
      final end = start + const Duration(milliseconds: 1800);
      final position = start + const Duration(milliseconds: 500);
      final small = lyricWordLift(
        position: position,
        start: start,
        end: end,
        fontSize: 12,
      );
      final large = lyricWordLift(
        position: position,
        start: start,
        end: end,
        fontSize: 34,
      );
      expect(large, greaterThan(small));
      expect(
        lyricWordLift(
          position: start,
          start: start,
          end: start,
          fontSize: 34,
        ),
        0,
      );
    });
  });
}
