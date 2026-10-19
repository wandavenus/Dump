// Native AutoMix core: PCM feature extraction and deterministic set planning.
#ifndef NAR_AUTOMIX_NATIVE_H_
#define NAR_AUTOMIX_NATIVE_H_

#include <stdint.h>

#include "native_audio_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

#define NAR_AUTOMIX_FEATURE_COUNT 23
#define NAR_AUTOMIX_KEY_FIELD_COUNT 2
#define NAR_AUTOMIX_ANALYSIS_VALUE_COUNT 32

// Structural region classification labels.
enum NarAutomixStructureRegion {
  NAR_AUTOMIX_STRUCTURE_UNKNOWN = 0,
  NAR_AUTOMIX_STRUCTURE_LOW_ACTIVITY = 1,
  NAR_AUTOMIX_STRUCTURE_BUILDUP = 2,
  NAR_AUTOMIX_STRUCTURE_DROP = 3,
  NAR_AUTOMIX_STRUCTURE_BREAKDOWN = 4,
  NAR_AUTOMIX_STRUCTURE_STABLE_HIGH = 5,
};

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
  NAR_AUTOMIX_VOCAL_LIKELIHOOD = 14,
  NAR_AUTOMIX_VOCAL_CONFIDENCE = 15,
  // Section structure at the mix seam: the outgoing track's tail region and
  // the incoming track's head region, each with its own confidence. The
  // region fields carry the enum NarAutomixStructureRegion value as a double
  // and are NAN when the window was not analyzed or had no confident label.
  NAR_AUTOMIX_STRUCTURE_REGION = 16,
  NAR_AUTOMIX_STRUCTURE_CONFIDENCE = 17,
  NAR_AUTOMIX_TAIL_STRUCTURE_REGION = 18,
  NAR_AUTOMIX_TAIL_STRUCTURE_CONFIDENCE = 19,
  // Coarse energy trend at the mix seam, in dB per quarter window (the
  // analyzer publishes per-quarter RMS medians; the caller differences the
  // first two and last two quarters). Positive means the section is building.
  // NAN when the window did not produce a complete quarter profile.
  NAR_AUTOMIX_INTRO_SLOPE = 20,
  NAR_AUTOMIX_OUTRO_SLOPE = 21,
  // Confidence for NAR_AUTOMIX_TAIL_BPM; appended to preserve existing slots.
  NAR_AUTOMIX_TAIL_BPM_CONFIDENCE = 22,
};

// Key fields per track: [Camelot number (0 means unknown), mode
// (-1 unknown, 0 major, 1 minor)].
//
// Analysis values (NAR_AUTOMIX_ANALYSIS_VALUE_COUNT = 28):
//  0: BPM (NaN when unknown)
//  1: BPM confidence (0..1)
//  2: Alternate BPM (NaN when unknown)
//  3: Beat offset ms (NaN when unknown)
//  4: Tonic pitch class (-1 unknown, 0..11)
//  5: isMinor (0 = major, 1 = minor)
//  6: Key confidence (0..1)
//  7: RMS dBFS (active frame median)
//  8: Spectral centroid Hz (active frame median)
//  9: Onset rate (onsets/sec)
// 10: Analyzed duration in seconds
// 11: Confident 16-beat phrase-start offset ms (NaN when unknown)
// 12: Drop cue ms (NaN when unknown)
// 13: Breakdown cue ms (NaN when unknown)
// 14: Drop confidence (0..1)
// 15: Breakdown confidence (0..1)
// 16: Structure region (enum NarAutomixStructureRegion 0..5)
// 17: Structure confidence (0..1)
// 18: Vocal likelihood (0..1)
// 19: Vocal confidence (0..1)
// 20: Tail BPM confidence (0..1); confidence of this analyzed window's tempo estimate
// 21: Start-quarter BPM (NaN when unknown); first quarter's own tempo estimate
// 22: End-quarter BPM (NaN when unknown); last quarter's own tempo estimate
// 23: Tempo stability (0..1, NaN when unknown); mean octave-folded agreement of the quarter-window tempo estimates with the whole-window estimate
// 24: First-quarter RMS dBFS (median of the quarter's frames)
// 25: Second-quarter RMS dBFS
// 26: Third-quarter RMS dBFS
// 27: Fourth-quarter RMS dBFS
// 28: Start-quarter BPM confidence (0..1; NaN if not estimated)
// 29: End-quarter BPM confidence (0..1; NaN if not estimated)
// 30: Start-quarter beat phase, relative to the window start and folded to
//      the start-quarter beat period (NaN if phase is unavailable)
// 31: End-quarter beat phase, relative to the window start and folded to
//      the end-quarter beat period (NaN if phase is unavailable)
// The quarter profile is a coarse energy trend (rising/falling intro and
// outro). Consumers derive per-seam slopes from adjacent quarters; silence
// floors at -120 dBFS, so the values stay finite whenever analysis succeeds.
FFI_PLUGIN_EXPORT int32_t nar_automix_analyze(
    const float* mono,
    int32_t sample_count,
    int32_t sample_rate,
    double* output,
    int32_t output_count);

// Variant used by the Android stereo bridge. `center_ratio` is the source
// mix's center-channel power divided by center-plus-side power, in [0,1].
// Pass NAN when the source is mono or the ratio is unavailable; the analyzer
// then falls back to the mono vocal estimate without center-channel evidence.
FFI_PLUGIN_EXPORT int32_t nar_automix_analyze_centered(
    const float* mono,
    int32_t sample_count,
    int32_t sample_rate,
    double center_ratio,
    double* output,
    int32_t output_count);

// Analyzes time-local chord progression into rows of four doubles:
// [window_start_ms, root_pitch_class (or -1), quality_id (or -1), confidence].
// Quality ids: 0 major, 1 minor, 2 diminished, 3 augmented, 4 dominant 7,
// 5 major 7, 6 minor 7, 7 suspended 4, 8 suspended 2, 9 half-diminished 7,
// 10 diminished 7, 11 augmented 7. Unknown chords use -1/-1/0.
// Returns rows written, 0 when the window is too short, or -1 for invalid input.
FFI_PLUGIN_EXPORT int32_t nar_automix_analyze_chords(
    const float* mono, int32_t sample_count, int32_t sample_rate,
    double* output, int32_t output_capacity);

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
