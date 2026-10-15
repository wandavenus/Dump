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
}

typedef NativeAutomixPcm = Float32List;
