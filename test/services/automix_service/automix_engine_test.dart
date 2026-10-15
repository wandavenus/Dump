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
}) {
  return AutomixTrackFeatures(
    songId: id,
    artist: artist,
    bpm: bpm,
    alternateBpm: alt,
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
  group('automixConfidenceBlend', () {
    test('moves unreliable estimates toward a neutral cost', () {
      expect(
        automixConfidenceBlend(0.0, 0.0, neutralCost: 0.35),
        0.35,
      );
      expect(
        automixConfidenceBlend(1.0, 0.0, neutralCost: 0.35),
        0.35,
      );
      expect(
        automixConfidenceBlend(0.0, 1.0, neutralCost: 0.35),
        0.0,
      );
      expect(
        automixConfidenceBlend(0.0, 0.5, neutralCost: 0.35),
        closeTo(0.175, 1e-12),
      );
      expect(
        automixConfidenceBlend(0.0, 0.0, neutralCost: 0.5),
        0.5,
      );
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
          _f(i, bpm: 90 + (i % 11) * 4, camelot: ((i * 5) % 12) + 1, minor: i.isOdd),
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

    test('empty list yields empty plan', () {
      final plan = AutomixEngine.planSet(
        tracks: const [],
        settings: const AutomixSettings(),
        startIndex: 0,
      );
      expect(plan.order, isEmpty);
      expect(plan.crossfadeSeconds, 0);
    });

    test('harmonic profile avoids big camelot jumps when alternatives exist', () {
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
    });

    test('finds a half-time match outside the local raw-BPM window', () {
      // Raw-BPM order places 60 BPM more than 12 slots from 120 BPM. The
      // half/double-time candidate pool should still discover it immediately.
      final tracks = <AutomixTrackFeatures>[
        _f(
          1,
          bpm: 120,
          camelot: 8,
          minor: true,
          bpmConf: 0.99,
          keyConf: 0.99,
        ),
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
      final peakIdx = energies.indexOf(energies.reduce(
        (a, b) => a > b ? a : b,
      ));
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
}
