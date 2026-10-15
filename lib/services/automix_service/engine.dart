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
  return isMinor ? (automixCamelotMinorNum[pc], true) : (automixCamelotMajorNum[pc], false);
}

/// Canonical chroma distribution profiles (Krumhansl–Schmuckler). The native
/// key extractor correlates measured chroma against 24 rotated versions of
/// these; mirrored here so the Dart tests can verify the same tuning math.
const List<double> automixKsMajorProfile = [
  6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
];
const List<double> automixKsMinorProfile = [
  6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
];

// ── Shared helpers ───────────────────────────────────────────────────────────

double automixClamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

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
    for (final raw in raws) raw == null ? 0.5 : automixClamp01((raw - lo) / span),
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
  final tempo = automixTempoCost(
    a.bpm, a.alternateBpm, b.bpm, b.alternateBpm, tolerance,
  );

  var key = automixCamelotCost(
    a.camelotNumber, a.camelotMinor, b.camelotNumber, b.camelotMinor,
  );
  if (settings.harmonicFilter && key >= 0.6) {
    key = (key * 1.5).clamp(0.0, 1.0);
  }
  // Uncertain key matches move the sub-cost halfway back to neutral.
  final kConf = automixClamp01((a.keyConfidence + b.keyConfidence) / 2);
  key = key * (0.55 + 0.45 * kConf);

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
  final variety = sameArtist
      ? (settings.avoidArtistRepeat ? 0.55 : 0.20)
      : 0.0;

  final (wT, wK, wE, wV) = _profileWeights[settings.profile]!;
  return ((wT * tempo + wK * key + wE * energy + wV * variety) /
          (wT + wK + wE + wV))
      .clamp(0.0, 1.0);
}

// ── Engine ───────────────────────────────────────────────────────────────────

class AutomixEngine {
  const AutomixEngine._();

  /// How much the one-step lookahead's estimated cost counts toward the final
  /// score of the immediate pick (0..1).
  static const double _lookaheadGamma = 0.35;

  /// How many tempo-sorted neighbor slots to explore on each side of the
  /// current track before falling back to a global scan.
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
    final n = tracks.length;
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
    final limit = _lookaheadTopK < scored.length ? _lookaheadTopK : scored.length;
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
    return low.clamp(0, slotOrder.length - 1);
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
    final median = bpms.isEmpty
        ? _defaultBpm
        : bpms[bpms.length ~/ 2];
    return (settings.crossfadeBeats * 60.0 / median).clamp(1.5, 12.0);
  }
}
