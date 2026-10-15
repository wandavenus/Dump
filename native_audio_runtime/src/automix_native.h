// Native AutoMix core: PCM feature extraction and deterministic set planning.
#ifndef NAR_AUTOMIX_NATIVE_H_
#define NAR_AUTOMIX_NATIVE_H_

#include <stdint.h>

#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

#define NAR_AUTOMIX_FEATURE_COUNT 14
#define NAR_AUTOMIX_KEY_FIELD_COUNT 2
#define NAR_AUTOMIX_ANALYSIS_VALUE_COUNT 11

// Flattened feature row order. A missing double is represented by NAN.
enum NarAutomixFeatureIndex {
  NAR_AUTOMIX_BPM = 0,
  NAR_AUTOMIX_BPM_CONFIDENCE = 1,
  NAR_AUTOMIX_ALTERNATE_BPM = 2,
  NAR_AUTOMIX_BEAT_OFFSET_MS = 3,
  NAR_AUTOMIX_KEY_CONFIDENCE = 4,
  NAR_AUTOMIX_LOUDNESS_LUFS = 5,
  NAR_AUTOMIX_RMS_DB = 6,
  NAR_AUTOMIX_CENTROID_HZ = 7,
  NAR_AUTOMIX_ONSET_RATE = 8,
  NAR_AUTOMIX_TAIL_BPM = 9,
  NAR_AUTOMIX_TAIL_BEAT_OFFSET_MS = 10,
  NAR_AUTOMIX_INTRO_ENERGY = 11,
  NAR_AUTOMIX_OUTRO_ENERGY = 12,
  NAR_AUTOMIX_ANALYZED_FRACTION = 13,
};

// Key fields per track: [Camelot number (0 means unknown), mode
// (-1 unknown, 0 major, 1 minor)].
//
// Analysis values: [BPM (NaN when unknown), BPM confidence, alternate BPM,
// beat offset ms, tonic pitch class (-1 unknown), isMinor (0/1), key
// confidence, RMS dBFS, spectral centroid Hz, onset rate, analyzed seconds].
FFI_PLUGIN_EXPORT int32_t nar_automix_analyze(
    const float* mono,
    int32_t sample_count,
    int32_t sample_rate,
    double* output,
    int32_t output_count);

// Profiles: 0 = DJ, 1 = harmonic, 2 = energy.
// `features` is row-major [track_count][NAR_AUTOMIX_FEATURE_COUNT], `keys` is
// row-major [track_count][NAR_AUTOMIX_KEY_FIELD_COUNT]. Song IDs break ties;
// artist groups are caller-assigned IDs after trim/lowercase normalization.
// Returns 1 on success; outputs plan indices and metrics [fade seconds,
// average transition cost].
FFI_PLUGIN_EXPORT int32_t nar_automix_plan_set(
    const int64_t* song_ids,
    const int32_t* artist_groups,
    const double* features,
    const int32_t* keys,
    int32_t track_count,
    int32_t profile,
    double bpm_tolerance,
    int32_t crossfade_beats,
    int32_t avoid_artist_repeat,
    int32_t harmonic_filter,
    int32_t start_index,
    int32_t* output_order,
    double* output_metrics,
    int32_t output_metrics_count);

#ifdef __cplusplus
}
#endif

#endif  // NAR_AUTOMIX_NATIVE_H_
