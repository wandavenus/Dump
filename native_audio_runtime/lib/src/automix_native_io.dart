import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart' as pkg_ffi;

import '../native_audio_runtime_bindings_generated.dart' as bindings;
import 'automix_native_types.dart';

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
    final count = tracks.length;
    final trackAllocationCount = count < 1 ? 1 : count;
    final featureAllocationCount = count * 14 < 1 ? 1 : count * 14;
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
        ];
        for (var field = 0; field < values.length; field++) {
          features[i * 14 + field] = values[field] ?? double.nan;
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
        startIndex,
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
    if (pcm.isEmpty) return null;
    final samples = pkg_ffi.calloc<ffi.Float>(pcm.length);
    final output = pkg_ffi.calloc<ffi.Double>(11);
    try {
      for (var i = 0; i < pcm.length; i++) {
        samples[i] = pcm[i];
      }
      final status = bindings.nar_automix_analyze(
        samples,
        pcm.length,
        sampleRate,
        output,
        11,
      );
      if (status != 1) return null;
      double? nullable(int index) =>
          output[index].isFinite ? output[index] : null;
      final tonic = output[4].isFinite ? output[4].toInt() : -1;
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
      );
    } finally {
      pkg_ffi.calloc.free(samples);
      pkg_ffi.calloc.free(output);
    }
  }
}
