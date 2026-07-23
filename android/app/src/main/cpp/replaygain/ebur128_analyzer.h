#ifndef REPLAYGAIN_EBUR128_ANALYZER_H
#define REPLAYGAIN_EBUR128_ANALYZER_H

#include <cstdint>
#include <memory>
#include <vector>

extern "C" {
#include <ebur128.h>
}

namespace replaygain {

// Result of a single-track EBU R128 analysis.
struct LoudnessResult {
    double integrated_lufs   = -HUGE_VAL;  // Integrated (program) loudness.
    double loudness_range_lu = 0.0;        // LRA — loudness range, in LU.
    double true_peak_dbtp    = -HUGE_VAL;  // Max true peak across channels, dBTP.
    double sample_peak_dbfs  = -HUGE_VAL;  // Max sample peak across channels, dBFS.
    double recommended_gain_db = 0.0;      // ReplayGain relative to -18 LUFS reference.
    bool   valid = false;
};

// Thin RAII wrapper around a single `ebur128_state*`.
//
// One instance is created per track being scanned. PCM is streamed in via
// AddFramesShort/AddFramesFloat as it's decoded (MediaCodec output buffers
// arrive in chunks — we never need the whole file in memory). Call Finish()
// once to compute the single-track result.
//
// For ALBUM gain, keep every track's EburAnalyzer alive (don't call Finish's
// disposal) until the whole album has been scanned, then pass their raw
// `ebur128_state*` handles to ComputeAlbumLoudness().
class EburAnalyzer {
public:
    // sample_rate: PCM sample rate in Hz. channels: 1-8 (matches libebur128's
    // supported channel count ceiling for standard surround layouts).
    // Returns nullptr if libebur128 rejects the parameters (e.g. unsupported
    // channel count or non-positive sample rate).
    static std::unique_ptr<EburAnalyzer> Create(uint32_t sample_rate, uint32_t channels);

    ~EburAnalyzer();

    EburAnalyzer(const EburAnalyzer&) = delete;
    EburAnalyzer& operator=(const EburAnalyzer&) = delete;

    // Feeds interleaved 16-bit PCM. frame_count = samples-per-channel in buf.
    // Returns false if libebur128 reported an internal error for this chunk.
    bool AddFramesShort(const int16_t* buf, size_t frame_count);

    // Feeds interleaved float PCM in [-1.0, 1.0].
    bool AddFramesFloat(const float* buf, size_t frame_count);

    // Finalizes and returns the single-track loudness result. Safe to call
    // multiple times (idempotent) but subsequent AddFrames calls after this
    // are still valid — libebur128 keeps accumulating.
    LoudnessResult Finish();

    // Exposes the raw handle for album-level multi-track aggregation.
    ebur128_state* raw_state() const { return state_.get(); }

    // FIX Temuan #5 (LOW): expose the channel count so JNI callers can
    // validate that a supplied frame_count doesn't cause AddFramesShort()
    // to read past the end of the provided array.
    uint32_t ChannelCount() const { return channels_; }

private:
    explicit EburAnalyzer(ebur128_state* state, uint32_t channels);

    struct StateDeleter {
        void operator()(ebur128_state* s) const;
    };
    std::unique_ptr<ebur128_state, StateDeleter> state_;
    uint32_t channels_ = 0;
};

// Computes the album-level integrated loudness across multiple already-fed
// EburAnalyzer instances (per ITU-R BS.1770-4 / EBU Tech 3341 album mode:
// gate + average track loudness across all tracks, not simple concatenation).
// Returns -HUGE_VAL if `states` is empty or all measurements were below the
// absolute gate.
double ComputeAlbumLoudness(const std::vector<ebur128_state*>& states);

// dB helpers shared by the JNI layer and tag_writer.
double LufsToReplayGainDb(double integrated_lufs);      // relative to -18 LUFS
int32_t LufsToR128Q7_8(double integrated_lufs);         // relative to -23 LUFS, Q7.8 fixed point

}  // namespace replaygain

#endif  // REPLAYGAIN_EBUR128_ANALYZER_H
