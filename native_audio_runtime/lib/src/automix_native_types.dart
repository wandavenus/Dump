import 'dart:typed_data';

/// Input features used by the native AutoMix sequencing core.
class NativeAutomixTrack {
  const NativeAutomixTrack({
    required this.songId,
    this.artistGroup = 0,
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
    this.vocalLikelihood = 0,
    this.vocalConfidence = 0,
    this.tailBpmConfidence = 0,
    this.startBpm,
    this.startBpmConfidence = 0,
    this.introTempoStability,
    this.outroTempoStability,
    this.structureRegion = 0,
    this.structureConfidence = 0,
    this.tailStructureRegion = 0,
    this.tailStructureConfidence = 0,
    this.introSlope,
    this.outroSlope,
  });

  final int songId;
  final int artistGroup;
  final double? bpm;
  final double bpmConfidence;
  final double? alternateBpm;
  final double? beatOffsetMs;
  final int? camelotNumber;
  final bool? camelotMinor;
  final double keyConfidence;
  final double? loudnessLufs;
  final double? rmsDb;
  final double? centroidHz;
  final double? onsetRate;
  final double? tailBpm;
  final double? tailBeatOffsetMs;
  final double? introEnergy;
  final double? outroEnergy;
  final double analyzedFraction;
  final double vocalLikelihood;
  final double vocalConfidence;
  final double tailBpmConfidence;

  /// Confident local tempo estimate of the intro edge.
  final double? startBpm;
  final double startBpmConfidence;
  final double? introTempoStability;
  final double? outroTempoStability;

  /// Section region of the analyzed head window
  /// (NarAutomixStructureRegion; 0 means unknown).
  final int structureRegion;
  final double structureConfidence;

  /// Section region of the analyzed exit (tail) window.
  final int tailStructureRegion;
  final double tailStructureConfidence;

  /// Coarse energy trend in dB per quarter window at the head (first two
  /// quarters) and exit (last two). Positive means building.
  final double? introSlope;
  final double? outroSlope;
}

class NativeAutomixPlan {
  const NativeAutomixPlan({
    required this.order,
    required this.crossfadeSeconds,
    required this.averageCost,
  });

  final List<int> order;
  final double crossfadeSeconds;
  final double averageCost;
}

/// Result fields from native AutoMix audio feature extraction.
class NativeAutomixAnalysis {
  const NativeAutomixAnalysis({
    required this.bpm,
    required this.bpmConfidence,
    required this.alternateBpm,
    required this.beatOffsetMs,
    required this.tonicPitchClass,
    required this.isMinor,
    required this.keyConfidence,
    required this.rmsDb,
    required this.centroidHz,
    required this.onsetRate,
    required this.analyzedSeconds,
    this.downbeatOffsetMs,
    this.dropCueMs,
    this.breakdownCueMs,
    this.dropConfidence = 0,
    this.breakdownConfidence = 0,
    this.structureRegion = 0,
    this.structureConfidence = 0,
    this.vocalLikelihood = 0,
    this.vocalConfidence = 0,
    this.tailBpmConfidence = 0,
    this.startBpm,
    this.endBpm,
    this.tempoStability,
    this.startBpmConfidence,
    this.endBpmConfidence,
    this.startBeatOffsetMs,
    this.endBeatOffsetMs,
    this.energyQuarters = const <double>[],
  });

  final double? bpm;
  final double bpmConfidence;
  final double? alternateBpm;
  final double? beatOffsetMs;
  final int? tonicPitchClass;
  final bool isMinor;
  final double keyConfidence;
  final double? rmsDb;
  final double? centroidHz;
  final double onsetRate;
  final double analyzedSeconds;
  final double? downbeatOffsetMs;
  final double? dropCueMs;
  final double? breakdownCueMs;
  final double dropConfidence;
  final double breakdownConfidence;
  final int structureRegion;
  final double structureConfidence;
  final double vocalLikelihood;
  final double vocalConfidence;
  final double tailBpmConfidence;

  /// Tempo-curve hints: first/last quarter BPM and 0..1 quarter-window
  /// stability relative to the whole-window tempo estimate.
  final double? startBpm;
  final double? endBpm;
  final double? tempoStability;
  final double? startBpmConfidence;
  final double? endBpmConfidence;
  final double? startBeatOffsetMs;
  final double? endBeatOffsetMs;

  /// Median RMS dBFS of each quarter of the analyzed window, in time order.
  /// Empty when any slot was not finite (an incomplete profile is unusable).
  final List<double> energyQuarters;
}

typedef NativeAutomixPcm = Float32List;
