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
    this.beatOffsetMs,
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

  /// Dominant-beat phase **relative to the window start** (ms).
  final double? beatOffsetMs;

  final int? camelotNumber;
  final bool? camelotMinor;
  final double keyConfidence;

  final double? rmsDb;
  final double? centroidHz;
  final double? onsetRate;
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
    this.introEnergy,
    this.outroEnergy,
    this.analyzedFraction = 0,
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

  // ── Serialization (SharedPreferences JSON) ─────────────────────────────────

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': songId,
    'title': title,
    'artist': artist,
    if (bpm != null) 'bpm': bpm,
    'bc': bpmConfidence,
    if (alternateBpm != null) 'alt': alternateBpm,
    if (beatOffsetMs != null) 'bo': beatOffsetMs,
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
