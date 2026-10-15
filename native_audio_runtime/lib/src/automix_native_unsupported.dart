import 'automix_native_types.dart';

/// Web builds cannot call native code. AutoMix analysis/playback is disabled
/// in the app's browser target.
class NativeAutomix {
  NativeAutomix._();

  static NativeAutomixPlan planSet({
    required List<NativeAutomixTrack> tracks,
    required int profile,
    required double bpmTolerance,
    required int crossfadeBeats,
    required bool avoidArtistRepeat,
    required bool harmonicFilter,
    required int startIndex,
  }) =>
      throw UnsupportedError('Native AutoMix is unavailable on this platform');

  static NativeAutomixAnalysis? analyze(NativeAutomixPcm pcm, int sampleRate) =>
      throw UnsupportedError('Native AutoMix is unavailable on this platform');
}
