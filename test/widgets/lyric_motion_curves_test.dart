import 'package:flutter_test/flutter_test.dart';
import '../../lib/widgets/player/lyric_motion_curves.dart';

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
  });
}
