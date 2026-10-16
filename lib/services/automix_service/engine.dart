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
    var weighted = 0.0;
    var weight = 0.0;
    var agreeing = 0.0;
    for (final s in withBpm) {
      final folded = automixFoldToOctave(s.bpm!, anchor.bpm!);
      weighted += folded * s.bpmConfidence;
      weight += s.bpmConfidence;
      if ((folded - anchor.bpm!).abs() / anchor.bpm! <= 0.04) {
        agreeing += s.bpmConfidence;
      }
    }
    if (weight > 0) {
      bpm = automixFoldToOctave(weighted / weight, anchor.bpm!);
      // A tempo only counts as confident when the windows agree with each other.
      bpmConfidence = automixClamp01(
        (agreeing / weight) * anchor.bpmConfidence,
      );
    }
  }

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

  // ── Coarse structure: first/last window relative to this track's peak ─────
  final segmentEnergy = <double?>[
    for (final s in segments)
      s.rmsDb == null ? null : automixClamp01((s.rmsDb! + 30.0) / 24.0),
  ];
  final present = segmentEnergy.whereType<double>().toList(growable: false);
  double? introEnergy;
  double? outroEnergy;
  if (present.length >= 2) {
    final peak = present.reduce(math.max);
    if (peak > 0.05) {
      introEnergy = segmentEnergy.first == null
          ? null
          : automixClamp01(segmentEnergy.first! / peak);
      outroEnergy = !tailSegmentAnalyzed || segmentEnergy.last == null
          ? null
          : automixClamp01(segmentEnergy.last! / peak);
    }
  }

  // ── Exit beat grid: the fade lives in the tail window ────────────────────
  double? tailBpm;
  double? tailBeatOffsetMs;
  double? tailDownbeatOffsetMs;
  for (final s
      in tailSegmentAnalyzed
          ? segments.reversed
          : const <AutomixSegmentFeatures>[]) {
    if (s.bpm == null || s.bpmConfidence < 0.20) continue;
    tailBpm = bpm == null ? s.bpm! : automixFoldToOctave(s.bpm!, bpm);
    if (s.beatOffsetMs != null && s.bpmConfidence >= 0.25) {
      tailBeatOffsetMs = s.startSeconds * 1000.0 + s.beatOffsetMs!;
    }
    if (s.downbeatOffsetMs != null && s.bpmConfidence >= 0.25) {
      tailDownbeatOffsetMs = s.startSeconds * 1000.0 + s.downbeatOffsetMs!;
    }
    break;
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
  final firstSegment = segments.isEmpty ? null : segments.first;
  final lastSegment = segments.isEmpty ? null : segments.last;
  final localDropCue = firstSegment?.dropCueMs;
  final localBreakdownCue = tailSegmentAnalyzed
      ? lastSegment?.breakdownCueMs
      : null;
  final dropCueMs =
      localDropCue != null && localDropCue.isFinite && localDropCue >= 0
      ? firstSegment!.startSeconds * 1000.0 + localDropCue
      : null;
  final tailBreakdownCueMs =
      localBreakdownCue != null &&
          localBreakdownCue.isFinite &&
          localBreakdownCue >= 0
      ? lastSegment!.startSeconds * 1000.0 + localBreakdownCue
      : null;

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
    beatOffsetMs: segments.isEmpty ? null : segments.first.beatOffsetMs,
    downbeatOffsetMs:
        segments.isEmpty || segments.first.downbeatOffsetMs == null
        ? null
        : segments.first.startSeconds * 1000.0 +
              segments.first.downbeatOffsetMs!,
    tailDownbeatOffsetMs: tailDownbeatOffsetMs,
    dropCueMs: dropCueMs,
    tailBreakdownCueMs: tailBreakdownCueMs,
    dropConfidence: firstSegment?.dropConfidence ?? 0,
    tailBreakdownConfidence: tailSegmentAnalyzed
        ? (lastSegment?.breakdownConfidence ?? 0)
        : 0,
    structureRegion: firstSegment?.structureRegion ?? 0,
    structureConfidence: firstSegment?.structureConfidence ?? 0,
    tailStructureRegion: tailSegmentAnalyzed
        ? (lastSegment?.structureRegion ?? 0)
        : 0,
    tailStructureConfidence: tailSegmentAnalyzed
        ? (lastSegment?.structureConfidence ?? 0)
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
    tailBeatOffsetMs: tailBeatOffsetMs,
    introEnergy: introEnergy,
    outroEnergy: outroEnergy,
    analyzedFraction: fileSeconds <= 0
        ? 0
        : automixClamp01(analyzedSeconds / fileSeconds),
    tailAnalyzed: tailSegmentAnalyzed,
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
    required this.outgoingBassOverlapGain,
    required this.incomingBassOverlapGain,
    required this.outgoingMidOverlapGain,
    required this.incomingMidOverlapGain,
    required this.outgoingHighOverlapGain,
    required this.incomingHighOverlapGain,
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

  /// Fade length in media-timeline seconds (opposite deck's tempo governs).
  final double fadeSeconds;

  /// Equal-power transfer shape: 1.0 = the classic cos/sin curve, > 1 hands the
  /// mix over faster (dense outros), < 1 slower (sparse outros).
  final double curveGamma;

  /// Level trims (≤ 1.0) applied across the overlap so the louder deck is
  /// attenuated toward the quieter one. Never boosts, so nothing can clip.
  final double outgoingTrim;
  final double incomingTrim;
}

/// Derives the fade length, transfer curve and level match for [outgoing] →
/// [incoming].
///
/// Structure-aware: a dense outro gets a shorter, faster hand-over (less
/// overlap of two busy sections) while a sparse outro gets a longer, gentler
/// blend; a sparse intro tolerates extra overlap. Confidently incompatible
/// tempos or keys shorten the fade automatically. Levels follow standard DJ
/// practice: only the louder deck is attenuated, by at most 6 dB.
/// Tempo that governs a track's exit: its tail estimate when the tail window
/// had one, else its head estimate.
double? automixExitBpm(AutomixTrackFeatures features) =>
    features.tailBpm ?? features.bpm;

AutomixTransitionCue automixTransitionCue({
  required AutomixTrackFeatures outgoing,
  required AutomixTrackFeatures incoming,
  required AutomixSettings settings,
  double fallbackFadeSeconds = 6.0,
}) {
  // The fade lives in the outgoing track's tail, so its exit tempo (falling
  // back to the head estimate) sets how many beats the blend spans.
  final tempo = automixExitBpm(outgoing) ?? incoming.bpm;
  var fadeSeconds = tempo == null || tempo <= 0
      ? fallbackFadeSeconds
      : settings.crossfadeBeats * 60.0 / tempo;

  var gamma = 1.0;
  final outro = outgoing.outroEnergy;
  if (outro != null) {
    if (outro >= 0.70) {
      // Busy outro: hand over faster so two dense sections overlap less.
      fadeSeconds *= 0.75;
      gamma = 1.35;
    } else if (outro <= 0.35) {
      // Sparse/quiet outro: a longer, gentler blend sounds intentional.
      fadeSeconds *= 1.25;
      gamma = 0.85;
    }
  }
  final intro = incoming.introEnergy;
  if (intro != null && intro <= 0.35) {
    // A sparse incoming intro can carry a longer overlap without clashing.
    fadeSeconds *= 1.15;
  }

  // Keep the transition fully automatic: when reliable analysis says the two
  // pulse grids cannot match, hand over sooner instead of holding a long,
  // rhythmically conflicting overlap. Confidently distant keys also get a
  // shorter blend. Uncertain estimates stay neutral and keep the regular fade.
  final exitTempo = automixExitBpm(outgoing);
  if (outgoing.bpmConfidence >= 0.45 &&
      incoming.bpmConfidence >= 0.45 &&
      exitTempo != null &&
      incoming.bpm != null &&
      !automixTempoMatch(
        referenceBpm: exitTempo,
        trackBpm: incoming.bpm,
        tolerance: settings.bpmTolerancePercent / 100.0,
      ).$1) {
    fadeSeconds *= 0.72;
    gamma = math.max(gamma, 1.20);
  }

  final keyCost = automixCamelotCost(
    outgoing.camelotNumber,
    outgoing.camelotMinor,
    incoming.camelotNumber,
    incoming.camelotMinor,
  );
  if (outgoing.keyConfidence >= 0.55 &&
      incoming.keyConfidence >= 0.55 &&
      keyCost >= 0.60) {
    fadeSeconds *= 0.82;
    gamma = math.max(gamma, 1.15);
  }

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
    if (lead >= 1.5 && lead <= 12.0) cueLeadSeconds = lead;
  }

  final exitTempo = automixExitBpm(outgoing);
  final tempoMismatch = outgoing.bpmConfidence >= 0.45 &&
      incoming.bpmConfidence >= 0.45 &&
      exitTempo != null &&
      incoming.bpm != null &&
      !automixTempoMatch(
        referenceBpm: exitTempo,
        trackBpm: incoming.bpm,
        tolerance: settings.bpmTolerancePercent / 100.0,
      ).$1;
  final keyCost = automixCamelotCost(
    outgoing.camelotNumber,
    outgoing.camelotMinor,
    incoming.camelotNumber,
    incoming.camelotMinor,
  );
  final keyMismatch = outgoing.keyConfidence >= 0.55 &&
      incoming.keyConfidence >= 0.55 &&
      keyCost >= 0.60;
  final denseTail = (outro != null && outro >= 0.70) ||
      (outgoing.tailStructureRegion == 3 &&
          outgoing.tailStructureConfidence >= 0.65);
  final sparseTail = (outro != null && outro <= 0.35) ||
      (outgoing.tailStructureRegion == 1 &&
          outgoing.tailStructureConfidence >= 0.75);
  final sparseIntro = intro != null && intro <= 0.35;

  final AutomixTransitionStrategy strategy;
  if (cueLeadSeconds != null) {
    strategy = AutomixTransitionStrategy.structureAligned;
  } else if (tempoMismatch || keyMismatch) {
    strategy = AutomixTransitionStrategy.shortHandover;
  } else if (denseTail) {
    strategy = AutomixTransitionStrategy.quickHandover;
  } else if (sparseTail || sparseIntro) {
    strategy = AutomixTransitionStrategy.longBlend;
  } else {
    strategy = AutomixTransitionStrategy.crossfade;
  }

  // Apply the selected strategy to the parameters sent to Media3. The values are
  // subsequently consumed by the real CrossfadeController, not just logged.
  switch (strategy) {
    case AutomixTransitionStrategy.crossfade:
      break;
    case AutomixTransitionStrategy.structureAligned:
      fadeSeconds = cueLeadSeconds!;
      break;
    case AutomixTransitionStrategy.shortHandover:
      fadeSeconds = math.min(fadeSeconds, 4.0);
      gamma = math.max(gamma, 1.20);
      break;
    case AutomixTransitionStrategy.longBlend:
      fadeSeconds = math.max(fadeSeconds, 6.0);
      gamma = math.min(gamma, 0.95);
      break;
    case AutomixTransitionStrategy.quickHandover:
      fadeSeconds = math.min(fadeSeconds, 3.0);
      gamma = math.max(gamma, 1.35);
      break;
  }
  fadeSeconds = fadeSeconds.clamp(1.5, 12.0).toDouble();

  // Derive conservative per-deck EQ targets from actual measured features.
  // Unknown metadata keeps bands neutral, except the historical outgoing-tail
  // filter fallback. These are overlap-only attenuations; neither deck is boosted.
  final confidentVocalClash = outgoing.vocalConfidence >= 0.45 &&
      incoming.vocalConfidence >= 0.45 &&
      outgoing.vocalLikelihood >= 0.55 &&
      incoming.vocalLikelihood >= 0.55;
  final outgoingBusy = (outgoing.outroEnergy ?? 0.5) >= 0.75 &&
      (outgoing.onsetRate ?? 0) >= 2.5;
  final incomingBusy = (incoming.introEnergy ?? 0.5) >= 0.75 &&
      (incoming.onsetRate ?? 0) >= 2.5;
  final outgoingBassGain = outgoingBusy ? 0.88 : 1.0;
  final incomingBassGain = incomingBusy ? 0.90 : 1.0;
  final outgoingMidGain = confidentVocalClash
      ? 0.78
      : (strategy == AutomixTransitionStrategy.quickHandover ? 0.92 : 1.0);
  final incomingMidGain = confidentVocalClash
      ? 0.78
      : (incoming.structureRegion == 4 &&
              incoming.structureConfidence >= 0.70
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
  final outgoingHighGain = highGain(outgoing, fallback: 0.25);
  final incomingHighGain = incoming.centroidHz == null
      ? 1.0
      : (1.0 -
              0.18 *
                  automixClamp01((incoming.centroidHz! - 900.0) / 2600.0))
          .clamp(0.82, 1.0)
          .toDouble();

  // Standard DJ level matching: attenuate the louder deck only.
  var outgoingTrim = 1.0;
  var incomingTrim = 1.0;
  final outLufs = outgoing.loudnessLufs;
  final inLufs = incoming.loudnessLufs;
  final useIntegratedLufs = outLufs != null && inLufs != null;
  final outLevelDb = useIntegratedLufs ? outLufs : outgoing.rmsDb;
  final inLevelDb = useIntegratedLufs ? inLufs : incoming.rmsDb;
  if (outLevelDb != null && inLevelDb != null) {
    final deltaDb = (outLevelDb - inLevelDb).clamp(-6.0, 6.0);
    if (deltaDb > 0.5) {
      outgoingTrim = math.pow(10, -deltaDb / 20).toDouble();
    } else if (deltaDb < -0.5) {
      incomingTrim = math.pow(10, deltaDb / 20).toDouble();
    }
  }

  return AutomixTransitionCue(
    fadeSeconds: fadeSeconds,
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
      final cenN = centroid == null
          ? 0.5
          : automixClamp01((centroid - 400.0) / 3600.0);
      final onN = onset == null ? 0.5 : automixClamp01((onset - 0.5) / 5.5);
      raws.add(0.5 * rmsN + 0.25 * cenN + 0.25 * onN);
      continue;
    }
    final lufs = f.loudnessLufs; // ~ -24 (quiet) .. -6 (loud) LUFS
    if (lufs != null) {
      final lufsN = automixClamp01((lufs + 24.0) / 18.0);
      final onN = onset == null ? 0.25 : automixClamp01((onset - 0.5) / 5.5);
      raws.add(0.75 * lufsN + 0.25 * onN);
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

// ── Transition cost ──────────────────────────────────────────────────────────

/// Weight sets per [AutomixProfile]: (tempo, key, energy, variety).
/// They intentionally sum to 1 so the weighted mean stays on 0..1.
const Map<AutomixProfile, (double, double, double, double)> _profileWeights = {
  AutomixProfile.dj: (0.40, 0.20, 0.25, 0.15),
  AutomixProfile.harmonic: (0.20, 0.45, 0.20, 0.15),
  AutomixProfile.energy: (0.15, 0.15, 0.55, 0.15),
};

/// Cost of playing track [b] immediately after track [a]. Weighted mean of
/// four sub-costs, clamped to 0..1:
///
/// * tempo — see [automixTempoCost]
/// * key   — [automixCamelotCost], scaled by key detection confidence
/// * energy — continuity + arc-following (see [_energyTargetPos])
/// * variety — small penalty for back-to-back same-artist tracks
double _transitionCost({
  required AutomixTrackFeatures a,
  required AutomixTrackFeatures b,
  required double eA,
  required double eB,
  required int stepIndex,
  required int totalSteps,
  required AutomixSettings settings,
}) {
  final tolerance = settings.bpmTolerancePercent / 100.0;
  final measuredTempo = automixTempoCost(
    a.bpm,
    a.alternateBpm,
    b.bpm,
    b.alternateBpm,
    tolerance,
  );
  final tempoConfidence = automixClamp01(
    (a.bpmConfidence + b.bpmConfidence) / 2,
  );
  final tempo = automixConfidenceBlend(
    measuredTempo,
    tempoConfidence,
    neutralCost: 0.35,
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
  if (settings.harmonicFilter && kConf >= 0.55 && measuredKey >= 0.6) {
    key = math.max(key, 0.9);
  }

  // Energy: blend continuity with the arc target; the "energy" profile adds
  // an explicit wrong-direction penalty so the arc keeps flowing forward.
  final pos = totalSteps <= 1
      ? 1.0
      : automixClamp01(stepIndex / (totalSteps - 1));
  final target = _energyTargetPos(pos, settings.profile);
  final delta = eB - eA;
  var energy = 0.30 * delta.abs() + 0.55 * (eB - target).abs();
  if (settings.profile == AutomixProfile.energy) {
    final beforePeak = pos < 0.55;
    if (beforePeak && delta < -0.05) {
      energy += 0.8 * (-delta);
    } else if (!beforePeak && delta > 0.05) {
      energy += 0.8 * delta;
    }
  }
  energy = energy.clamp(0.0, 1.0);

  final sameArtist =
      a.artist.trim().toLowerCase() == b.artist.trim().toLowerCase() &&
      a.artist.trim().isNotEmpty;
  final variety = sameArtist ? (settings.avoidArtistRepeat ? 0.55 : 0.20) : 0.0;

  final vA = a.vocalLikelihood;
  final vB = b.vocalLikelihood;
  final cA = a.vocalConfidence;
  final cB = b.vocalConfidence;
  var vocalPenalty = 0.0;
  if (vA.isFinite &&
      vB.isFinite &&
      cA.isFinite &&
      cB.isFinite &&
      cA >= 0.35 &&
      cB >= 0.35 &&
      vA > 0.5 &&
      vB > 0.5) {
    final effectiveA = (vA - 0.5) * cA;
    final effectiveB = (vB - 0.5) * cB;
    vocalPenalty = effectiveA * effectiveB * 0.4;
  }

  final (wT, wK, wE, wV) = _profileWeights[settings.profile]!;
  return ((wT * tempo + wK * key + wE * energy + wV * variety + vocalPenalty) /
          (wT + wK + wE + wV))
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
  static const double _minTempoBpm = 60.0;
  static const double _maxTempoBpm = 200.0;

  /// Number of best candidates that get a full one-step lookahead re-score.
  static const int _lookaheadTopK = 3;

  /// Improvement-pass budget for the swap polisher.
  static const int _maxPasses = 6;
  static const int _maxSwapBreach = 4;
  static const int _maxEvalsPerPass = 4000;

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
    for (var pass = 0; pass < _maxPasses && evals < _maxEvalsPerPass; pass++) {
      var improved = false;
      for (int i = 1; i < n - 1 && evals < _maxEvalsPerPass; i++) {
        final jEnd = (i + _maxSwapBreach).clamp(i + 1, n - 1);
        for (int j = i + 1; j <= jEnd && evals < _maxEvalsPerPass; j++) {
          evals++;
          final before = _localCost(plan, i, j, tracks, energies, settings);
          final origI = plan[i];
          final origJ = plan[j];
          plan[i] = origJ;
          plan[j] = origI;
          final after = _localCost(plan, i, j, tracks, energies, settings);
          if (after < before - 1e-9) {
            improved = true;
          } else {
            plan[i] = origI;
            plan[j] = origJ;
          }
        }
      }
      if (!improved) break;
    }

    return AutomixPlan(
      order: List<int>.unmodifiable(plan),
      crossfadeSeconds: _crossfadeSeconds(tracks, plan, settings),
      averageCost: _pathCost(plan, tracks, energies, settings) / (n - 1),
    );
  }

  /// Median BPM among tracks that have an analyzed value, else
  /// [_defaultBpm].
  static double _medianKnownBpm(List<AutomixTrackFeatures> tracks) {
    final bpms = tracks.map((t) => t.bpm).whereType<double>().toList()..sort();
    if (bpms.isEmpty) return _defaultBpm;
    return bpms[bpms.length ~/ 2];
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
        final cost = _transitionCost(
          a: tracks[current],
          b: tracks[cand],
          eA: energies[current],
          eB: energies[cand],
          stepIndex: stepIndex,
          totalSteps: totalSteps,
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

    // One-step lookahead over the top few candidates: score
    // cost1 + γ · min over next-next.
    var best = scored.first.$1;
    var bestScore = double.infinity;
    final limit = _lookaheadTopK < scored.length
        ? _lookaheadTopK
        : scored.length;
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
        medianBpm: medianBpm,
        excludeIndex: cand,
      );
      for (final cand2 in nextCandidates) {
        if (played[cand2] || cand2 == current) continue;
        final c = _transitionCost(
          a: tracks[cand],
          b: tracks[cand2],
          eA: energies[cand],
          eB: energies[cand2],
          stepIndex: stepIndex + 1,
          totalSteps: totalSteps,
          settings: settings,
        );
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

  /// Bounded candidate set from local BPM order and half/double-time anchors.
  /// Unknown-BPM tracks remain discoverable through the ordinary slot window.
  static List<int> _candidatePool({
    required int current,
    required List<bool> played,
    required List<int> slotOf,
    required List<int> slotOrder,
    required List<AutomixTrackFeatures> tracks,
    required double medianBpm,
    int? excludeIndex,
  }) {
    final n = tracks.length;
    final found = <int>{};
    void addSlot(int slot) {
      if (slot < 0 || slot >= n) return;
      final candidate = slotOrder[slot];
      if (!played[candidate] && candidate != excludeIndex) {
        found.add(candidate);
      }
    }

    final slot = slotOf[current];
    for (int reach = 1; reach <= _window; reach++) {
      addSlot(slot + reach);
      addSlot(slot - reach);
    }

    final track = tracks[current];
    final bpm = track.bpm;
    if (bpm != null && bpm > 0) {
      final anchors = <double>{bpm, bpm / 2.0, bpm * 2.0};
      final alternate = track.alternateBpm;
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

  /// Sum of all transition costs across a plan.
  static double _pathCost(
    List<int> plan,
    List<AutomixTrackFeatures> tracks,
    List<double> energies,
    AutomixSettings settings,
  ) {
    var sum = 0.0;
    final n = plan.length;
    for (int i = 0; i + 1 < n; i++) {
      sum += _transitionCost(
        a: tracks[plan[i]],
        b: tracks[plan[i + 1]],
        eA: energies[plan[i]],
        eB: energies[plan[i + 1]],
        stepIndex: i + 1,
        totalSteps: n,
        settings: settings,
      );
    }
    return sum;
  }

  /// Exact cost of the links a swap of positions [i] ↔ [j] would disturb:
  /// the up-to-four boundary links. Interior links between the two positions
  /// are unaffected (their endpoints keep their relative order).
  static double _localCost(
    List<int> plan,
    int i,
    int j,
    List<AutomixTrackFeatures> tracks,
    List<double> energies,
    AutomixSettings settings,
  ) {
    final n = plan.length;
    double link(int from, int to) {
      assert(0 <= from && from < n && 0 <= to && to < n);
      return _transitionCost(
        a: tracks[plan[from]],
        b: tracks[plan[to]],
        eA: energies[plan[from]],
        eB: energies[plan[to]],
        stepIndex: to,
        totalSteps: n,
        settings: settings,
      );
    }

    var sum = 0.0;
    if (i > 0) sum += link(i - 1, i);
    sum += link(i, i + 1);
    if (j != i + 1) {
      sum += link(j - 1, j);
    } else {
      // Adjacent swap: the (i, i+1) link is the SAME link as (j-1, j); the
      // line above already added exactly one copy via link(i, i+1).
    }
    if (j + 1 < n) sum += link(j, j + 1);
    return sum;
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
    return (settings.crossfadeBeats * 60.0 / median).clamp(1.5, 12.0);
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
          tailBeatOffsetMs: track.tailBeatOffsetMs,
          introEnergy: track.introEnergy,
          outroEnergy: track.outroEnergy,
          analyzedFraction: track.analyzedFraction,
          vocalLikelihood: track.vocalLikelihood,
          vocalConfidence: track.vocalConfidence,
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
}
