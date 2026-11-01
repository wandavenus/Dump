part of '../automix_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AutomixEngine — pure, synchronous, deterministic sequencing without AI.
//
// All costs are closed-form heuristics grounded in standard (non-ML) DJ tool
// practice: spectral-flux autocorrelation tempos from the native extractor,
// Krumhansl–Schmuckler chroma keys mapped onto the Camelot wheel, and a
// user-referenced normalized energy score.  The engine:
//
//   1. Normalizes raw per-track energy across the *candidate set*
//      (robust percentiles), so ordering is relative, not absolute.
//   2. Chains tracks greedily with a bounded one-step lookahead — the naive
//      greedy "best next" frequently strands the set on a tempo plateau;
//      looking one hop ahead costs little on mobile and measurably flattens
//      the end-of-set dud transitions.
//   3. Polishes with bounded local position swaps, recomputing the *exact*
//      affected-link cost (including the energy-arc target of swapped
//      positions).
//
// Deterministic: equal costs break by song id, so the same input always
// produces the same plan even across restarts.
// ═══════════════════════════════════════════════════════════════════════════════

// ── Camelot wheel tables ─────────────────────────────────────────────────────
//
// Minors live on ring "A" (1A..12A), their relative majors on ring "B"
// (1B..12B).  Canonical anchors: C major = 8B, A minor = 8A.
// Index = tonic pitch class (0 = C, 1 = C#/Db, ... 11 = B).

/// Major scale: pitch class (0 = C) → camelot number (ring "B").
/// Minors use the relative-pair table (ring "A").
const List<int> automixCamelotMajorNum = [
  8, // C
  3, // C#/Db
  10, // D
  5, // D#/Eb
  12, // E
  7, // F
  2, // F#/Gb
  9, // G
  4, // G#/Ab
  11, // A
  6, // A#/Bb
  1, // B
];

/// Minor scale: pitch class (0 = C) → camelot number (ring "A").
const List<int> automixCamelotMinorNum = [
  5, // C
  12, // C#/Db
  7, // D
  2, // D#/Eb
  9, // E
  4, // F
  11, // F#/Gb
  6, // G
  1, // G#/Ab
  8, // A
  3, // A#/Bb
  10, // B
];

/// Maps a Krumhansl–Schmuckler extraction result onto the Camelot wheel.
/// Exposed so tests can cross-check the native extractor's mapping against
/// this Dart mirror (the Kotlin side encodes the identical table).
(int number, bool minor)? automixKeyToCamelot(int tonicPc, bool isMinor) {
  final pc = ((tonicPc % 12) + 12) % 12;
  return isMinor
      ? (automixCamelotMinorNum[pc], true)
      : (automixCamelotMajorNum[pc], false);
}

/// Canonical chroma distribution profiles (Krumhansl–Schmuckler). The native
/// key extractor correlates measured chroma against 24 rotated versions of
/// these; mirrored here so the Dart tests can verify the same tuning math.
const List<double> automixKsMajorProfile = [
  6.35,
  2.23,
  3.48,
  2.33,
  4.38,
  4.09,
  2.52,
  5.19,
  2.39,
  3.66,
  2.29,
  2.88,
];
const List<double> automixKsMinorProfile = [
  6.33,
  2.68,
  3.52,
  5.38,
  2.60,
  3.53,
  2.54,
  4.75,
  3.98,
  2.69,
  3.34,
  3.17,
];

// ── Shared helpers ───────────────────────────────────────────────────────────

double automixClamp01(double v) =>
    !v.isFinite ? 0 : (v < 0 ? 0 : (v > 1 ? 1 : v));

/// Moves an uncertain feature cost toward its neutral fallback instead of
/// treating a low-confidence estimate as ground truth.
double automixConfidenceBlend(
  double measuredCost,
  double confidence, {
  required double neutralCost,
}) {
  final c = automixClamp01(confidence);
  return neutralCost + (measuredCost - neutralCost) * c;
}

// ── Planning window ──────────────────────────────────────────────────────────

/// Rotates a queue so [startIndex] is first while preserving the cyclic order
/// of every other item. Used by one-shot AutoMix to keep the selected track
/// anchored without requiring the planner to inspect an unbounded playlist.
List<T> automixRotateQueueFrom<T>(List<T> queue, int startIndex) {
  if (queue.isEmpty) return <T>[];
  final start = startIndex.clamp(0, queue.length - 1);
  return <T>[...queue.skip(start), ...queue.take(start)];
}

/// Bounded planning window: the start track plus up to [horizon] upcoming
/// tracks.
///
/// Sequencing an entire 3000-song library buys nothing the first few
/// transitions do not already deliver (the DJ flow is local by nature) while
/// making every replan cost grow with the library. The user's order is kept
/// untouched past the window.
List<T> automixPlanWindow<T>(List<T> queue, int startIndex, int horizon) {
  if (queue.isEmpty) return <T>[];
  final start = startIndex.clamp(0, queue.length - 1);
  if (horizon < 1) return <T>[queue[start]];
  final end = math.min(queue.length, start + horizon + 1);
  return queue.sublist(start, end);
}

/// Merges the planned window order back onto the full queue tail.
///
/// The engine may only permute the window ([plannedIds]); [tailIds] is the
/// caller's authoritative tail, of which the first [windowUpcomingCount] items
/// were the window's upcoming tracks. Everything after them keeps its original
/// order, so the result is always a permutation of [tailIds].
List<T> automixOrderedTail<T>(
  List<T> plannedIds,
  List<T> tailIds,
  int windowUpcomingCount,
) {
  final kept = windowUpcomingCount <= 0
      ? 0
      : math.min(windowUpcomingCount, tailIds.length);
  return <T>[...plannedIds, ...tailIds.skip(kept)];
}

/// True when [tail] is exactly the continuation of a plan that already
/// sequenced [planned] — whose first entry is the track that just started.
///
/// This is what lets AutoMix sequence the whole remaining queue **once** instead
/// of re-planning before every transition: a plain track advance leaves the
/// plan valid, while any real queue edit (add / remove / reorder / skip)
/// breaks it and triggers a fresh pass.
bool automixPlanContinues(List<int> planned, List<int> tail) {
  if (tail.isEmpty) return true;
  final start = planned.indexOf(tail.first);
  if (start < 0) return false;
  if (planned.length - start != tail.length) return false;
  for (var i = 0; i < tail.length; i++) {
    if (planned[start + i] != tail[i]) return false;
  }
  return true;
}

/// Exact ordered-queue snapshot comparison. Membership alone is insufficient:
/// reordering the same IDs while AutoMix is planning is a real queue edit.
bool automixQueueSnapshotMatches(List<int> expected, List<int> actual) {
  if (expected.length != actual.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (expected[i] != actual[i]) return false;
  }
  return true;
}

/// Returns tracks in the order AutoMix can safely target for the next fade.
/// In shuffle mode Media3 owns the permutation; only its reported next index is
/// authoritative, so do not infer further transitions from the linear queue.
List<T> automixUpcomingTracks<T>(
  List<T> queue,
  int currentIndex, {
  required bool shuffleEnabled,
  required int? nextTrackIndex,
}) {
  if (currentIndex < 0 || currentIndex >= queue.length) return <T>[];
  if (!shuffleEnabled) {
    return queue.skip(currentIndex + 1).toList(growable: false);
  }
  final next = nextTrackIndex;
  if (next == null ||
      next < 0 ||
      next >= queue.length ||
      next == currentIndex) {
    return <T>[];
  }
  return <T>[queue[next]];
}

// ── Tempo matching ───────────────────────────────────────────────────────────

/// Relative tempo distance beyond which two decks are **not** pulled together.
///
/// Pulling a pair further apart than this needs a stretch the ear hears as a
/// wobble, so those transitions stay a plain equal-power crossfade: no tempo
/// pull, no beat-grid start, no bass swap. Only pairs that already sit close
/// enough to sound like one record get beat-matched — the Apple-Music rule.
const double automixTempoMatchTolerance = 0.06;

/// Tempo pull for one deck, as `(matched, multiplier)`.
///
/// [multiplier] is `1.0` (untouched) unless [trackBpm] can be pulled onto
/// [referenceBpm] by at most [tolerance]. The comparison includes half/double
/// pulse folds so an octave-ambiguous detector result can still provide a
/// usable beat grid without applying an audible 2× rate change. A `false` match
/// means the caller must not publish a beat grid for that deck.
(bool matched, double multiplier) automixTempoMatch({
  required double? referenceBpm,
  required double? trackBpm,
  double tolerance = automixTempoMatchTolerance,
}) {
  if (referenceBpm == null ||
      trackBpm == null ||
      !referenceBpm.isFinite ||
      !trackBpm.isFinite ||
      referenceBpm <= 0 ||
      trackBpm <= 0) {
    return (false, 1.0);
  }

  // Tempo analysis can report a track at half or double its musical pulse.
  // Compare those octave folds as well as the raw estimate, but keep the
  // resulting speed correction near 1.0 so this never applies a 2× rate change.
  final candidates = <double>[trackBpm, trackBpm * 2.0, trackBpm / 2.0];
  var bestMultiplier = 1.0;
  var bestDistance = double.infinity;
  for (final candidate in candidates) {
    if (!candidate.isFinite || candidate <= 0) continue;
    final multiplier = referenceBpm / candidate;
    final distance = (multiplier - 1.0).abs();
    if (distance < bestDistance) {
      bestDistance = distance;
      bestMultiplier = multiplier;
    }
  }
  if (!bestDistance.isFinite || bestDistance > tolerance) {
    return (false, 1.0);
  }
  return (true, bestMultiplier.clamp(0.92, 1.08).toDouble());
}

// ── Segmented (full-song) analysis ───────────────────────────────────────────

/// Folds [value] onto [reference]'s octave (half/double-time ambiguity).
double automixFoldToOctave(double value, double reference) {
  if (value <= 0 || reference <= 0) return value;
  var v = value;
  while (v > reference * 1.4) {
    v /= 2;
  }
  while (v < reference / 1.4) {
    v *= 2;
  }
  return v;
}

/// Flattens overlapping analysis windows into a stable chord timeline.
/// Repeated labels in adjacent one-second hops are compressed; overlapping
/// windows that disagree at effectively the same timestamp keep the stronger
/// estimate instead of creating a rapid, artificial chord run.
List<AutomixChordEvent> automixMergeChordProgressions(
  List<AutomixSegmentFeatures> segments,
) {
  final candidates = <AutomixChordEvent>[
    for (final segment in segments) ...segment.chordProgression,
  ]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final merged = <AutomixChordEvent>[];
  for (final chord in candidates) {
    if (merged.isEmpty) {
      merged.add(chord);
      continue;
    }
    final previous = merged.last;
    final deltaMs = chord.startMs - previous.startMs;
    if (deltaMs < 0) continue;
    if (previous.rootPitchClass == chord.rootPitchClass &&
        previous.quality == chord.quality &&
        deltaMs <= 3000) {
      if (chord.confidence > previous.confidence) {
        merged[merged.length - 1] = AutomixChordEvent(
          startMs: previous.startMs,
          rootPitchClass: chord.rootPitchClass,
          root: chord.root,
          quality: chord.quality,
          confidence: chord.confidence,
        );
      }
      continue;
    }
    if (deltaMs < 500 && chord.confidence <= previous.confidence) continue;
    if (deltaMs < 500 && chord.confidence > previous.confidence) {
      merged[merged.length - 1] = chord;
      continue;
    }
    merged.add(chord);
  }
  return List<AutomixChordEvent>.unmodifiable(merged);
}

/// Edge-local section label derived from the 15 s seam window and the two
/// quarters nearest the mix seam. The native label is computed from a whole
/// 120 s window, which can average a quiet intro with a loud drop; this
/// directional label keeps the head and tail independent for the transition
/// planner. Segments without edge slots fall back to the quarter profile.
({int region, double confidence})? _automixEdgeStructure(
  AutomixSegmentFeatures segment, {
  required bool head,
}) {
  final quarters = segment.energyQuarters;
  // The edge 15 s is the material the fade actually overlaps. Normalise it
  // against this window's own median instead of the absolute dB thresholds
  // that made almost every modern master STABLE_HIGH. The quarter profile is
  // still needed for the slope, and remains the fallback for old cache entries
  // or a native library that predates the edge slots.
  final edgeDb = head ? segment.introEdgeRmsDb : segment.outroEdgeRmsDb;
  final hasEdge =
      edgeDb != null &&
      edgeDb.isFinite &&
      segment.rmsDb != null &&
      segment.rmsDb!.isFinite;
  if (!hasEdge && quarters.length != 4) return null;
  final first = quarters.length == 4
      ? (head ? quarters[0] : quarters[2])
      : null;
  final second = quarters.length == 4
      ? (head ? quarters[1] : quarters[3])
      : null;
  if (first != null && (!first.isFinite || !second!.isFinite)) return null;
  final meanDb = first != null && second != null
      ? (first + second) / 2.0
      : null;
  final slope = first != null && second != null ? second - first : 0.0;

  final cue = head ? segment.dropCueMs : segment.breakdownCueMs;
  final cueConfidence = head
      ? segment.dropConfidence
      : segment.breakdownConfidence;
  final cueNearEdge =
      cue != null &&
      cue.isFinite &&
      cue >= 0 &&
      segment.seconds > 0 &&
      (head ? cue <= 45000 : cue >= (segment.seconds - 60.0) * 1000.0);
  if (cueNearEdge && cueConfidence >= 0.45) {
    return (
      region: head ? 3 : 4,
      confidence: automixClamp01(0.55 + 0.30 * cueConfidence),
    );
  }

  if (hasEdge) {
    final relativeDb = edgeDb - segment.rmsDb!;
    // A silent or near-silent edge is low activity regardless of the window
    // median; a normal fade-out is captured by the negative slope below.
    if (relativeDb <= -16.0 || edgeDb <= -45.0) {
      return (region: 1, confidence: 0.70);
    }
    if (slope > 1.5 && relativeDb < -4.0) {
      return (region: 2, confidence: automixClamp01(0.55 + slope / 12.0));
    }
    if (slope < -1.5 && relativeDb < -2.0) {
      return (region: 4, confidence: automixClamp01(0.55 - slope / 12.0));
    }
    if (relativeDb >= -6.0 && slope.abs() <= 1.5) {
      return (region: 5, confidence: 0.70);
    }
    if (relativeDb >= -12.0 && slope >= -1.5) {
      return (region: 5, confidence: 0.55);
    }
    return (region: 1, confidence: 0.50);
  }

  // Legacy path for segment objects without edge slots (tests/old caches).
  if (meanDb! < -32.0) {
    return (region: 1, confidence: 0.70);
  }
  if (slope > 1.5 && meanDb < -18.0) {
    return (region: 2, confidence: automixClamp01(0.55 + slope / 12.0));
  }
  if (meanDb > -18.0 && slope.abs() <= 1.5) {
    return (region: 5, confidence: 0.70);
  }
  if (meanDb > -22.0 && slope >= -1.5) {
    return (region: 5, confidence: 0.55);
  }
  return (region: 1, confidence: 0.50);
}

/// Merges the analyzed windows of one file into per-track features.
///
/// Long tracks are *sampled* rather than truncated: tempo is a
/// confidence-weighted vote of every window (folded onto the strongest
/// window's octave), the key is a confidence-weighted vote, energy is
/// duration-weighted, and the first/last window give the coarse structure
/// markers the transition planner keys on. The last window additionally
/// provides the exit beat grid ([AutomixTrackFeatures.tailBpm] /
/// [AutomixTrackFeatures.tailBeatOffsetMs]) because the fade happens at the end
/// of the file, not at its start.
AutomixTrackFeatures automixMergeSegments({
  required int songId,
  String title = '',
  String artist = '',
  required List<AutomixSegmentFeatures> segments,
  double? loudnessLufs,
  double? sourceDurationSeconds,
  bool tailSegmentAnalyzed = true,
}) {
  // ── Tempo vote ────────────────────────────────────────────────────────────
  final withBpm = segments
      .where((s) => s.bpm != null && s.bpmConfidence > 0)
      .toList();
  double? bpm;
  var bpmConfidence = 0.0;
  AutomixSegmentFeatures? tempoAnchor;
  if (withBpm.isNotEmpty) {
    final anchor = withBpm.reduce(
      (a, b) => a.bpmConfidence >= b.bpmConfidence ? a : b,
    );
    tempoAnchor = anchor;
    final foldedTempos = <(double, double)>[];
    var weight = 0.0;
    var agreeing = 0.0;
    for (final s in withBpm) {
      final folded = automixFoldToOctave(s.bpm!, anchor.bpm!);
      foldedTempos.add((folded, s.bpmConfidence));
      weight += s.bpmConfidence;
      if ((folded - anchor.bpm!).abs() / anchor.bpm! <= 0.04) {
        agreeing += s.bpmConfidence;
      }
    }
    if (weight > 0) {
      // A weighted mean of disagreeing windows invents a tempo nobody
      // measured (120, 120, 90 -> 110). Use the weighted median instead, and
      // cut confidence when the windows do not broadly agree; the planner then
      // treats the tempo as neutral rather than trusting the invented value.
      foldedTempos.sort((a, b) => a.$1.compareTo(b.$1));
      var cumulative = 0.0;
      var median = foldedTempos.first.$1;
      for (final (value, confidence) in foldedTempos) {
        cumulative += confidence;
        if (cumulative >= weight * 0.5) {
          median = value;
          break;
        }
      }
      final agreement = automixClamp01(agreeing / weight);
      bpm = automixFoldToOctave(median, anchor.bpm!);
      bpmConfidence = automixClamp01(
        anchor.bpmConfidence *
            (agreement >= 0.70 ? agreement : agreement * 0.5),
      );
    }
  }

  // ── Tempo curve: outward pulse and cross-window stability ────────────────
  // The head window supplies the intro pulse and the last analyzed window the
  // exit pulse, both folded into the track BPM's octave like [tailBpm]. Only
  // tail windows count towards the exit pulse so a missing tail decode cannot
  // silently promote the intro grid to the exit.
  double? curveBpmOf(double? value) {
    if (value == null || !value.isFinite || value <= 0) return null;
    return bpm == null ? value : automixFoldToOctave(value, bpm);
  }

  // An edge phase is measured modulo the edge tempo's beat period. Folding a
  // faster edge estimate down to the track octave shortens that period, so the
  // same phase can represent either a main beat or its offbeat. Only a slower
  // edge estimate (whose period is a multiple of the published one) preserves
  // the phase unambiguously.
  bool edgePhaseSurvivesFold(double? measuredBpm, double? publishedBpm) {
    if (measuredBpm == null || publishedBpm == null) return true;
    if (!measuredBpm.isFinite ||
        !publishedBpm.isFinite ||
        measuredBpm <= 0 ||
        publishedBpm <= 0) {
      return false;
    }
    return measuredBpm <= publishedBpm * 1.03;
  }

  double? startBpm;
  double? endBpm;
  var startBpmConfidence = 0.0;
  var endBpmConfidence = 0.0;
  double? introBeatOffsetMs;
  double? introTempoStability;
  double? outroTempoStability;
  if (segments.isNotEmpty) {
    final head = segments.first;
    startBpm = curveBpmOf(head.startBpm);
    startBpmConfidence = startBpm == null ? 0.0 : head.startBpmConfidence;
    if (startBpm != null &&
        startBpmConfidence >= AutomixContract.tempoConfidenceMin &&
        edgePhaseSurvivesFold(head.startBpm, startBpm) &&
        head.startBeatOffsetMs != null &&
        head.startBeatOffsetMs!.isFinite &&
        head.startBeatOffsetMs! >= 0) {
      introBeatOffsetMs = head.startBeatOffsetMs;
    }
    introTempoStability = head.tempoStability;
    if (tailSegmentAnalyzed) {
      final tail = segments.last;
      endBpm = curveBpmOf(tail.endBpm);
      endBpmConfidence = endBpm == null ? 0.0 : tail.endBpmConfidence;
      outroTempoStability = tail.tempoStability;
    }
  }
  var stabilityWeight = 0.0;
  var stabilitySum = 0.0;
  for (final s in segments) {
    if (s.tempoStability != null &&
        s.tempoStability!.isFinite &&
        s.tempoStability! >= 0 &&
        s.tempoStability! <= 1) {
      final w = s.bpmConfidence > 0 ? s.bpmConfidence : 0.5;
      stabilitySum += s.tempoStability! * w;
      stabilityWeight += w;
    }
  }
  final tempoStability = stabilityWeight > 0
      ? stabilitySum / stabilityWeight
      : null;

  // ── Key vote ──────────────────────────────────────────────────────────────
  final withKey = segments
      .where((s) => s.camelotNumber != null && s.keyConfidence > 0)
      .toList();
  int? camelotNumber;
  bool? camelotMinor;
  var keyConfidence = 0.0;
  if (withKey.isNotEmpty) {
    final votes = <String, (int, bool, double)>{};
    var total = 0.0;
    for (final s in withKey) {
      final minor = s.camelotMinor ?? false;
      final key = '${s.camelotNumber}:$minor';
      final previous = votes[key];
      votes[key] = (
        s.camelotNumber!,
        minor,
        (previous?.$3 ?? 0) + s.keyConfidence,
      );
      total += s.keyConfidence;
    }
    final best = votes.values.reduce((a, b) => b.$3 > a.$3 ? b : a);
    camelotNumber = best.$1;
    camelotMinor = best.$2;
    keyConfidence = total <= 0
        ? 0
        : automixClamp01((best.$3 / total) * automixClamp01(best.$3));
  }

  // ── Duration-weighted raw energy ──────────────────────────────────────────
  double? weightedMean(double? Function(AutomixSegmentFeatures) pick) {
    var sum = 0.0;
    var weight = 0.0;
    for (final s in segments) {
      final v = pick(s);
      if (v == null) continue;
      final w = s.seconds <= 0 ? 1.0 : s.seconds;
      sum += v * w;
      weight += w;
    }
    return weight <= 0 ? null : sum / weight;
  }

  final rmsDb = weightedMean((s) => s.rmsDb);
  final centroidHz = weightedMean((s) => s.centroidHz);
  final onsetRate = weightedMean((s) => s.onsetRate);

  final firstSegment = segments.isEmpty ? null : segments.first;
  final lastSegment = segments.isEmpty ? null : segments.last;

  // ── Coarse structure: first/last window relative to this track's peak ─────
  // The window medians still define the set-level peak, so the 0..1 scale is
  // comparable with older analyses. The edge values, however, are what decide
  // the seam: a quiet final 15 s is no longer masked by a loud 120 s median.
  final segmentEnergy = <double?>[
    for (final s in segments)
      s.rmsDb == null ? null : automixClamp01((s.rmsDb! + 30.0) / 24.0),
  ];
  final present = segmentEnergy.whereType<double>().toList(growable: false);
  double? edgeEnergy(double? edgeRmsDb) =>
      edgeRmsDb == null || !edgeRmsDb.isFinite
      ? null
      : automixClamp01((edgeRmsDb + 30.0) / 24.0);
  final headEdgeRmsDb = firstSegment?.introEdgeRmsDb ?? firstSegment?.rmsDb;
  final tailEdgeRmsDb = tailSegmentAnalyzed
      ? (lastSegment?.outroEdgeRmsDb ?? lastSegment?.rmsDb)
      : null;
  double? introEnergy;
  double? outroEnergy;
  if (present.length >= 2) {
    final peak = present.reduce(math.max);
    if (peak > 0.05) {
      final headEnergy = edgeEnergy(headEdgeRmsDb);
      final tailEnergy = edgeEnergy(tailEdgeRmsDb);
      introEnergy = headEnergy == null
          ? null
          : automixClamp01(headEnergy / peak);
      outroEnergy = !tailSegmentAnalyzed || tailEnergy == null
          ? null
          : automixClamp01(tailEnergy / peak);
    }
  }

  // ── Exit beat grid: the fade lives in the tail window ────────────────────
  double? tailBpm;
  var tailBpmConfidence = 0.0;
  double? tailBeatOffsetMs;
  double? tailDownbeatOffsetMs;
  // Only the last (tail) window may publish the exit grid. Falling back to
  // middle/head windows here would attach a valid phase and confidence to a
  // completely different part of the file when the tail tempo is unusable.
  final exitWindow = tailSegmentAnalyzed && segments.isNotEmpty
      ? segments.last
      : null;
  if (exitWindow != null) {
    final s = exitWindow;
    if (s.endBpm != null &&
        s.endBpmConfidence >= AutomixContract.tempoConfidenceMin) {
      tailBpm = bpm == null ? s.endBpm! : automixFoldToOctave(s.endBpm!, bpm);
      tailBpmConfidence = s.endBpmConfidence;
      if (edgePhaseSurvivesFold(s.endBpm, tailBpm) &&
          s.endBeatOffsetMs != null &&
          s.endBeatOffsetMs!.isFinite &&
          s.endBeatOffsetMs! >= 0) {
        tailBeatOffsetMs = s.startSeconds * 1000.0 + s.endBeatOffsetMs!;
      }
      // This phrase phase was estimated with whole-window tempo. Do not pair
      // it with a local exit BPM.
    } else if (s.bpm != null && s.bpmConfidence >= 0.20) {
      tailBpm = bpm == null ? s.bpm! : automixFoldToOctave(s.bpm!, bpm);
      final tailConfidence = s.tailBpmConfidence;
      tailBpmConfidence =
          tailConfidence.isFinite && tailConfidence >= 0 && tailConfidence <= 1
          ? tailConfidence
          : 0.0;
      final phaseSurvivesFold = edgePhaseSurvivesFold(s.bpm, tailBpm);
      if (phaseSurvivesFold &&
          s.beatOffsetMs != null &&
          s.bpmConfidence >= 0.25) {
        tailBeatOffsetMs = s.startSeconds * 1000.0 + s.beatOffsetMs!;
      }
      if (phaseSurvivesFold &&
          s.downbeatOffsetMs != null &&
          s.bpmConfidence >= 0.25) {
        tailDownbeatOffsetMs = s.startSeconds * 1000.0 + s.downbeatOffsetMs!;
      }
    }
  }

  var analyzedSeconds = 0.0;
  for (final s in segments) {
    analyzedSeconds += s.seconds;
  }
  final inferredFileSeconds = segments.isEmpty
      ? 0.0
      : segments.last.startSeconds + segments.last.seconds;
  final hasSourceDuration =
      sourceDurationSeconds != null &&
      sourceDurationSeconds.isFinite &&
      sourceDurationSeconds > 0;
  // A failed tail/middle decode must not shrink the actual source duration to
  // the end of the last successful window. Keep the larger valid boundary as
  // a defensive guard against slightly inconsistent window metadata.
  final fileSeconds = hasSourceDuration
      ? math.max(sourceDurationSeconds, inferredFileSeconds).toDouble()
      : inferredFileSeconds;
  final headStructure = firstSegment == null
      ? null
      : _automixEdgeStructure(firstSegment, head: true);
  final tailStructure = lastSegment == null
      ? null
      : _automixEdgeStructure(lastSegment, head: false);

  // ── Energy momentum at the edges: quarter profile → dB/quarter slope ─────
  // The head window describes the intro, the exit window the outro. Only a
  // complete four-quarter profile is usable; a missing profile (older native
  // library or failed quarter) leaves the term neutral instead of inventing a
  // trend. A missing tail decode must not promote the intro slope to the exit.
  double? quarterSlope(
    AutomixSegmentFeatures? segment,
    int earlier,
    int later,
  ) {
    final quarters = segment?.energyQuarters;
    if (quarters == null || quarters.length != 4) return null;
    final first = quarters[earlier];
    final second = quarters[later];
    if (!first.isFinite || !second.isFinite) return null;
    return second - first;
  }

  final introSlope = quarterSlope(firstSegment, 0, 1);
  final outroSlope = tailSegmentAnalyzed
      ? quarterSlope(lastSegment, 2, 3)
      : null;
  // ── Head beat grid: same octave guard as the tail ────────────────────────
  // A window's beat phase is measured modulo that window's own beat period.
  // The merged track BPM can be an octave fold of the head estimate (a sparse
  // intro detected at half speed, for example), which changes the period while
  // leaving the old phase looking valid. Reusing it would place every other
  // beat on an offbeat, so withhold the head grid unless its tempo survives the
  // octave fold. This is the guard [automixHasConfidentIntroGrid] already
  // relies on for the local quarter grid.
  double? headBeatOffsetMs;
  double? headDownbeatOffsetMs;
  // The metre belongs to the window whose grid is published: the head window
  // for the intro grid, the exit window for the tail grid. Native only uses it
  // to size the phrase grid and the phrase lock, so an unknown metre stays at
  // the 4/4 prior rather than disabling alignment.
  final headMeter = firstSegment?.meter ?? 4;
  final tailMeter = exitWindow?.meter ?? 4;
  if (firstSegment != null) {
    final headPhaseUsable =
        firstSegment.bpmConfidence >= 0.20 &&
        edgePhaseSurvivesFold(firstSegment.bpm, bpm);
    if (headPhaseUsable) {
      final beatOffset = firstSegment.beatOffsetMs;
      if (beatOffset != null && beatOffset.isFinite && beatOffset >= 0) {
        headBeatOffsetMs = firstSegment.startSeconds * 1000.0 + beatOffset;
      }
      final downbeatOffset = firstSegment.downbeatOffsetMs;
      if (downbeatOffset != null &&
          downbeatOffset.isFinite &&
          downbeatOffset >= 0) {
        headDownbeatOffsetMs =
            firstSegment.startSeconds * 1000.0 + downbeatOffset;
      }
    }
  }

  // H04: a file's first usable drop is not necessarily in the head window.
  // Collect the native top-three candidates from every analyzed window and
  // pick the earliest one inside the early-handover envelope. The strongest
  // candidate is still available for structure labels, but it must not hide an
  // earlier drop that is the musically correct handover point.
  final dropCandidates = <AutomixDropCue>[];
  for (final segment in segments) {
    final cues = segment.dropCues.isNotEmpty
        ? segment.dropCues
        : <AutomixDropCue>[
            if (segment.dropCueMs != null)
              AutomixDropCue(
                cueMs: segment.dropCueMs!,
                confidence: segment.dropConfidence,
              ),
          ];
    for (final cue in cues) {
      if (!cue.cueMs.isFinite || cue.cueMs < 0) continue;
      dropCandidates.add(
        AutomixDropCue(
          cueMs: segment.startSeconds * 1000.0 + cue.cueMs,
          confidence: cue.confidence,
        ),
      );
    }
  }
  dropCandidates.sort((a, b) => a.cueMs.compareTo(b.cueMs));
  AutomixDropCue? selectedDrop;
  for (final candidate in dropCandidates) {
    if (candidate.confidence < AutomixContract.dropConfidenceMin) continue;
    if (candidate.cueMs < AutomixContract.dropHandoverMinMs ||
        candidate.cueMs > AutomixContract.dropHandoverMaxMs) {
      continue;
    }
    selectedDrop = candidate;
    break;
  }
  final dropCueMs = selectedDrop?.cueMs;
  final localBreakdownCue = tailSegmentAnalyzed
      ? lastSegment?.breakdownCueMs
      : null;
  final tailBreakdownCueMs =
      localBreakdownCue != null &&
          localBreakdownCue.isFinite &&
          localBreakdownCue >= 0
      ? lastSegment!.startSeconds * 1000.0 + localBreakdownCue
      : null;

  // ── Track-level section boundary near the exit ────────────────────────────
  // The exit window's 2 s-block chroma change point is an actual section
  // boundary, so a transition that starts there hands over at the beginning of
  // the final section instead of at an arbitrary point. The 2 s block granularity
  // is too coarse for a short fade lead but exactly right for the 30–65 s early
  // handover, which is the only consumer.
  double? tailSectionCueMs;
  var tailSectionCueConfidence = 0.0;
  if (exitWindow != null) {
    final localCue = exitWindow.sectionCueMs;
    final cueConfidence = exitWindow.sectionCueConfidence;
    if (localCue != null &&
        localCue.isFinite &&
        localCue >= 0 &&
        cueConfidence.isFinite &&
        cueConfidence >= 0.50) {
      tailSectionCueMs = exitWindow.startSeconds * 1000.0 + localCue;
      tailSectionCueConfidence = cueConfidence;
    }
  }

  final anchorAlternateBpm = tempoAnchor?.alternateBpm;
  final alternateBpm =
      bpm != null &&
          anchorAlternateBpm != null &&
          anchorAlternateBpm.isFinite &&
          anchorAlternateBpm > 0
      ? anchorAlternateBpm
      : null;

  // ── Vocal likelihood ─────────────────────────────────────────────────────
  final withVocal = segments.where((s) => s.vocalConfidence > 0).toList();
  var vocalLikelihood = 0.0;
  var vocalConfidence = 0.0;
  if (withVocal.isNotEmpty) {
    var weightedLikelihood = 0.0;
    var totalWeight = 0.0;
    for (final s in withVocal) {
      final w = s.vocalConfidence;
      weightedLikelihood += s.vocalLikelihood * w;
      totalWeight += w;
    }
    if (totalWeight > 0) {
      vocalLikelihood = automixClamp01(weightedLikelihood / totalWeight);
      vocalConfidence = automixClamp01(totalWeight / withVocal.length);
    }
  }

  return AutomixTrackFeatures(
    songId: songId,
    title: title,
    artist: artist,
    bpm: bpm,
    bpmConfidence: bpmConfidence,
    alternateBpm: alternateBpm,
    beatOffsetMs: headBeatOffsetMs,
    downbeatOffsetMs: headDownbeatOffsetMs,
    tailDownbeatOffsetMs: tailDownbeatOffsetMs,
    meter: headMeter,
    tailMeter: tailMeter,
    dropCueMs: dropCueMs,
    tailBreakdownCueMs: tailBreakdownCueMs,
    dropConfidence: selectedDrop?.confidence ?? 0,
    tailBreakdownConfidence: tailSegmentAnalyzed
        ? (lastSegment?.breakdownConfidence ?? 0)
        : 0,
    structureRegion:
        headStructure?.region ?? firstSegment?.structureRegion ?? 0,
    structureConfidence: headStructure != null
        ? math.max(
            headStructure.confidence,
            firstSegment?.structureConfidence ?? 0,
          )
        : (firstSegment?.structureConfidence ?? 0),
    tailStructureRegion: tailSegmentAnalyzed
        ? (tailStructure?.region ?? lastSegment?.structureRegion ?? 0)
        : 0,
    tailStructureConfidence: tailSegmentAnalyzed
        ? (tailStructure != null
              ? math.max(
                  tailStructure.confidence,
                  lastSegment?.structureConfidence ?? 0,
                )
              : (lastSegment?.structureConfidence ?? 0))
        : 0,
    tailSectionCueMs: tailSegmentAnalyzed ? tailSectionCueMs : null,
    tailSectionCueConfidence: tailSegmentAnalyzed
        ? tailSectionCueConfidence
        : 0,
    vocalLikelihood: vocalLikelihood,
    vocalConfidence: vocalConfidence,
    durationSeconds: fileSeconds,
    camelotNumber: camelotNumber,
    camelotMinor: camelotMinor,
    keyConfidence: keyConfidence,
    loudnessLufs: loudnessLufs,
    rmsDb: rmsDb,
    centroidHz: centroidHz,
    onsetRate: onsetRate,
    tailBpm: tailBpm,
    tailBpmConfidence: tailBpmConfidence,
    tailBeatOffsetMs: tailBeatOffsetMs,
    startBpm: startBpm,
    startBpmConfidence: startBpmConfidence,
    endBpm: endBpm,
    endBpmConfidence: endBpmConfidence,
    introBeatOffsetMs: introBeatOffsetMs,
    tempoStability: tempoStability,
    introTempoStability: introTempoStability,
    outroTempoStability: outroTempoStability,
    introSlope: introSlope,
    outroSlope: outroSlope,
    introRmsDb: headEdgeRmsDb,
    outroRmsDb: tailEdgeRmsDb,
    introEnergy: introEnergy,
    outroEnergy: outroEnergy,
    introEdgeLufs: firstSegment?.introEdgeLufs,
    outroEdgeLufs: tailSegmentAnalyzed ? lastSegment?.outroEdgeLufs : null,
    introEdgeOnsetRate: firstSegment?.introEdgeOnsetRate,
    outroEdgeOnsetRate: tailSegmentAnalyzed
        ? lastSegment?.outroEdgeOnsetRate
        : null,
    analyzedFraction: fileSeconds <= 0
        ? 0
        : automixClamp01(analyzedSeconds / fileSeconds),
    tailAnalyzed: tailSegmentAnalyzed,
    chordProgression: automixMergeChordProgressions(segments),
  );
}

// ── Per-transition cue ───────────────────────────────────────────────────────

/// Strategy selected by the analyzer/transition planner. Codes are mirrored in
/// Media3PlaybackService's target parser; changing a code requires changing both.
enum AutomixTransitionStrategy {
  crossfade(0),
  structureAligned(1),
  shortHandover(2),
  longBlend(3),
  quickHandover(4);

  const AutomixTransitionStrategy(this.code);
  final int code;
}

/// Everything the native fade needs for ONE transition.
@immutable
class AutomixTransitionCue {
  const AutomixTransitionCue({
    required this.fadeSeconds,
    required this.curveGamma,
    required this.outgoingTrim,
    required this.incomingTrim,
    required this.strategy,
    this.transitionStartMs,
    required this.outgoingBassOverlapGain,
    required this.incomingBassOverlapGain,
    required this.outgoingMidOverlapGain,
    required this.incomingMidOverlapGain,
    required this.outgoingHighOverlapGain,
    required this.incomingHighOverlapGain,
    required this.outgoingPitchSemitones,
    this.earlyHandover = false,
    this.earlyHandoverUnavailableReason,
  });

  /// Strategy that controls the production fade behavior on Android.
  final AutomixTransitionStrategy strategy;

  /// Per-deck spectral/structure-driven isolator targets at the center of the
  /// overlap. Native smoothing and an envelope return all bands to unity.
  final double outgoingBassOverlapGain;
  final double incomingBassOverlapGain;
  final double outgoingMidOverlapGain;
  final double incomingMidOverlapGain;
  final double outgoingHighOverlapGain;
  final double incomingHighOverlapGain;

  /// Signed semitone shift applied to the OUTGOING deck only while the two
  /// decks overlap, so a confident one-semitone key difference is smoothed
  /// over without changing the incoming track. Zero means no shift.
  final double outgoingPitchSemitones;

  /// Fade length in media-timeline seconds (opposite deck's tempo governs).
  final double fadeSeconds;

  /// Absolute source position (ms) in the outgoing track where an early
  /// handover should begin. Null keeps the conventional near-end crossfade.
  /// This is deliberately separate from [fadeSeconds]: the outgoing deck can
  /// be handed over 35–60 s before EOF while the actual overlap stays short.
  final double? transitionStartMs;

  /// Whether the incoming drop path was selected. When it was not, the reason
  /// is carried for the diagnostic log so a silently unavailable early
  /// handover is visible (audit AM9-H04).
  final bool earlyHandover;
  final String? earlyHandoverUnavailableReason;

  /// Equal-power transfer shape: 1.0 = the classic cos/sin curve, > 1 hands the
  /// mix over faster (dense outros), < 1 slower (sparse outros).
  final double curveGamma;

  /// Level trims (≤ 1.0) applied across the overlap so the louder deck is
  /// attenuated toward the quieter one. Never boosts, so nothing can clip.
  final double outgoingTrim;
  final double incomingTrim;
}

/// Whether the exit BPM is trustworthy enough to steer planning/playback.
/// The gate comes from [AutomixContract], mirrored by the native planner.
bool automixHasConfidentTailBpm(AutomixTrackFeatures features) {
  final bpm = features.tailBpm;
  final confidence = features.tailBpmConfidence;
  return bpm != null &&
      bpm.isFinite &&
      bpm > 0 &&
      confidence.isFinite &&
      confidence >= AutomixContract.tempoConfidenceMin &&
      confidence <= 1.0;
}

/// Tempo that governs a track's exit. A weak/missing tail estimate falls back
/// to the whole-track/head BPM instead of letting untrusted tail metadata steer
/// sequencing or the fade duration.
double? automixExitBpm(AutomixTrackFeatures features) =>
    automixHasConfidentTailBpm(features) ? features.tailBpm : features.bpm;

/// Confidence corresponding to [automixExitBpm], never borrowed from the head
/// when a confident tail BPM is the value actually being used.
double automixExitBpmConfidence(AutomixTrackFeatures features) =>
    automixHasConfidentTailBpm(features)
    ? features.tailBpmConfidence
    : features.bpmConfidence;

/// Minimum measured edge-tempo stability required for active tempo pull.
/// Unknown stability keeps legacy behavior; a measured unstable curve uses a
/// conventional crossfade instead of varispeed.
const double automixTempoStabilityThreshold = 0.65;

bool automixTempoStabilityAllowsPull(double? stability) =>
    stability == null ||
    !stability.isFinite ||
    stability >= automixTempoStabilityThreshold;

bool automixTempoCurveAllowsPair(
  AutomixTrackFeatures outgoing,
  AutomixTrackFeatures incoming,
) =>
    automixTempoStabilityAllowsPull(outgoing.outroTempoStability) &&
    automixTempoStabilityAllowsPull(incoming.introTempoStability);

bool automixHasConfidentIntroBpm(AutomixTrackFeatures features) {
  final bpm = features.startBpm;
  final confidence = features.startBpmConfidence;
  return bpm != null &&
      bpm.isFinite &&
      bpm > 0 &&
      confidence.isFinite &&
      confidence >= AutomixContract.tempoConfidenceMin &&
      confidence <= 1.0;
}

/// Tempo at which the incoming track actually begins, falling back to its
/// whole-window estimate if the local intro estimate is not confident.
double? automixEntryBpm(AutomixTrackFeatures features) =>
    automixHasConfidentIntroBpm(features) ? features.startBpm : features.bpm;

double automixEntryBpmConfidence(AutomixTrackFeatures features) =>
    automixHasConfidentIntroBpm(features)
    ? features.startBpmConfidence
    : features.bpmConfidence;

/// A local intro grid is usable only when BPM and phase came from the same
/// quarter. Never combine local BPM with whole-window beat phase.
bool automixHasConfidentIntroGrid(AutomixTrackFeatures features) =>
    automixHasConfidentIntroBpm(features) &&
    features.introBeatOffsetMs != null &&
    features.introBeatOffsetMs!.isFinite &&
    features.introBeatOffsetMs! >= 0;

/// True when the outgoing grid uses the locally measured end-quarter tempo.
/// Its whole-window phrase phase must not be paired with this local clock.
bool automixHasConfidentLocalTailBpm(AutomixTrackFeatures features) =>
    features.endBpm != null &&
    features.endBpm!.isFinite &&
    features.endBpm! > 0 &&
    features.endBpmConfidence.isFinite &&
    features.endBpmConfidence >= AutomixContract.tempoConfidenceMin &&
    features.endBpmConfidence <= 1.0;

/// A conservative cost for the outgoing tail chord → incoming intro chord.
/// 0 is compatible and 1 is strongly clashing. Null means no confident pair.
double? automixChordProgressionCost(
  AutomixTrackFeatures outgoing,
  AutomixTrackFeatures incoming,
) {
  AutomixChordEvent? lastOutgoing;
  for (final chord in outgoing.chordProgression) {
    if (chord.confidence < 0.45) continue;
    if (outgoing.durationSeconds > 0 &&
        chord.startMs <
            (outgoing.durationSeconds - 30).clamp(0, double.infinity) * 1000) {
      continue;
    }
    if (lastOutgoing == null || chord.startMs > lastOutgoing.startMs) {
      lastOutgoing = chord;
    }
  }
  AutomixChordEvent? firstIncoming;
  for (final chord in incoming.chordProgression) {
    if (chord.confidence < 0.45 || chord.startMs > 30000) continue;
    if (firstIncoming == null || chord.startMs < firstIncoming.startMs) {
      firstIncoming = chord;
    }
  }
  if (lastOutgoing == null || firstIncoming == null) return null;

  final rawDistance =
      (lastOutgoing.rootPitchClass - firstIncoming.rootPitchClass).abs();
  final distance = rawDistance > 6 ? 12 - rawDistance : rawDistance;
  final baseCost = switch (distance) {
    0 => 0.04,
    1 => 0.82,
    2 => 0.30,
    3 => 0.20,
    4 => 0.20,
    5 => 0.12,
    6 => 0.92,
    _ => 0.40,
  };
  final qualityAdjusted = lastOutgoing.quality == firstIncoming.quality
      ? baseCost
      : (baseCost + 0.08).clamp(0.0, 1.0).toDouble();
  final confidence = math
      .min(lastOutgoing.confidence, firstIncoming.confidence)
      .toDouble();
  // Partial confidence returns the estimate toward neutral, never makes an
  // uncertain spectral-template match into a hard rejection.
  return automixClamp01(
    qualityAdjusted * confidence + 0.5 * (1.0 - confidence),
  );
}

/// Adaptive lead time, in seconds, for an early handover.
///
/// Blends three signals into the documented 35–60 second window:
/// outgoing tail density (weight 2), a sparse incoming intro (weight 1), and
/// a confident tail structure cue (weight 1). Neutral metadata returns the
/// historical 45 second lead. This is the lead before EOF, not the fade
/// duration; Media3 still phrase-aligns the resulting start on the outgoing
/// grid.
double automixEarlyHandoverLeadSeconds({
  required double? outroEnergy,
  required double? introEnergy,
  int tailStructureRegion = 0,
  double tailStructureConfidence = 0,
}) {
  const minLead = 35.0;
  const neutralLead = 45.0;
  const maxLead = 60.0;
  var weighted = 0.0;
  var weight = 0.0;

  if (outroEnergy != null && outroEnergy.isFinite) {
    final density = outroEnergy.clamp(0.0, 1.0).toDouble();
    final lead = density <= 0.525
        ? minLead +
              ((density - 0.35) / 0.175).clamp(0.0, 1.0) *
                  (neutralLead - minLead)
        : neutralLead +
              ((density - 0.525) / 0.175).clamp(0.0, 1.0) *
                  (maxLead - neutralLead);
    weighted += lead * 2.0;
    weight += 2.0;
  }

  // A sparse intro can carry a later handover; a dense intro stays neutral.
  if (introEnergy != null && introEnergy.isFinite && introEnergy < 0.50) {
    final sparse = ((0.50 - introEnergy) / 0.15).clamp(0.0, 1.0);
    weighted += neutralLead - 10.0 * sparse;
    weight += 1.0;
  }

  // Region 3 is DROP, region 1 is LOW_ACTIVITY. The confidence gates match
  // denseTail/sparseTail in the strategy selection above.
  if (tailStructureRegion == 3 && tailStructureConfidence >= 0.65) {
    weighted += maxLead;
    weight += 1.0;
  } else if (tailStructureRegion == 1 && tailStructureConfidence >= 0.75) {
    weighted += minLead;
    weight += 1.0;
  }

  if (weight == 0.0) return neutralLead;
  return (weighted / weight).clamp(minLead, maxLead).toDouble();
}

/// Derives the fade length, transfer curve and level match for [outgoing] →
/// [incoming].
///
/// Structure-aware: dense outros favour a quicker handover; sparse outros and
/// intros can support a longer blend. Confident tempo/key/chord mismatches can
/// shorten the overlap automatically. The selected cue is consumed by Media3.
AutomixTransitionCue automixTransitionCue({
  required AutomixTrackFeatures outgoing,
  required AutomixTrackFeatures incoming,
  required AutomixSettings settings,
  double fallbackFadeSeconds = 6.0,
}) {
  // The fade lives in the outgoing track's tail, so its exit tempo (falling
  // back to the head estimate) sets how many beats the blend spans.
  final tempo = automixExitBpm(outgoing) ?? automixEntryBpm(incoming);
  // Scale the beat count, not the seconds. Multiplying 4 beats by 1.25 and
  // 1.15 produced 5.75 beats (and even 1.15 alone broke the grid), so the fade
  // ended off-beat and the decks were out of phase at the handover tail.
  double fadeBeats = settings.crossfadeBeats.toDouble();
  var gamma = 1.0;
  final outro = outgoing.outroEnergy;
  if (outro != null) {
    if (outro >= 0.70) {
      // Busy outro: hand over faster so two dense sections overlap less.
      fadeBeats *= 0.75;
      gamma = 1.35;
    } else if (outro <= 0.35) {
      // Sparse/quiet outro: a longer, gentler blend sounds intentional.
      fadeBeats *= 1.25;
      gamma = 0.85;
    }
  }
  final intro = incoming.introEnergy;
  if (intro != null && intro <= 0.35) {
    // A sparse incoming intro can carry a longer overlap without clashing.
    fadeBeats *= 1.15;
  }
  // Keep half-beat resolution: a musically meaningful result without forcing
  // every blend to a whole beat.
  fadeBeats = (fadeBeats * 2).round() / 2;
  var fadeSeconds = tempo == null || tempo <= 0
      ? fallbackFadeSeconds
      : fadeBeats * 60.0 / tempo;

  // Structure metadata only controls transition timing when confidence is
  // strong. The cue is file-absolute and valid only if it lies near the tail.
  final durationMs = outgoing.durationSeconds * 1000.0;
  final breakdownMs = outgoing.tailBreakdownCueMs;
  double? cueLeadSeconds;
  if (outgoing.tailBreakdownConfidence >= 0.45 &&
      durationMs.isFinite &&
      durationMs > 0 &&
      breakdownMs != null &&
      breakdownMs.isFinite &&
      breakdownMs >= 0) {
    final lead = (durationMs - breakdownMs) / 1000.0;
    if (lead >= AutomixContract.fadeMinSeconds &&
        lead <= AutomixContract.fadeMaxSeconds) {
      cueLeadSeconds = lead;
    }
  }

  final exitTempo = automixExitBpm(outgoing);
  final incomingTempo = automixEntryBpm(incoming);
  final incomingTempoConfidence = automixEntryBpmConfidence(incoming);
  final tempoMismatch =
      automixTempoCurveAllowsPair(outgoing, incoming) &&
      automixExitBpmConfidence(outgoing) >=
          AutomixContract.tempoConfidenceMin &&
      incomingTempoConfidence >= AutomixContract.tempoConfidenceMin &&
      exitTempo != null &&
      incomingTempo != null &&
      !automixTempoMatch(
        referenceBpm: exitTempo,
        trackBpm: incomingTempo,
        tolerance: settings.bpmTolerancePercent / 100.0,
      ).$1;
  final keyCost = automixCamelotCost(
    outgoing.camelotNumber,
    outgoing.camelotMinor,
    incoming.camelotNumber,
    incoming.camelotMinor,
  );
  // Harmonic compatibility is owned by the planner's weighted cost. The old
  // cue-level hard reject (keyCost >= 0.60 / chordCost >= 0.62) applied two
  // hand-tuned thresholds to the same feature and could silently downgrade a
  // transition the planner had ranked as acceptable. Keep a single blended
  // value for shaping only, never rejection.
  final chordCost = automixChordProgressionCost(outgoing, incoming);
  final harmonicCost = math.max(keyCost, chordCost ?? 0.0);
  final harmonicConfident =
      (outgoing.keyConfidence >= AutomixContract.keyConfidenceMin &&
          incoming.keyConfidence >= AutomixContract.keyConfidenceMin) ||
      chordCost != null;
  final denseTail =
      (outro != null && outro >= 0.70) ||
      (outgoing.tailStructureRegion == 3 &&
          outgoing.tailStructureConfidence >=
              AutomixContract.structureConfidenceMin);
  final sparseTail =
      (outro != null && outro <= 0.35) ||
      (outgoing.tailStructureRegion == 1 &&
          outgoing.tailStructureConfidence >= 0.75);
  final sparseIntro = intro != null && intro <= 0.35;

  // Strong incoming-drop and beat-grid evidence takes priority over a
  // breakdown cue that happens only in the final 12 seconds. Otherwise that
  // near-EOF cue can repeatedly force transitions to wait until the song ends.
  final incomingDropMs = incoming.dropCueMs;
  final hasConfidentIncomingDrop =
      incomingDropMs != null &&
      incomingDropMs.isFinite &&
      incomingDropMs >= AutomixContract.dropHandoverMinMs &&
      incomingDropMs <= AutomixContract.dropHandoverMaxMs &&
      incoming.dropConfidence >= AutomixContract.dropConfidenceMin;
  final outgoingGridBpm = outgoing.tailBpm;
  final incomingHasLocalGrid = automixHasConfidentIntroGrid(incoming);
  final incomingGridBpm = incomingHasLocalGrid
      ? incoming.startBpm
      : incoming.bpm;
  final incomingGridOffsetMs = incomingHasLocalGrid
      ? incoming.introBeatOffsetMs
      : incoming.beatOffsetMs;
  final incomingGridConfidence = incomingHasLocalGrid
      ? incoming.startBpmConfidence
      : incoming.bpmConfidence;
  final hasConfidentBeatPair =
      outgoingGridBpm != null &&
      outgoingGridBpm.isFinite &&
      outgoingGridBpm >= AutomixContract.bpmMin &&
      outgoingGridBpm <= AutomixContract.bpmMax &&
      outgoing.tailBpmConfidence >= AutomixContract.tempoConfidenceMin &&
      outgoing.tailBeatOffsetMs != null &&
      outgoing.tailBeatOffsetMs!.isFinite &&
      outgoing.tailBeatOffsetMs! >= 0 &&
      incomingGridBpm != null &&
      incomingGridBpm.isFinite &&
      incomingGridBpm >= AutomixContract.bpmMin &&
      incomingGridBpm <= AutomixContract.bpmMax &&
      incomingGridConfidence >= AutomixContract.tempoConfidenceMin &&
      incomingGridOffsetMs != null &&
      incomingGridOffsetMs.isFinite &&
      incomingGridOffsetMs >= 0 &&
      automixTempoMatch(
        referenceBpm: outgoingGridBpm,
        trackBpm: incomingGridBpm,
      ).$1;
  final earlyHandoverEligible =
      outgoing.durationSeconds >= 120 &&
      durationMs.isFinite &&
      durationMs > 0 &&
      hasConfidentIncomingDrop &&
      hasConfidentBeatPair &&
      !tempoMismatch;

  final AutomixTransitionStrategy strategy;
  if (earlyHandoverEligible) {
    // The early drop path keeps the conventional fade duration while
    // scheduling its own start below.
    strategy = AutomixTransitionStrategy.crossfade;
  } else if (tempoMismatch) {
    // A real tempo clash must not be masked by a nominally aligned cue: a long
    // overlap would expose the clash for longer.
    strategy = AutomixTransitionStrategy.shortHandover;
  } else if (cueLeadSeconds != null) {
    strategy = AutomixTransitionStrategy.structureAligned;
  } else if (denseTail) {
    strategy = AutomixTransitionStrategy.quickHandover;
  } else if (sparseTail || sparseIntro) {
    strategy = AutomixTransitionStrategy.longBlend;
  } else {
    strategy = AutomixTransitionStrategy.crossfade;
  }

  // Apply the selected strategy to the parameters sent to Media3. Strategy
  // durations are expressed in bars at the outgoing metre, not seconds: a
  // second cap at 120 BPM used to end a quick handover on beat 6 (mid-bar).
  // The absolute clamp below is only a safety envelope.
  final outgoingMeter =
      AutomixContract.supportedMeters.contains(outgoing.tailMeter)
      ? outgoing.tailMeter
      : 4;
  final barSeconds = tempo != null && tempo > 0
      ? outgoingMeter * 60.0 / tempo
      : null;
  switch (strategy) {
    case AutomixTransitionStrategy.crossfade:
      break;
    case AutomixTransitionStrategy.structureAligned:
      fadeSeconds = cueLeadSeconds!;
      break;
    case AutomixTransitionStrategy.shortHandover:
      // Half a bar: two beats at 4/4, the shorter end of the handover range.
      fadeSeconds = barSeconds != null
          ? barSeconds * 0.5
          : math.min(fadeSeconds, 4.0);
      gamma = math.max(gamma, 1.20);
      break;
    case AutomixTransitionStrategy.longBlend:
      // At least two bars; a dense/sparse density cue may still ask for more.
      fadeSeconds = barSeconds != null
          ? math.max(fadeSeconds, barSeconds * 2.0)
          : math.max(fadeSeconds, 6.0);
      gamma = math.min(gamma, 0.95);
      break;
    case AutomixTransitionStrategy.quickHandover:
      // One bar, so the outgoing deck lands on the next bar line.
      fadeSeconds = barSeconds ?? math.min(fadeSeconds, 3.0);
      gamma = math.max(gamma, 1.35);
      break;
  }
  fadeSeconds = fadeSeconds
      .clamp(AutomixContract.fadeMinSeconds, AutomixContract.fadeMaxSeconds)
      .toDouble();
  // Structure-aligned cues are intentionally anchored to a musical boundary;
  // every other strategy is re-quantised after its cap so the executed fade is
  // a whole or half beat for sure.
  if (strategy != AutomixTransitionStrategy.structureAligned &&
      tempo != null &&
      tempo > 0) {
    final beatSeconds = 60.0 / tempo;
    final halfBeats = (fadeSeconds / beatSeconds * 2).round().clamp(3, 48);
    fadeSeconds = (halfBeats * 0.5 * beatSeconds)
        .clamp(AutomixContract.fadeMinSeconds, AutomixContract.fadeMaxSeconds)
        .toDouble();
  }
  // A confident harmonic mismatch is still a shaping signal: shorten the
  // overlap slightly without letting it override the planner's decision.
  if (harmonicCost >= 0.60 && harmonicConfident && tempo != null && tempo > 0) {
    final beatSeconds = 60.0 / tempo;
    fadeSeconds = math.max(
      AutomixContract.fadeMinSeconds,
      fadeSeconds - 0.5 * beatSeconds,
    );
  }

  // Schedule the early handover whenever the incoming drop and both beat grids
  // are trustworthy. Near-EOF breakdown cues are handled above only when this
  // stronger, independent early-handover path is unavailable.
  double? transitionStartMs;
  if (earlyHandoverEligible) {
    final breakdown = outgoing.tailBreakdownCueMs;
    final breakdownLeadSeconds =
        outgoing.tailBreakdownConfidence >= 0.45 &&
            breakdown != null &&
            breakdown.isFinite &&
            breakdown >= 0 &&
            breakdown < durationMs
        ? (durationMs - breakdown) / 1000.0
        : null;
    // A track-level section boundary (start of the final section) measured on
    // 2 s chroma blocks is the musically correct place to hand over: the next
    // track enters where the arrangement changes, not in the middle of the
    // final section. It is only preferred when it lands inside the same 30–65 s
    // window the early handover already supports.
    final sectionCue = outgoing.tailSectionCueMs;
    final sectionLeadSeconds =
        outgoing.tailSectionCueConfidence >= 0.50 &&
            sectionCue != null &&
            sectionCue.isFinite &&
            sectionCue >= 0 &&
            sectionCue < durationMs
        ? (durationMs - sectionCue) / 1000.0
        : null;
    final double leadSeconds;
    if (breakdownLeadSeconds != null &&
        breakdownLeadSeconds >= 30 &&
        breakdownLeadSeconds <= 65) {
      leadSeconds = breakdownLeadSeconds;
    } else if (sectionLeadSeconds != null &&
        sectionLeadSeconds >= 30 &&
        sectionLeadSeconds <= 65) {
      leadSeconds = sectionLeadSeconds;
    } else {
      leadSeconds = automixEarlyHandoverLeadSeconds(
        outroEnergy: outgoing.outroEnergy,
        introEnergy: incoming.introEnergy,
        tailStructureRegion: outgoing.tailStructureRegion,
        tailStructureConfidence: outgoing.tailStructureConfidence,
      );
    }
    final candidateStartMs = durationMs - leadSeconds * 1000.0;
    // Keep at least five seconds of outgoing audio beyond the fade duration,
    // and leave very short tracks on the conventional transition path.
    if (candidateStartMs >= 0 &&
        durationMs - candidateStartMs >= fadeSeconds * 1000.0 + 5000) {
      transitionStartMs = candidateStartMs;
    }
  }

  // Derive conservative per-deck EQ targets from actual measured features.
  // Unknown metadata keeps bands neutral. These are overlap-only
  // attenuations; neither deck is boosted.
  final confidentVocalClash =
      outgoing.vocalConfidence >= AutomixContract.vocalConfidenceMin &&
      incoming.vocalConfidence >= AutomixContract.vocalConfidenceMin &&
      outgoing.vocalLikelihood >= AutomixContract.vocalLikelihoodMin &&
      incoming.vocalLikelihood >= AutomixContract.vocalLikelihoodMin;
  // Attenuate the overlap mid band in proportion to how strongly both edges
  // agree that a vocal is present, instead of applying a fixed -2.2 dB shelf to
  // every borderline match. The 0.55/0.45 entry point is the old confidence
  // gate; a strong match (likelihood 0.75+, confidence 0.65+) reaches the old
  // 0.78 target.
  final vocalClashStrength = confidentVocalClash
      ? automixClamp01(
          math.min(
            (math.min(outgoing.vocalLikelihood, incoming.vocalLikelihood) -
                    0.55) /
                0.20,
            (math.min(outgoing.vocalConfidence, incoming.vocalConfidence) -
                    0.45) /
                0.20,
          ),
        )
      : 0.0;
  final vocalMidGain = 1.0 - 0.22 * vocalClashStrength;
  // Edge onset density, not the whole-track average, decides whether two busy
  // sections will actually overlap.
  final outgoingOnset =
      outgoing.outroEdgeOnsetRate ?? outgoing.onsetRate ?? 0.0;
  final incomingOnset =
      incoming.introEdgeOnsetRate ?? incoming.onsetRate ?? 0.0;
  final outgoingBusy =
      (outgoing.outroEnergy ?? 0.5) >= 0.75 && outgoingOnset >= 2.5;
  final incomingBusy =
      (incoming.introEnergy ?? 0.5) >= 0.75 && incomingOnset >= 2.5;
  final outgoingBassGain = outgoingBusy ? 0.88 : 1.0;
  final incomingBassGain = incomingBusy ? 0.90 : 1.0;
  final outgoingMidGain = confidentVocalClash
      ? vocalMidGain
      : (strategy == AutomixTransitionStrategy.quickHandover ? 0.92 : 1.0);
  final incomingMidGain = confidentVocalClash
      ? vocalMidGain
      : (incoming.structureRegion == 4 && incoming.structureConfidence >= 0.70
            ? 0.90
            : 1.0);
  double highGain(AutomixTrackFeatures features, {required double fallback}) {
    final centroid = features.centroidHz;
    if (centroid == null || !centroid.isFinite || centroid <= 0) {
      return fallback;
    }
    final brightness = automixClamp01((centroid - 900.0) / 2600.0);
    return (0.90 - 0.55 * brightness).clamp(0.32, 0.90).toDouble();
  }

  final outgoingHighGain = highGain(outgoing, fallback: 0.90);
  final incomingHighGain = incoming.centroidHz == null
      ? 1.0
      : (1.0 - 0.18 * automixClamp01((incoming.centroidHz! - 900.0) / 2600.0))
            .clamp(0.82, 1.0)
            .toDouble();

  // Level-match only comparable measurements. The edge LUFS pair is the
  // correct overlap measurement; edge RMS is the fallback when the K-weighted
  // estimator has too little material. Integrated replay-gain LUFS and
  // whole-track RMS are last resorts. Mixing a section RMS with integrated LUFS
  // would mistake a quiet outro for a loud full track (or vice versa), so each
  // pair stays within one metric family.
  var outgoingTrim = 1.0;
  var incomingTrim = 1.0;
  double? outLevelDb;
  double? inLevelDb;
  if (outgoing.outroEdgeLufs != null && incoming.introEdgeLufs != null) {
    outLevelDb = outgoing.outroEdgeLufs;
    inLevelDb = incoming.introEdgeLufs;
  } else if (outgoing.outroRmsDb != null && incoming.introRmsDb != null) {
    outLevelDb = outgoing.outroRmsDb;
    inLevelDb = incoming.introRmsDb;
  } else if (outgoing.loudnessLufs != null && incoming.loudnessLufs != null) {
    outLevelDb = outgoing.loudnessLufs;
    inLevelDb = incoming.loudnessLufs;
  } else if (outgoing.rmsDb != null && incoming.rmsDb != null) {
    outLevelDb = outgoing.rmsDb;
    inLevelDb = incoming.rmsDb;
  }
  if (outLevelDb != null &&
      inLevelDb != null &&
      outLevelDb.isFinite &&
      inLevelDb.isFinite) {
    final deltaDb = (outLevelDb - inLevelDb).clamp(-6.0, 6.0);
    if (deltaDb > 0.5) {
      outgoingTrim = math.pow(10, -deltaDb / 20).toDouble();
    } else if (deltaDb < -0.5) {
      incomingTrim = math.pow(10, deltaDb / 20).toDouble();
    }
  }

  final String? earlyHandoverUnavailableReason;
  if (earlyHandoverEligible && transitionStartMs != null) {
    earlyHandoverUnavailableReason = null;
  } else if (earlyHandoverEligible) {
    earlyHandoverUnavailableReason =
        'candidate start violates the fade/lead envelope';
  } else if (outgoing.durationSeconds < 120) {
    earlyHandoverUnavailableReason = 'outgoing shorter than 120 s';
  } else if (!hasConfidentIncomingDrop) {
    final rawCue = incoming.dropCueMs;
    earlyHandoverUnavailableReason = rawCue == null
        ? 'no confident incoming drop cue'
        : 'incoming drop ${rawCue.toStringAsFixed(0)} ms outside '
              '${AutomixContract.dropHandoverMinMs}–'
              '${AutomixContract.dropHandoverMaxMs} ms or below confidence';
  } else if (!hasConfidentBeatPair) {
    earlyHandoverUnavailableReason = 'incoming/outgoing beat grid unavailable';
  } else if (tempoMismatch) {
    earlyHandoverUnavailableReason = 'tempo mismatch';
  } else {
    earlyHandoverUnavailableReason = 'no valid early-handover start';
  }

  return AutomixTransitionCue(
    fadeSeconds: fadeSeconds,
    transitionStartMs: transitionStartMs,
    earlyHandover: earlyHandoverEligible && transitionStartMs != null,
    earlyHandoverUnavailableReason: earlyHandoverUnavailableReason,
    curveGamma: gamma,
    outgoingTrim: outgoingTrim,
    incomingTrim: incomingTrim,
    strategy: strategy,
    outgoingBassOverlapGain: outgoingBassGain,
    incomingBassOverlapGain: incomingBassGain,
    outgoingMidOverlapGain: outgoingMidGain,
    incomingMidOverlapGain: incomingMidGain,
    outgoingHighOverlapGain: outgoingHighGain,
    incomingHighOverlapGain: incomingHighGain,
    outgoingPitchSemitones: automixOutgoingPitchSemitones(outgoing, incoming),
  );
}

/// Order-sensitive FNV-1a fingerprint of a queue. Detects real queue edits
/// (add/remove/reorder) without building a string over thousands of ids.
int automixQueueFingerprint(Iterable<int> ids) {
  var hash = 0x811c9dc5;
  for (final id in ids) {
    hash ^= id & 0xFFFFFFFF;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

// ── Camelot cost ─────────────────────────────────────────────────────────────

/// Camelot-distance base cost (0..1).
double automixCamelotCost(int? numA, bool? minorA, int? numB, bool? minorB) {
  if (numA == null || numB == null || minorA == null || minorB == null) {
    return 0.5; // neutral fallback when key info is missing
  }
  if (numA == numB) {
    return minorA == minorB ? 0.0 : 0.15; // same key / relative maj-min pair
  }
  final sameRing = minorA == minorB;
  // Folded wheel distance 0..6 — the wheel is circular in BOTH directions.
  int dist = ((numA - numB) % 12 + 12) % 12;
  if (dist > 6) dist = 12 - dist;
  if (!sameRing) {
    return switch (dist) {
      1 => 0.45, // diagonal adjacent (energy-shift cross-ring move)
      2 => 0.6,
      _ => 1.0,
    };
  }
  return switch (dist) {
    1 => 0.2,
    2 => 0.3,
    3 => 0.6,
    _ => 1.0,
  };
}

/// Signed semitone shift in `[-1, 1]` to apply to [outgoing] during the
/// overlap so its key matches [incoming], or 0 when no safe shift applies.
///
/// Camelot neighbours are a fifth apart (7 semitones), so a folded wheel
/// distance of 5 is exactly a one-semitone pitch-class difference. The shift
/// is limited to the outgoing deck: the incoming track keeps its recorded key.
/// Cross-ring moves are relative major/minor pairs and are deliberately
/// neutral, because a semitone shift preserves the mode.
double automixOutgoingPitchSemitones(
  AutomixTrackFeatures outgoing,
  AutomixTrackFeatures incoming,
) {
  final outNumber = outgoing.camelotNumber;
  final inNumber = incoming.camelotNumber;
  final outMinor = outgoing.camelotMinor;
  final inMinor = incoming.camelotMinor;
  if (outNumber == null ||
      inNumber == null ||
      outMinor == null ||
      inMinor == null ||
      outMinor != inMinor ||
      // A semitone shift on a wrong key estimate is far worse than a
      // suboptimal Camelot score. Wait for calibrated confidence.
      outgoing.keyConfidence < 0.70 ||
      incoming.keyConfidence < 0.70) {
    return 0.0;
  }
  var wheelDistance = (outNumber - inNumber).abs() % 12;
  if (wheelDistance > 6) wheelDistance = 12 - wheelDistance;
  if (wheelDistance != 5) return 0.0;

  final table = outMinor ? automixCamelotMinorNum : automixCamelotMajorNum;
  final outgoingPc = table.indexOf(outNumber);
  final incomingPc = table.indexOf(inNumber);
  if (outgoingPc < 0 || incomingPc < 0) return 0.0;
  var shift = (incomingPc - outgoingPc) % 12;
  if (shift > 6) shift -= 12;
  // The wheel geometry guarantees ±1 for distance 5; keep the guard so a
  // future table change can never turn this into a large automatic shift.
  return shift.abs() == 1 ? shift.toDouble() : 0.0;
}

// ── Tempo cost ───────────────────────────────────────────────────────────────

/// Tempo distance between two tracks across half/double-time interpretations,
/// 0..1 (0 = beat-perfect, 1 = fully mismatched).
///
/// Distance is the relative ratio error against the slower tempo, folded
/// through half/double-time variants so 120→60 scores like 120→120.
double automixTempoCost(
  double? bpmA,
  double? altA,
  double? bpmB,
  double? altB,
  double toleranceFrac,
) {
  if (bpmA == null || bpmB == null) return 0.35; // neutral fallback

  // Tempo variants include the explicit ±1 octave folds, so a 120 ↔ 60 pair
  // is free without relying on the extractor's alternate-bpm report.
  List<double> variants(double bpm, double? alt) => bpm <= 0
      ? const <double>[]
      : <double>[bpm, bpm * 2, bpm / 2, if (alt != null && alt > 0) alt];

  final tempoA = variants(bpmA, altA);
  final tempoB = variants(bpmB, altB);

  var best = double.infinity;
  for (final x in tempoA) {
    for (final y in tempoB) {
      if (x <= 0 || y <= 0) continue;
      final slower = math.min(x, y);
      final faster = math.max(x, y);
      final d = faster / slower - 1.0;
      if (d < best) best = d;
    }
  }
  if (best >= double.infinity) return 0.35;
  if (best <= 0.01) return 0.0; // beat-perfect (within 1%)
  if (best <= toleranceFrac) {
    final t = (best / toleranceFrac).clamp(0.0, 1.0);
    return t * t * 0.5; // quadratic ramp inside tolerance
  }
  // Beyond tolerance: ramp from 0.5 to a full 1.0 by the time the
  // slower-relative tempo mismatch reaches tolerance + 25 percentage points.
  final over = (best - toleranceFrac) / 0.25;
  return (0.5 + over * 0.5).clamp(0.0, 1.0);
}

// ── Energy ───────────────────────────────────────────────────────────────────

/// Builds a 0..1 energy score per track from raw feature values.
///
/// Normalization is *relative to the candidate set* (robust p10/p90 rescale),
/// so a quiet-but-bright track among quiet sources still orders sensibly.
/// Missing analysis degrades to a loudness-only proxy (via ReplayGain LUFS);
/// a fully unknown set degrades to flat 0.5 — the engine then still orders
/// through BPM, key, and artist-variety signals.
List<double> automixNormalizeEnergy(List<AutomixTrackFeatures> feats) {
  if (feats.isEmpty) return const [];

  final raws = <double?>[];
  for (final f in feats) {
    final rms = f.rmsDb; // active-frame median, ~ -30..-6 dBFS
    final centroid = f.centroidHz; // brightness, ~ 400..4000 Hz
    final onset = f.onsetRate; // onsets/sec, ~ 0.5..6
    if (rms != null) {
      final rmsN = automixClamp01((rms + 30.0) / 24.0);
      var weighted = 0.5 * rmsN;
      var weight = 0.5;
      if (centroid != null) {
        weighted += 0.25 * automixClamp01((centroid - 400.0) / 3600.0);
        weight += 0.25;
      }
      if (onset != null) {
        weighted += 0.25 * automixClamp01((onset - 0.5) / 5.5);
        weight += 0.25;
      }
      raws.add(weighted / weight);
      continue;
    }
    final lufs = f.loudnessLufs; // ~ -24 (quiet) .. -6 (loud) LUFS
    if (lufs != null) {
      final lufsN = automixClamp01((lufs + 24.0) / 18.0);
      var weighted = 0.75 * lufsN;
      var weight = 0.75;
      if (onset != null) {
        weighted += 0.25 * automixClamp01((onset - 0.5) / 5.5);
        weight += 0.25;
      }
      raws.add(weighted / weight);
      continue;
    }
    raws.add(null);
  }

  final present = raws.whereType<double>().toList(growable: false);
  if (present.isEmpty) {
    return List<double>.filled(feats.length, 0.5, growable: false);
  }

  present.sort();
  double pct(double p) {
    final idx = ((present.length - 1) * p).clamp(0.0, present.length - 1.0);
    final lo = idx.floor();
    final hi = idx.ceil();
    return lo == hi
        ? present[lo]
        : present[lo] + (present[hi] - present[lo]) * (idx - lo);
  }

  final lo = pct(0.10);
  final hiRaw = pct(0.90);
  final span = (hiRaw - lo) < 0.08 ? 0.08 : (hiRaw - lo);
  return <double>[
    for (final raw in raws)
      raw == null ? 0.5 : automixClamp01((raw - lo) / span),
  ];
}

// ── Energy arc ───────────────────────────────────────────────────────────────

/// Desired normalized energy at the relative set position `pos` (0..1),
/// per profile. DJ sets rise slightly; the "energy" profile runs a
/// warm-up → peak (at 55 % of the set) → cooldown arc; harmonic sets try to
/// stay level.
double _energyTargetPos(double pos, AutomixProfile profile) {
  switch (profile) {
    case AutomixProfile.energy:
      final p = automixClamp01(pos);
      return p < 0.55
          ? 0.30 + 0.70 * (p / 0.55)
          : 1.00 - 0.55 * ((p - 0.55) / 0.45);
    case AutomixProfile.dj:
      return 0.25 + 0.50 * automixClamp01(pos);
    case AutomixProfile.harmonic:
      return 0.60;
  }
}

/// Set-adaptive energy arc: the profile arc projected onto the measured
/// p20..p80 range of the normalized set energies. Mirrors `build_energy_arc`
/// in the native planner; a set with fewer than four tracks or a narrow
/// measured range keeps the fixed profile target only.
class _EnergyArc {
  const _EnergyArc._(this.low, this.high, this.adaptive);

  final double low;
  final double high;
  final bool adaptive;

  static const _EnergyArc disabled = _EnergyArc._(0.0, 1.0, false);

  factory _EnergyArc.fromEnergies(List<double> energies) {
    if (energies.length < 4) return _EnergyArc.disabled;
    final sorted = List<double>.of(energies)..sort();
    final low = _percentileSorted(sorted, 0.20);
    final high = _percentileSorted(sorted, 0.80);
    if (high - low < 0.10) return _EnergyArc.disabled;
    return _EnergyArc._(low, high, true);
  }

  static double _percentileSorted(List<double> sorted, double fraction) {
    final index = (sorted.length - 1) * fraction;
    final low = index.floor();
    final high = index.ceil();
    if (low == high) return sorted[low];
    return sorted[low] + (sorted[high] - sorted[low]) * (index - low);
  }
}

/// Smooth 0..1 arc shape over the normalized plan position. The underlying
/// tent peaks at `peak` and falls to zero at both ends; the smoothstep
/// removes the corner at the peak. `base` lifts the ends for flat profiles.
double _arcShape(double position, AutomixProfile profile) {
  var peak = 0.6;
  var base = 0.0;
  if (profile == AutomixProfile.energy) {
    peak = 0.5;
  } else if (profile == AutomixProfile.harmonic) {
    base = 0.35;
  }
  final p = automixClamp01(position);
  final t = automixClamp01(p < peak ? p / peak : (1.0 - p) / (1.0 - peak));
  final smooth = t * t * (3.0 - 2.0 * t);
  return base + (1.0 - base) * smooth;
}

double _energyTargetArc(double pos, AutomixProfile profile, _EnergyArc arc) {
  final fixed = _energyTargetPos(pos, profile);
  if (!arc.adaptive) return fixed;
  final adaptive = arc.low + (arc.high - arc.low) * _arcShape(pos, profile);
  return automixClamp01(0.5 * fixed + 0.5 * adaptive);
}

// ── Transition cost ──────────────────────────────────────────────────────────

/// Weight sets per [AutomixProfile]: (tempo, key, energy). They intentionally
/// sum to 1 so the weighted mean stays on 0..1.
///
/// Artist repetition is deliberately *not* part of this objective any more.
/// It used to be a fourth `variety` sub-cost (0.15 weight) while the greedy
/// pick also added an artist-cooldown penalty, so one signal owned two
/// objectives with hand-balanced constants. The cooldown now owns artist
/// spread alone; the three harmonic/rhythmic weights keep their old relative
/// proportions (the removed 0.15 is redistributed, not re-invented).
const Map<AutomixProfile, (double, double, double)> _profileWeights = {
  AutomixProfile.dj: (0.47, 0.24, 0.29),
  AutomixProfile.harmonic: (0.24, 0.53, 0.23),
  AutomixProfile.energy: (0.18, 0.18, 0.64),
};

/// Section-shape compatibility across the mix seam. The loudness side of a
/// hand-over is already covered by the energy seam; this term adds the shape:
/// two full-arrangement peaks back to back are rough, while leaving a peak
/// into a calm or building intro (or moving between calm sections) is smooth.
/// Mirrors `structure_seam_cost` in the native planner.
double _structureSeamCost(int tailRegion, int headRegion) {
  // Region ids follow NarAutomixStructureRegion: 1 low activity, 2 buildup,
  // 3 drop, 4 breakdown, 5 stable high.
  bool quiet(int region) => region == 1 || region == 2 || region == 4;
  bool peak(int region) => region == 3 || region == 5;
  if (peak(tailRegion) && peak(headRegion)) {
    return (tailRegion == 3 || headRegion == 3) ? 0.5 : 0.35;
  }
  if (quiet(tailRegion) && quiet(headRegion)) return 0.0;
  if (peak(tailRegion) && quiet(headRegion)) return 0.0;
  if (quiet(tailRegion) && peak(headRegion)) return 0.2;
  return 0.0;
}

/// Cost of playing track [b] immediately after track [a]. Weighted mean of
/// four sub-costs, clamped to 0..1:
///
/// * tempo — see [automixTempoCost], measured at the mix seam (outgoing exit
///   tempo vs incoming head tempo) when the outgoing tail window has one
/// * key   — [automixCamelotCost], scaled by key detection confidence
/// * energy — continuity + arc-following (see [_energyTargetPos]) plus an
///   intro/outro section-seam term and a confidence-gated section-shape term
double _transitionCost({
  required AutomixTrackFeatures a,
  required AutomixTrackFeatures b,
  required double eA,
  required double eB,
  required int stepIndex,
  required int totalSteps,
  required AutomixSettings settings,
  _EnergyArc arc = _EnergyArc.disabled,
}) {
  final tolerance = settings.bpmTolerancePercent / 100.0;
  // Score the tempo at the actual seam. A tail BPM is eligible only when
  // its own confidence passes the shared 0.35 gate; otherwise use head BPM.
  final referenceBpm = automixExitBpm(a);
  final outgoingTempoConfidence = automixExitBpmConfidence(a);
  final useLocalExitTempo = automixHasConfidentTailBpm(a);
  final useLocalEntryTempo = automixHasConfidentIntroBpm(b);
  final measuredTempo = automixTempoCost(
    referenceBpm,
    useLocalExitTempo ? null : a.alternateBpm,
    automixEntryBpm(b),
    useLocalEntryTempo ? null : b.alternateBpm,
    tolerance,
  );
  final entryTempoConfidence = automixEntryBpmConfidence(b);
  final exitStability = a.outroTempoStability;
  final entryStability = b.introTempoStability;
  final exitStabilityWeight = exitStability == null || !exitStability.isFinite
      ? 1.0
      : automixClamp01(exitStability);
  final entryStabilityWeight =
      entryStability == null || !entryStability.isFinite
      ? 1.0
      : automixClamp01(entryStability);
  final tempoConfidence = automixClamp01(
    (outgoingTempoConfidence * exitStabilityWeight +
            entryTempoConfidence * entryStabilityWeight) /
        2,
  );
  final tempo = automixConfidenceBlend(
    measuredTempo,
    tempoConfidence,
    neutralCost: AutomixContract.tempoConfidenceMin,
  );

  final measuredKey = automixCamelotCost(
    a.camelotNumber,
    a.camelotMinor,
    b.camelotNumber,
    b.camelotMinor,
  );
  final kConf = automixClamp01((a.keyConfidence + b.keyConfidence) / 2);
  var key = automixConfidenceBlend(measuredKey, kConf, neutralCost: 0.5);
  // Harmonic filter means a confidently incompatible key is strongly
  // discouraged. If detection is uncertain, confidence blending above keeps
  // it near neutral rather than rejecting a potentially compatible track.
  if (settings.harmonicFilter &&
      kConf >= AutomixContract.keyConfidenceMin &&
      measuredKey >= 0.6) {
    key = math.max(key, 0.9);
  }

  // Energy: blend continuity with the arc target; the "energy" profile adds
  // an explicit wrong-direction penalty so the arc keeps flowing forward.
  final pos = totalSteps <= 1
      ? 1.0
      : automixClamp01(stepIndex / (totalSteps - 1));
  final target = _energyTargetArc(pos, settings.profile, arc);
  final delta = eB - eA;
  // Section-seam continuity: a fade between a quiet outro and a loud intro (or
  // the reverse) is rougher than the whole-track energy delta alone implies.
  // Both values are relative to their own track's peak, so a large gap marks a
  // mismatched hand-over. Missing or non-finite sections stay neutral.
  final outro = a.outroEnergy;
  final intro = b.introEnergy;
  final seam =
      outro != null && intro != null && outro.isFinite && intro.isFinite
      ? (outro - intro).abs() * 0.5
      : 0.0;
  // Energy momentum across the seam: a still-rising tail is rough unless the
  // incoming head keeps building, while a falling tail into any head reads as
  // a natural valley (the level seam above already covers the drop). Mirrors
  // the native momentum term.
  final outroSlopeA = a.outroSlope;
  final introSlopeB = b.introSlope;
  var momentum = 0.0;
  if (outroSlopeA != null &&
      introSlopeB != null &&
      outroSlopeA.isFinite &&
      introSlopeB.isFinite &&
      outroSlopeA > 1.0) {
    final interrupted = outroSlopeA - introSlopeB;
    if (interrupted > 0) {
      momentum = math.min(0.10, interrupted / 24.0 * 0.10);
    }
  }
  // Section-shape compatibility across the seam, gated on both windows having
  // a confident region label. Missing or uncertain structure stays neutral.
  final tailRegion = a.tailStructureRegion;
  final headRegion = b.structureRegion;
  var structure = 0.0;
  if (a.tailStructureConfidence >= AutomixContract.structureConfidenceMin &&
      b.structureConfidence >= AutomixContract.structureConfidenceMin &&
      tailRegion >= 1 &&
      tailRegion <= 5 &&
      headRegion >= 1 &&
      headRegion <= 5) {
    structure = _structureSeamCost(tailRegion, headRegion);
  }
  // Coefficients sum to exactly 1.0 including the momentum cap. The old terms
  // summed to 1.40 (+0.30 momentum) before clamping, so every sufficiently
  // bad pair scored 1.0 and the optimizer had no gradient exactly where it
  // needed one. Keep the clamp only as a numerical guard.
  var energy =
      0.22 * delta.abs() +
      0.40 * (eB - target).abs() +
      0.18 * seam +
      0.10 * structure +
      momentum;
  if (settings.profile == AutomixProfile.energy) {
    final beforePeak = pos < 0.55;
    if (beforePeak && delta < -0.05) {
      energy += 0.12 * (-delta);
    } else if (!beforePeak && delta > 0.05) {
      energy += 0.12 * delta;
    }
  }
  energy = energy.clamp(0.0, 1.0);

  final vA = a.vocalLikelihood;
  final vB = b.vocalLikelihood;
  final cA = a.vocalConfidence;
  final cB = b.vocalConfidence;
  var vocalCost = 0.0;
  if (vA.isFinite &&
      vB.isFinite &&
      cA.isFinite &&
      cB.isFinite &&
      cA >= AutomixContract.vocalConfidenceMin &&
      cB >= AutomixContract.vocalConfidenceMin &&
      vA >= AutomixContract.vocalLikelihoodMin &&
      vB >= AutomixContract.vocalLikelihoodMin) {
    final effectiveA = (vA - 0.5) * cA;
    final effectiveB = (vB - 0.5) * cB;
    vocalCost = (effectiveA * effectiveB * 4.0).clamp(0.0, 1.0);
  }

  final (wT, wK, wE) = _profileWeights[settings.profile]!;
  // The vocal term is a fourth weighted sub-cost, not an unnormalised addend:
  // every term shares one denominator, so the result cannot exceed 1.0
  // before the final clamp.
  const wVocal = 0.10;
  return ((wT * tempo + wK * key + wE * energy + wVocal * vocalCost) /
          (wT + wK + wE + wVocal))
      .clamp(0.0, 1.0);
}

// ── Engine ───────────────────────────────────────────────────────────────────

/// Pure-Dart reference retained as a regression oracle for the native port.
class DartAutomixEngineReference {
  const DartAutomixEngineReference._();

  /// How much the one-step lookahead's estimated cost counts toward the final
  /// score of the immediate pick (0..1).
  static const double _lookaheadGamma = 0.35;

  /// Local raw-tempo neighborhood size. Equivalent tempo anchors add a second
  /// bounded candidate set, including for half/double-time matches.
  static const int _window = 12;

  /// Also inspect nearby slots for the half/double-time interpretations of a
  /// track's BPM. This catches compatible tempos outside its raw-BPM cluster
  /// without turning large-library sequencing into an O(n²) global scan.
  static const int _tempoAnchorWindow = 4;
  static const double _minTempoBpm = AutomixContract.bpmMin;
  static const double _maxTempoBpm = AutomixContract.bpmMax;

  /// Receding-horizon beam: the eight cheapest first steps are scored with
  /// two follow-up steps. Mirrors NAR_PLAN_BEAM_WIDTH/DEPTH in the planner.
  static const int _beamWidth = 8;
  static const int _beamDepth = 2;

  /// Improvement-pass budget for the swap polisher. Insertion (Or-opt) and
  /// reversal scans extend the neighborhood for sets at or above
  /// [_polishMinTracks] — the same size gate the greedy lookahead uses.
  static const int _maxPasses = 8;
  static const int _maxSwapBreach = 6;
  static const int _maxEvalsPerPass = 6000;
  static const int _maxInsertEvals = 3000;
  static const int _maxReverseEvals = 1800;
  static const int _polishMinTracks = 12;

  /// A repeated artist inside this many recent positions is discouraged by
  /// the greedy pick. This is the *only* artist-spread mechanism: the old
  /// `variety` sub-cost inside [_transitionCost] was removed so the same
  /// signal is not scored by two objectives.
  static const int _artistCooldown = 4;

  /// Median crossfade bound guard.
  static const double _defaultBpm = 110.0;

  static AutomixPlan planSet({
    required List<AutomixTrackFeatures> tracks,
    required AutomixSettings settings,
    required int startIndex,
  }) {
    final n = tracks.length;
    if (n == 0) {
      return const AutomixPlan(order: [], crossfadeSeconds: 0, averageCost: 0);
    }
    if (n == 1) {
      return const AutomixPlan(
        order: [0],
        crossfadeSeconds: 2.0,
        averageCost: 0,
      );
    }

    // ── 1. Energies ───────────────────────────────────────────────────
    final energies = automixNormalizeEnergy(tracks);
    final arc = _EnergyArc.fromEnergies(energies);

    // ── 2. Tempo-sorted slot order for the bounded-neighborhood walk ──
    // Unknown tempos occupy the median so they sit between known plateaus
    // instead of clumping at both extremes.
    final medianBpm = _medianKnownBpm(tracks);
    final slotOrder = List<int>.generate(n, (i) => i)
      ..sort((x, y) {
        final bx = tracks[x].bpm ?? medianBpm;
        final by = tracks[y].bpm ?? medianBpm;
        final cmp = bx.compareTo(by);
        if (cmp != 0) return cmp;
        return tracks[x].songId.compareTo(tracks[y].songId);
      });
    final slotOf = List<int>.filled(n, 0);
    for (int s = 0; s < n; s++) {
      slotOf[slotOrder[s]] = s;
    }

    // ── 3. Greedy chain with bounded lookahead ────────────────────────
    final first = startIndex.clamp(0, n - 1);
    final played = List<bool>.filled(n, false);
    played[first] = true;
    final plan = <int>[first];

    final withLookahead = n > 24;
    int current = first;
    while (plan.length < n) {
      final next = _pickNext(
        current: current,
        stepIndex: plan.length,
        played: played,
        slotOf: slotOf,
        slotOrder: slotOrder,
        tracks: tracks,
        energies: energies,
        settings: settings,
        totalSteps: n,
        medianBpm: medianBpm,
        withLookahead: withLookahead,
        plan: plan,
        arc: arc,
      );
      // Defensive: _pickNext always returns an unplayed index, but a bug must
      // never crash playback — degrade to the first unplayed track instead.
      final safe = (next >= 0 && next < n && !played[next])
          ? next
          : played.indexOf(false);
      plan.add(safe);
      played[safe] = true;
      current = safe;
    }

    // ── 4. Bounded local improvement ──────────────────────────────────
    var evals = 0;
    var insertEvals = 0;
    var reverseEvals = 0;
    for (var pass = 0; pass < _maxPasses; pass++) {
      var improved = false;
      // Pairwise swaps within the breach window.
      for (int i = 1; i < n - 1 && evals < _maxEvalsPerPass; i++) {
        final jEnd = (i + _maxSwapBreach).clamp(i + 1, n - 1);
        for (int j = i + 1; j <= jEnd && evals < _maxEvalsPerPass; j++) {
          evals++;
          final before = _localCost(
            plan,
            i,
            j,
            tracks,
            energies,
            settings,
            arc,
          );
          final origI = plan[i];
          final origJ = plan[j];
          plan[i] = origJ;
          plan[j] = origI;
          final after = _localCost(plan, i, j, tracks, energies, settings, arc);
          if (after < before - 1e-9) {
            improved = true;
          } else {
            plan[i] = origI;
            plan[j] = origJ;
          }
        }
      }
      if (n >= _polishMinTracks) {
        // Or-opt: relocate a single track to a nearby position. Unlike a swap
        // this also re-times the interior links (their arc positions shift),
        // so the move is scored by recomputing the affected link window.
        for (int i = 1; i < n - 1 && insertEvals < _maxInsertEvals; i++) {
          for (
            int step = 1;
            step <= _maxSwapBreach && insertEvals < _maxInsertEvals;
            step++
          ) {
            for (
              int backwards = 0;
              backwards < 2 && insertEvals < _maxInsertEvals;
              backwards++
            ) {
              final to = backwards == 1 ? i - step : i + step;
              // Never displace the pinned start track or run off the end.
              if (to <= 0 || to >= n) continue;
              insertEvals++;
              final lo = i < to ? i : to;
              final hi = i < to ? to : i;
              final cooldownEnd = hi + _artistCooldown;
              final lastLink = cooldownEnd < n ? cooldownEnd : n - 1;
              final before = _windowCost(
                plan,
                lo,
                lastLink,
                tracks,
                energies,
                settings,
                arc,
              );
              _moveElement(plan, i, to);
              final after = _windowCost(
                plan,
                lo,
                lastLink,
                tracks,
                energies,
                settings,
                arc,
              );
              if (after < before - 1e-9) {
                improved = true;
              } else {
                _moveElement(plan, to, i);
              }
            }
          }
        }
        // 2-opt style reversal of short segments; arc positions stay attached
        // to the plan slots, only the links inside the window change.
        for (int i = 1; i < n - 1 && reverseEvals < _maxReverseEvals; i++) {
          for (
            int step = 2;
            step <= _maxSwapBreach && reverseEvals < _maxReverseEvals;
            step++
          ) {
            final j = i + step;
            if (j >= n) continue;
            reverseEvals++;
            final cooldownEnd = j + _artistCooldown;
            final lastLink = cooldownEnd < n ? cooldownEnd : n - 1;
            final before = _windowCost(
              plan,
              i,
              lastLink,
              tracks,
              energies,
              settings,
              arc,
            );
            _reverseRange(plan, i, j);
            final after = _windowCost(
              plan,
              i,
              lastLink,
              tracks,
              energies,
              settings,
              arc,
            );
            if (after < before - 1e-9) {
              improved = true;
            } else {
              _reverseRange(plan, i, j);
            }
          }
        }
      }
      if (!improved) break;
    }

    return AutomixPlan(
      order: List<int>.unmodifiable(plan),
      crossfadeSeconds: _crossfadeSeconds(tracks, plan, settings),
      averageCost: _pathCost(plan, tracks, energies, settings, arc) / (n - 1),
    );
  }

  /// Mean transition cost of an existing order, using the same objective as
  /// [planSet]. Used by the service to apply reorder hysteresis: a new plan is
  /// only worth a queue mutation when it beats the live order by a margin.
  static double scoreOrder({
    required List<AutomixTrackFeatures> tracks,
    required List<int> order,
    required AutomixSettings settings,
  }) {
    final n = order.length;
    if (n < 2) return 0.0;
    if (order.any((index) => index < 0 || index >= tracks.length)) {
      return double.infinity;
    }
    final energies = automixNormalizeEnergy(tracks);
    final arc = _EnergyArc.fromEnergies(energies);
    return _pathCost(order, tracks, energies, settings, arc) / (n - 1);
  }

  /// Median BPM among tracks that have an analyzed value, else
  /// [_defaultBpm].
  static double _medianKnownBpm(List<AutomixTrackFeatures> tracks) {
    final bpms = tracks.map((t) => t.bpm).whereType<double>().toList()..sort();
    if (bpms.isEmpty) return _defaultBpm;
    return bpms[bpms.length ~/ 2];
  }

  /// Penalty for repeating an artist within the last [_artistCooldown] slots.
  /// This is the single owner of artist spread, so it covers the immediately
  /// previous slot too (the removed `variety` sub-cost used to own that one).
  /// The base reproduces that old effective penalty (≈0.09 after
  /// normalisation) and decays linearly with distance, so a repeat two to four
  /// slots back is cheaper than an immediate one while still discouraged.
  /// [planSlot] is the position the candidate would occupy and [planFilled] is
  /// how many positions of [plan] are actually written; the lookahead scans
  /// with `planSlot = plan.length + 1` while `planFilled = plan.length`, so a
  /// not-yet-written slot must never be used as an artist lookup.
  static double _artistCooldownCost({
    required List<int> plan,
    required int planSlot,
    required int planFilled,
    required List<AutomixTrackFeatures> tracks,
    required AutomixTrackFeatures candidate,
    required AutomixSettings settings,
  }) {
    final artist = candidate.artist.trim().toLowerCase();
    if (artist.isEmpty) return 0.0;
    final base = settings.avoidArtistRepeat ? 0.09 : 0.03;
    var penalty = 0.0;
    for (var back = 1; back <= _artistCooldown; back++) {
      final index = planSlot - back;
      if (index < 0) break;
      if (index >= planFilled) continue;
      final other = tracks[plan[index]].artist.trim().toLowerCase();
      if (other != artist) continue;
      final scaled = base * (_artistCooldown - back + 1) / _artistCooldown;
      if (scaled > penalty) penalty = scaled;
    }
    return penalty;
  }

  static int _pickNext({
    required int current,
    required int stepIndex,
    required List<bool> played,
    required List<int> slotOf,
    required List<int> slotOrder,
    required List<AutomixTrackFeatures> tracks,
    required List<double> energies,
    required AutomixSettings settings,
    required int totalSteps,
    required double medianBpm,
    required bool withLookahead,
    required List<int> plan,
    required _EnergyArc arc,
  }) {
    final nTotal = tracks.length;

    // Score the raw-BPM neighborhood plus nearby positions around equivalent
    // half/double-time tempos. A Set avoids rescoring tracks that appear in
    // more than one tempo neighborhood.
    final candidates = _candidatePool(
      current: current,
      played: played,
      slotOf: slotOf,
      slotOrder: slotOrder,
      tracks: tracks,
      energies: energies,
      settings: settings,
      medianBpm: medianBpm,
    );
    final scored = <(int, double)>[];
    for (final cand in candidates) {
      scored.add((
        cand,
        _transitionCost(
              a: tracks[current],
              b: tracks[cand],
              eA: energies[current],
              eB: energies[cand],
              stepIndex: stepIndex,
              totalSteps: totalSteps,
              settings: settings,
              arc: arc,
            ) +
            _artistCooldownCost(
              plan: plan,
              planSlot: plan.length,
              planFilled: plan.length,
              tracks: tracks,
              candidate: tracks[cand],
              settings: settings,
            ),
      ));
    }

    if (scored.isEmpty) {
      // Neighborhood exhausted (only realistic with tiny lists): scan
      // everything once, in slot order for determinism.
      int best = -1;
      double bestScore = double.infinity;
      for (int s = 0; s < nTotal; s++) {
        final cand = slotOrder[s];
        if (played[cand]) continue;
        final cost =
            _transitionCost(
              a: tracks[current],
              b: tracks[cand],
              eA: energies[current],
              eB: energies[cand],
              stepIndex: stepIndex,
              totalSteps: totalSteps,
              settings: settings,
              arc: arc,
            ) +
            _artistCooldownCost(
              plan: plan,
              planSlot: plan.length,
              planFilled: plan.length,
              tracks: tracks,
              candidate: tracks[cand],
              settings: settings,
            );
        if (cost < bestScore) {
          bestScore = cost;
          best = cand;
        }
      }
      return best;
    }

    scored.sort((x, y) {
      final c = x.$2.compareTo(y.$2);
      if (c != 0) return c;
      return tracks[x.$1].songId.compareTo(tracks[y.$1].songId);
    });

    if (!withLookahead || scored.length == 1) {
      return scored.first.$1;
    }

    // Receding-horizon beam over the top eight candidates:
    // cost1 + γ·cost2 + γ²·cost3.
    var best = scored.first.$1;
    var bestScore = double.infinity;
    final limit = _beamWidth < scored.length ? _beamWidth : scored.length;
    for (int k = 0; k < limit; k++) {
      final (cand, base) = scored[k];
      var score = base;
      var minNext = double.infinity;
      final nextCandidates = _candidatePool(
        current: cand,
        played: played,
        slotOf: slotOf,
        slotOrder: slotOrder,
        tracks: tracks,
        energies: energies,
        settings: settings,
        medianBpm: medianBpm,
        excludeIndex: cand,
      );
      for (final cand2 in nextCandidates) {
        if (played[cand2] || cand2 == current) continue;
        // plan.length + 1 because the candidate will occupy one more slot
        // than the path built so far when cand2 actually follows it.
        var c =
            _transitionCost(
              a: tracks[cand],
              b: tracks[cand2],
              eA: energies[cand],
              eB: energies[cand2],
              stepIndex: stepIndex + 1,
              totalSteps: totalSteps,
              settings: settings,
              arc: arc,
            ) +
            _artistCooldownCost(
              plan: plan,
              planSlot: plan.length + 1,
              planFilled: plan.length,
              tracks: tracks,
              candidate: tracks[cand2],
              settings: settings,
            );
        if (_beamDepth >= 2) {
          var minAfter = double.infinity;
          final afterCandidates = _candidatePool(
            current: cand2,
            played: played,
            slotOf: slotOf,
            slotOrder: slotOrder,
            tracks: tracks,
            energies: energies,
            settings: settings,
            medianBpm: medianBpm,
            excludeIndex: cand2,
          );
          for (final cand3 in afterCandidates) {
            if (played[cand3] || cand3 == current || cand3 == cand) {
              continue;
            }
            final c3 =
                _transitionCost(
                  a: tracks[cand2],
                  b: tracks[cand3],
                  eA: energies[cand2],
                  eB: energies[cand3],
                  stepIndex: stepIndex + 2,
                  totalSteps: totalSteps,
                  settings: settings,
                  arc: arc,
                ) +
                _artistCooldownCost(
                  plan: plan,
                  planSlot: plan.length + 2,
                  planFilled: plan.length,
                  tracks: tracks,
                  candidate: tracks[cand3],
                  settings: settings,
                );
            if (c3 < minAfter) minAfter = c3;
          }
          if (minAfter.isFinite) c += _lookaheadGamma * minAfter;
        }
        if (c < minNext) minNext = c;
      }
      if (minNext.isFinite) score += _lookaheadGamma * minNext;
      if (score < bestScore) {
        bestScore = score;
        best = cand;
      }
    }
    return best;
  }

  /// Bounded candidate set from local BPM order, half/double-time anchors,
  /// seam-local tempos and profile-aware key/energy buckets. Unknown-BPM
  /// tracks get a small quota instead of relying entirely on their median
  /// placeholder slot.
  static List<int> _candidatePool({
    required int current,
    required List<bool> played,
    required List<int> slotOf,
    required List<int> slotOrder,
    required List<AutomixTrackFeatures> tracks,
    required List<double> energies,
    required AutomixSettings settings,
    required double medianBpm,
    int? excludeIndex,
  }) {
    final n = tracks.length;
    final found = <int>{};
    bool available(int candidate) =>
        !played[candidate] && candidate != excludeIndex;
    void addSlot(int slot) {
      if (slot < 0 || slot >= n) return;
      final candidate = slotOrder[slot];
      if (available(candidate)) found.add(candidate);
    }

    final slot = slotOf[current];
    for (int reach = 1; reach <= _window; reach++) {
      addSlot(slot + reach);
      addSlot(slot - reach);
    }

    final track = tracks[current];
    final bpm = automixExitBpm(track) ?? track.bpm;
    final alternate = track.alternateBpm;
    if (bpm != null && bpm > 0) {
      final anchors = <double>{bpm, bpm / 2.0, bpm * 2.0};
      if (alternate != null && alternate > 0) {
        anchors.add(alternate);
        anchors.add(alternate / 2.0);
        anchors.add(alternate * 2.0);
      }
      for (final target in anchors) {
        if (!target.isFinite ||
            target < _minTempoBpm ||
            target > _maxTempoBpm) {
          continue;
        }
        final insertion = _lowerBoundTempo(
          target,
          slotOrder,
          tracks,
          medianBpm,
        );
        for (int reach = 0; reach <= _tempoAnchorWindow; reach++) {
          addSlot(insertion + reach);
          addSlot(insertion - 1 - reach);
        }
      }

      // A candidate may have an unusual whole-window BPM but a perfectly
      // matched local intro/exit tempo.
      for (var i = 0; i < n; i++) {
        if (!available(i) || found.contains(i)) continue;
        final seam = automixHasConfidentIntroBpm(tracks[i])
            ? tracks[i].startBpm
            : automixHasConfidentTailBpm(tracks[i])
            ? tracks[i].tailBpm
            : null;
        if (seam == null || !seam.isFinite || seam <= 0) continue;
        if (automixTempoCost(bpm, alternate, seam, null, 0.08) <= 0.25) {
          found.add(i);
        }
      }
    }

    // Unknown-tempo tracks get a deterministic quota.
    var unknownAdded = 0;
    for (var i = 0; i < n && unknownAdded < 2; i++) {
      if (!available(i) || found.contains(i)) continue;
      if (tracks[i].bpm != null) continue;
      found.add(i);
      unknownAdded++;
    }

    if (settings.profile == AutomixProfile.harmonic) {
      for (var i = 0; i < n; i++) {
        if (!available(i) || found.contains(i)) continue;
        final cost = automixCamelotCost(
          track.camelotNumber,
          track.camelotMinor,
          tracks[i].camelotNumber,
          tracks[i].camelotMinor,
        );
        if (cost <= 0.45) found.add(i);
      }
    } else if (settings.profile == AutomixProfile.energy) {
      for (var i = 0; i < n; i++) {
        if (!available(i) || found.contains(i)) continue;
        if ((energies[i] - energies[current]).abs() <= 0.18) {
          found.add(i);
        }
      }
    }

    // Hard floor: fill up to eight by nearest slot tempo. Song-id ordering
    // remains the deterministic tie-breaker in the final candidate sort.
    final targetTempo = tracks[current].bpm ?? medianBpm;
    while (found.length < 8) {
      var best = -1;
      var bestDistance = double.infinity;
      for (var s = 0; s < n; s++) {
        final candidate = slotOrder[s];
        if (!available(candidate) || found.contains(candidate)) continue;
        final tempo = tracks[candidate].bpm ?? medianBpm;
        final distance = (tempo - targetTempo).abs();
        if (distance < bestDistance ||
            (distance == bestDistance &&
                best >= 0 &&
                tracks[candidate].songId < tracks[best].songId)) {
          bestDistance = distance;
          best = candidate;
        }
      }
      if (best < 0) break;
      found.add(best);
    }

    final result = found.toList();
    result.sort((a, b) => tracks[a].songId.compareTo(tracks[b].songId));
    return result;
  }

  static int _lowerBoundTempo(
    double target,
    List<int> slotOrder,
    List<AutomixTrackFeatures> tracks,
    double medianBpm,
  ) {
    var low = 0;
    var high = slotOrder.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      final bpm = tracks[slotOrder[mid]].bpm ?? medianBpm;
      if (bpm < target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low.clamp(0, slotOrder.length - 1).toInt();
  }

  /// Sum of all transition and artist-cooldown costs across a plan.
  static double _pathCost(
    List<int> plan,
    List<AutomixTrackFeatures> tracks,
    List<double> energies,
    AutomixSettings settings,
    _EnergyArc arc,
  ) {
    var sum = 0.0;
    final n = plan.length;
    for (int i = 0; i + 1 < n; i++) {
      sum +=
          _transitionCost(
            a: tracks[plan[i]],
            b: tracks[plan[i + 1]],
            eA: energies[plan[i]],
            eB: energies[plan[i + 1]],
            stepIndex: i + 1,
            totalSteps: n,
            settings: settings,
            arc: arc,
          ) +
          _artistCooldownCost(
            plan: plan,
            planSlot: i + 1,
            planFilled: i + 1,
            tracks: tracks,
            candidate: tracks[plan[i + 1]],
            settings: settings,
          );
    }
    return sum;
  }

  /// Exact cost of links whose transition or artist-cooldown cost can change
  /// when positions [i] and [j] are swapped. Cooldown looks back four slots,
  /// so a swap can change penalties through [j] + [_artistCooldown]. Any
  /// unchanged transition costs inside that bounded window cancel out.
  static double _localCost(
    List<int> plan,
    int i,
    int j,
    List<AutomixTrackFeatures> tracks,
    List<double> energies,
    AutomixSettings settings,
    _EnergyArc arc,
  ) {
    final n = plan.length;
    final firstLink = i > 0 ? i : 1;
    final lastLink = j + _artistCooldown < n ? j + _artistCooldown : n - 1;
    return _windowCost(
      plan,
      firstLink,
      lastLink,
      tracks,
      energies,
      settings,
      arc,
    );
  }

  /// Sum of the path links (p-1, p) for p in [firstLink, lastLink]. Insertion
  /// and reversal moves disturb interior link positions; cooldown costs can
  /// also change for up to four slots after the moved range, so callers extend
  /// the window through that horizon.
  static double _windowCost(
    List<int> plan,
    int firstLink,
    int lastLink,
    List<AutomixTrackFeatures> tracks,
    List<double> energies,
    AutomixSettings settings,
    _EnergyArc arc,
  ) {
    var sum = 0.0;
    for (var p = firstLink; p <= lastLink; p++) {
      sum +=
          _transitionCost(
            a: tracks[plan[p - 1]],
            b: tracks[plan[p]],
            eA: energies[plan[p - 1]],
            eB: energies[plan[p]],
            stepIndex: p,
            totalSteps: plan.length,
            settings: settings,
            arc: arc,
          ) +
          _artistCooldownCost(
            plan: plan,
            planSlot: p,
            planFilled: p,
            tracks: tracks,
            candidate: tracks[plan[p]],
            settings: settings,
          );
    }
    return sum;
  }

  /// Move plan[from] to index [to], shifting the elements in between. The
  /// inverse call `_moveElement(plan, to, from)` restores the previous order.
  static void _moveElement(List<int> plan, int from, int to) {
    final value = plan[from];
    if (to > from) {
      for (var k = from; k < to; k++) {
        plan[k] = plan[k + 1];
      }
    } else if (to < from) {
      for (var k = from; k > to; k--) {
        plan[k] = plan[k - 1];
      }
    }
    plan[to] = value;
  }

  /// Reverse plan[left..right] in place.
  static void _reverseRange(List<int> plan, int left, int right) {
    while (left < right) {
      final value = plan[left];
      plan[left] = plan[right];
      plan[right] = value;
      left++;
      right--;
    }
  }

  /// Whole-set crossfade: [AutomixSettings.crossfadeBeats] beats at the
  /// set's median analyzed BPM, clamped to 1.5..12 s so pathological tempos
  /// cannot produce absurd fades.
  static double _crossfadeSeconds(
    List<AutomixTrackFeatures> tracks,
    List<int> plan,
    AutomixSettings settings,
  ) {
    final bpms = <double>[];
    for (final idx in plan) {
      final bpm = tracks[idx].bpm;
      if (bpm != null && bpm > 0) bpms.add(bpm);
    }
    bpms.sort();
    final median = bpms.isEmpty ? _defaultBpm : bpms[bpms.length ~/ 2];
    return (settings.crossfadeBeats * 60.0 / median).clamp(
      AutomixContract.fadeMinSeconds,
      AutomixContract.fadeMaxSeconds,
    );
  }
}

/// Production sequencing runs in the shared native C AutoMix core.
class AutomixEngine {
  const AutomixEngine._();

  static AutomixPlan planSet({
    required List<AutomixTrackFeatures> tracks,
    required AutomixSettings settings,
    required int startIndex,
  }) {
    final artistGroups = <String, int>{};
    final nativeTracks = <NativeAutomixTrack>[];
    for (final track in tracks) {
      final artist = track.artist.trim().toLowerCase();
      final artistGroup = artist.isEmpty
          ? 0
          : artistGroups.putIfAbsent(artist, () => artistGroups.length + 1);
      nativeTracks.add(
        NativeAutomixTrack(
          songId: track.songId,
          artistGroup: artistGroup,
          bpm: track.bpm,
          bpmConfidence: track.bpmConfidence,
          alternateBpm: track.alternateBpm,
          beatOffsetMs: track.beatOffsetMs,
          camelotNumber: track.camelotNumber,
          camelotMinor: track.camelotMinor,
          keyConfidence: track.keyConfidence,
          loudnessLufs: track.loudnessLufs,
          rmsDb: track.rmsDb,
          centroidHz: track.centroidHz,
          onsetRate: track.onsetRate,
          tailBpm: track.tailBpm,
          tailBpmConfidence: track.tailBpmConfidence,
          tailBeatOffsetMs: track.tailBeatOffsetMs,
          startBpm: track.startBpm,
          startBpmConfidence: track.startBpmConfidence,
          introTempoStability: track.introTempoStability,
          outroTempoStability: track.outroTempoStability,
          introEnergy: track.introEnergy,
          outroEnergy: track.outroEnergy,
          analyzedFraction: track.analyzedFraction,
          vocalLikelihood: track.vocalLikelihood,
          vocalConfidence: track.vocalConfidence,
          structureRegion: track.structureRegion,
          structureConfidence: track.structureConfidence,
          tailStructureRegion: track.tailStructureRegion,
          tailStructureConfidence: track.tailStructureConfidence,
          introSlope: track.introSlope,
          outroSlope: track.outroSlope,
        ),
      );
    }
    final plan = NativeAutomix.planSet(
      tracks: nativeTracks,
      profile: settings.profile.index,
      bpmTolerance: settings.bpmTolerancePercent / 100.0,
      crossfadeBeats: settings.crossfadeBeats,
      avoidArtistRepeat: settings.avoidArtistRepeat,
      harmonicFilter: settings.harmonicFilter,
      startIndex: startIndex,
    );
    return AutomixPlan(
      order: List<int>.unmodifiable(plan.order),
      crossfadeSeconds: plan.crossfadeSeconds,
      averageCost: plan.averageCost,
    );
  }

  /// Mean cost of an existing order, used by reorder hysteresis. This is the
  /// pure-Dart reference objective, independent of the native plan call.
  static double scoreOrder({
    required List<AutomixTrackFeatures> tracks,
    required List<int> order,
    required AutomixSettings settings,
  }) => DartAutomixEngineReference.scoreOrder(
    tracks: tracks,
    order: order,
    settings: settings,
  );
}
