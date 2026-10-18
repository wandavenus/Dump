import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicplayer/services/audio/audio_effects_service.dart';
import 'package:musicplayer/services/automix_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AutoMix End-to-End Integration Harness', () {
    test('AutoMix ON vs OFF setting toggle and state isolation', () {
      AutomixService.settings.value = const AutomixSettings(
        profile: AutomixProfile.dj,
        bpmTolerancePercent: 6.0,
        crossfadeBeats: 16,
      );

      expect(AutomixService.automixEnabled.value, isFalse);
      expect(AutomixService.automixActive.value, isFalse);

      AutomixService.automixEnabled.value = true;
      expect(AutomixService.automixEnabled.value, isTrue);

      AutomixService.automixEnabled.value = false;
      expect(AutomixService.automixEnabled.value, isFalse);
    });

    test('Loudness matching with similar and large loudness differences', () {
      final quietTrack = AutomixTrackFeatures(
        songId: 1,
        loudnessLufs: -20.0,
        rmsDb: -22.0,
        introRmsDb: -22.0,
        outroRmsDb: -22.0,
      );
      final loudTrack = AutomixTrackFeatures(
        songId: 2,
        loudnessLufs: -10.0,
        rmsDb: -12.0,
        introRmsDb: -12.0,
        outroRmsDb: -12.0,
      );

      final cueLoudToQuiet = automixTransitionCue(
        outgoing: loudTrack,
        incoming: quietTrack,
        settings: const AutomixSettings(),
      );
      expect(cueLoudToQuiet.outgoingTrim, lessThan(1.0));
      expect(cueLoudToQuiet.incomingTrim, 1.0);
      expect(cueLoudToQuiet.outgoingTrim, greaterThanOrEqualTo(0.5)); // max 6 dB attenuation

      final cueQuietToLoud = automixTransitionCue(
        outgoing: quietTrack,
        incoming: loudTrack,
        settings: const AutomixSettings(),
      );
      expect(cueQuietToLoud.outgoingTrim, 1.0);
      expect(cueQuietToLoud.incomingTrim, lessThan(1.0));
      expect(cueQuietToLoud.incomingTrim, greaterThanOrEqualTo(0.5));
    });

    test('Tempo matching, octave folds, and untrusted beat grid fallbacks', () {
      // 1. Matching tempo (120 BPM -> 122 BPM)
      final match = automixTempoMatch(referenceBpm: 120, trackBpm: 122);
      expect(match.$1, isTrue);
      expect(match.$2, closeTo(120 / 122, 0.01));

      // 2. Half-time tempo fold (120 BPM -> 60 BPM)
      final halfFold = automixTempoMatch(referenceBpm: 120, trackBpm: 60);
      expect(halfFold.$1, isTrue);
      expect(halfFold.$2, 1.0);

      // 3. Mismatched tempo beyond tolerance (120 BPM -> 150 BPM)
      final mismatch = automixTempoMatch(referenceBpm: 120, trackBpm: 150);
      expect(mismatch.$1, isFalse);

      // 4. Untrusted tail beat grid (tailBpmConfidence < 0.35)
      final untrustedTail = AutomixTrackFeatures(
        songId: 10,
        bpm: 120,
        tailBpm: 120,
        bpmConfidence: 0.9,
        tailBpmConfidence: 0.1, // untrusted
      );
      final incoming = const AutomixTrackFeatures(
        songId: 11,
        bpm: 150,
        bpmConfidence: 0.9,
      );

      final cue = automixTransitionCue(
        outgoing: untrustedTail,
        incoming: incoming,
        settings: const AutomixSettings(),
      );
      // Untrusted tail falls back to plain crossfade
      expect(cue.strategy, AutomixTransitionStrategy.crossfade);
      expect(cue.fadeSeconds, closeTo(8.0, 0.1));
    });

    test('Bit-Perfect mode stops and resumes the AutoMix idle sweep', () async {
      AutomixService.automixEnabled.value = false;
      AudioEffectsService.bitPerfectMode.value = false;
      AutomixService.resetInMemoryState();
      SharedPreferences.setMockInitialValues({});
      await AutomixService.loadSettings();
      AutomixService.initializeAutoMix();

      try {
        await AutomixService.setAutomixEnabled(true);
        expect(AutomixService.hasPendingLibrarySweepForTesting, isTrue);

        AudioEffectsService.bitPerfectMode.value = true;
        expect(AutomixService.hasPendingLibrarySweepForTesting, isFalse);
        expect(AutomixService.automixEnabled.value, isTrue);

        AudioEffectsService.bitPerfectMode.value = false;
        expect(AutomixService.hasPendingLibrarySweepForTesting, isTrue);
      } finally {
        AudioEffectsService.bitPerfectMode.value = true;
        AutomixService.automixEnabled.value = false;
        AutomixService.resetInMemoryState();
        AudioEffectsService.bitPerfectMode.value = false;
      }
    });

    test('Bit-Perfect mode rejects explicit library analysis before decoding', () async {
      AutomixService.automixEnabled.value = false;
      AutomixService.resetInMemoryState();
      SharedPreferences.setMockInitialValues({});
      await AutomixService.loadSettings();

      AudioEffectsService.bitPerfectMode.value = true;
      // A batch must not even be announced while Pure Playback owns the
      // decoder: the progress readout stays exactly as the caller left it.
      AutomixService.analysisProgress.value =
          const AutomixAnalysisProgress(total: 7);
      try {
        await AutomixService.analyzeLibrary(const []);

        expect(AutomixService.analysisProgress.value.total, 7);
        expect(AutomixService.analysisProgress.value.running, isFalse);
      } finally {
        AudioEffectsService.bitPerfectMode.value = false;
        AutomixService.analysisProgress.value = const AutomixAnalysisProgress();
        AutomixService.resetInMemoryState();
      }
    });
  });
}
