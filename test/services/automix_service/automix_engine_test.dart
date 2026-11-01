import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/services/automix_service.dart';

AutomixTrackFeatures _f(
  int id, {
  double? bpm,
  double? alt,
  int? camelot,
  bool? minor,
  double? lufs,
  double? rms,
  double? centroid,
  double? onset,
  String artist = '',
  double bpmConf = 0.9,
  double keyConf = 0.9,
  double? beatOffsetMs,
  double? downbeatOffsetMs,
  double? tailDownbeatOffsetMs,
  double? dropCueMs,
  double? tailBreakdownCueMs,
  double durationSeconds = 0,
  double vocalLikelihood = 0,
  double vocalConfidence = 0,
  int structureRegion = 0,
  double structureConfidence = 0,
  int tailStructureRegion = 0,
  double tailStructureConfidence = 0,
  double dropConfidence = 0,
  double tailBreakdownConfidence = 0,
  double? tailBpm,
  double tailBpmConfidence = 0,
  double? introEnergy,
  double? outroEnergy,
  double? introSlope,
  double? outroSlope,
  double? introEdgeLufs,
  double? outroEdgeLufs,
  double? introEdgeOnsetRate,
  double? outroEdgeOnsetRate,
}) {
  return AutomixTrackFeatures(
    songId: id,
    artist: artist,
    bpm: bpm,
    alternateBpm: alt,
    beatOffsetMs: beatOffsetMs,
    downbeatOffsetMs: downbeatOffsetMs,
    tailDownbeatOffsetMs: tailDownbeatOffsetMs,
    dropCueMs: dropCueMs,
    tailBreakdownCueMs: tailBreakdownCueMs,
    dropConfidence: dropConfidence,
    tailBreakdownConfidence: tailBreakdownConfidence,
    structureRegion: structureRegion,
    structureConfidence: structureConfidence,
    tailStructureRegion: tailStructureRegion,
    tailStructureConfidence: tailStructureConfidence,
    vocalLikelihood: vocalLikelihood,
    vocalConfidence: vocalConfidence,
    durationSeconds: durationSeconds,
    camelotNumber: camelot,
    camelotMinor: minor,
    bpmConfidence: bpmConf,
    keyConfidence: keyConf,
    loudnessLufs: lufs,
    rmsDb: rms,
    centroidHz: centroid,
    onsetRate: onset,
    tailBpm: tailBpm,
    tailBpmConfidence: tailBpmConfidence,
    introEnergy: introEnergy,
    outroEnergy: outroEnergy,
    introSlope: introSlope,
    outroSlope: outroSlope,
    introEdgeLufs: introEdgeLufs,
    outroEdgeLufs: outroEdgeLufs,
    introEdgeOnsetRate: introEdgeOnsetRate,
    outroEdgeOnsetRate: outroEdgeOnsetRate,
  );
}

void main() {
  group('AutoMix decision contract', () {
    test('native header and Dart mirror agree', () {
      final header = File('native_audio_runtime/src/automix_native.h')
          .readAsStringSync();
      double define(String name) {
        final match = RegExp('#define $name ([0-9.]+)').firstMatch(header);
        expect(match, isNotNull, reason: name);
        return double.parse(match!.group(1)!);
      }

      expect(AutomixContract.bpmMin, define('NAR_AUTOMIX_BPM_MIN'));
      expect(AutomixContract.bpmMax, define('NAR_AUTOMIX_BPM_MAX'));
      expect(
        AutomixContract.tempoConfidenceMin,
        define('NAR_AUTOMIX_TEMPO_CONFIDENCE_MIN'),
      );
      expect(
        AutomixContract.keyConfidenceMin,
        define('NAR_AUTOMIX_KEY_CONFIDENCE_MIN'),
      );
      expect(
        AutomixContract.structureConfidenceMin,
        define('NAR_AUTOMIX_STRUCTURE_CONFIDENCE_MIN'),
      );
      expect(
        AutomixContract.dropConfidenceMin,
        define('NAR_AUTOMIX_DROP_CONFIDENCE_MIN'),
      );
      expect(
        AutomixContract.dropHandoverMinMs.toDouble(),
        define('NAR_AUTOMIX_DROP_HANDOVER_MIN_MS'),
      );
      expect(
        AutomixContract.dropHandoverMaxMs.toDouble(),
        define('NAR_AUTOMIX_DROP_HANDOVER_MAX_MS'),
      );
      expect(
        AutomixContract.vocalConfidenceMin,
        define('NAR_AUTOMIX_VOCAL_CONFIDENCE_MIN'),
      );
      expect(
        AutomixContract.vocalLikelihoodMin,
        define('NAR_AUTOMIX_VOCAL_LIKELIHOOD_MIN'),
      );
      expect(
        AutomixContract.fadeMinSeconds,
        define('NAR_AUTOMIX_FADE_MIN_SECONDS'),
      );
      expect(
        AutomixContract.fadeMaxSeconds,
        define('NAR_AUTOMIX_FADE_MAX_SECONDS'),
      );
    });
  });

  group('AutoMix analysis window sizing', () {
    test('short multi-window tracks use disjoint bounded halves', () {
      for (final duration in <double>[120.1, 121, 180, 239.9]) {
        final window = AutomixService.analysisWindowSecondsForDuration(
          duration,
        );
        expect(window, lessThanOrEqualTo(120));
        expect(window * 2, lessThanOrEqualTo(duration));
      }
      expect(AutomixService.analysisWindowSecondsForDuration(121), 60);
      expect(AutomixService.analysisWindowSecondsForDuration(180), 90);
      expect(AutomixService.analysisWindowSecondsForDuration(240), 120);
      expect(AutomixService.analysisWindowSecondsForDuration(480), 120);
    });
  });

  group('AutomixTrackFeatures serialization', () {
    test('round trips phase/cue metadata and accepts older cache entries', () {
      final feature = AutomixTrackFeatures(
        songId: 17,
        bpm: 120,
        alternateBpm: 240,
        beatOffsetMs: 123.5,
        downbeatOffsetMs: 350.0,
        tailDownbeatOffsetMs: 8350.0,
        dropCueMs: 32000.0,
        tailBreakdownCueMs: 178000.0,
        vocalLikelihood: 0.85,
        vocalConfidence: 0.9,
        structureRegion: 3,
        structureConfidence: 0.8,
        tailStructureRegion: 4,
        tailStructureConfidence: 0.75,
        dropConfidence: 0.7,
        tailBreakdownConfidence: 0.9,
        durationSeconds: 180.0,
        introSlope: 5.0,
        outroSlope: -4.0,
        introRmsDb: -18.0,
        outroRmsDb: -24.0,
        introEdgeLufs: -17.5,
        outroEdgeLufs: -23.5,
        introEdgeOnsetRate: 1.6,
        outroEdgeOnsetRate: 0.7,
        startBpm: 122.0,
        startBpmConfidence: 0.81,
        endBpm: 126.0,
        endBpmConfidence: 0.84,
        introBeatOffsetMs: 188.0,
        introTempoStability: 0.78,
        outroTempoStability: 0.71,
        chordProgression: const <AutomixChordEvent>[
          AutomixChordEvent(
            startMs: 0,
            rootPitchClass: 0,
            root: 'C',
            quality: 'maj',
            confidence: 0.92,
          ),
          AutomixChordEvent(
            startMs: 16000,
            rootPitchClass: 7,
            root: 'G',
            quality: 'maj',
            confidence: 0.84,
          ),
        ],
      );
      final restored = AutomixTrackFeatures.fromMap(feature.toMap());
      expect(restored.alternateBpm, 240.0);
      expect(restored.beatOffsetMs, 123.5);
      expect(restored.downbeatOffsetMs, 350.0);
      expect(restored.tailDownbeatOffsetMs, 8350.0);
      expect(restored.dropCueMs, 32000.0);
      expect(restored.tailBreakdownCueMs, 178000.0);
      expect(restored.vocalLikelihood, 0.85);
      expect(restored.vocalConfidence, 0.9);
      expect(restored.structureRegion, 3);
      expect(restored.structureConfidence, 0.8);
      expect(restored.tailStructureRegion, 4);
      expect(restored.tailStructureConfidence, 0.75);
      expect(restored.dropConfidence, 0.7);
      expect(restored.tailBreakdownConfidence, 0.9);
      expect(restored.durationSeconds, 180.0);
      expect(restored.introSlope, 5.0);
      expect(restored.outroSlope, -4.0);
      expect(restored.introRmsDb, -18.0);
      expect(restored.outroRmsDb, -24.0);
      expect(restored.introEdgeLufs, -17.5);
      expect(restored.outroEdgeLufs, -23.5);
      expect(restored.introEdgeOnsetRate, 1.6);
      expect(restored.outroEdgeOnsetRate, 0.7);
      expect(restored.startBpm, 122.0);
      expect(restored.startBpmConfidence, 0.81);
      expect(restored.endBpm, 126.0);
      expect(restored.endBpmConfidence, 0.84);
      expect(restored.introBeatOffsetMs, 188.0);
      expect(restored.introTempoStability, 0.78);
      expect(restored.outroTempoStability, 0.71);
      expect(restored.chordProgression.map((c) => c.label), ['Cmaj', 'Gmaj']);
      expect(restored.chordProgression.last.startMs, 16000.0);
      expect(restored.chordProgression.last.confidence, 0.84);

      final legacy = AutomixTrackFeatures.fromMap({'id': 17, 'bpm': 120});
      expect(legacy.alternateBpm, isNull);
      expect(legacy.beatOffsetMs, isNull);
      expect(legacy.dropCueMs, isNull);
      expect(legacy.tailBreakdownCueMs, isNull);
      expect(legacy.durationSeconds, 0.0);
      expect(legacy.introEdgeLufs, isNull);
      expect(legacy.outroEdgeLufs, isNull);
      expect(legacy.chordProgression, isEmpty);
    });
  });

  group('native AutoMix analysis map contract', () {
    test('rejects non-finite and non-integer Camelot values safely', () {
      for (final value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        8.5,
        0,
        13,
      ]) {
        final segment = automixSegmentFeaturesFromAnalysisMap(
          <String, dynamic>{
            'camelotNumber': value,
            'camelotMinor': true,
            'keyConfidence': 0.9,
          },
          fallbackStartSeconds: 0,
          fallbackSeconds: 120,
        );
        expect(segment.camelotNumber, isNull, reason: 'value=$value');
        expect(segment.camelotMinor, isNull, reason: 'value=$value');
        expect(segment.keyConfidence, 0, reason: 'value=$value');
      }
    });

    test('invalid confidence and likelihood values fall back to zero', () {
      final segment = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'bpm': 120.0,
          'bpmConfidence': 1.7,
          'keyConfidence': double.infinity,
          'dropConfidence': -0.1,
          'breakdownConfidence': double.nan,
          'structureConfidence': 4.0,
          'vocalLikelihood': 1.2,
          'vocalConfidence': -2.0,
        },
        fallbackStartSeconds: 0,
        fallbackSeconds: 120,
      );

      expect(segment.bpm, isNull);
      expect(segment.bpmConfidence, 0);
      expect(segment.keyConfidence, 0);
      expect(segment.dropConfidence, 0);
      expect(segment.breakdownConfidence, 0);
      expect(segment.structureConfidence, 0);
      expect(segment.vocalLikelihood, 0);
      expect(segment.vocalConfidence, 0);
    });

    test('forwards vocal and structural confidence with safe defaults', () {
      final segment = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'segmentStartSeconds': 120.0,
          'segmentSeconds': 118.0,
          'bpm': 124.0,
          'bpmConfidence': 0.9,
          'alternateBpm': 62.0,
          'beatOffsetMs': 24.0,
          'downbeatOffsetMs': 240.0,
          'dropCueMs': 34000.0,
          'breakdownCueMs': 113000.0,
          'dropConfidence': 0.81,
          'breakdownConfidence': 0.77,
          'structureRegion': 4,
          'structureConfidence': 0.88,
          'vocalLikelihood': 0.72,
          'vocalConfidence': 0.93,
          'camelotNumber': 8,
          'camelotMinor': true,
          'keyConfidence': 0.9,
          'rmsDb': -11.0,
          'centroidHz': 2600.0,
          'onsetRate': 3.2,
          'introEdgeRmsDb': -18.0,
          'outroEdgeRmsDb': -24.0,
          'introEdgeLufs': -17.5,
          'outroEdgeLufs': -23.5,
          'introEdgeOnsetRate': 1.6,
          'outroEdgeOnsetRate': 0.7,
        },
        fallbackStartSeconds: 0,
        fallbackSeconds: 120,
      );

      expect(segment.startSeconds, 120);
      expect(segment.bpm, 124);
      expect(segment.alternateBpm, 62);
      expect(segment.dropConfidence, 0.81);
      expect(segment.breakdownConfidence, 0.77);
      expect(segment.structureRegion, 4);
      expect(segment.structureConfidence, 0.88);
      expect(segment.vocalLikelihood, 0.72);
      expect(segment.vocalConfidence, 0.93);
      expect(segment.introEdgeRmsDb, -18);
      expect(segment.outroEdgeRmsDb, -24);
      expect(segment.introEdgeLufs, -17.5);
      expect(segment.outroEdgeLufs, -23.5);
      expect(segment.introEdgeOnsetRate, 1.6);
      expect(segment.outroEdgeOnsetRate, 0.7);
    });

    test('parses and time-sorts the three drop candidates', () {
      final segment = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'dropCueMs': 40000.0,
          'dropConfidence': 0.80,
          'dropCueMs2': 30000.0,
          'dropConfidence2': 0.60,
          'dropCueMs3': 20000.0,
          'dropConfidence3': 0.90,
        },
        fallbackStartSeconds: 0,
        fallbackSeconds: 120,
      );
      expect(segment.dropCues.map((cue) => cue.cueMs), [20000, 30000, 40000]);
      expect(segment.dropCues.map((cue) => cue.confidence), [0.9, 0.6, 0.8]);
      // Adjacent frames from one onset collapse to the stronger candidate.
      final deduped = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'dropCueMs': 30000.0,
          'dropConfidence': 0.6,
          'dropCueMs2': 30200.0,
          'dropConfidence2': 0.8,
        },
        fallbackStartSeconds: 0,
        fallbackSeconds: 120,
      );
      expect(deduped.dropCues, hasLength(1));
      expect(deduped.dropCues.single.cueMs, 30200);
      expect(deduped.dropCues.single.confidence, 0.8);
    });

    test('parses metre and the track-level section cue', () {
      final segment = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'bpm': 120.0,
          'bpmConfidence': 0.9,
          'downbeatOffsetMs': 137.0,
          'meter': 3,
          'sectionCueMs': 30000.0,
          'sectionCueConfidence': 0.82,
        },
        fallbackStartSeconds: 0,
        fallbackSeconds: 120,
      );
      expect(segment.meter, 3);
      expect(segment.sectionCueMs, 30000);
      expect(segment.sectionCueConfidence, 0.82);

      // Compound 6/8 at a dotted-quarter pulse is metre 2 and must survive
      // parsing; a missing or out-of-contract metre is the legacy 4/4
      // assumption, never a silently accepted 5- or 7-beat bar.
      final compound = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{'bpm': 80.0, 'bpmConfidence': 0.8, 'meter': 2},
        fallbackStartSeconds: 0,
        fallbackSeconds: 120,
      );
      expect(compound.meter, 2);
      for (final raw in <Object?>[null, 5, 7, 4.5, double.nan]) {
        final fallback = automixSegmentFeaturesFromAnalysisMap(
          <String, dynamic>{'bpm': 120.0, 'bpmConfidence': 0.9, 'meter': raw},
          fallbackStartSeconds: 0,
          fallbackSeconds: 120,
        );
        expect(fallback.meter, 4, reason: 'meter=$raw');
      }
    });

    test('merge keeps per-edge metre and absolutises the section cue', () {
      final head = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'segmentStartSeconds': 0.0,
          'segmentSeconds': 118.0,
          'bpm': 120.0,
          'bpmConfidence': 0.9,
          'downbeatOffsetMs': 100.0,
          'meter': 4,
        },
        fallbackStartSeconds: 0,
        fallbackSeconds: 120,
      );
      final tail = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'segmentStartSeconds': 122.0,
          'segmentSeconds': 118.0,
          'bpm': 120.0,
          'bpmConfidence': 0.9,
          'endBpm': 120.0,
          'endBpmConfidence': 0.9,
          'tailBpmConfidence': 0.9,
          'downbeatOffsetMs': 200.0,
          'meter': 3,
          'sectionCueMs': 30000.0,
          'sectionCueConfidence': 0.82,
        },
        fallbackStartSeconds: 122,
        fallbackSeconds: 118,
      );
      final merged = automixMergeSegments(
        songId: 9,
        segments: <AutomixSegmentFeatures>[head, tail],
      );
      expect(merged.meter, 4);
      expect(merged.tailMeter, 3);
      expect(merged.tailSectionCueMs, 152000);
      expect(merged.tailSectionCueConfidence, 0.82);

      // The new fields must survive the SharedPreferences round trip.
      final restored = AutomixTrackFeatures.fromMap(merged.toMap());
      expect(restored.meter, 4);
      expect(restored.tailMeter, 3);
      expect(restored.tailSectionCueMs, 152000);
      expect(restored.tailSectionCueConfidence, 0.82);
    });

    test('parses and rejects time-stamped chord estimates safely', () {
      final segment = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'chordProgression': <Map<String, Object>>[
            <String, Object>{
              'startMs': 1200,
              'rootPitchClass': 0,
              'root': 'C',
              'quality': 'maj',
              'label': 'Cmaj',
              'confidence': 0.91,
            },
            <String, Object>{
              'startMs': 2400,
              'rootPitchClass': 7,
              'quality': 'min',
              'confidence': 0.83,
            },
            <String, Object>{
              'startMs': double.infinity,
              'rootPitchClass': 4,
              'quality': 'maj',
              'confidence': 0.9,
            },
            <String, Object>{
              'startMs': 4000,
              'rootPitchClass': 2,
              'quality': 'unsupported',
              'confidence': 0.99,
            },
            <String, Object>{
              'startMs': 4400,
              'rootPitchClass': 11,
              'quality': 'm7b5',
              'label': 'Bm7b5',
              'confidence': 0.77,
            },
            <String, Object>{
              'startMs': 4800,
              'rootPitchClass': 5,
              'quality': 'sus2',
              'confidence': 0.66,
            },
            <String, Object>{
              'startMs': 5000,
              'rootPitchClass': 9,
              'quality': 'min',
              'confidence': 0.01,
            },
          ],
          'startBpm': 128.5,
          'endBpm': 0.0,
          'tempoStability': 0.62,
        },
        fallbackStartSeconds: 0,
        fallbackSeconds: 120,
      );

      expect(segment.chordProgression, hasLength(4));
      expect(segment.chordProgression.first.label, 'Cmaj');
      expect(segment.chordProgression[1].label, 'Gmin');
      expect(segment.chordProgression[1].confidence, 0.83);
      expect(segment.chordProgression[2].label, 'Bm7b5');
      expect(segment.chordProgression[3].label, 'Fsus2');
      // Non-positive BPMs are rejected; a valid stability parses.
      expect(segment.startBpm, 128.5);
      expect(segment.endBpm, isNull);
      expect(segment.tempoStability, 0.62);

      final invalidCurve = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'startBpm': 'fast',
          'endBpm': double.nan,
          'tempoStability': 1.5,
        },
        fallbackStartSeconds: 0,
        fallbackSeconds: 120,
      );
      expect(invalidCurve.startBpm, isNull);
      expect(invalidCurve.endBpm, isNull);
      expect(invalidCurve.tempoStability, isNull);
    });

    test('parses local edge-tempo confidence and matching beat phases', () {
      final segment = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'startBpm': 118.0,
          'startBpmConfidence': 0.74,
          'endBpm': 126.0,
          'endBpmConfidence': 0.88,
          'startBeatOffsetMs': 122.0,
          'endBeatOffsetMs': 275.0,
          'tempoStability': 0.81,
        },
        fallbackStartSeconds: 0,
        fallbackSeconds: 120,
      );
      expect(segment.startBpm, 118.0);
      expect(segment.startBpmConfidence, 0.74);
      expect(segment.endBpm, 126.0);
      expect(segment.endBpmConfidence, 0.88);
      expect(segment.startBeatOffsetMs, 122.0);
      expect(segment.endBeatOffsetMs, 275.0);

      final invalid = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'startBpm': 118.0,
          'startBpmConfidence': double.infinity,
          'endBpm': 126.0,
          'endBpmConfidence': -0.2,
          'startBeatOffsetMs': -1.0,
          'endBeatOffsetMs': double.nan,
        },
        fallbackStartSeconds: 0,
        fallbackSeconds: 120,
      );
      expect(invalid.startBpmConfidence, 0);
      expect(invalid.endBpmConfidence, 0);
      expect(invalid.startBeatOffsetMs, isNull);
      expect(invalid.endBeatOffsetMs, isNull);
    });

    test('parses only complete finite quarter energy profiles', () {
      final complete = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'energyQuarters': <double>[-24, -18, -12, -6],
        },
        fallbackStartSeconds: 0,
        fallbackSeconds: 120,
      );
      expect(complete.energyQuarters, [-24, -18, -12, -6]);

      for (final raw in <Object?>[
        <double>[-24, -18, -12],
        <double>[-24, -18, -12, double.nan],
        <Object>[-24, -18, -12, 'loud'],
        'quarters',
      ]) {
        final segment = automixSegmentFeaturesFromAnalysisMap(
          <String, dynamic>{'energyQuarters': raw},
          fallbackStartSeconds: 0,
          fallbackSeconds: 120,
        );
        expect(segment.energyQuarters, isEmpty, reason: 'raw=$raw');
      }
    });

    test('uses neutral fallbacks for malformed field types', () {
      final segment = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'segmentStartSeconds': 'not-a-number',
          'segmentSeconds': false,
          'bpm': 'fast',
          'bpmConfidence': 'certain',
          'alternateBpm': 'double-time',
          'keyConfidence': 0.9,
          'camelotNumber': '8',
          'camelotMinor': 'true',
          'vocalLikelihood': true,
          'vocalConfidence': <String, Object>{'value': 0.9},
          'structureRegion': 'drop',
        },
        fallbackStartSeconds: 12,
        fallbackSeconds: 120,
      );

      expect(segment.startSeconds, 12);
      expect(segment.seconds, 120);
      expect(segment.bpm, isNull);
      expect(segment.bpmConfidence, 0);
      expect(segment.alternateBpm, isNull);
      expect(segment.camelotNumber, isNull);
      expect(segment.camelotMinor, isNull);
      expect(segment.vocalLikelihood, 0);
      expect(segment.vocalConfidence, 0);
      expect(segment.structureRegion, 0);
    });

    test('rejects non-finite or out-of-range confidence metadata', () {
      final segment = automixSegmentFeaturesFromAnalysisMap(
        <String, dynamic>{
          'bpm': double.nan,
          'bpmConfidence': double.nan,
          'dropConfidence': double.infinity,
          'breakdownConfidence': -0.3,
          'structureRegion': 99,
          'structureConfidence': 4.0,
          'vocalLikelihood': double.nan,
          'vocalConfidence': 1.7,
          'dropCueMs': double.infinity,
          'camelotNumber': 99,
          'keyConfidence': 1,
        },
        fallbackStartSeconds: 0,
        fallbackSeconds: 120,
      );

      expect(segment.bpm, isNull);
      expect(segment.bpmConfidence, 0);
      expect(segment.dropConfidence, 0);
      expect(segment.breakdownConfidence, 0);
      expect(segment.structureRegion, 0);
      expect(segment.structureConfidence, 0);
      expect(segment.vocalLikelihood, 0);
      expect(segment.vocalConfidence, 0);
      expect(segment.dropCueMs, isNull);
      expect(segment.camelotNumber, isNull);
    });
  });

  group('automixConfidenceBlend', () {
    test('moves unreliable estimates toward a neutral cost', () {
      expect(automixConfidenceBlend(0.0, 0.0, neutralCost: 0.35), 0.35);
      expect(automixConfidenceBlend(1.0, 0.0, neutralCost: 0.35), 0.35);
      expect(automixConfidenceBlend(0.0, 1.0, neutralCost: 0.35), 0.0);
      expect(
        automixConfidenceBlend(0.0, 0.5, neutralCost: 0.35),
        closeTo(0.175, 1e-12),
      );
      expect(automixConfidenceBlend(0.0, 0.0, neutralCost: 0.5), 0.5);
    });
  });

  group('automixCamelotCost', () {
    test('same key is free, relative pair cheap, unknown neutral', () {
      expect(automixCamelotCost(8, true, 8, true), 0.0); // 8A → 8A
      expect(automixCamelotCost(8, false, 8, false), 0.0); // 8B → 8B
      expect(automixCamelotCost(8, true, 8, false), 0.15); // 8A → 8B
      expect(automixCamelotCost(8, false, 8, true), 0.15);
      expect(automixCamelotCost(8, true, null, true), 0.5);
      expect(automixCamelotCost(null, true, 8, true), 0.5);
    });

    test('same-ring adjacency wraps 12 ↔ 1', () {
      final adjacentWrap = automixCamelotCost(1, true, 12, true);
      final inside = automixCamelotCost(5, true, 6, true);
      expect(adjacentWrap, inside); // both "±1 same ring" (folded)
      expect(adjacentWrap, 0.2);

      final wrapTwo = automixCamelotCost(12, true, 2, true);
      final insideTwo = automixCamelotCost(5, true, 7, true);
      expect(wrapTwo, insideTwo); // folded ±2
      expect(wrapTwo, 0.3);

      final far = automixCamelotCost(1, true, 6, true);
      expect(far, 1.0);

      final crossRingSameNumber = automixCamelotCost(7, false, 7, true);
      expect(crossRingSameNumber, 0.15);
      final crossRingDiagonal = automixCamelotCost(7, false, 8, true);
      expect(crossRingDiagonal, 0.45);
    });
  });

  group('automixTempoCost', () {
    const tol = 0.06;

    test('identical BPM is free', () {
      expect(automixTempoCost(120, null, 120, null, tol), 0.0);
      expect(automixTempoCost(120.5, null, 120.9, null, tol), lessThan(0.2));
    });

    test('half/double-time folds to beat-perfect', () {
      expect(automixTempoCost(120, null, 60, null, tol), 0.0);
      expect(automixTempoCost(120, null, 240, null, tol), 0.0);
      // Extractor-reported alternate also folds.
      expect(automixTempoCost(86, 172, 90, null, tol), isNonNegative);
      expect(automixTempoCost(86, 172, 90, null, tol), lessThan(1.0));
    });

    test('percentage tolerance uses slower tempo as denominator', () {
      final near = automixTempoCost(120, null, 123, null, tol);
      final fivePercent = automixTempoCost(120, null, 126, null, tol);
      final sixPercent = automixTempoCost(120, null, 127.2, null, tol);
      final reverse = automixTempoCost(127.2, null, 120, null, tol);
      final way = automixTempoCost(120, null, 170, null, tol);

      expect(near, inInclusiveRange(0, fivePercent));
      // 126 BPM is +5% relative to 120 BPM, so it remains inside 6%.
      expect(fivePercent, inInclusiveRange(0, 0.5));
      // 127.2 BPM is exactly +6%; either direction reaches the ramp boundary.
      expect(sixPercent, closeTo(0.5, 0.01));
      expect(reverse, closeTo(sixPercent, 1e-9));
      expect(near, lessThan(fivePercent));
      expect(way, 1.0);
    });

    test('unknown tempos land on the neutral fallback', () {
      expect(automixTempoCost(null, null, 120, null, tol), 0.35);
      expect(automixTempoCost(120, null, null, null, tol), 0.35);
    });
  });

  group('AutoMix edge-tempo stability gate', () {
    test('allows stable or unknown curves and rejects measured drift', () {
      final stableOutgoing = AutomixTrackFeatures(
        songId: 1,
        bpm: 120,
        bpmConfidence: 0.9,
        tailBpm: 122,
        tailBpmConfidence: 0.9,
        outroTempoStability: 0.82,
      );
      final stableIncoming = AutomixTrackFeatures(
        songId: 2,
        bpm: 121,
        bpmConfidence: 0.9,
        startBpm: 121,
        startBpmConfidence: 0.9,
        introTempoStability: 0.65,
      );
      final unstableOutgoing = AutomixTrackFeatures(
        songId: 3,
        bpm: 120,
        bpmConfidence: 0.9,
        tailBpm: 96,
        tailBpmConfidence: 0.9,
        outroTempoStability: 0.42,
      );

      expect(
        automixTempoCurveAllowsPair(stableOutgoing, stableIncoming),
        isTrue,
      );
      expect(
        automixTempoCurveAllowsPair(unstableOutgoing, stableIncoming),
        isFalse,
      );
      expect(automixTempoStabilityAllowsPull(null), isTrue);
      expect(automixTempoStabilityAllowsPull(0.649), isFalse);
    });
  });

  group('automixKeyToCamelot', () {
    test('canonical anchors', () {
      expect(automixKeyToCamelot(0, false), (8, false)); // C major = 8B
      expect(automixKeyToCamelot(9, true), (8, true)); // A minor = 8A
      expect(automixKeyToCamelot(1, false), (3, false)); // Db major = 3B
      expect(automixKeyToCamelot(4, false), (12, false)); // E major = 12B
      expect(automixKeyToCamelot(-12, false), (8, false));
      expect(automixKeyToCamelot(-3, false), automixKeyToCamelot(9, false));
    });

    test('relative pairs share the number', () {
      for (var pc = 0; pc < 12; pc++) {
        final maj = automixKeyToCamelot(pc, false)!;
        // relative minor of pitch class +3 flats to the same camelot number?
        // C major (8B) ↔ A minor (8A): minor tonic = major tonic - 3.
        final relMinor = automixKeyToCamelot((pc + 9) % 12, true)!;
        expect(relMinor.$1, maj.$1, reason: 'pc=$pc');
      }
    });
  });

  group('automixNormalizeEnergy', () {
    test('missing analysis degrades to neutral', () {
      final e = automixNormalizeEnergy([_f(1), _f(2)]);
      expect(e, [0.5, 0.5]);
    });

    test('loudness ordering is preserved and bounded', () {
      final feats = [
        _f(1, lufs: -22),
        _f(2, lufs: -14),
        _f(3, lufs: -8),
        _f(4), // missing → 0.5
      ];
      final e = automixNormalizeEnergy(feats);
      expect(e[0], lessThan(e[1]));
      expect(e[1], lessThan(e[2]));
      for (final v in e) {
        expect(v, inInclusiveRange(0, 1));
      }
      expect(e[3], 0.5);
    });

    test('rms+centroid+onset beats lufs-only when both present', () {
      final a = _f(1, lufs: -12, rms: -8, centroid: 3000, onset: 4);
      final b = _f(2, lufs: -12, rms: -20, centroid: 600, onset: 1);
      final e = automixNormalizeEnergy([a, b]);
      expect(e[0], greaterThan(e[1]));
    });
  });

  group('AutomixEngine.planSet', () {
    test('single track', () {
      final plan = AutomixEngine.planSet(
        tracks: [_f(1)],
        settings: const AutomixSettings(),
        startIndex: 0,
      );
      expect(plan.order, [0]);
      expect(plan.crossfadeSeconds, 2.0);
    });

    test('keeps the requested start track and visits every track once', () {
      final tracks = [
        for (var i = 1; i <= 30; i++)
          _f(
            i,
            bpm: 100 + (i % 7) * 3.0,
            alt: null,
            camelot: (i % 12) + 1,
            minor: i.isEven,
          ),
      ];
      const settings = AutomixSettings(profile: AutomixProfile.dj);
      final plan = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 7,
      );
      expect(plan.order.first, 7);
      expect(plan.order.toSet().length, tracks.length);
      expect(plan.order.length, tracks.length);
      for (final idx in plan.order) {
        expect(idx, inInclusiveRange(0, tracks.length - 1));
      }
      // Average cost in [0,1].
      expect(plan.averageCost, inInclusiveRange(0, 1));
    });

    test('deterministic across repeated calls', () {
      final tracks = [
        for (var i = 1; i <= 40; i++)
          _f(
            i,
            bpm: 90 + (i % 11) * 4,
            camelot: ((i * 5) % 12) + 1,
            minor: i.isOdd,
          ),
      ];
      const settings = AutomixSettings(profile: AutomixProfile.harmonic);
      final a = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 3,
      );
      final b = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 3,
      );
      expect(a.order, b.order);
      expect(a.averageCost, closeTo(b.averageCost, 1e-12));
    });

    test('native planner preserves the Dart reference across profiles', () {
      final tracks = [
        for (var i = 0; i < 36; i++)
          _f(
            i + 1,
            bpm: i % 9 == 0 ? null : 78 + (i * 17 % 83).toDouble(),
            alt: i % 4 == 0 ? 120 + (i % 5).toDouble() : null,
            camelot: i % 7 == 0 ? null : (i * 5 % 12) + 1,
            minor: i % 7 == 0 ? null : i.isOdd,
            lufs: i % 5 == 0 ? null : -24 + (i * 7 % 19).toDouble(),
            rms: i % 3 == 0 ? -25 + (i % 18).toDouble() : null,
            centroid: i % 4 == 0 ? 500 + (i * 131 % 3900).toDouble() : null,
            onset: i % 6 == 0 ? null : 0.5 + (i % 6).toDouble(),
            artist: i % 5 < 2 ? ' Artist ${i % 5} ' : '',
            bpmConf: (i % 10) / 10,
            keyConf: (i % 8) / 8,
          ),
      ];

      for (final profile in AutomixProfile.values) {
        final settings = AutomixSettings(
          profile: profile,
          bpmTolerancePercent: 7.5,
          crossfadeBeats: 24,
          harmonicFilter: profile == AutomixProfile.harmonic,
        );
        final reference = DartAutomixEngineReference.planSet(
          tracks: tracks,
          settings: settings,
          startIndex: 5,
        );
        final native = AutomixEngine.planSet(
          tracks: tracks,
          settings: settings,
          startIndex: 5,
        );
        expect(native.order, reference.order, reason: 'profile $profile');
        expect(
          native.crossfadeSeconds,
          closeTo(reference.crossfadeSeconds, 1e-10),
          reason: 'profile $profile crossfade',
        );
        expect(
          native.averageCost,
          closeTo(reference.averageCost, 1e-10),
          reason: 'profile $profile average cost',
        );
      }
    });

    test(
      'high-confidence vocal clash prefers the low-confidence alternative',
      () {
        final tracks = [
          _f(
            1,
            bpm: 120,
            camelot: 8,
            minor: true,
            vocalLikelihood: 0.9,
            vocalConfidence: 0.8,
          ),
          _f(
            2,
            bpm: 120,
            camelot: 8,
            minor: true,
            vocalLikelihood: 0.9,
            vocalConfidence: 0.8,
          ),
          _f(
            3,
            bpm: 120,
            camelot: 8,
            minor: true,
            vocalLikelihood: 0.9,
            vocalConfidence: 0.1,
          ),
        ];
        const settings = AutomixSettings(profile: AutomixProfile.dj);
        final native = AutomixEngine.planSet(
          tracks: tracks,
          settings: settings,
          startIndex: 0,
        );
        final reference = DartAutomixEngineReference.planSet(
          tracks: tracks,
          settings: settings,
          startIndex: 0,
        );
        expect(native.order, [0, 2, 1]);
        expect(native.order, reference.order);
      },
    );

    test('empty list yields empty plan', () {
      final plan = AutomixEngine.planSet(
        tracks: const [],
        settings: const AutomixSettings(),
        startIndex: 0,
      );
      expect(plan.order, isEmpty);
      expect(plan.crossfadeSeconds, 0);
    });

    test(
      'harmonic profile avoids big camelot jumps when alternatives exist',
      () {
        // Track 1: 8A; candidate 2: 8A-compatible; candidate 3: 1B (far).
        final tracks = [
          _f(1, bpm: 120, camelot: 8, minor: true),
          _f(2, bpm: 120, camelot: 8, minor: true),
          _f(3, bpm: 120, camelot: 1, minor: false),
        ];
        const settings = AutomixSettings(profile: AutomixProfile.harmonic);
        final plan = AutomixEngine.planSet(
          tracks: tracks,
          settings: settings,
          startIndex: 0,
        );
        expect(plan.order[1], 1); // compatible neighbor first
      },
    );

    test('finds a half-time match outside the local raw-BPM window', () {
      // Raw-BPM order places 60 BPM more than 12 slots from 120 BPM. The
      // half/double-time candidate pool should still discover it immediately.
      final tracks = <AutomixTrackFeatures>[
        _f(1, bpm: 120, camelot: 8, minor: true, bpmConf: 0.99, keyConf: 0.99),
        for (var i = 0; i < 30; i++)
          _f(
            i + 2,
            bpm: 90 + i.toDouble(),
            camelot: 1,
            minor: false,
            bpmConf: 0.99,
            keyConf: 0.99,
          ),
        _f(
          1000,
          bpm: 60,
          camelot: 8,
          minor: true,
          bpmConf: 0.99,
          keyConf: 0.99,
        ),
      ];
      final plan = AutomixEngine.planSet(
        tracks: tracks,
        settings: const AutomixSettings(profile: AutomixProfile.dj),
        startIndex: 0,
      );

      expect(plan.order.first, 0);
      expect(tracks[plan.order[1]].songId, 1000);
    });

    test('artist variety spreads same-artist tracks when possible', () {
      final tracks = [
        _f(1, bpm: 100, artist: 'X'),
        _f(2, bpm: 100, artist: 'Y'),
        _f(3, bpm: 100, artist: 'X'),
        _f(4, bpm: 100, artist: 'Y'),
      ];
      const settings = AutomixSettings(
        profile: AutomixProfile.dj,
        avoidArtistRepeat: true,
      );
      final plan = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );
      for (var i = 0; i + 1 < plan.order.length; i++) {
        final aArtist = tracks[plan.order[i]].artist;
        final bArtist = tracks[plan.order[i + 1]].artist;
        expect(aArtist, isNot(bArtist), reason: 'pair ${plan.order[i]}');
      }
    });

    test('P10: 50-track plans avoid artist repeats within two slots', () {
      final tracks = <AutomixTrackFeatures>[
        for (var artistIndex = 0; artistIndex < 10; artistIndex++)
          for (var trackIndex = 0; trackIndex < 5; trackIndex++)
            _f(
              artistIndex * 5 + trackIndex + 1,
              bpm: 120,
              camelot: 8,
              minor: true,
              artist: 'Artist $artistIndex',
            ),
      ];
      const settings = AutomixSettings(
        profile: AutomixProfile.dj,
        avoidArtistRepeat: true,
      );
      final plan = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );
      final reference = DartAutomixEngineReference.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );

      expect(plan.order, hasLength(50));
      expect(plan.order.toSet(), hasLength(50));
      expect(
        plan.order,
        isNot(List<int>.generate(50, (index) => index)),
        reason: 'artist cooldown must improve the original queue order',
      );
      expect(plan.order, reference.order);
      for (var i = 0; i < plan.order.length; i++) {
        final artist = tracks[plan.order[i]].artist;
        for (var prior = i - 2; prior < i; prior++) {
          if (prior < 0) continue;
          expect(
            artist,
            isNot(tracks[plan.order[prior]].artist),
            reason: 'repeated $artist at planned positions $prior and $i',
          );
        }
      }
    });

    test('energy profile pushes loud tracks toward the middle', () {
      final tracks = [
        _f(1, lufs: -24), // quiet
        _f(2, lufs: -12), // loud
        _f(3, lufs: -8), // loudest
        _f(4, lufs: -20),
      ];
      const settings = AutomixSettings(profile: AutomixProfile.energy);
      final plan = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );
      final energies = automixNormalizeEnergy(tracks);
      final peakIdx = energies.indexOf(
        energies.reduce((a, b) => a > b ? a : b),
      );
      final peakPos = plan.order.indexOf(peakIdx) / (plan.order.length - 1);
      expect(peakPos, greaterThan(0.3));
      expect(peakPos, lessThan(0.8));
    });
  });

  group('mix-seam-aware sequencing', () {
    test('scores tempo at the seam using the outgoing exit (tail) tempo', () {
      // Track A's head sits at 100 BPM, but its tail (where the fade happens)
      // is 128 BPM. The naturally compatible incoming track heads at 128.
      final tracks = [
        _f(
          1,
          bpm: 100,
          tailBpm: 128,
          tailBpmConfidence: 0.95,
          camelot: 8,
          minor: true,
          rms: -12,
        ),
        _f(2, bpm: 128, camelot: 8, minor: true, rms: -12),
        _f(3, bpm: 100, camelot: 8, minor: true, rms: -12),
      ];
      const settings = AutomixSettings(profile: AutomixProfile.dj);
      final native = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );
      final reference = DartAutomixEngineReference.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );

      // The tail-matched track (index 1) must follow the outgoing track, even
      // though the head-BPM-matched track (index 2) is what a head-only score
      // would pick.
      expect(native.order, [0, 1, 2]);
      expect(native.order, reference.order);
    });

    test('ignores an untrusted tail BPM and uses the head BPM/confidence', () {
      final tracks = [
        _f(
          1,
          bpm: 100,
          tailBpm: 128,
          tailBpmConfidence: 0.1,
          camelot: 8,
          minor: true,
          rms: -12,
        ),
        _f(2, bpm: 128, camelot: 8, minor: true, rms: -12),
        _f(3, bpm: 100, camelot: 8, minor: true, rms: -12),
      ];

      expect(automixExitBpm(tracks.first), 100);
      expect(automixExitBpmConfidence(tracks.first), 0.9);

      const settings = AutomixSettings(profile: AutomixProfile.dj);
      final native = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );
      final reference = DartAutomixEngineReference.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );

      expect(native.order, [0, 2, 1]);
      expect(native.order, reference.order);
    });

    test('penalizes a mismatched outro/intro energy seam', () {
      // Track 0 exits loud. Track 1 enters quiet and track 2 enters equally
      // loud; track 1 has the smaller song id, so only the section-seam term
      // makes the engine prefer the matching-energy track 2 first.
      final tracks = [
        _f(1, bpm: 120, camelot: 8, minor: true, rms: -12, outroEnergy: 0.9),
        _f(2, bpm: 120, camelot: 8, minor: true, rms: -12, introEnergy: 0.1),
        _f(3, bpm: 120, camelot: 8, minor: true, rms: -12, introEnergy: 0.9),
      ];
      const settings = AutomixSettings(profile: AutomixProfile.dj);
      final native = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );
      final reference = DartAutomixEngineReference.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );

      expect(native.order, [0, 2, 1]);
      expect(native.order, reference.order);
    });

    test('prefers a calm structural seam over a repeated peak', () {
      // Track 0 exits on a drop. Track 1 enters on a drop as well and has the
      // smaller song id; track 2 enters on a buildup. Only the structural
      // seam term separates them, so the planner must hand over into track 2.
      final tracks = [
        _f(
          1,
          bpm: 120,
          camelot: 8,
          minor: true,
          rms: -12,
          tailStructureRegion: 3,
          tailStructureConfidence: 0.9,
        ),
        _f(
          2,
          bpm: 120,
          camelot: 8,
          minor: true,
          rms: -12,
          structureRegion: 3,
          structureConfidence: 0.9,
        ),
        _f(
          3,
          bpm: 120,
          camelot: 8,
          minor: true,
          rms: -12,
          structureRegion: 2,
          structureConfidence: 0.9,
        ),
      ];
      const settings = AutomixSettings(profile: AutomixProfile.dj);
      final native = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );
      final reference = DartAutomixEngineReference.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );

      expect(native.order, [0, 2, 1]);
      expect(native.order, reference.order);
    });

    test('continues a building outro into a building intro', () {
      // Track 0 exits while still building (+12 dB/quarter). Track 1 keeps
      // building (+12), track 2 falls hard (-12) and has the smaller song id,
      // so without the momentum term the id tie-break would pick track 2.
      final tracks = [
        _f(1, bpm: 120, camelot: 8, minor: true, rms: -12, outroSlope: 12),
        _f(3, bpm: 120, camelot: 8, minor: true, rms: -12, introSlope: 12),
        _f(2, bpm: 120, camelot: 8, minor: true, rms: -12, introSlope: -12),
      ];
      const settings = AutomixSettings(profile: AutomixProfile.dj);
      final native = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );
      final reference = DartAutomixEngineReference.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );

      expect(native.order, [0, 1, 2]);
      expect(native.order, reference.order);
    });

    test('ignores unconfident structure labels at the seam', () {
      // Same shape as the confident-seam fixture, but every structure label is
      // below the 0.5 confidence gate: the term must stay neutral and the
      // smaller song id (track 1) keeps the tie.
      final tracks = [
        _f(
          1,
          bpm: 120,
          camelot: 8,
          minor: true,
          rms: -12,
          tailStructureRegion: 3,
          tailStructureConfidence: 0.3,
        ),
        _f(
          2,
          bpm: 120,
          camelot: 8,
          minor: true,
          rms: -12,
          structureRegion: 3,
          structureConfidence: 0.3,
        ),
        _f(
          3,
          bpm: 120,
          camelot: 8,
          minor: true,
          rms: -12,
          structureRegion: 2,
          structureConfidence: 0.3,
        ),
      ];
      const settings = AutomixSettings(profile: AutomixProfile.dj);
      final native = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );
      final reference = DartAutomixEngineReference.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );

      expect(native.order, [0, 1, 2]);
      expect(native.order, reference.order);
    });

    test('adaptive energy arc lifts loud tracks into the measured peak', () {
      // Same fixture as the native regression: five quiet tracks and two
      // loud ones over equal tempo/key. The set-adaptive arc projects the DJ
      // arc onto the measured p20..p80 range, so the loud pair lands near the
      // middle instead of chaining ascending energies (0..6).
      const rms = [-26.0, -25.0, -24.0, -22.0, -20.0, -4.0, -3.0];
      final tracks = [
        for (var i = 0; i < 7; i++)
          _f(i + 1, bpm: 120, camelot: 8, minor: true, rms: rms[i]),
      ];
      const settings = AutomixSettings(profile: AutomixProfile.dj);
      final native = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );
      final reference = DartAutomixEngineReference.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );

      expect(native.order, [0, 1, 2, 5, 6, 4, 3]);
      expect(native.order, reference.order);
    });

    test('spreads a repeated artist past the cooldown window', () {
      // Every transition costs the same, so only the artist cooldown can break
      // the id-ordered tie. Without it the planner would chain X, Y, X (song
      // id 3), Z; with it the X at distance 2 yields to the unlabeled Z and
      // the repeat lands outside the cooldown window.
      final tracks = [
        _f(1, bpm: 120, camelot: 8, minor: true, rms: -12, artist: 'X'),
        _f(2, bpm: 120, camelot: 8, minor: true, rms: -12, artist: 'Y'),
        _f(3, bpm: 120, camelot: 8, minor: true, rms: -12, artist: 'X'),
        _f(4, bpm: 120, camelot: 8, minor: true, rms: -12, artist: 'Z'),
      ];
      const settings = AutomixSettings(
        profile: AutomixProfile.dj,
        avoidArtistRepeat: true,
      );
      final native = AutomixEngine.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );
      final reference = DartAutomixEngineReference.planSet(
        tracks: tracks,
        settings: settings,
        startIndex: 0,
      );

      expect(native.order, [0, 1, 3, 2]);
      expect(native.order, reference.order);
      // The path and average cost include the same full artist cooldown in
      // both implementations, not only the transition term.
      expect(native.averageCost, closeTo(reference.averageCost, 1e-10));
      expect(native.averageCost, greaterThan(0));
    });

    test(
      'local polish scores artist cooldown beyond changed transition links',
      () {
        // Identical audio features isolate artist cooldown. Reversing slots 2–8
        // improves the full path score, including penalties in the four slots
        // after the moved range; the old boundary-only scorer missed those.
        const artists = <String>[
          'A3',
          'A4',
          'A0',
          'A4',
          'A4',
          'A1',
          'A2',
          'A3',
          'A1',
          'A1',
          'A4',
          'A2',
        ];
        final tracks = [
          for (var i = 0; i < artists.length; i++)
            _f(
              i + 1,
              bpm: 120,
              camelot: 8,
              minor: true,
              rms: -12,
              artist: artists[i],
            ),
        ];
        const settings = AutomixSettings(
          profile: AutomixProfile.dj,
          avoidArtistRepeat: true,
        );
        final native = AutomixEngine.planSet(
          tracks: tracks,
          settings: settings,
          startIndex: 0,
        );
        final reference = DartAutomixEngineReference.planSet(
          tracks: tracks,
          settings: settings,
          startIndex: 0,
        );
        const knownImprovement = <int>[0, 1, 8, 6, 3, 7, 2, 5, 11, 4, 9, 10];
        final plannedCost = AutomixEngine.scoreOrder(
          tracks: tracks,
          order: native.order,
          settings: settings,
        );
        final improvedCost = AutomixEngine.scoreOrder(
          tracks: tracks,
          order: knownImprovement,
          settings: settings,
        );

        expect(native.order, reference.order);
        expect(native.averageCost, closeTo(plannedCost, 1e-10));
        expect(plannedCost, lessThanOrEqualTo(improvedCost + 1e-9));
      },
    );

    test(
      'keeps native/reference parity when mix-seam features are present',
      () {
        final tracks = [
          for (var i = 0; i < 30; i++)
            _f(
              i + 1,
              bpm: 78 + (i * 13 % 70).toDouble(),
              tailBpm: i % 3 == 0 ? null : 90 + (i * 7 % 60).toDouble(),
              introEnergy: i % 4 == 0 ? null : (i % 10) / 10,
              outroEnergy: i % 5 == 0 ? null : ((i + 3) % 10) / 10,
              camelot: (i * 5 % 12) + 1,
              minor: i.isOdd,
              rms: -24 + (i % 12).toDouble(),
              bpmConf: (i % 10) / 10,
              keyConf: (i % 8) / 8,
              structureRegion: i % 3 == 0 ? 0 : (i % 5) + 1,
              structureConfidence: i % 4 == 0 ? 0 : 0.6 + (i % 3) * 0.1,
              tailStructureRegion: i % 5 == 0 ? 0 : (i % 5) + 1,
              tailStructureConfidence: 0.7,
            ),
        ];
        for (final profile in AutomixProfile.values) {
          final settings = AutomixSettings(
            profile: profile,
            bpmTolerancePercent: 7.5,
            crossfadeBeats: 24,
            harmonicFilter: profile == AutomixProfile.harmonic,
          );
          final reference = DartAutomixEngineReference.planSet(
            tracks: tracks,
            settings: settings,
            startIndex: 5,
          );
          final native = AutomixEngine.planSet(
            tracks: tracks,
            settings: settings,
            startIndex: 5,
          );
          expect(native.order, reference.order, reason: 'profile $profile');
          expect(
            native.crossfadeSeconds,
            closeTo(reference.crossfadeSeconds, 1e-10),
            reason: 'profile $profile crossfade',
          );
          expect(
            native.averageCost,
            closeTo(reference.averageCost, 1e-10),
            reason: 'profile $profile average cost',
          );
        }
      },
    );
  });

  group('crossfade derivation', () {
    test('clamps to 1.5..12 s over extreme median tempos', () {
      final slow = [_f(1, bpm: 58), _f(2, bpm: 60)];
      final fast = [_f(1, bpm: 198), _f(2, bpm: 200)];
      const settings = AutomixSettings(crossfadeBeats: 32);

      final slowPlan = AutomixEngine.planSet(
        tracks: slow,
        settings: settings,
        startIndex: 0,
      );
      final fastPlan = AutomixEngine.planSet(
        tracks: fast,
        settings: settings,
        startIndex: 0,
      );
      expect(slowPlan.crossfadeSeconds, 12.0);
      expect(fastPlan.crossfadeSeconds, inInclusiveRange(1.5, 12.0));
      // 32 beats at ~199 BPM ≈ 9.6 s — inside the clamp.
      expect(fastPlan.crossfadeSeconds, closeTo(32 * 60 / 199, 0.35));
    });
  });

  group('segmented analysis merge', () {
    AutomixSegmentFeatures seg(
      double start, {
      double? bpm,
      double? alt,
      double conf = 0.8,
      double? rms,
      double? beatOffsetMs,
      double? downbeatOffsetMs,
      double? dropCueMs,
      double? breakdownCueMs,
      double dropConfidence = 0,
      double breakdownConfidence = 0,
      int structureRegion = 0,
      double structureConfidence = 0,
      double vocalLikelihood = 0,
      double vocalConfidence = 0,
      double tailBpmConfidence = 0,
      double? startBpm,
      double startBpmConfidence = 0,
      double? endBpm,
      double endBpmConfidence = 0,
      double? startQuarterPhaseMs,
      double? endQuarterPhaseMs,
      double? tempoStability,
      List<double> quarters = const <double>[],
      double? introEdgeRmsDb,
      double? outroEdgeRmsDb,
      double? introEdgeLufs,
      double? outroEdgeLufs,
      double? introEdgeOnsetRate,
      double? outroEdgeOnsetRate,
    }) => AutomixSegmentFeatures(
      startSeconds: start,
      seconds: 120,
      bpm: bpm,
      bpmConfidence: conf,
      alternateBpm: alt,
      beatOffsetMs: beatOffsetMs,
      downbeatOffsetMs: downbeatOffsetMs,
      dropCueMs: dropCueMs,
      breakdownCueMs: breakdownCueMs,
      dropConfidence: dropConfidence,
      breakdownConfidence: breakdownConfidence,
      structureRegion: structureRegion,
      structureConfidence: structureConfidence,
      vocalLikelihood: vocalLikelihood,
      vocalConfidence: vocalConfidence,
      tailBpmConfidence: tailBpmConfidence,
      startBpm: startBpm,
      startBpmConfidence: startBpmConfidence,
      endBpm: endBpm,
      endBpmConfidence: endBpmConfidence,
      startBeatOffsetMs: startQuarterPhaseMs,
      endBeatOffsetMs: endQuarterPhaseMs,
      tempoStability: tempoStability,
      energyQuarters: quarters,
      introEdgeRmsDb: introEdgeRmsDb,
      outroEdgeRmsDb: outroEdgeRmsDb,
      introEdgeLufs: introEdgeLufs,
      outroEdgeLufs: outroEdgeLufs,
      introEdgeOnsetRate: introEdgeOnsetRate,
      outroEdgeOnsetRate: outroEdgeOnsetRate,
      camelotNumber: 8,
      camelotMinor: true,
      keyConfidence: 0.8,
      rmsDb: rms,
    );

    test('head and tail windows vote on one tempo and keep the exit grid', () {
      final merged = automixMergeSegments(
        songId: 1,
        segments: [
          seg(0, bpm: 120, conf: 0.9, rms: -12),
          seg(240, bpm: 60, conf: 0.7, rms: -18, beatOffsetMs: 40),
        ],
      );
      // The tail's 60 BPM folds onto the head's 120 BPM octave.
      expect(merged.bpm, closeTo(120, 6));
      expect(merged.tailBpm, closeTo(120, 6));
      // Tail phase is reported in absolute file time (ms from the file start).
      expect(merged.tailBeatOffsetMs, closeTo(240_040, 0.5));
      // Both windows agreed, so the vote is not neutral.
      expect(merged.bpmConfidence, greaterThan(0.3));
    });

    test('analyzedFraction counts overlapping windows once', () {
      final merged = automixMergeSegments(
        songId: 30,
        segments: [seg(0), seg(165), seg(330), seg(495), seg(580)],
        sourceDurationSeconds: 700,
      );

      // The final 495–615 and 580–700 s windows overlap by 35 s. Their
      // union covers 565 s, rather than the 600 s produced by a raw sum.
      expect(merged.analyzedFraction, closeTo(565 / 700, 1e-12));
    });

    test('keeps the head beat grid when its tempo is a slower octave', () {
      // A 60 BPM intro estimate is a subset of the 120 BPM track pulse, so its
      // phase lands on a main beat and remains usable.
      final merged = automixMergeSegments(
        songId: 2,
        segments: [
          seg(0, bpm: 60, conf: 0.5, beatOffsetMs: 210, downbeatOffsetMs: 830),
          seg(240, bpm: 120, conf: 0.9),
        ],
      );
      expect(merged.bpm, closeTo(120, 1));
      expect(merged.beatOffsetMs, closeTo(210, 0.5));
      expect(merged.downbeatOffsetMs, closeTo(830, 0.5));
    });

    test('drops a head grid measured at a faster octave than the track', () {
      // 240 BPM is a double-time misread of a 120 BPM track. Its phase is
      // measured modulo a 250 ms period, so reusing it on the 500 ms grid can
      // place the reference phase on an offbeat. Withhold it instead.
      final merged = automixMergeSegments(
        songId: 3,
        segments: [
          seg(0, bpm: 240, conf: 0.5, beatOffsetMs: 210, downbeatOffsetMs: 830),
          seg(240, bpm: 120, conf: 0.9),
        ],
      );
      expect(merged.bpm, closeTo(120, 1));
      expect(merged.beatOffsetMs, isNull);
      expect(merged.downbeatOffsetMs, isNull);
    });

    test('derives head/tail structure from seam-local energy quarters', () {
      final merged = automixMergeSegments(
        songId: 19,
        segments: [
          seg(
            0,
            bpm: 120,
            conf: 0.9,
            quarters: const <double>[-40, -40, -10, -8],
          ),
          seg(
            240,
            bpm: 120,
            conf: 0.9,
            quarters: const <double>[-9, -8, -10, -8],
          ),
        ],
      );
      expect(merged.structureRegion, 1);
      expect(merged.structureConfidence, greaterThanOrEqualTo(0.5));
      expect(merged.tailStructureRegion, 5);
      expect(merged.tailStructureConfidence, greaterThanOrEqualTo(0.5));
    });

    test('seam-local section cues override whole-window structure', () {
      final merged = automixMergeSegments(
        songId: 20,
        segments: [
          seg(
            0,
            bpm: 120,
            conf: 0.9,
            dropCueMs: 20000,
            dropConfidence: 0.9,
            structureRegion: 1,
            structureConfidence: 0.9,
            quarters: const <double>[-40, -40, -10, -8],
          ),
          seg(
            240,
            bpm: 120,
            conf: 0.9,
            breakdownCueMs: 100000,
            breakdownConfidence: 0.9,
            structureRegion: 5,
            structureConfidence: 0.9,
            quarters: const <double>[-9, -8, -10, -8],
          ),
        ],
      );
      expect(merged.structureRegion, 3);
      expect(merged.tailStructureRegion, 4);
    });

    test('uses edge-local BPM, confidence, and phase at the mix seam', () {
      final merged = automixMergeSegments(
        songId: 18,
        segments: [
          seg(
            0,
            bpm: 120,
            conf: 0.95,
            startBpm: 118,
            startBpmConfidence: 0.75,
            startQuarterPhaseMs: 122,
            tempoStability: 0.91,
          ),
          seg(
            240,
            bpm: 120,
            conf: 0.9,
            endBpm: 126,
            endBpmConfidence: 0.88,
            endQuarterPhaseMs: 275,
            tempoStability: 0.84,
          ),
        ],
      );

      expect(automixEntryBpm(merged), 118.0);
      expect(merged.introBeatOffsetMs, 122.0);
      expect(automixExitBpm(merged), 126.0);
      expect(merged.tailBpmConfidence, 0.88);
      expect(merged.tailBeatOffsetMs, 240275.0);
      expect(merged.introTempoStability, 0.91);
      expect(merged.outroTempoStability, 0.84);
    });

    test('drops an edge phase that a faster quarter tempo cannot map', () {
      final merged = automixMergeSegments(
        songId: 23,
        segments: [
          seg(
            0,
            bpm: 120,
            conf: 0.95,
            startBpm: 240,
            startBpmConfidence: 0.9,
            startQuarterPhaseMs: 100,
          ),
          seg(
            240,
            bpm: 120,
            conf: 0.9,
            endBpm: 240,
            endBpmConfidence: 0.9,
            endQuarterPhaseMs: 125,
          ),
        ],
      );

      // 240 BPM folds onto the 120 BPM track octave, but its 250 ms phase
      // could be either main beat or offbeat on the resulting 500 ms grid.
      expect(merged.startBpm, closeTo(120, 1));
      expect(merged.endBpm, closeTo(120, 1));
      expect(merged.introBeatOffsetMs, isNull);
      expect(merged.tailBeatOffsetMs, isNull);
      // The tempo estimates remain usable even though their phase is dropped.
      expect(merged.startBpmConfidence, 0.9);
      expect(merged.tailBpmConfidence, 0.9);
    });

    test('keeps an edge phase when the quarter tempo is slower', () {
      final merged = automixMergeSegments(
        songId: 24,
        segments: [
          seg(
            0,
            bpm: 120,
            conf: 0.95,
            startBpm: 60,
            startBpmConfidence: 0.9,
            startQuarterPhaseMs: 300,
          ),
          seg(
            240,
            bpm: 120,
            conf: 0.9,
            endBpm: 60,
            endBpmConfidence: 0.9,
            endQuarterPhaseMs: 300,
          ),
        ],
      );

      // A 1000 ms edge period is a multiple of the 500 ms track period, so its
      // phase is still the correct main-beat phase after the octave fold.
      expect(merged.startBpm, closeTo(120, 1));
      expect(merged.endBpm, closeTo(120, 1));
      expect(merged.introBeatOffsetMs, 300);
      expect(merged.tailBeatOffsetMs, closeTo(240300, 0.5));
    });

    test('folds the tempo curve into the track BPM octave', () {
      final merged = automixMergeSegments(
        songId: 8,
        segments: [
          seg(
            0,
            bpm: 120,
            conf: 0.9,
            startBpm: 120,
            endBpm: 121,
            tempoStability: 0.8,
          ),
          seg(
            240,
            bpm: 60,
            conf: 0.7,
            startBpm: 62,
            endBpm: 60,
            tempoStability: 0.4,
          ),
        ],
      );
      // The head start stays at 120; the tail's 60 BPM folds onto that octave.
      expect(merged.startBpm, closeTo(120, 1));
      expect(merged.endBpm, closeTo(120, 1));
      // Confidence-weighted stability: (0.8*0.9 + 0.4*0.7) / (0.9 + 0.7).
      expect(merged.tempoStability, closeTo(0.625, 0.001));
    });

    test('keeps the exit pulse unknown when the tail window failed', () {
      final merged = automixMergeSegments(
        songId: 9,
        segments: [seg(0, bpm: 120, conf: 0.9, startBpm: 120, endBpm: 118)],
        tailSegmentAnalyzed: false,
      );
      expect(merged.startBpm, closeTo(120, 1));
      expect(merged.endBpm, isNull);
      expect(merged.tempoStability, isNull);
    });

    test('derives intro and outro energy slopes from quarter profiles', () {
      final merged = automixMergeSegments(
        songId: 10,
        segments: [
          seg(0, bpm: 120, conf: 0.9, quarters: const [-24, -18, -12, -6]),
          seg(240, bpm: 120, conf: 0.9, quarters: const [-6, -12, -18, -24]),
        ],
      );
      // Head builds (+6 dB per quarter); the exit window cools (-6).
      expect(merged.introSlope, closeTo(6.0, 1e-9));
      expect(merged.outroSlope, closeTo(-6.0, 1e-9));
    });

    test(
      'leaves slopes null when the profile is incomplete or the tail failed',
      () {
        final noProfile = automixMergeSegments(
          songId: 11,
          segments: [seg(0, bpm: 120, conf: 0.9)],
        );
        expect(noProfile.introSlope, isNull);
        expect(noProfile.outroSlope, isNull);

        final missingTail = automixMergeSegments(
          songId: 12,
          segments: [
            seg(0, bpm: 120, conf: 0.9, quarters: const [-24, -18, -12, -6]),
          ],
          tailSegmentAnalyzed: false,
        );
        expect(missingTail.introSlope, closeTo(6.0, 1e-9));
        expect(missingTail.outroSlope, isNull);
      },
    );

    test('does not substitute general BPM confidence for tail confidence', () {
      final missingTailConfidence = automixMergeSegments(
        songId: 6,
        segments: [seg(0, bpm: 120, conf: 0.95), seg(240, bpm: 120, conf: 0.9)],
      );
      expect(missingTailConfidence.tailBpm, 120);
      expect(missingTailConfidence.tailBpmConfidence, 0);

      final explicitTailConfidence = automixMergeSegments(
        songId: 7,
        segments: [
          seg(0, bpm: 120, conf: 0.95),
          seg(240, bpm: 120, conf: 0.9, tailBpmConfidence: 0.65),
        ],
      );
      expect(explicitTailConfidence.tailBpmConfidence, 0.65);
    });

    test(
      'does not promote a middle/head exit grid when the tail has no BPM',
      () {
        final merged = automixMergeSegments(
          songId: 19,
          segments: [
            seg(
              0,
              bpm: 120,
              conf: 0.95,
              endBpm: 121,
              endBpmConfidence: 0.9,
              endQuarterPhaseMs: 40,
            ),
            seg(
              120,
              bpm: 124,
              conf: 0.9,
              endBpm: 126,
              endBpmConfidence: 0.9,
              endQuarterPhaseMs: 80,
            ),
            // Tail window decoded, but it has no usable tempo estimate.
            seg(240, conf: 0.9, rms: -18),
          ],
        );

        expect(merged.endBpm, isNull);
        expect(merged.endBpmConfidence, 0);
        expect(merged.tailBpm, isNull);
        expect(merged.tailBpmConfidence, 0);
        expect(merged.tailBeatOffsetMs, isNull);
        expect(merged.tailDownbeatOffsetMs, isNull);
      },
    );

    test(
      'disagreeing windows use the weighted median, not an invented mean',
      () {
        final merged = automixMergeSegments(
          songId: 13,
          segments: [
            seg(0, bpm: 120, conf: 0.8),
            seg(120, bpm: 120, conf: 0.8),
            seg(240, bpm: 90, conf: 0.6),
          ],
        );
        expect(merged.bpm, 120);
        expect(merged.bpmConfidence, lessThan(0.7));
      },
    );

    test('keeps alternate BPM from the highest-confidence tempo anchor', () {
      final merged = automixMergeSegments(
        songId: 4,
        segments: [
          seg(0, bpm: 80, alt: 160, conf: 0.9),
          seg(240, bpm: 40, alt: 80, conf: 0.6),
        ],
      );
      expect(merged.bpm, closeTo(80, 1.0));
      expect(merged.alternateBpm, closeTo(160, 0.1));
    });

    test('preserves source duration when the tail analysis window is missing', () {
      final merged = automixMergeSegments(
        songId: 5,
        segments: [seg(0, bpm: 120, rms: -12)],
        sourceDurationSeconds: 360,
        tailSegmentAnalyzed: false,
      );

      // Only the 120-second head window succeeded, but the source is 6 minutes.
      expect(merged.durationSeconds, 360);
      expect(merged.analyzedFraction, closeTo(1 / 3, 0.001));
      expect(merged.tailAnalyzed, isFalse);
      expect(merged.tailBpm, isNull);
      expect(merged.tailBeatOffsetMs, isNull);
      expect(merged.tailBreakdownCueMs, isNull);
      expect(merged.outroEnergy, isNull);
    });

    test('merge picks the earliest confident drop across all windows', () {
      final merged = automixMergeSegments(
        songId: 12,
        segments: [
          AutomixSegmentFeatures(
            startSeconds: 0,
            seconds: 120,
            dropCueMs: 160000,
            dropConfidence: 0.9,
            dropCues: const [AutomixDropCue(cueMs: 160000, confidence: 0.9)],
          ),
          const AutomixSegmentFeatures(
            startSeconds: 120,
            seconds: 120,
            dropCueMs: 10000,
            dropConfidence: 0.7,
            dropCues: [AutomixDropCue(cueMs: 10000, confidence: 0.7)],
          ),
        ],
      );
      // The head candidate is outside the 150 s early-handover envelope; the
      // middle-window candidate at 130 s must still open the path.
      expect(merged.dropCueMs, 130000);
      expect(merged.dropConfidence, 0.7);
    });

    test('structure markers describe the first and last window', () {
      final merged = automixMergeSegments(
        songId: 2,
        segments: [seg(0, rms: -30), seg(120, rms: -8), seg(240, rms: -22)],
      );
      expect(merged.introEnergy, 0);
      expect(merged.outroEnergy, closeTo(0.3636, 0.01));
      expect(merged.analyzedFraction, closeTo(1.0, 0.001));
    });

    test(
      'retains confidence and absolute structure/vocal cues across windows',
      () {
        final merged = automixMergeSegments(
          songId: 3,
          segments: [
            seg(
              0,
              dropCueMs: 28000,
              dropConfidence: 0.74,
              structureRegion: 3,
              structureConfidence: 0.82,
              vocalLikelihood: 0.8,
              vocalConfidence: 0.9,
            ),
            seg(
              240,
              breakdownCueMs: 114000,
              breakdownConfidence: 0.88,
              structureRegion: 4,
              structureConfidence: 0.76,
              vocalLikelihood: 0.4,
              vocalConfidence: 0.5,
            ),
          ],
        );
        expect(merged.dropCueMs, 28000);
        expect(merged.dropConfidence, 0.74);
        expect(merged.tailBreakdownCueMs, 354000);
        expect(merged.tailBreakdownConfidence, 0.88);
        expect(merged.structureRegion, 3);
        expect(merged.structureConfidence, 0.82);
        expect(merged.tailStructureRegion, 4);
        expect(merged.tailStructureConfidence, 0.76);
        expect(
          merged.vocalLikelihood,
          closeTo((0.8 * 0.9 + 0.4 * 0.5) / 1.4, 1e-9),
        );
        expect(merged.vocalConfidence, closeTo(0.7, 1e-9));
        expect(merged.durationSeconds, 360);
      },
    );
    test('merge uses edge RMS, LUFS and onset instead of window medians', () {
      final merged = automixMergeSegments(
        songId: 9,
        segments: [
          seg(
            0,
            bpm: 120,
            rms: -12,
            introEdgeRmsDb: -18,
            outroEdgeRmsDb: -12,
            introEdgeLufs: -17.5,
            outroEdgeLufs: -12.5,
            introEdgeOnsetRate: 0.4,
            outroEdgeOnsetRate: 3.2,
            quarters: const [-12, -12, -12, -12],
          ),
          seg(
            240,
            bpm: 120,
            rms: -12,
            introEdgeRmsDb: -12,
            outroEdgeRmsDb: -30,
            introEdgeLufs: -12.5,
            outroEdgeLufs: -29.5,
            introEdgeOnsetRate: 3.2,
            outroEdgeOnsetRate: 0.4,
            quarters: const [-12, -12, -12, -14],
          ),
        ],
      );

      // The window medians are both -12 dB, so the old implementation would
      // publish intro/outro energy 1.0 and a STABLE_HIGH tail. The edge
      // measurements expose the quiet, sparse final 15 s.
      expect(merged.introRmsDb, -18);
      expect(merged.outroRmsDb, -30);
      expect(merged.introEdgeLufs, -17.5);
      expect(merged.outroEdgeLufs, -29.5);
      expect(merged.introEdgeOnsetRate, 0.4);
      expect(merged.outroEdgeOnsetRate, 0.4);
      expect(merged.introEnergy, closeTo(0.6667, 0.001));
      expect(merged.outroEnergy, 0.0);
      expect(merged.tailStructureRegion, 1);
      expect(merged.outroSlope, -2);
    });
  });

  group('chord progression compatibility', () {
    test(
      'merges adjacent chord windows and resolves overlapping estimates',
      () {
        final merged = automixMergeChordProgressions([
          AutomixSegmentFeatures(
            startSeconds: 0,
            seconds: 120,
            chordProgression: const <AutomixChordEvent>[
              AutomixChordEvent(
                startMs: 0,
                rootPitchClass: 0,
                root: 'C',
                quality: 'maj',
                confidence: 0.70,
              ),
              AutomixChordEvent(
                startMs: 1000,
                rootPitchClass: 0,
                root: 'C',
                quality: 'maj',
                confidence: 0.80,
              ),
              AutomixChordEvent(
                startMs: 2000,
                rootPitchClass: 7,
                root: 'G',
                quality: 'maj',
                confidence: 0.88,
              ),
            ],
          ),
          AutomixSegmentFeatures(
            startSeconds: 120,
            seconds: 120,
            chordProgression: const <AutomixChordEvent>[
              AutomixChordEvent(
                startMs: 1000,
                rootPitchClass: 0,
                root: 'C',
                quality: 'maj',
                confidence: 0.95,
              ),
              AutomixChordEvent(
                startMs: 2000,
                rootPitchClass: 7,
                root: 'G',
                quality: 'maj',
                confidence: 0.72,
              ),
              AutomixChordEvent(
                startMs: 3000,
                rootPitchClass: 9,
                root: 'A',
                quality: 'min',
                confidence: 0.91,
              ),
            ],
          ),
        ]);

        expect(merged.map((chord) => chord.label), ['Cmaj', 'Gmaj', 'Amin']);
        expect(merged.first.startMs, 0);
        expect(merged.first.confidence, 0.95);
      },
    );

    test(
      'recognizes compatible fifths and penalizes confident semitone clashes',
      () {
        AutomixTrackFeatures track(
          int id,
          int pc,
          String quality,
          double confidence,
          double timeMs, {
          double duration = 180,
        }) => AutomixTrackFeatures(
          songId: id,
          durationSeconds: duration,
          chordProgression: <AutomixChordEvent>[
            AutomixChordEvent(
              startMs: timeMs,
              rootPitchClass: pc,
              root: const <String>[
                'C',
                'C#',
                'D',
                'D#',
                'E',
                'F',
                'F#',
                'G',
                'G#',
                'A',
                'A#',
                'B',
              ][pc],
              quality: quality,
              confidence: confidence,
            ),
          ],
        );

        final outgoing = track(1, 0, 'maj', 0.95, 170000);
        final fifth = track(2, 7, 'maj', 0.95, 1000, duration: 120);
        final semitone = track(3, 1, 'maj', 0.95, 1000, duration: 120);
        expect(automixChordProgressionCost(outgoing, fifth), lessThan(0.3));
        expect(
          automixChordProgressionCost(outgoing, semitone),
          greaterThan(0.62),
        );
      },
    );

    test('returns neutral absence when either chord grid is missing', () {
      expect(automixChordProgressionCost(_f(1), _f(2)), isNull);
    });
  });

  group('per-transition cue', () {
    AutomixTrackFeatures track(
      int id, {
      double? lufs,
      double? bpm,
      double? tailBpm,
      double? outro,
      double? intro,
      double durationSeconds = 0,
      double? tailBreakdownCueMs,
      double tailBreakdownConfidence = 0,
      double tailBpmConfidence = 0,
      double? tailBeatOffsetMs,
      double? beatOffsetMs,
      int tailMeter = 4,
      double? dropCueMs,
      double dropConfidence = 0,
      double analyzedFraction = 0,
      double bpmConfidence = 0.9,
      double? rmsDb,
      double? introRmsDb,
      double? outroRmsDb,
      double? introEdgeLufs,
      double? outroEdgeLufs,
      double? centroidHz,
      double? onsetRate,
      int structureRegion = 0,
      double structureConfidence = 0,
      int tailStructureRegion = 0,
      double tailStructureConfidence = 0,
      double vocalLikelihood = 0,
      double vocalConfidence = 0,
      double? tailSectionCueMs,
      double tailSectionCueConfidence = 0,
      List<AutomixChordEvent> chords = const <AutomixChordEvent>[],
    }) => AutomixTrackFeatures(
      songId: id,
      bpm: bpm ?? tailBpm,
      tailSectionCueMs: tailSectionCueMs,
      tailSectionCueConfidence: tailSectionCueConfidence,
      bpmConfidence: bpmConfidence,
      beatOffsetMs: beatOffsetMs,
      tailBpm: tailBpm,
      tailBpmConfidence: tailBpmConfidence,
      tailMeter: tailMeter,
      tailBeatOffsetMs: tailBeatOffsetMs,
      dropCueMs: dropCueMs,
      dropConfidence: dropConfidence,
      loudnessLufs: lufs,
      rmsDb: rmsDb,
      introRmsDb: introRmsDb,
      outroRmsDb: outroRmsDb,
      introEdgeLufs: introEdgeLufs,
      outroEdgeLufs: outroEdgeLufs,
      centroidHz: centroidHz,
      onsetRate: onsetRate,
      outroEnergy: outro,
      introEnergy: intro,
      durationSeconds: durationSeconds,
      analyzedFraction: analyzedFraction,
      tailBreakdownCueMs: tailBreakdownCueMs,
      tailBreakdownConfidence: tailBreakdownConfidence,
      structureRegion: structureRegion,
      structureConfidence: structureConfidence,
      tailStructureRegion: tailStructureRegion,
      tailStructureConfidence: tailStructureConfidence,
      vocalLikelihood: vocalLikelihood,
      vocalConfidence: vocalConfidence,
      chordProgression: chords,
    );

    test(
      'falls back to head BPM for fade duration when tail confidence is low',
      () {
        final cue = automixTransitionCue(
          outgoing: track(1, bpm: 100, tailBpm: 128, tailBpmConfidence: 0.1),
          incoming: track(2, bpm: 100),
          settings: const AutomixSettings(),
        );

        // Default is 16 beats: 16 * 60 / 100 = 9.6 seconds. The rejected
        // 128 BPM tail estimate must not shorten it to 7.5 seconds.
        expect(cue.fadeSeconds, closeTo(9.6, 1e-9));
      },
    );

    test('density scaling keeps the fade on a half-beat grid', () {
      final cue = automixTransitionCue(
        outgoing: track(1, tailBpm: 100),
        incoming: track(2, tailBpm: 100, intro: 0.2),
        settings: const AutomixSettings(crossfadeBeats: 16),
      );

      // 16 beats x 1.15 (sparse intro) = 18.4 beats. The old code multiplied
      // seconds, so the fade ended on a fraction of a beat; beat-count scaling
      // with half-beat quantization yields 18.5 beats = 11.1 s at 100 BPM.
      expect(cue.fadeSeconds, closeTo(11.1, 1e-9));
    });

    test('shapes chord compatibility without a cue-level reject', () {
      final cue = automixTransitionCue(
        outgoing: track(
          1,
          tailBpm: 120,
          durationSeconds: 180,
          chords: const <AutomixChordEvent>[
            AutomixChordEvent(
              startMs: 170000,
              rootPitchClass: 0,
              root: 'C',
              quality: 'maj',
              confidence: 0.95,
            ),
          ],
        ),
        incoming: track(
          2,
          tailBpm: 120,
          chords: const <AutomixChordEvent>[
            AutomixChordEvent(
              startMs: 0,
              rootPitchClass: 1,
              root: 'C#',
              quality: 'maj',
              confidence: 0.95,
            ),
          ],
        ),
        settings: const AutomixSettings(),
      );

      // Harmony no longer selects shortHandover here; the cue only shortens
      // the overlap by half a beat as a shaping signal.
      expect(cue.strategy, AutomixTransitionStrategy.crossfade);
      expect(cue.fadeSeconds, closeTo(7.75, 1e-9));
    });

    test('dense outro hands over sooner and the louder deck is trimmed', () {
      final cue = automixTransitionCue(
        outgoing: track(1, lufs: -12, tailBpm: 120, outro: 0.9),
        incoming: track(2, lufs: -16, tailBpm: 120),
        settings: const AutomixSettings(),
      );
      // Dense outro selects a quick handover: one 4/4 bar at 120 BPM.
      expect(cue.strategy, AutomixTransitionStrategy.quickHandover);
      expect(cue.fadeSeconds, closeTo(2.0, 1e-9));
      expect(cue.curveGamma, greaterThanOrEqualTo(1.35));
      expect(cue.outgoingTrim, closeTo(0.6309, 0.001)); // 4 dB
      expect(cue.incomingTrim, 1.0);
    });

    test('confident incoming drop schedules an early exit separately from fade length', () {
      final outgoing = track(
        1,
        tailBpm: 120,
        tailBpmConfidence: 0.9,
        tailBeatOffsetMs: 125.0,
        durationSeconds: 240,
      );
      final incoming = track(
        2,
        tailBpm: 120,
        bpmConfidence: 0.9,
        beatOffsetMs: 300.0,
        dropCueMs: 32000,
        dropConfidence: 0.9,
        durationSeconds: 210,
      );

      final cue = automixTransitionCue(
        outgoing: outgoing,
        incoming: incoming,
        settings: const AutomixSettings(),
      );

      expect(cue.transitionStartMs, 195000.0);
      expect(cue.fadeSeconds, inInclusiveRange(1.5, 12.0));
      expect(cue.fadeSeconds, lessThan(45.0));
    });

    test(
      'partially analyzed long incoming file reports a missing drop cue',
      () {
        final cue = automixTransitionCue(
          outgoing: track(
            1,
            tailBpm: 120,
            tailBpmConfidence: 0.9,
            tailBeatOffsetMs: 125.0,
            durationSeconds: 240,
          ),
          incoming: track(
            2,
            bpm: 120,
            bpmConfidence: 0.9,
            beatOffsetMs: 300.0,
            durationSeconds: 720,
            analyzedFraction: 0.82,
          ),
          settings: const AutomixSettings(),
        );

        expect(cue.earlyHandover, isFalse);
        expect(cue.transitionStartMs, isNull);
        expect(
          cue.earlyHandoverUnavailableReason,
          'no confident incoming drop cue',
        );
      },
    );

    test('confident section boundary moves the early handover to the section start', () {
      // The outgoing track's final section starts 40 s before EOF. The fade
      // must start there (a real change point) instead of at the generic
      // neutral 45 s lead.
      final cue = automixTransitionCue(
        outgoing: track(
          1,
          tailBpm: 120,
          tailBpmConfidence: 0.9,
          tailBeatOffsetMs: 125.0,
          durationSeconds: 240,
          tailSectionCueMs: 200000,
          tailSectionCueConfidence: 0.82,
        ),
        incoming: track(
          2,
          tailBpm: 120,
          bpmConfidence: 0.9,
          beatOffsetMs: 300.0,
          dropCueMs: 32000,
          dropConfidence: 0.9,
          durationSeconds: 210,
        ),
        settings: const AutomixSettings(),
      );

      expect(cue.transitionStartMs, 200000.0);
    });

    test('section cue outside the early-handover window is ignored', () {
      final cue = automixTransitionCue(
        outgoing: track(
          1,
          tailBpm: 120,
          tailBpmConfidence: 0.9,
          tailBeatOffsetMs: 125.0,
          durationSeconds: 240,
          // 90 s before EOF: too early for the supported 30-65 s lead.
          tailSectionCueMs: 150000,
          tailSectionCueConfidence: 0.9,
        ),
        incoming: track(
          2,
          tailBpm: 120,
          bpmConfidence: 0.9,
          beatOffsetMs: 300.0,
          dropCueMs: 32000,
          dropConfidence: 0.9,
          durationSeconds: 210,
        ),
        settings: const AutomixSettings(),
      );

      expect(cue.transitionStartMs, 195000.0);
    });

    test('low-confidence section cue never moves the handover', () {
      final cue = automixTransitionCue(
        outgoing: track(
          1,
          tailBpm: 120,
          tailBpmConfidence: 0.9,
          tailBeatOffsetMs: 125.0,
          durationSeconds: 240,
          tailSectionCueMs: 200000,
          tailSectionCueConfidence: 0.2,
        ),
        incoming: track(
          2,
          tailBpm: 120,
          bpmConfidence: 0.9,
          beatOffsetMs: 300.0,
          dropCueMs: 32000,
          dropConfidence: 0.9,
          durationSeconds: 210,
        ),
        settings: const AutomixSettings(),
      );

      expect(cue.transitionStartMs, 195000.0);
    });

    test('early exit lead blends dense tail and sparse intro density', () {
      final cue = automixTransitionCue(
        outgoing: track(
          1,
          tailBpm: 120,
          tailBpmConfidence: 0.9,
          tailBeatOffsetMs: 125.0,
          outro: 0.90,
          durationSeconds: 240,
        ),
        incoming: track(
          2,
          tailBpm: 120,
          bpmConfidence: 0.9,
          beatOffsetMs: 300.0,
          intro: 0.35,
          dropCueMs: 32000,
          dropConfidence: 0.9,
          durationSeconds: 210,
        ),
        settings: const AutomixSettings(),
      );

      // (60 * 2 + 35) / 3 = 51.666... seconds before EOF.
      expect(cue.transitionStartMs, closeTo(188333.33, 0.1));
    });

    test('early drop handover takes priority over a breakdown in the final 12 seconds', () {
      final cue = automixTransitionCue(
        outgoing: track(
          1,
          tailBpm: 120,
          tailBpmConfidence: 0.9,
          tailBeatOffsetMs: 125.0,
          durationSeconds: 240,
          tailBreakdownCueMs: 236000,
          tailBreakdownConfidence: 0.9,
        ),
        incoming: track(
          2,
          tailBpm: 120,
          bpmConfidence: 0.9,
          beatOffsetMs: 300.0,
          dropCueMs: 32000,
          dropConfidence: 0.9,
          durationSeconds: 210,
        ),
        settings: const AutomixSettings(),
      );

      // The near-EOF breakdown (4 s from EOF) must not mask a valid early drop
      // handover (neutral lead = 45 s). Keep the normal 16-beat fade duration.
      expect(cue.transitionStartMs, 195000.0);
      expect(cue.strategy, AutomixTransitionStrategy.crossfade);
      expect(cue.fadeSeconds, closeTo(8.0, 1e-9));
    });

    test(
      'uncertain incoming drop keeps the conventional near-end transition',
      () {
        final cue = automixTransitionCue(
          outgoing: track(
            1,
            tailBpm: 120,
            tailBpmConfidence: 0.9,
            tailBeatOffsetMs: 125.0,
            durationSeconds: 240,
          ),
          incoming: track(
            2,
            tailBpm: 120,
            bpmConfidence: 0.9,
            beatOffsetMs: 300.0,
            dropCueMs: 32000,
            dropConfidence: 0.2,
            durationSeconds: 210,
          ),
          settings: const AutomixSettings(),
        );

        expect(cue.transitionStartMs, isNull);
      },
    );

    test('tempo-mismatched tracks do not use early drop handover', () {
      final cue = automixTransitionCue(
        outgoing: track(
          1,
          tailBpm: 120,
          tailBpmConfidence: 0.9,
          tailBeatOffsetMs: 125.0,
          durationSeconds: 240,
        ),
        incoming: track(
          2,
          tailBpm: 165,
          bpmConfidence: 0.9,
          beatOffsetMs: 300.0,
          dropCueMs: 32000,
          dropConfidence: 0.9,
          durationSeconds: 210,
        ),
        settings: const AutomixSettings(),
      );

      expect(cue.transitionStartMs, isNull);
    });

    test(
      'structure cues require reliable tail confidence and select alignment',
      () {
        final aligned = automixTransitionCue(
          outgoing: track(
            1,
            tailBpm: 120,
            durationSeconds: 180,
            tailBreakdownCueMs: 174000,
            tailBreakdownConfidence: 0.9,
            tailStructureRegion: 4,
            tailStructureConfidence: 0.8,
          ),
          incoming: track(2, tailBpm: 120),
          settings: const AutomixSettings(),
        );
        expect(aligned.strategy, AutomixTransitionStrategy.structureAligned);
        expect(aligned.fadeSeconds, 6.0);

        final untrusted = automixTransitionCue(
          outgoing: track(
            3,
            tailBpm: 120,
            durationSeconds: 180,
            tailBreakdownCueMs: 174000,
            tailBreakdownConfidence: 0.1,
          ),
          incoming: track(4, tailBpm: 120),
          settings: const AutomixSettings(),
        );
        expect(untrusted.strategy, AutomixTransitionStrategy.crossfade);
        expect(untrusted.fadeSeconds, 8.0);
      },
    );

    test('vocal conflict and spectral measurements drive EQ targets', () {
      final clash = automixTransitionCue(
        outgoing: track(
          1,
          tailBpm: 120,
          vocalLikelihood: 0.9,
          vocalConfidence: 0.9,
          centroidHz: 3000,
          outro: 0.9,
          onsetRate: 4.0,
        ),
        incoming: track(
          2,
          tailBpm: 120,
          vocalLikelihood: 0.85,
          vocalConfidence: 0.8,
          centroidHz: 2800,
          intro: 0.8,
          onsetRate: 3.5,
        ),
        settings: const AutomixSettings(),
      );
      expect(clash.outgoingMidOverlapGain, 0.78);
      expect(clash.incomingMidOverlapGain, 0.78);
      expect(clash.outgoingBassOverlapGain, lessThan(1.0));
      expect(clash.incomingBassOverlapGain, lessThan(1.0));
      expect(clash.outgoingHighOverlapGain, lessThan(0.6));
      expect(clash.incomingHighOverlapGain, lessThan(1.0));

      final uncertain = automixTransitionCue(
        outgoing: track(
          3,
          tailBpm: 120,
          vocalLikelihood: 0.9,
          vocalConfidence: 0.2,
        ),
        incoming: track(
          4,
          tailBpm: 120,
          vocalLikelihood: 0.9,
          vocalConfidence: 0.1,
        ),
        settings: const AutomixSettings(),
      );
      expect(uncertain.outgoingMidOverlapGain, 1.0);
      expect(uncertain.incomingMidOverlapGain, 1.0);
    });

    test('prefers paired overlap-section RMS over integrated LUFS', () {
      final cue = automixTransitionCue(
        outgoing: track(1, tailBpm: 120, lufs: -8, outroRmsDb: -22, rmsDb: -8),
        incoming: track(
          2,
          tailBpm: 120,
          lufs: -16,
          introRmsDb: -18,
          rmsDb: -16,
        ),
        settings: const AutomixSettings(),
      );
      // Section levels differ by 4 dB; integrated LUFS is intentionally ignored.
      expect(cue.outgoingTrim, 1.0);
      expect(cue.incomingTrim, closeTo(0.6309, 0.001));
    });

    test('prefers edge LUFS over integrated loudness and edge RMS', () {
      final cue = automixTransitionCue(
        outgoing: track(
          1,
          tailBpm: 120,
          lufs: -8,
          outroRmsDb: -10,
          outroEdgeLufs: -20,
        ),
        incoming: track(
          2,
          tailBpm: 120,
          lufs: -8,
          introRmsDb: -10,
          introEdgeLufs: -14,
        ),
        settings: const AutomixSettings(),
      );
      // Integrated LUFS and edge RMS both say the decks are equal; only the
      // edge LUFS pair sees the 6 dB quieter outgoing overlap.
      expect(cue.outgoingTrim, 1.0);
      expect(cue.incomingTrim, closeTo(0.5012, 0.001));
    });

    test('partial vocal evidence attenuates the mid band continuously', () {
      final cue = automixTransitionCue(
        outgoing: track(
          1,
          tailBpm: 120,
          vocalLikelihood: 0.65,
          vocalConfidence: 0.55,
        ),
        incoming: track(
          2,
          tailBpm: 120,
          vocalLikelihood: 0.65,
          vocalConfidence: 0.55,
        ),
        settings: const AutomixSettings(),
      );
      expect(cue.outgoingMidOverlapGain, closeTo(0.89, 1e-9));
      expect(cue.incomingMidOverlapGain, closeTo(0.89, 1e-9));
    });

    test('does not compare a section RMS value against integrated LUFS', () {
      final cue = automixTransitionCue(
        outgoing: track(1, tailBpm: 120, outroRmsDb: -24),
        incoming: track(2, tailBpm: 120, lufs: -8),
        settings: const AutomixSettings(),
      );
      expect(cue.outgoingTrim, 1.0);
      expect(cue.incomingTrim, 1.0);
    });

    test('uses paired RMS dBFS for level matching when LUFS is missing', () {
      final cue = automixTransitionCue(
        outgoing: track(1, tailBpm: 120, rmsDb: -12),
        incoming: track(2, tailBpm: 120, rmsDb: -16),
        settings: const AutomixSettings(),
      );
      expect(cue.outgoingTrim, closeTo(0.6309, 0.001));
      expect(cue.incomingTrim, 1.0);
    });

    test('sparse outro lengthens the blend and never boosts a deck', () {
      final cue = automixTransitionCue(
        outgoing: track(1, lufs: -20, tailBpm: 120, outro: 0.2),
        incoming: track(2, lufs: -10, tailBpm: 120, intro: 0.2),
        settings: const AutomixSettings(),
      );
      // 8 s × 1.25 (quiet outro) × 1.15 (sparse intro).
      expect(cue.fadeSeconds, closeTo(11.5, 0.05));
      expect(cue.curveGamma, lessThan(1.0));
      expect(cue.outgoingTrim, 1.0);
      // 10 dB apart, clamped to the 6 dB ceiling — always attenuation.
      expect(cue.incomingTrim, closeTo(0.5012, 0.001));
      expect(cue.incomingTrim, lessThanOrEqualTo(1.0));
    });

    test('starts the fade at a detected late-outro breakdown', () {
      final cue = automixTransitionCue(
        outgoing: track(
          1,
          tailBpm: 120,
          durationSeconds: 180,
          tailBreakdownCueMs: 174000,
          tailBreakdownConfidence: 0.9,
        ),
        incoming: track(2, tailBpm: 120),
        settings: const AutomixSettings(),
      );
      // The cue is 6 s before end, so the crossfade starts at the breakdown.
      expect(cue.fadeSeconds, 6.0);
    });

    test('unknown structure and levels keep the plain equal-power fade', () {
      final cue = automixTransitionCue(
        outgoing: track(1, tailBpm: 120),
        incoming: track(2, tailBpm: 120),
        settings: const AutomixSettings(),
      );
      expect(cue.fadeSeconds, closeTo(8.0, 0.01));
      expect(cue.curveGamma, 1.0);
      expect(cue.outgoingTrim, 1.0);
      expect(cue.incomingTrim, 1.0);
    });

    test(
      'shortens a confident transition when the pulse grids cannot match',
      () {
        final cue = automixTransitionCue(
          outgoing: AutomixTrackFeatures(
            songId: 1,
            bpm: 120,
            tailBpm: 120,
            bpmConfidence: 0.9,
            tailBpmConfidence: 0.9,
          ),
          incoming: const AutomixTrackFeatures(
            songId: 2,
            bpm: 150,
            bpmConfidence: 0.9,
          ),
          settings: const AutomixSettings(),
        );

        // A confident mismatch is a short handover: half a 4/4 bar at 120 BPM
        // is 1 s, raised to the 1.5 s musical floor.
        expect(cue.strategy, AutomixTransitionStrategy.shortHandover);
        expect(cue.fadeSeconds, 1.5);
        expect(cue.curveGamma, greaterThanOrEqualTo(1.20));
      },
    );

    test('sizes short, quick and long transitions in outgoing bars', () {
      // 60 BPM keeps every half-beat quantisation exact, and a two-beat base
      // fade leaves the strategy itself to choose the duration. A 2-beat bar
      // is the compound 6/8 pulse produced by the analyzer.
      const cases = <int, List<double>>{
        2: [1.5, 2.0, 4.0], // half bar -> floor, one bar, two bars
        3: [1.5, 3.0, 6.0],
        4: [2.0, 4.0, 8.0],
        6: [3.0, 6.0, 12.0],
      };
      for (final entry in cases.entries) {
        final meter = entry.key;
        final short = automixTransitionCue(
          outgoing: track(
            1,
            tailBpm: 60,
            tailBpmConfidence: 0.9,
            tailMeter: meter,
          ),
          incoming: track(2, tailBpm: 90, bpmConfidence: 0.9),
          settings: const AutomixSettings(crossfadeBeats: 2),
        );
        expect(
          short.strategy,
          AutomixTransitionStrategy.shortHandover,
          reason: 'meter $meter',
        );
        expect(short.fadeSeconds, closeTo(entry.value[0], 1e-9));

        final quick = automixTransitionCue(
          outgoing: track(1, tailBpm: 60, tailMeter: meter, outro: 0.9),
          incoming: track(2, tailBpm: 60),
          settings: const AutomixSettings(crossfadeBeats: 2),
        );
        expect(
          quick.strategy,
          AutomixTransitionStrategy.quickHandover,
          reason: 'meter $meter',
        );
        expect(quick.fadeSeconds, closeTo(entry.value[1], 1e-9));

        final long = automixTransitionCue(
          outgoing: track(1, tailBpm: 60, tailMeter: meter, outro: 0.2),
          incoming: track(2, tailBpm: 60),
          settings: const AutomixSettings(crossfadeBeats: 2),
        );
        expect(
          long.strategy,
          AutomixTransitionStrategy.longBlend,
          reason: 'meter $meter',
        );
        expect(long.fadeSeconds, closeTo(entry.value[2], 1e-9));
      }
    });

    test('clamps extreme bar lengths to the 1.5-12 s envelope', () {
      final fast = automixTransitionCue(
        outgoing: track(1, tailBpm: 220, tailMeter: 4, outro: 0.9),
        incoming: track(2, tailBpm: 220),
        settings: const AutomixSettings(crossfadeBeats: 2),
      );
      // One 4/4 bar at 220 BPM is 1.09 s; both quick and short clamp up.
      expect(fast.fadeSeconds, 1.5);
      final fastShort = automixTransitionCue(
        outgoing: track(1, tailBpm: 220, tailBpmConfidence: 0.9, tailMeter: 4),
        incoming: track(2, tailBpm: 110, bpmConfidence: 0.9),
        settings: const AutomixSettings(crossfadeBeats: 2),
      );
      expect(fastShort.fadeSeconds, 1.5);

      final slow = automixTransitionCue(
        outgoing: track(1, tailBpm: 50, tailMeter: 6, outro: 0.2),
        incoming: track(2, tailBpm: 50),
        settings: const AutomixSettings(crossfadeBeats: 2),
      );
      // Two 6/8 bars at 50 BPM are 14.4 s, capped at the 12 s envelope.
      expect(slow.fadeSeconds, 12.0);
    });

    test(
      'keeps tempo mismatches neutral when either estimate is uncertain',
      () {
        final cue = automixTransitionCue(
          outgoing: const AutomixTrackFeatures(
            songId: 1,
            bpm: 120,
            tailBpm: 120,
            bpmConfidence: 0.9,
          ),
          incoming: const AutomixTrackFeatures(
            songId: 2,
            bpm: 150,
            bpmConfidence: 0.1,
          ),
          settings: const AutomixSettings(),
        );

        expect(cue.fadeSeconds, 8.0);
        expect(cue.curveGamma, 1.0);
      },
    );

    test(
      'shapes a confident harmonic clash but leaves uncertain keys neutral',
      () {
        final clash = automixTransitionCue(
          outgoing: const AutomixTrackFeatures(
            songId: 1,
            bpm: 120,
            tailBpm: 120,
            bpmConfidence: 0.9,
            camelotNumber: 8,
            camelotMinor: false,
            keyConfidence: 0.9,
          ),
          incoming: const AutomixTrackFeatures(
            songId: 2,
            bpm: 120,
            bpmConfidence: 0.9,
            camelotNumber: 1,
            camelotMinor: false,
            keyConfidence: 0.9,
          ),
          settings: const AutomixSettings(),
        );
        // The planner owns the harmonic reject; the cue only shortens the
        // overlap by half a beat as a shaping signal.
        expect(clash.strategy, AutomixTransitionStrategy.crossfade);
        expect(clash.fadeSeconds, closeTo(7.75, 1e-9));
        expect(clash.curveGamma, 1.0);
        // 8B (C major) -> 1B (B major): the outgoing deck moves down one
        // semitone during the overlap to match the incoming key.
        expect(clash.outgoingPitchSemitones, -1.0);

        final uncertain = automixTransitionCue(
          outgoing: const AutomixTrackFeatures(
            songId: 3,
            bpm: 120,
            tailBpm: 120,
            bpmConfidence: 0.9,
            camelotNumber: 8,
            camelotMinor: false,
            keyConfidence: 0.2,
          ),
          incoming: const AutomixTrackFeatures(
            songId: 4,
            bpm: 120,
            bpmConfidence: 0.9,
            camelotNumber: 1,
            camelotMinor: false,
            keyConfidence: 0.2,
          ),
          settings: const AutomixSettings(),
        );
        expect(uncertain.fadeSeconds, 8.0);
        expect(uncertain.curveGamma, 1.0);
        expect(uncertain.outgoingPitchSemitones, 0.0);
      },
    );
  });

  group('automixOutgoingPitchSemitones', () {
    test('a folded wheel distance of five is a signed one-semitone move', () {
      // 8B (C major) -> 3B (C# major) needs +1 semitone.
      expect(
        automixOutgoingPitchSemitones(
          _f(1, camelot: 8, minor: false),
          _f(2, camelot: 3, minor: false),
        ),
        1.0,
      );
      // The reverse direction needs -1.
      expect(
        automixOutgoingPitchSemitones(
          _f(1, camelot: 3, minor: false),
          _f(2, camelot: 8, minor: false),
        ),
        -1.0,
      );
      // 8A (A minor) -> 3A (A# minor) is the same relative move on ring A.
      expect(
        automixOutgoingPitchSemitones(
          _f(1, camelot: 8, minor: true),
          _f(2, camelot: 3, minor: true),
        ),
        1.0,
      );
    });

    test('other distances, modes and weak keys stay neutral', () {
      // Adjacent Camelot numbers are a fifth; no automatic shift.
      expect(
        automixOutgoingPitchSemitones(
          _f(1, camelot: 8, minor: false),
          _f(2, camelot: 9, minor: false),
        ),
        0.0,
      );
      // Relative major/minor is a mode change, not a semitone transpose.
      expect(
        automixOutgoingPitchSemitones(
          _f(1, camelot: 8, minor: false),
          _f(2, camelot: 8, minor: true),
        ),
        0.0,
      );
      expect(
        automixOutgoingPitchSemitones(
          _f(1, camelot: 8, minor: false, keyConf: 0.2),
          _f(2, camelot: 3, minor: false, keyConf: 0.2),
        ),
        0.0,
      );
      expect(
        automixOutgoingPitchSemitones(
          _f(1, camelot: null, minor: false),
          _f(2, camelot: 3, minor: false),
        ),
        0.0,
      );
    });
  });

  group('automixEarlyHandoverLeadSeconds', () {
    test('neutral metadata keeps the historical 45 second lead', () {
      expect(
        automixEarlyHandoverLeadSeconds(outroEnergy: null, introEnergy: null),
        45.0,
      );
    });

    test('outgoing density maps continuously into the 35-60 second window', () {
      expect(
        automixEarlyHandoverLeadSeconds(outroEnergy: 0.20, introEnergy: null),
        35.0,
      );
      expect(
        automixEarlyHandoverLeadSeconds(outroEnergy: 0.6125, introEnergy: null),
        closeTo(52.5, 1e-9),
      );
      expect(
        automixEarlyHandoverLeadSeconds(outroEnergy: 0.90, introEnergy: null),
        60.0,
      );
    });

    test('a sparse incoming intro pulls the handover later', () {
      expect(
        automixEarlyHandoverLeadSeconds(outroEnergy: null, introEnergy: 0.35),
        35.0,
      );
      // Dense tail (weight 2) plus sparse intro (weight 1): (120 + 35) / 3.
      expect(
        automixEarlyHandoverLeadSeconds(outroEnergy: 0.90, introEnergy: 0.35),
        closeTo(51.6666667, 1e-6),
      );
      // A dense intro leaves the outgoing density signal untouched.
      expect(
        automixEarlyHandoverLeadSeconds(outroEnergy: 0.90, introEnergy: 0.80),
        60.0,
      );
    });

    test('confident tail structure adds its own lead signal', () {
      expect(
        automixEarlyHandoverLeadSeconds(
          outroEnergy: null,
          introEnergy: null,
          tailStructureRegion: 3,
          tailStructureConfidence: 0.65,
        ),
        60.0,
      );
      expect(
        automixEarlyHandoverLeadSeconds(
          outroEnergy: null,
          introEnergy: null,
          tailStructureRegion: 1,
          tailStructureConfidence: 0.75,
        ),
        35.0,
      );
      // Weak structure confidence is ignored.
      expect(
        automixEarlyHandoverLeadSeconds(
          outroEnergy: null,
          introEnergy: null,
          tailStructureRegion: 3,
          tailStructureConfidence: 0.64,
        ),
        45.0,
      );
      // DROP (60) combined with a sparse intro (35): (60 + 35) / 2.
      expect(
        automixEarlyHandoverLeadSeconds(
          outroEnergy: null,
          introEnergy: 0.35,
          tailStructureRegion: 3,
          tailStructureConfidence: 0.65,
        ),
        closeTo(47.5, 1e-9),
      );
    });
  });

  group('bounded planning window', () {
    test(
      'one-shot start rotates from selection and leaves overflow ordered',
      () {
        final queue = List<int>.generate(320, (index) => index + 1);
        final rotated = automixRotateQueueFrom<int>(queue, 12);
        expect(rotated.first, 13);
        expect(rotated, [...queue.skip(12), ...queue.take(12)]);

        // A horizon of 250 means the selected track plus up to 250 successors.
        const horizon = 250;
        final window = automixPlanWindow<int>(rotated, 0, horizon);
        expect(window, rotated.take(horizon + 1));

        // Model a valid planner result: the first item stays pinned, while the
        // remaining window is reordered; the overflow remains in source order.
        final plannedWindow = <int>[
          window.first,
          ...window.skip(1).toList().reversed,
        ];
        final sequenced = <int>[
          ...plannedWindow,
          ...rotated.skip(window.length),
        ];
        expect(sequenced.length, queue.length);
        expect(sequenced.first, 13);
        expect(sequenced.toSet(), queue.toSet());
        expect(sequenced.skip(window.length), rotated.skip(window.length));
      },
    );

    test('window is the start track plus the bounded upcoming tail', () {
      expect(automixPlanWindow<int>([1, 2, 3, 4, 5], 1, 2), [2, 3, 4]);
      expect(automixPlanWindow<int>([1, 2, 3], 2, 5), [3]);
      expect(automixPlanWindow<int>([1, 2, 3], 0, 0), [1]);
      expect(automixPlanWindow<int>([], 0, 4), isEmpty);
      // A stale index clamps instead of throwing.
      expect(automixPlanWindow<int>([1, 2, 3], 9, 2), [3]);
    });

    test(
      'ordered tail keeps the planned window and the untouched remainder',
      () {
        expect(automixOrderedTail<int>([3, 2, 1], [1, 2, 3, 4, 5], 3), [
          3,
          2,
          1,
          4,
          5,
        ]);
        // A window larger than the tail is clamped, never padded.
        expect(automixOrderedTail<int>([2, 1], [1, 2], 5), [2, 1]);
        expect(automixOrderedTail<int>([], [1, 2, 3], 0), [1, 2, 3]);
      },
    );

    test('planning a 60-track queue only permutes its window', () {
      final tracks = [
        for (var i = 1; i <= 60; i++)
          _f(
            i,
            bpm: 100 + (i % 7) * 3.0,
            camelot: (i % 12) + 1,
            minor: i.isEven,
          ),
      ];
      const horizon = 25;
      final window = automixPlanWindow<AutomixTrackFeatures>(
        tracks,
        4,
        horizon,
      );
      expect(window.length, horizon + 1);

      final plan = AutomixEngine.planSet(
        tracks: window,
        settings: const AutomixSettings(),
        startIndex: 0,
      );
      expect(plan.order.first, 0);
      final plannedIds = [
        for (final index in plan.order.skip(1)) window[index].songId,
      ];
      final tailIds = [for (final track in tracks.skip(5)) track.songId];
      final ordered = automixOrderedTail<int>(plannedIds, tailIds, horizon);

      expect(ordered.length, tailIds.length);
      expect(ordered.toSet(), tailIds.toSet());
      // Past the window the user's order is preserved byte-for-byte.
      expect(ordered.sublist(horizon), tailIds.sublist(horizon));
      // Inside the window the engine owns the order.
      expect(ordered.take(horizon).toSet(), tailIds.take(horizon).toSet());
      expect(ordered.take(horizon).toList(), plannedIds);
    });
  });

  group('tempo match guard', () {
    test('pulls only a pair that is already close', () {
      final same = automixTempoMatch(referenceBpm: 120, trackBpm: 120);
      expect(same.$1, isTrue);
      expect(same.$2, 1.0);

      final close = automixTempoMatch(referenceBpm: 120, trackBpm: 124);
      expect(close.$1, isTrue);
      expect(close.$2, closeTo(120 / 124, 0.0005));

      // 120 → 140 is ~16 % away: a stretch the ear hears as a wobble, so the
      // pair is left untouched and native runs a plain crossfade.
      final far = automixTempoMatch(referenceBpm: 120, trackBpm: 140);
      expect(far.$1, isFalse);
      expect(far.$2, 1.0);
    });

    test(
      'matches half/double-time pulse estimates without octave speed changes',
      () {
        final halfTime = automixTempoMatch(referenceBpm: 120, trackBpm: 60);
        expect(halfTime, (true, 1.0));

        final doubleTime = automixTempoMatch(referenceBpm: 60, trackBpm: 120);
        expect(doubleTime, (true, 1.0));

        // A 61 BPM analysis can be interpreted as 122 BPM; only the small
        // correction needed to line up that pulse is applied to the deck.
        final nearHalfTime = automixTempoMatch(referenceBpm: 120, trackBpm: 61);
        expect(nearHalfTime.$1, isTrue);
        expect(nearHalfTime.$2, closeTo(120 / 122, 0.0005));
      },
    );

    test('stays neutral when a tempo is missing or unusable', () {
      expect(automixTempoMatch(referenceBpm: null, trackBpm: 120), (
        false,
        1.0,
      ));
      expect(automixTempoMatch(referenceBpm: 120, trackBpm: null), (
        false,
        1.0,
      ));
      expect(automixTempoMatch(referenceBpm: 0, trackBpm: 120), (false, 1.0));
      expect(automixTempoMatch(referenceBpm: double.nan, trackBpm: 120), (
        false,
        1.0,
      ));
      expect(automixTempoMatch(referenceBpm: double.infinity, trackBpm: 120), (
        false,
        1.0,
      ));
    });

    test('the tolerance boundary is inclusive, just past it is not', () {
      // |100 / 94.34 − 1| = 6 % exactly → still matchable.
      expect(automixTempoMatch(referenceBpm: 100, trackBpm: 94.34).$1, isTrue);
      // |100 / 94 − 1| ≈ 6.4 % → not matchable.
      expect(automixTempoMatch(referenceBpm: 100, trackBpm: 94).$1, isFalse);
    });

    test('never exceeds the ±8 % the native stretch stage accepts', () {
      final faster = automixTempoMatch(
        referenceBpm: 200,
        trackBpm: 180,
        tolerance: 1.0,
      );
      expect(faster.$1, isTrue);
      expect(faster.$2, 1.08);

      final slower = automixTempoMatch(
        referenceBpm: 180,
        trackBpm: 200,
        tolerance: 1.0,
      );
      expect(slower.$2, 0.92);
    });
  });

  group('whole-queue plan continuation', () {
    test('accepts a plain track advance', () {
      expect(automixPlanContinues([2, 3, 4], [3, 4]), isTrue);
      // A skip the plan already covers is still a continuation.
      expect(automixPlanContinues([2, 3, 4], [4]), isTrue);
      expect(automixPlanContinues([2, 3, 4], <int>[]), isTrue);
    });

    test('rejects every edit the plan does not already cover', () {
      // Reordered tail.
      expect(automixPlanContinues([2, 3, 4], [4, 3]), isFalse);
      // A track appended after the plan's last entry.
      expect(automixPlanContinues([2, 3, 4], [3, 4, 5]), isFalse);
      // A track the plan never saw became current.
      expect(automixPlanContinues([2, 3, 4], [9]), isFalse);
      // Nothing planned yet.
      expect(automixPlanContinues(const <int>[], [1]), isFalse);
    });
  });

  group('queue snapshot validation', () {
    test('requires the exact same ordered queue, not just matching IDs', () {
      expect(automixQueueSnapshotMatches([10, 20, 30], [10, 20, 30]), isTrue);
      expect(automixQueueSnapshotMatches([10, 20, 30], [20, 10, 30]), isFalse);
      expect(
        automixQueueSnapshotMatches([10, 20, 30], [10, 20, 30, 40]),
        isFalse,
      );
      expect(automixQueueSnapshotMatches([10, 20, 30], [10, 30]), isFalse);
    });
  });

  group('shuffle-aware upcoming tracks', () {
    const queue = <String>['A', 'B', 'C', 'D'];
    test('uses Media3 next index under shuffle', () {
      expect(
        automixUpcomingTracks(
          queue,
          1,
          shuffleEnabled: true,
          nextTrackIndex: 3,
        ),
        ['D'],
      );
    });
    test('does not guess when native shuffle state is unknown or invalid', () {
      expect(
        automixUpcomingTracks(
          queue,
          1,
          shuffleEnabled: true,
          nextTrackIndex: null,
        ),
        isEmpty,
      );
      expect(
        automixUpcomingTracks(
          queue,
          1,
          shuffleEnabled: true,
          nextTrackIndex: -1,
        ),
        isEmpty,
      );
      expect(
        automixUpcomingTracks(
          queue,
          1,
          shuffleEnabled: true,
          nextTrackIndex: 1,
        ),
        isEmpty,
      );
    });
    test('preserves full linear tail with shuffle disabled', () {
      expect(
        automixUpcomingTracks(
          queue,
          1,
          shuffleEnabled: false,
          nextTrackIndex: 3,
        ),
        ['C', 'D'],
      );
    });
  });
}
