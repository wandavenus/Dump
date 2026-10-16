part of '../automix_service.dart';

// ── Feature model ─────────────────────────────────────────────────────────────
//
// Per-track descriptors consumed by [AutomixEngine]. Everything is derived
// offline: BPM + key come from the native DSP extractor (spectral-flux
// autocorrelation + Krumhansl-Schmuckler chroma correlation, no ML), loudness
// from the ReplayGain scan (EBU R128 LUFS), and energy from a loudness/
// brightness/onset-density composite computed by the native extractor.
//
// Any field may be null/zero when the analysis is unavailable or uncertain —
// the engine uses neutral fallback costs instead of rejecting the track.

/// One analyzed window of a file: the native extractor runs on a bounded PCM
/// window so a long track can be sampled head/middle/tail instead of only its
/// first five minutes. [automixMergeSegments] folds these into per-track
/// features.
@immutable
class AutomixSegmentFeatures {
  const AutomixSegmentFeatures({
    required this.startSeconds,
    required this.seconds,
    this.bpm,
    this.bpmConfidence = 0,
    this.alternateBpm,
    this.beatOffsetMs,
    this.downbeatOffsetMs,
    this.dropCueMs,
    this.breakdownCueMs,
    this.dropConfidence = 0,
    this.breakdownConfidence = 0,
    this.structureRegion = 0,
    this.structureConfidence = 0,
    this.vocalLikelihood = 0,
    this.vocalConfidence = 0,
    this.camelotNumber,
    this.camelotMinor,
    this.keyConfidence = 0,
    this.rmsDb,
    this.centroidHz,
    this.onsetRate,
  });

  /// Window start in the file (seconds) and its length.
  final double startSeconds;
  final double seconds;

  final double? bpm;
  final double bpmConfidence;

  /// Half/double-time alternative for octave-ambiguous tempo estimates.
  final double? alternateBpm;

  /// Dominant-beat phase relative to this analysis window (ms).
  final double? beatOffsetMs;

  /// Estimated 16-beat phrase-start phase relative to this window (ms).
  /// It stays null unless repeated onset accents distinguish one phrase phase.
  final double? downbeatOffsetMs;

  /// Candidate structural cues relative to this window (ms), if detected.
  final double? dropCueMs;
  final double? breakdownCueMs;
  final double dropConfidence;
  final double breakdownConfidence;

  /// Structural region (0=unknown, 1=low_activity, 2=buildup, 3=drop, 4=breakdown, 5=stable_high)
  final int structureRegion;
  final double structureConfidence;

  final double vocalLikelihood;
  final double vocalConfidence;

  final int? camelotNumber;
  final bool? camelotMinor;
  final double keyConfidence;

  final double? rmsDb;
  final double? centroidHz;
  final double? onsetRate;
}

/// Converts the full native-analysis MethodChannel map into a validated window
/// model. Keep this parser pure so ABI-field forwarding is covered by Dart tests.
AutomixSegmentFeatures automixSegmentFeaturesFromAnalysisMap(
  Map<String, dynamic> map, {
  required double fallbackStartSeconds,
  required double fallbackSeconds,
}) {
  double? finiteValue(String key) {
    final raw = map[key];
    if (raw is! num) return null;
    final value = raw.toDouble();
    return value.isFinite ? value : null;
  }

  double unitValue(String key) {
    final value = finiteValue(key);
    // Confidence/likelihood fields are probabilities, not values to saturate.
    // Out-of-contract data must not become falsely high-confidence metadata.
    return value != null && value >= 0 && value <= 1 ? value : 0;
  }

  double? nonNegativeValue(String key) {
    final value = finiteValue(key);
    return value != null && value >= 0 ? value : null;
  }

  int structureValue(String key) {
    final value = finiteValue(key);
    if (value == null) return 0;
    final region = value.toInt();
    return region >= 0 && region <= 5 ? region : 0;
  }

  final bpm = finiteValue('bpm');
  final bpmConfidence = unitValue('bpmConfidence');
  final keyConfidence = unitValue('keyConfidence');
  final rawAlternateBpm = finiteValue('alternateBpm');
  final rawCamelotNumber = map['camelotNumber'];
  final camelotValue = rawCamelotNumber is num
      ? rawCamelotNumber.toDouble()
      : null;
  final camelotNumber = camelotValue != null &&
          camelotValue.isFinite &&
          camelotValue == camelotValue.roundToDouble() &&
          camelotValue >= 1 &&
          camelotValue <= 12
      ? camelotValue.toInt()
      : null;
  final rawCamelotMinor = map['camelotMinor'];
  final camelotMinor = rawCamelotMinor is bool ? rawCamelotMinor : null;
  final start = finiteValue('segmentStartSeconds');
  final seconds = finiteValue('segmentSeconds');
  final beatOffset = nonNegativeValue('beatOffsetMs');
  final downbeatOffset = nonNegativeValue('downbeatOffsetMs');

  return AutomixSegmentFeatures(
    startSeconds: start != null && start >= 0
        ? start
        : fallbackStartSeconds,
    seconds: seconds != null && seconds > 0 ? seconds : fallbackSeconds,
    bpm: bpm != null && bpm > 0 && bpmConfidence >= 0.15 ? bpm : null,
    bpmConfidence: bpm != null && bpm > 0 && bpmConfidence >= 0.15
        ? bpmConfidence
        : 0,
    alternateBpm: bpmConfidence >= 0.15 &&
            rawAlternateBpm != null &&
            rawAlternateBpm > 0
        ? rawAlternateBpm
        : null,
    beatOffsetMs: bpm != null && bpm > 0 && bpmConfidence >= 0.20
        ? beatOffset
        : null,
    downbeatOffsetMs: bpm != null && bpm > 0 && bpmConfidence >= 0.20
        ? downbeatOffset
        : null,
    dropCueMs: nonNegativeValue('dropCueMs'),
    breakdownCueMs: nonNegativeValue('breakdownCueMs'),
    dropConfidence: unitValue('dropConfidence'),
    breakdownConfidence: unitValue('breakdownConfidence'),
    structureRegion: structureValue('structureRegion'),
    structureConfidence: unitValue('structureConfidence'),
    vocalLikelihood: unitValue('vocalLikelihood'),
    vocalConfidence: unitValue('vocalConfidence'),
    camelotNumber: keyConfidence >= 0.25 &&
            camelotNumber != null &&
            camelotNumber >= 1 &&
            camelotNumber <= 12
        ? camelotNumber
        : null,
    camelotMinor: keyConfidence >= 0.25 ? camelotMinor : null,
    keyConfidence: keyConfidence >= 0.25 ? keyConfidence : 0,
    rmsDb: finiteValue('rmsDb'),
    centroidHz: finiteValue('centroidHz'),
    onsetRate: finiteValue('onsetRate'),
  );
}

@immutable
class AutomixTrackFeatures {
  const AutomixTrackFeatures({
    required this.songId,
    this.title = '',
    this.artist = '',
    this.bpm,
    this.bpmConfidence = 0,
    this.alternateBpm,
    this.beatOffsetMs,
    this.camelotNumber,
    this.camelotMinor,
    this.keyConfidence = 0,
    this.loudnessLufs,
    this.rmsDb,
    this.centroidHz,
    this.onsetRate,
    this.tailBpm,
    this.tailBeatOffsetMs,
    this.downbeatOffsetMs,
    this.tailDownbeatOffsetMs,
    this.dropCueMs,
    this.tailBreakdownCueMs,
    this.dropConfidence = 0,
    this.tailBreakdownConfidence = 0,
    this.structureRegion = 0,
    this.structureConfidence = 0,
    this.tailStructureRegion = 0,
    this.tailStructureConfidence = 0,
    this.vocalLikelihood = 0,
    this.vocalConfidence = 0,
    this.durationSeconds = 0,
    this.introEnergy,
    this.outroEnergy,
    this.analyzedFraction = 0,
    this.tailAnalyzed = false,
  });

  final int songId;

  /// Song metadata kept in-features so the variety cost (back-to-back same
  /// artist penalization) also works when nothing was analyzed.
  final String title;
  final String artist;

  /// Estimated tempo in BPM, or null when no confident estimate exists.
  final double? bpm;

  /// 0..1 confidence for [bpm] (autocorrelation peak ratio).
  final double bpmConfidence;

  /// Half/double-time alternative of [bpm], used for octave-ambiguity
  /// resolution when matching consecutive tempos.
  final double? alternateBpm;

  /// Estimated dominant-beat phase in milliseconds from the start of the file.
  /// This is a heuristic onset-grid phase, not a guaranteed musical downbeat.
  final double? beatOffsetMs;

  /// Estimated intro 16-beat phrase phase in milliseconds from the file start.
  final double? downbeatOffsetMs;

  /// Estimated outro 16-beat phrase phase in milliseconds from the file start.
  final double? tailDownbeatOffsetMs;

  /// Intro drop cue (absolute milliseconds from file start), if confidently
  /// detected in the head analysis window.
  final double? dropCueMs;

  /// Outgoing breakdown cue (absolute milliseconds from file start), if
  /// confidently detected in the tail analysis window.
  final double? tailBreakdownCueMs;

  final double dropConfidence;
  final double tailBreakdownConfidence;
  final int structureRegion;
  final double structureConfidence;
  final int tailStructureRegion;
  final double tailStructureConfidence;
  final double vocalLikelihood;
  final double vocalConfidence;

  /// Source duration inferred from the native analysis windows, in seconds.
  final double durationSeconds;

  /// Camelot wheel position 1..12, or null when key detection was too
  /// uncertain. Letter: `camelotMinor == true` → "A" (minor), else "B" (major).
  final int? camelotNumber;
  final bool? camelotMinor;

  /// 0..1 confidence for the key estimate (profile correlation margin).
  final double keyConfidence;

  /// Integrated loudness in LUFS when known (ReplayGain scan).
  final double? loudnessLufs;

  /// Raw analysis features (dBFS RMS, spectral centroid Hz, onsets/second).
  /// Combined into a normalized energy score inside the engine.
  final double? rmsDb;
  final double? centroidHz;
  final double? onsetRate;

  /// Beat grid of the track's **exit** (`tailBpm` in the same octave as [bpm],
  /// [tailBeatOffsetMs] measured from the start of the file). The end-of-track
  /// fade happens there, so this — not the intro grid — is what the transition
  /// is aligned against.
  final double? tailBpm;
  final double? tailBeatOffsetMs;

  /// 0..1 energy of the first/last analyzed window relative to the loudest
  /// window of the same track — the coarse "structure" signal used to pick the
  /// fade length and curve.
  final double? introEnergy;
  final double? outroEnergy;

  /// Share of the file that was actually analyzed (1.0 = whole file).
  final double analyzedFraction;

  /// True only when the file's exit window was analyzed (or the head window
  /// covers the entire short file). Partial analysis must not masquerade as an
  /// outro beat grid.
  final bool tailAnalyzed;

  // ── Serialization (SharedPreferences JSON) ─────────────────────────────────

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': songId,
    'title': title,
    'artist': artist,
    if (bpm != null) 'bpm': bpm,
    'bc': bpmConfidence,
    if (alternateBpm != null) 'alt': alternateBpm,
    if (beatOffsetMs != null) 'bo': beatOffsetMs,
    if (downbeatOffsetMs != null) 'dbo': downbeatOffsetMs,
    if (tailDownbeatOffsetMs != null) 'tdbo': tailDownbeatOffsetMs,
    if (dropCueMs != null) 'dc': dropCueMs,
    if (tailBreakdownCueMs != null) 'tbkc': tailBreakdownCueMs,
    if (dropConfidence > 0) 'dconf': dropConfidence,
    if (tailBreakdownConfidence > 0) 'tbconf': tailBreakdownConfidence,
    if (structureRegion > 0) 'sreg': structureRegion,
    if (structureConfidence > 0) 'sconf': structureConfidence,
    if (tailStructureRegion > 0) 'tsreg': tailStructureRegion,
    if (tailStructureConfidence > 0) 'tsconf': tailStructureConfidence,
    if (vocalLikelihood > 0) 'vlike': vocalLikelihood,
    if (vocalConfidence > 0) 'vconf': vocalConfidence,
    if (durationSeconds > 0) 'dur': durationSeconds,
    if (camelotNumber != null) 'kn': camelotNumber,
    if (camelotMinor != null) 'km': camelotMinor,
    'kc': keyConfidence,
    if (loudnessLufs != null) 'lufs': loudnessLufs,
    if (rmsDb != null) 'rms': rmsDb,
    if (centroidHz != null) 'cen': centroidHz,
    if (onsetRate != null) 'on': onsetRate,
    if (tailBpm != null) 'tbpm': tailBpm,
    if (tailBeatOffsetMs != null) 'tbo': tailBeatOffsetMs,
    if (introEnergy != null) 'ie': introEnergy,
    if (outroEnergy != null) 'oe': outroEnergy,
    if (analyzedFraction > 0) 'af': analyzedFraction,
    'ta': tailAnalyzed,
  };

  factory AutomixTrackFeatures.fromMap(Map<dynamic, dynamic> map) {
    return AutomixTrackFeatures(
      songId: (map['id'] as num?)?.toInt() ?? 0,
      title: map['title'] as String? ?? '',
      artist: map['artist'] as String? ?? '',
      bpm: (map['bpm'] as num?)?.toDouble(),
      bpmConfidence: (map['bc'] as num?)?.toDouble() ?? 0,
      alternateBpm: (map['alt'] as num?)?.toDouble(),
      beatOffsetMs: (map['bo'] as num?)?.toDouble(),
      downbeatOffsetMs: (map['dbo'] as num?)?.toDouble(),
      tailDownbeatOffsetMs: (map['tdbo'] as num?)?.toDouble(),
      dropCueMs: (map['dc'] as num?)?.toDouble(),
      tailBreakdownCueMs: (map['tbkc'] as num?)?.toDouble(),
      dropConfidence: (map['dconf'] as num?)?.toDouble() ?? 0,
      tailBreakdownConfidence: (map['tbconf'] as num?)?.toDouble() ?? 0,
      structureRegion: (map['sreg'] as num?)?.toInt() ?? 0,
      structureConfidence: (map['sconf'] as num?)?.toDouble() ?? 0,
      tailStructureRegion: (map['tsreg'] as num?)?.toInt() ?? 0,
      tailStructureConfidence: (map['tsconf'] as num?)?.toDouble() ?? 0,
      vocalLikelihood: (map['vlike'] as num?)?.toDouble() ?? 0,
      vocalConfidence: (map['vconf'] as num?)?.toDouble() ?? 0,
      durationSeconds: (map['dur'] as num?)?.toDouble() ?? 0,
      camelotNumber: (map['kn'] as num?)?.toInt(),
      camelotMinor: map['km'] as bool?,
      keyConfidence: (map['kc'] as num?)?.toDouble() ?? 0,
      loudnessLufs: (map['lufs'] as num?)?.toDouble(),
      rmsDb: (map['rms'] as num?)?.toDouble(),
      centroidHz: (map['cen'] as num?)?.toDouble(),
      onsetRate: (map['on'] as num?)?.toDouble(),
      tailBpm: (map['tbpm'] as num?)?.toDouble(),
      tailBeatOffsetMs: (map['tbo'] as num?)?.toDouble(),
      introEnergy: (map['ie'] as num?)?.toDouble(),
      outroEnergy: (map['oe'] as num?)?.toDouble(),
      analyzedFraction: (map['af'] as num?)?.toDouble() ?? 0,
      tailAnalyzed: map['ta'] as bool? ?? false,
    );
  }
}

// ── Profiles ──────────────────────────────────────────────────────────────────

/// Sequencing personality — changes the weight balance of the transition cost
/// and the shape of the energy flow the engine plans while it orders tracks.
enum AutomixProfile {
  /// Beat DJ flow: tempo matching dominates, energy continuity secondary.
  dj,

  /// Harmonic mixing: Camelot key compatibility dominates (like a penthouse
  /// set), tempo and energy act as tie-breakers.
  harmonic,

  /// Energy arc: plans warm-up → peak → cooldown using normalized energy.
  energy;

  String get storageName => name;
}

// ── Settings ─────────────────────────────────────────────────────────────────

/// Full automix configuration. Persisted in SharedPreferences via
/// [AutomixService.loadSettings] / [AutomixService.saveSettings].
@immutable
class AutomixSettings {
  const AutomixSettings({
    this.profile = AutomixProfile.dj,
    this.bpmTolerancePercent = 6.0,
    this.crossfadeBeats = 16,
    this.avoidArtistRepeat = true,
    this.harmonicFilter = false,
  });

  /// [AutomixProfile] used to balance transition weights.
  final AutomixProfile profile;

  /// Maximum tempo distance (percent) for a transition to be considered
  /// "matched". Distances within tolerance are cheap; beyond it the cost
  /// ramps quadratically and large mismatches saturate.
  final double bpmTolerancePercent;

  /// Number of beats the transition crossfade should span (the engine
  /// converts this to seconds from the set's median BPM).
  final int crossfadeBeats;

  /// Penalize two consecutive tracks by the same artist so authored sets
  /// don't cluster one artist without moving through the collection.
  final bool avoidArtistRepeat;

  /// Hard-prefer transitions with compatible keys. `false` = key only
  /// infuences scoring (soft), `true` = out-of-key candidates get a heavy
  /// fixed penalty instead of their proportional cost.
  final bool harmonicFilter;

  AutomixSettings copyWith({
    AutomixProfile? profile,
    double? bpmTolerancePercent,
    int? crossfadeBeats,
    bool? avoidArtistRepeat,
    bool? harmonicFilter,
  }) => AutomixSettings(
    profile: profile ?? this.profile,
    bpmTolerancePercent: bpmTolerancePercent ?? this.bpmTolerancePercent,
    crossfadeBeats: crossfadeBeats ?? this.crossfadeBeats,
    avoidArtistRepeat: avoidArtistRepeat ?? this.avoidArtistRepeat,
    harmonicFilter: harmonicFilter ?? this.harmonicFilter,
  );

  Map<String, dynamic> toMap() => <String, dynamic>{
    'profile': profile.name,
    'bpmTolerance': bpmTolerancePercent,
    'beats': crossfadeBeats,
    'avoidArtistRepeat': avoidArtistRepeat,
    'harmonicFilter': harmonicFilter,
  };

  factory AutomixSettings.fromMap(Map<dynamic, dynamic> map) {
    return AutomixSettings(
      profile:
          AutomixProfile.values.asNameMap()[(map['profile'] as String?)] ??
          AutomixProfile.dj,
      bpmTolerancePercent: (map['bpmTolerance'] as num?)?.toDouble() ?? 6.0,
      crossfadeBeats: (map['beats'] as num?)?.toInt() ?? 16,
      avoidArtistRepeat: map['avoidArtistRepeat'] as bool? ?? true,
      harmonicFilter: map['harmonicFilter'] as bool? ?? false,
    );
  }
}

// ── Engine output ────────────────────────────────────────────────────────────

@immutable
class AutomixPlan {
  const AutomixPlan({
    required this.order,
    required this.crossfadeSeconds,
    required this.averageCost,
  });

  /// Indices (into the request order list) of the sequenced tracks —
  /// `plan.order[i]` is the index in the *input* list of the track that should
  /// play i-th. The first entry is the requested start track.
  final List<int> order;

  /// Crossfade duration (seconds) for the whole set, derived from the set's
  /// median BPM so that [ AutomixSettings.crossfadeBeats ] beats have a
  /// constant perceived length on average.
  final double crossfadeSeconds;

  /// Mean pairwise transition cost of the final sequence (0..1) — surfaced for
  /// diagnostics/logging.
  final double averageCost;
}

// ── Progress snapshot for the batch analysis run ─────────────────────────────

@immutable
class AutomixAnalysisProgress {
  const AutomixAnalysisProgress({
    this.done = 0,
    this.total = 0,
    this.failed = 0,
    this.running = false,
    this.cancelled = false,
    this.currentTitle = '',
  });

  final int done;
  final int total;
  final int failed;
  final bool running;
  final bool cancelled;
  final String currentTitle;

  bool get idle => !running && total == 0;
  bool get finished => !running && total > 0;

  AutomixAnalysisProgress copyWith({
    int? done,
    int? total,
    int? failed,
    bool? running,
    bool? cancelled,
    String? currentTitle,
  }) => AutomixAnalysisProgress(
    done: done ?? this.done,
    total: total ?? this.total,
    failed: failed ?? this.failed,
    running: running ?? this.running,
    cancelled: cancelled ?? this.cancelled,
    currentTitle: currentTitle ?? this.currentTitle,
  );
}
