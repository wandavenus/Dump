#include "ebur128_analyzer.h"

#include <cmath>

namespace replaygain {

namespace {
// ReplayGain 2.0 / EBU R128 reference levels.
constexpr double kReplayGainReferenceLufs = -18.0;
constexpr double kR128ReferenceLufs       = -23.0;
}  // namespace

void EburAnalyzer::StateDeleter::operator()(ebur128_state* s) const {
    if (s != nullptr) {
        ebur128_state* mutable_s = s;
        ebur128_destroy(&mutable_s);
    }
}

EburAnalyzer::EburAnalyzer(ebur128_state* state, uint32_t channels)
    : state_(state), channels_(channels) {}

EburAnalyzer::~EburAnalyzer() = default;

std::unique_ptr<EburAnalyzer> EburAnalyzer::Create(uint32_t sample_rate, uint32_t channels) {
    if (sample_rate == 0 || channels == 0 || channels > 8) return nullptr;

    const int mode = EBUR128_MODE_I          // integrated loudness
                    | EBUR128_MODE_LRA        // loudness range
                    | EBUR128_MODE_TRUE_PEAK  // oversampled true peak (dBTP)
                    | EBUR128_MODE_SAMPLE_PEAK
                    | EBUR128_MODE_HISTOGRAM; // reduces memory vs. storing every block

    ebur128_state* state = ebur128_init(channels, sample_rate, static_cast<unsigned>(mode));
    if (state == nullptr) return nullptr;

    return std::unique_ptr<EburAnalyzer>(new EburAnalyzer(state, channels));
}

bool EburAnalyzer::AddFramesShort(const int16_t* buf, size_t frame_count) {
    if (state_ == nullptr || frame_count == 0) return true;
    return ebur128_add_frames_short(state_.get(), buf, frame_count) == EBUR128_SUCCESS;
}

bool EburAnalyzer::AddFramesFloat(const float* buf, size_t frame_count) {
    if (state_ == nullptr || frame_count == 0) return true;
    return ebur128_add_frames_float(state_.get(), buf, frame_count) == EBUR128_SUCCESS;
}

LoudnessResult EburAnalyzer::Finish() {
    LoudnessResult result;
    if (state_ == nullptr) return result;

    double integrated = -HUGE_VAL;
    if (ebur128_loudness_global(state_.get(), &integrated) != EBUR128_SUCCESS) {
        return result;
    }

    double lra = 0.0;
    ebur128_loudness_range(state_.get(), &lra);  // non-fatal if unsupported

    double max_true_peak = -HUGE_VAL;
    double max_sample_peak = -HUGE_VAL;
    for (uint32_t ch = 0; ch < channels_; ch++) {
        double tp = 0.0;
        if (ebur128_true_peak(state_.get(), ch, &tp) == EBUR128_SUCCESS) {
            const double tp_db = (tp > 0.0) ? 20.0 * std::log10(tp) : -HUGE_VAL;
            if (tp_db > max_true_peak) max_true_peak = tp_db;
        }
        double sp = 0.0;
        if (ebur128_sample_peak(state_.get(), ch, &sp) == EBUR128_SUCCESS) {
            const double sp_db = (sp > 0.0) ? 20.0 * std::log10(sp) : -HUGE_VAL;
            if (sp_db > max_sample_peak) max_sample_peak = sp_db;
        }
    }

    result.integrated_lufs     = integrated;
    result.loudness_range_lu   = lra;
    result.true_peak_dbtp      = max_true_peak;
    result.sample_peak_dbfs    = max_sample_peak;
    result.recommended_gain_db = LufsToReplayGainDb(integrated);
    result.valid                = std::isfinite(integrated);
    return result;
}

double ComputeAlbumLoudness(const std::vector<ebur128_state*>& states) {
    if (states.empty()) return -HUGE_VAL;

    double album_loudness = -HUGE_VAL;
    const int rc = ebur128_loudness_global_multiple(
        const_cast<ebur128_state**>(states.data()), states.size(), &album_loudness);
    if (rc != EBUR128_SUCCESS) return -HUGE_VAL;
    return album_loudness;
}

double LufsToReplayGainDb(double integrated_lufs) {
    if (!std::isfinite(integrated_lufs)) return 0.0;
    return kReplayGainReferenceLufs - integrated_lufs;
}

int32_t LufsToR128Q7_8(double integrated_lufs) {
    if (!std::isfinite(integrated_lufs)) return 0;
    // R128_TRACK_GAIN / R128_ALBUM_GAIN per the Opus/xiph spec: signed Q7.8
    // fixed point (256 = 1 dB), gain relative to -23 LUFS reference.
    const double gain_db = kR128ReferenceLufs - integrated_lufs;
    const double q7_8 = std::lround(gain_db * 256.0);
    // Clamp to int16 range — the tag field is a 16-bit signed integer.
    if (q7_8 > 32767.0) return 32767;
    if (q7_8 < -32768.0) return -32768;
    return static_cast<int32_t>(q7_8);
}

}  // namespace replaygain
