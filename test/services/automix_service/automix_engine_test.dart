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
}) {
  return AutomixTrackFeatures(
    songId: id,
    artist: artist,
    bpm: bpm,
    alternateBpm: alt,
    beatOffsetMs: beatOffsetMs,
    camelotNumber: camelot,
    camelotMinor: minor,
    bpmConfidence: bpmConf,
    keyConfidence: keyConf,
    loudnessLufs: lufs,
    rmsDb: rms,
    centroidHz: centroid,
    onsetRate: onset,
  );
}

void main() {
  group('AutomixTrackFeatures serialization', () {
    test('round trips beat phase and accepts older cache entries', () {
      final feature = _f(17, bpm: 120, beatOffsetMs: 123.5);
      final restored = AutomixTrackFeatures.fromMap(feature.toMap());
      expect(restored.beatOffsetMs, 123.5);

      final legacy = AutomixTrackFeatures.fromMap({'id': 17, 'bpm': 120});
      expect(legacy.beatOffsetMs, isNull);
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
      double conf = 0.8,
      double? rms,
      double? beatOffsetMs,
    }) => AutomixSegmentFeatures(
      startSeconds: start,
      seconds: 120,
      bpm: bpm,
      bpmConfidence: conf,
      beatOffsetMs: beatOffsetMs,
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

    test('structure markers describe the first and last window', () {
      final merged = automixMergeSegments(
        songId: 2,
        segments: [seg(0, rms: -30), seg(120, rms: -8), seg(240, rms: -22)],
      );
      expect(merged.introEnergy, 0);
      expect(merged.outroEnergy, closeTo(0.3636, 0.01));
      expect(merged.analyzedFraction, closeTo(1.0, 0.001));
    });
  });

  group('per-transition cue', () {
    AutomixTrackFeatures track(
      int id, {
      double? lufs,
      double? tailBpm,
      double? outro,
      double? intro,
    }) => AutomixTrackFeatures(
      songId: id,
      bpm: tailBpm,
      bpmConfidence: 0.9,
      tailBpm: tailBpm,
      loudnessLufs: lufs,
      outroEnergy: outro,
      introEnergy: intro,
    );

    test('dense outro hands over sooner and the louder deck is trimmed', () {
      final cue = automixTransitionCue(
        outgoing: track(1, lufs: -12, tailBpm: 120, outro: 0.9),
        incoming: track(2, lufs: -16, tailBpm: 120),
        settings: const AutomixSettings(),
      );
      // 16 beats at 120 BPM = 8 s, shortened for a busy outro.
      expect(cue.fadeSeconds, closeTo(6.0, 0.01));
      expect(cue.curveGamma, greaterThan(1.0));
      expect(cue.outgoingTrim, closeTo(0.6309, 0.001)); // 4 dB
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
          ),
          incoming: const AutomixTrackFeatures(
            songId: 2,
            bpm: 150,
            bpmConfidence: 0.9,
          ),
          settings: const AutomixSettings(),
        );

        // 16 beats at 120 BPM is 8 s; incompatible confident tempos use a
        // shorter 5.76 s hand-off instead of a long rhythmic overlap.
        expect(cue.fadeSeconds, closeTo(8.0 * 0.72, 0.01));
        expect(cue.curveGamma, greaterThanOrEqualTo(1.20));
      },
    );

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
      'shortens a confident harmonic clash but leaves uncertain keys neutral',
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
        expect(clash.fadeSeconds, closeTo(8.0 * 0.82, 0.01));
        expect(clash.curveGamma, greaterThanOrEqualTo(1.15));

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
      },
    );
  });

  group('bounded planning window', () {
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
}
