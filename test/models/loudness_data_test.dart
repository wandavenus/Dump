import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/models/loudness_data.dart';

void main() {
  group('LoudnessData', () {
    group('LoudnessData.none()', () {
      test('hasData is false', () {
        const data = LoudnessData.none();
        expect(data.hasData, isFalse);
      });

      test('gainDb is 0.0', () {
        const data = LoudnessData.none();
        expect(data.gainDb, equals(0.0));
      });

      test('safeGain returns 0.0 when no data', () {
        const data = LoudnessData.none();
        expect(data.safeGain(), equals(0.0));
        expect(data.safeGain(preamp: 6.0), equals(0.0));
      });
    });

    group('safeGain', () {
      test('returns gainDb when no peak clipping needed', () {
        const data = LoudnessData(
          gainDb: 3.0,
          source: LoudnessSource.replayGainTrack,
        );
        expect(data.safeGain(), equals(3.0));
      });

      test('adds preamp to gainDb', () {
        const data = LoudnessData(
          gainDb: 2.0,
          source: LoudnessSource.replayGainTrack,
        );
        expect(data.safeGain(preamp: 3.0), equals(5.0));
      });

      test('clamps result to +24 dB maximum', () {
        const data = LoudnessData(
          gainDb: 30.0,
          source: LoudnessSource.replayGainTrack,
        );
        expect(data.safeGain(), equals(24.0));
      });

      test('clamps result to -24 dB minimum', () {
        const data = LoudnessData(
          gainDb: -30.0,
          source: LoudnessSource.replayGainTrack,
        );
        expect(data.safeGain(), equals(-24.0));
      });

      test('clips gain to peak-limited maximum when peak is provided', () {
        // peak = 0.5 → maxGain ≈ -20 * log10(0.5) ≈ 6.02 dB
        // gainDb = 10.0 exceeds that, so result should be clamped to ~6.02
        const data = LoudnessData(
          gainDb: 10.0,
          peakLinear: 0.5,
          source: LoudnessSource.replayGainTrack,
        );
        final result = data.safeGain();
        expect(result, lessThanOrEqualTo(6.03));
        expect(result, greaterThanOrEqualTo(6.01));
      });

      test('does not clip when gain is below peak-limited maximum', () {
        // peak = 0.5 → maxGain ≈ 6.02 dB; gainDb = 3.0 → no clip
        const data = LoudnessData(
          gainDb: 3.0,
          peakLinear: 0.5,
          source: LoudnessSource.replayGainTrack,
        );
        expect(data.safeGain(), equals(3.0));
      });
    });

    group('gainMb', () {
      test('returns gainDb * 100', () {
        const data = LoudnessData(
          gainDb: 3.5,
          source: LoudnessSource.replayGainTrack,
        );
        expect(data.gainMb, equals(350.0));
      });
    });

    group('LyricsQuality extension helpers', () {
      test('hasData is true for non-none source', () {
        const data = LoudnessData(
          gainDb: 0.0,
          source: LoudnessSource.r128Track,
        );
        expect(data.hasData, isTrue);
      });
    });
  });
}
