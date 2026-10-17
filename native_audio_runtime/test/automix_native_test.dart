import 'dart:math' as math;
import 'dart:typed_data';

import 'package:native_audio_runtime/native_audio_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('native AutoMix signal analyzer', () {
    test('reports measured PCM RMS for a sine wave', () {
      const sampleRate = 22050;
      const amplitude = 0.5;
      final pcm = Float32List.fromList([
        for (var i = 0; i < sampleRate * 2; i++)
          (amplitude * math.sin(2 * math.pi * 440 * i / sampleRate)).toDouble(),
      ]);

      final result = NativeAutomix.analyze(pcm, sampleRate);

      expect(result, isNotNull);
      expect(result!.rmsDb, closeTo(-9.03, 1.0));
      expect(result.analyzedSeconds, closeTo(2.0, 1e-9));
      expect(result.onsetRate, greaterThanOrEqualTo(0));
      // The analyzer ABI has 20 output slots. The FFI facade must pass the
      // full count or native rejects the call before writing any analysis.
      expect(result.bpmConfidence, inInclusiveRange(0.0, 1.0));
      expect(result.keyConfidence, inInclusiveRange(0.0, 1.0));
      expect(result.isMinor, isA<bool>());
    });

    test('rejects too-short input', () {
      expect(NativeAutomix.analyze(Float32List(100), 22050), isNull);
    });
  });

  group('native AutoMix set planner', () {
    test('keeps the start track and emits a complete deterministic order', () {
      final tracks = [
        for (var i = 0; i < 32; i++)
          NativeAutomixTrack(
            songId: i + 1,
            artistGroup: i % 4 == 0 ? 1 : 2,
            bpm: 82 + (i * 13 % 73).toDouble(),
            bpmConfidence: 0.9,
            camelotNumber: i % 12 + 1,
            camelotMinor: i.isOdd,
            keyConfidence: 0.8,
            rmsDb: -25 + (i % 18).toDouble(),
          ),
      ];
      NativeAutomixPlan plan() => NativeAutomix.planSet(
        tracks: tracks,
        profile: 0,
        bpmTolerance: 0.06,
        crossfadeBeats: 16,
        avoidArtistRepeat: true,
        harmonicFilter: false,
        startIndex: 7,
      );

      final first = plan();
      final second = plan();
      expect(first.order.first, 7);
      expect(first.order.toSet().length, tracks.length);
      expect(first.order, second.order);
      expect(first.averageCost, inInclusiveRange(0, 1));
      expect(first.crossfadeSeconds, inInclusiveRange(1.5, 12));
    });

    test('handles an empty track list', () {
      final result = NativeAutomix.planSet(
        tracks: const [],
        profile: 0,
        bpmTolerance: 0.06,
        crossfadeBeats: 16,
        avoidArtistRepeat: true,
        harmonicFilter: false,
        startIndex: 0,
      );
      expect(result.order, isEmpty);
      expect(result.crossfadeSeconds, 0);
      expect(result.averageCost, 0);
    });
  });
}
