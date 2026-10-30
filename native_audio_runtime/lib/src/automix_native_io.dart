import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart' as pkg_ffi;

import '../native_audio_runtime_bindings_generated.dart' as bindings;
import 'automix_native_types.dart';

// Must match NAR_AUTOMIX_ANALYSIS_VALUE_COUNT in src/automix_native.h.
const int _analysisOutputCount = 35;
const int _featureCount = 27;

/// Synchronous FFI facade over the AutoMix native C core.
class NativeAutomix {
  NativeAutomix._();

  static NativeAutomixPlan planSet({
    required List<NativeAutomixTrack> tracks,
    required int profile,
    required double bpmTolerance,
    required int crossfadeBeats,
    required bool avoidArtistRepeat,
    required bool harmonicFilter,
    required int startIndex,
  }) {
    if (tracks.isEmpty) {
      return const NativeAutomixPlan(
        order: [],
        crossfadeSeconds: 0,
        averageCost: 0,
      );
    }
    final count = tracks.length;
    final safeStartIndex = startIndex.clamp(0, count - 1);
    final trackAllocationCount = count < 1 ? 1 : count;
    final featureAllocationCount = count * _featureCount < 1
        ? 1
        : count * _featureCount;
    final keyAllocationCount = count * 2 < 1 ? 1 : count * 2;
    final ids = pkg_ffi.calloc<ffi.Int64>(trackAllocationCount);
    final artists = pkg_ffi.calloc<ffi.Int32>(trackAllocationCount);
    final features = pkg_ffi.calloc<ffi.Double>(featureAllocationCount);
    final keys = pkg_ffi.calloc<ffi.Int32>(keyAllocationCount);
    final order = pkg_ffi.calloc<ffi.Int32>(trackAllocationCount);
    final metrics = pkg_ffi.calloc<ffi.Double>(2);
    try {
      for (var i = 0; i < count; i++) {
        final track = tracks[i];
        ids[i] = track.songId;
        artists[i] = track.artistGroup;
        final values = <double?>[
          track.bpm,
          track.bpmConfidence,
          track.alternateBpm,
          track.beatOffsetMs,
          track.keyConfidence,
          track.loudnessLufs,
          track.rmsDb,
          track.centroidHz,
          track.onsetRate,
          track.tailBpm,
          track.tailBeatOffsetMs,
          track.introEnergy,
          track.outroEnergy,
          track.analyzedFraction,
          track.vocalLikelihood,
          track.vocalConfidence,
          track.structureRegion > 0 ? track.structureRegion.toDouble() : null,
          track.structureConfidence,
          track.tailStructureRegion > 0
              ? track.tailStructureRegion.toDouble()
              : null,
          track.tailStructureConfidence,
          track.introSlope,
          track.outroSlope,
          track.tailBpmConfidence,
          track.startBpm,
          track.startBpmConfidence,
          track.introTempoStability,
          track.outroTempoStability,
        ];
        for (var field = 0; field < values.length; field++) {
          features[i * _featureCount + field] = values[field] ?? double.nan;
        }
        keys[i * 2] = track.camelotNumber ?? 0;
        keys[i * 2 + 1] = track.camelotMinor == null
            ? -1
            : track.camelotMinor!
            ? 1
            : 0;
      }
      final status = bindings.nar_automix_plan_set(
        ids,
        artists,
        features,
        keys,
        count,
        profile,
        bpmTolerance,
        crossfadeBeats,
        avoidArtistRepeat ? 1 : 0,
        harmonicFilter ? 1 : 0,
        safeStartIndex,
        order,
        metrics,
        2,
      );
      if (status != 1) {
        throw StateError('Native AutoMix planner failed (status $status)');
      }
      return NativeAutomixPlan(
        order: List<int>.generate(count, (i) => order[i], growable: false),
        crossfadeSeconds: metrics[0],
        averageCost: metrics[1],
      );
    } finally {
      pkg_ffi.calloc.free(ids);
      pkg_ffi.calloc.free(artists);
      pkg_ffi.calloc.free(features);
      pkg_ffi.calloc.free(keys);
      pkg_ffi.calloc.free(order);
      pkg_ffi.calloc.free(metrics);
    }
  }

  /// Analyze mono float32 PCM. The app's Android decoder uses the JNI entry
  /// point into this same C function; this FFI entry is useful for host tests.
  static NativeAutomixAnalysis? analyze(NativeAutomixPcm pcm, int sampleRate) {
    if (pcm.isEmpty || sampleRate <= 0) return null;
    final samples = pkg_ffi.calloc<ffi.Float>(pcm.length);
    final output = pkg_ffi.calloc<ffi.Double>(_analysisOutputCount);
    try {
      for (var i = 0; i < pcm.length; i++) {
        samples[i] = pcm[i];
      }
      final status = bindings.nar_automix_analyze(
        samples,
        pcm.length,
        sampleRate,
        output,
        _analysisOutputCount,
      );
      if (status != 1) return null;
      double? nullable(int index) =>
          output[index].isFinite ? output[index] : null;
      final tonic = output[4].isFinite ? output[4].toInt() : -1;
      final quarters = <double>[
        for (var index = 24; index < 28; index++) output[index],
      ];
      return NativeAutomixAnalysis(
        bpm: nullable(0),
        bpmConfidence: output[1],
        alternateBpm: nullable(2),
        beatOffsetMs: nullable(3),
        tonicPitchClass: tonic < 0 ? null : tonic,
        isMinor: output[5] > 0.5,
        keyConfidence: output[6],
        rmsDb: nullable(7),
        centroidHz: nullable(8),
        onsetRate: output[9],
        analyzedSeconds: output[10],
        downbeatOffsetMs: nullable(11),
        dropCueMs: nullable(12),
        breakdownCueMs: nullable(13),
        dropConfidence: output[14],
        breakdownConfidence: output[15],
        structureRegion: output[16].toInt(),
        structureConfidence: output[17],
        vocalLikelihood: output[18],
        vocalConfidence: output[19],
        tailBpmConfidence: output[20],
        startBpm: nullable(21),
        endBpm: nullable(22),
        tempoStability: nullable(23),
        startBpmConfidence: nullable(28),
        endBpmConfidence: nullable(29),
        startBeatOffsetMs: nullable(30),
        endBeatOffsetMs: nullable(31),
        meter: output[32].isFinite && output[32] >= 3 && output[32] <= 6
            ? output[32].toInt()
            : null,
        sectionCueMs: nullable(33),
        sectionCueConfidence: output[34].isFinite ? output[34] : 0,
        energyQuarters: quarters.every((value) => value.isFinite)
            ? quarters
            : const <double>[],
      );
    } finally {
      pkg_ffi.calloc.free(samples);
      pkg_ffi.calloc.free(output);
    }
  }
}
