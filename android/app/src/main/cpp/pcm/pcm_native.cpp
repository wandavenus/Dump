// ─────────────────────────────────────────────────────────────────────────────
// pcm_native — implementation.
//
// The sample-domain path is deliberately self-contained: no Media3, JNI or
// Android headers live here. That makes the DSP testable on the host and keeps
// the JNI bridge a thin validation layer.
//
// ARM64 NEON coverage:
//   • U8 / S16 / S32 / F32 decoder formats (stereo and mono)
//   • stereo bus summation with a per-frame gain ramp
//   • non-finite sanitisation before the limiter
//   • windowed-sinc resampler history/coefficient math (scalar, branch-free
//     inner loop; the expensive format conversions around it are vectorised)
// ─────────────────────────────────────────────────────────────────────────────

#include "pcm_native.h"

#include <algorithm>
#include <cfloat>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <new>
#include <vector>

#if defined(__aarch64__)
#include <arm_neon.h>
#endif

namespace {

constexpr int kMaxChannels = 8;
constexpr int kBusChannels = NAR_PCM_BUS_CHANNELS;
constexpr int kDefaultTaps = 32;
constexpr int kDefaultPhases = 256;
// Typical Media3/FFmpeg decoder buffers are far smaller than this. Reserving
// up front keeps the first rendered block allocation-free; larger blocks grow
// the vector once and then stay at that high-water mark.
constexpr int kInitialInputFrames = 8192;
constexpr double kPi = 3.14159265358979323846264338327950288;
constexpr float kLimiterCeiling = 0.98f;
constexpr float kLimiterReleaseMs = 50.0f;
constexpr float kGainSmoothingMs = 12.0f;

inline bool is_finite(float value) {
    return std::isfinite(value);
}

inline float sanitize(float value) {
    return is_finite(value) ? value : 0.0f;
}

inline float clamp_sample(float value) {
    if (value > 8.0f) return 8.0f;
    if (value < -8.0f) return -8.0f;
    return value;
}

inline uint32_t load_u32_le(const uint8_t* p) {
    return static_cast<uint32_t>(p[0]) |
           (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) |
           (static_cast<uint32_t>(p[3]) << 24);
}

inline uint32_t load_u32_be(const uint8_t* p) {
    return (static_cast<uint32_t>(p[0]) << 24) |
           (static_cast<uint32_t>(p[1]) << 16) |
           (static_cast<uint32_t>(p[2]) << 8) |
           static_cast<uint32_t>(p[3]);
}

inline uint64_t load_u64_le(const uint8_t* p) {
    return static_cast<uint64_t>(load_u32_le(p)) |
           (static_cast<uint64_t>(load_u32_le(p + 4)) << 32);
}

inline uint64_t load_u64_be(const uint8_t* p) {
    return (static_cast<uint64_t>(load_u32_be(p)) << 32) |
           static_cast<uint64_t>(load_u32_be(p + 4));
}

inline float load_sample(const uint8_t* p, int format, bool big_endian) {
    switch (format) {
        case NAR_PCM_U8:
            return (static_cast<float>(*p) - 128.0f) * (1.0f / 128.0f);
        case NAR_PCM_S16: {
            const uint16_t raw = big_endian
                ? static_cast<uint16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1])
                : static_cast<uint16_t>((static_cast<uint16_t>(p[1]) << 8) | p[0]);
            return static_cast<float>(static_cast<int16_t>(raw)) * (1.0f / 32768.0f);
        }
        case NAR_PCM_S24: {
            const uint32_t b0 = p[0];
            const uint32_t b1 = p[1];
            const uint32_t b2 = p[2];
            const uint32_t raw = big_endian
                ? ((b0 << 16) | (b1 << 8) | b2)
                : ((b2 << 16) | (b1 << 8) | b0);
            const int32_t signed_value = (raw & 0x00800000u) != 0
                ? static_cast<int32_t>(raw | 0xFF000000u)
                : static_cast<int32_t>(raw);
            return static_cast<float>(signed_value) * (1.0f / 8388608.0f);
        }
        case NAR_PCM_S32: {
            const uint32_t raw = big_endian ? load_u32_be(p) : load_u32_le(p);
            return static_cast<float>(static_cast<int32_t>(raw)) *
                   (1.0f / 2147483648.0f);
        }
        case NAR_PCM_F32: {
            const uint32_t raw = big_endian ? load_u32_be(p) : load_u32_le(p);
            float value = 0.0f;
            std::memcpy(&value, &raw, sizeof(value));
            return sanitize(value);
        }
        case NAR_PCM_F64: {
            const uint64_t raw = big_endian ? load_u64_be(p) : load_u64_le(p);
            double value = 0.0;
            std::memcpy(&value, &raw, sizeof(value));
            return sanitize(static_cast<float>(value));
        }
        default:
            return 0.0f;
    }
}

inline int bytes_per_sample(int format) {
    switch (format) {
        case NAR_PCM_U8: return 1;
        case NAR_PCM_S16: return 2;
        case NAR_PCM_S24: return 3;
        case NAR_PCM_S32: return 4;
        case NAR_PCM_F32: return 4;
        case NAR_PCM_F64: return 8;
        default: return 0;
    }
}

inline float gain_step(float current, float target, float coefficient) {
    return current + (target - current) * coefficient;
}

inline float safe_target(float value) {
    if (!is_finite(value)) return 1.0f;
    if (value < 0.0f) return 0.0f;
    if (value > 1.0f) return 1.0f;
    return value;
}

#if defined(__aarch64__)
inline float32x4_t sanitize_finite_neon(float32x4_t value) {
    const float32x4_t limit = vdupq_n_f32(FLT_MAX);
    const uint32x4_t finite = vcleq_f32(vabsq_f32(value), limit);
    return vbslq_f32(finite, value, vdupq_n_f32(0.0f));
}

inline float32x4_t s16_to_f32(int16x4_t value) {
    return vcvtq_f32_s32(vmovl_s16(value));
}

inline float32x4_t s32_to_f32(int32x4_t value) {
    return vcvtq_f32_s32(value);
}
#endif

// ── Format conversion ────────────────────────────────────────────────────────

void convert_u8(const uint8_t* src, int frames, int channels, float* dst) {
    [[maybe_unused]] const int samples = frames * channels;
#if defined(__aarch64__)
    if (channels == 2) {
        const float32x4_t scale = vdupq_n_f32(1.0f / 128.0f);
        const float32x4_t midpoint = vdupq_n_f32(128.0f);
        int i = 0;
        for (; i + 8 <= samples; i += 8) {
            const uint8x8_t raw = vld1_u8(src + i);
            const uint16x8_t wide = vmovl_u8(raw);
            const float32x4_t lo = vcvtq_f32_u32(vmovl_u16(vget_low_u16(wide)));
            const float32x4_t hi = vcvtq_f32_u32(vmovl_u16(vget_high_u16(wide)));
            vst1q_f32(dst + i, vmulq_f32(vsubq_f32(lo, midpoint), scale));
            vst1q_f32(dst + i + 4, vmulq_f32(vsubq_f32(hi, midpoint), scale));
        }
        for (; i < samples; ++i) {
            dst[i] = (static_cast<float>(src[i]) - 128.0f) * (1.0f / 128.0f);
        }
        return;
    }
    if (channels == 1) {
        const float32x4_t scale = vdupq_n_f32(1.0f / 128.0f);
        const float32x4_t midpoint = vdupq_n_f32(128.0f);
        int frame = 0;
        for (; frame + 8 <= frames; frame += 8) {
            const uint8x8_t raw = vld1_u8(src + frame);
            const uint16x8_t wide = vmovl_u8(raw);
            float32x4_t lo = vcvtq_f32_u32(vmovl_u16(vget_low_u16(wide)));
            float32x4_t hi = vcvtq_f32_u32(vmovl_u16(vget_high_u16(wide)));
            lo = vmulq_f32(vsubq_f32(lo, midpoint), scale);
            hi = vmulq_f32(vsubq_f32(hi, midpoint), scale);
            const float32x4x2_t left = {lo, lo};
            const float32x4x2_t right = {hi, hi};
            vst2q_f32(dst + frame * 2, left);
            vst2q_f32(dst + frame * 2 + 8, right);
        }
        for (; frame < frames; ++frame) {
            const float value = (static_cast<float>(src[frame]) - 128.0f) * (1.0f / 128.0f);
            dst[frame * 2] = value;
            dst[frame * 2 + 1] = value;
        }
        return;
    }
#endif
    if (channels == 1) {
        for (int frame = 0; frame < frames; ++frame) {
            const float value =
                (static_cast<float>(src[frame]) - 128.0f) * (1.0f / 128.0f);
            dst[frame * 2] = value;
            dst[frame * 2 + 1] = value;
        }
        return;
    }
    for (int frame = 0; frame < frames; ++frame) {
        for (int channel = 0; channel < channels; ++channel) {
            dst[frame * 2 + channel] =
                (static_cast<float>(src[frame * channels + channel]) - 128.0f) *
                (1.0f / 128.0f);
        }
    }
}

void convert_s16(const uint8_t* src, int frames, int channels, bool big_endian, float* dst) {
    [[maybe_unused]] const int samples = frames * channels;
#if defined(__aarch64__)
    if (!big_endian && channels == 2) {
        const float32x4_t scale = vdupq_n_f32(1.0f / 32768.0f);
        int i = 0;
        for (; i + 8 <= samples; i += 8) {
            const int16x8_t raw = vld1q_s16(
                reinterpret_cast<const int16_t*>(src + static_cast<size_t>(i) * 2));
            const float32x4_t lo = vmulq_f32(s16_to_f32(vget_low_s16(raw)), scale);
            const float32x4_t hi = vmulq_f32(s16_to_f32(vget_high_s16(raw)), scale);
            vst1q_f32(dst + i, lo);
            vst1q_f32(dst + i + 4, hi);
        }
        for (; i < samples; ++i) {
            dst[i] = load_sample(src + static_cast<size_t>(i) * 2, NAR_PCM_S16, false);
        }
        return;
    }
    if (!big_endian && channels == 1) {
        const float32x4_t scale = vdupq_n_f32(1.0f / 32768.0f);
        int frame = 0;
        for (; frame + 8 <= frames; frame += 8) {
            const int16x8_t raw = vld1q_s16(
                reinterpret_cast<const int16_t*>(src + static_cast<size_t>(frame) * 2));
            float32x4_t lo = vmulq_f32(s16_to_f32(vget_low_s16(raw)), scale);
            float32x4_t hi = vmulq_f32(s16_to_f32(vget_high_s16(raw)), scale);
            const float32x4x2_t left = {lo, lo};
            const float32x4x2_t right = {hi, hi};
            vst2q_f32(dst + frame * 2, left);
            vst2q_f32(dst + frame * 2 + 8, right);
        }
        for (; frame < frames; ++frame) {
            const float value = load_sample(
                src + static_cast<size_t>(frame) * 2, NAR_PCM_S16, false);
            dst[frame * 2] = value;
            dst[frame * 2 + 1] = value;
        }
        return;
    }
#endif
    if (channels == 1) {
        for (int frame = 0; frame < frames; ++frame) {
            const float value = load_sample(
                src + static_cast<size_t>(frame) * 2, NAR_PCM_S16, big_endian);
            dst[frame * 2] = value;
            dst[frame * 2 + 1] = value;
        }
        return;
    }
    for (int frame = 0; frame < frames; ++frame) {
        for (int channel = 0; channel < channels; ++channel) {
            dst[frame * 2 + channel] = load_sample(
                src + (static_cast<size_t>(frame) * channels + channel) * 2,
                NAR_PCM_S16,
                big_endian);
        }
    }
}

void convert_s32(const uint8_t* src, int frames, int channels, bool big_endian, float* dst) {
    [[maybe_unused]] const int samples = frames * channels;
#if defined(__aarch64__)
    if (!big_endian && channels == 2) {
        const float32x4_t scale = vdupq_n_f32(1.0f / 2147483648.0f);
        int i = 0;
        for (; i + 4 <= samples; i += 4) {
            const int32x4_t raw = vld1q_s32(
                reinterpret_cast<const int32_t*>(src + static_cast<size_t>(i) * 4));
            vst1q_f32(dst + i, vmulq_f32(s32_to_f32(raw), scale));
        }
        for (; i < samples; ++i) {
            dst[i] = load_sample(src + static_cast<size_t>(i) * 4, NAR_PCM_S32, false);
        }
        return;
    }
    if (!big_endian && channels == 1) {
        const float32x4_t scale = vdupq_n_f32(1.0f / 2147483648.0f);
        int frame = 0;
        for (; frame + 4 <= frames; frame += 4) {
            const int32x4_t raw = vld1q_s32(
                reinterpret_cast<const int32_t*>(src + static_cast<size_t>(frame) * 4));
            const float32x4_t mono = vmulq_f32(s32_to_f32(raw), scale);
            const float32x4x2_t left = {mono, mono};
            vst2q_f32(dst + frame * 2, left);
        }
        for (; frame < frames; ++frame) {
            const float value = load_sample(
                src + static_cast<size_t>(frame) * 4, NAR_PCM_S32, false);
            dst[frame * 2] = value;
            dst[frame * 2 + 1] = value;
        }
        return;
    }
#endif
    if (channels == 1) {
        for (int frame = 0; frame < frames; ++frame) {
            const float value = load_sample(
                src + static_cast<size_t>(frame) * 4, NAR_PCM_S32, big_endian);
            dst[frame * 2] = value;
            dst[frame * 2 + 1] = value;
        }
        return;
    }
    for (int frame = 0; frame < frames; ++frame) {
        for (int channel = 0; channel < channels; ++channel) {
            dst[frame * 2 + channel] = load_sample(
                src + (static_cast<size_t>(frame) * channels + channel) * 4,
                NAR_PCM_S32,
                big_endian);
        }
    }
}

void convert_f32(const uint8_t* src, int frames, int channels, bool big_endian, float* dst) {
    [[maybe_unused]] const int samples = frames * channels;
#if defined(__aarch64__)
    if (!big_endian && channels == 2) {
        int i = 0;
        for (; i + 4 <= samples; i += 4) {
            const float32x4_t raw = vld1q_f32(
                reinterpret_cast<const float*>(src + static_cast<size_t>(i) * 4));
            vst1q_f32(dst + i, sanitize_finite_neon(raw));
        }
        for (; i < samples; ++i) {
            dst[i] = load_sample(src + static_cast<size_t>(i) * 4, NAR_PCM_F32, false);
        }
        return;
    }
    if (!big_endian && channels == 1) {
        int frame = 0;
        for (; frame + 4 <= frames; frame += 4) {
            const float32x4_t raw = vld1q_f32(
                reinterpret_cast<const float*>(src + static_cast<size_t>(frame) * 4));
            const float32x4_t mono = sanitize_finite_neon(raw);
            const float32x4x2_t left = {mono, mono};
            vst2q_f32(dst + frame * 2, left);
        }
        for (; frame < frames; ++frame) {
            const float value = load_sample(
                src + static_cast<size_t>(frame) * 4, NAR_PCM_F32, false);
            dst[frame * 2] = value;
            dst[frame * 2 + 1] = value;
        }
        return;
    }
#endif
    if (channels == 1) {
        for (int frame = 0; frame < frames; ++frame) {
            const float value = load_sample(
                src + static_cast<size_t>(frame) * 4, NAR_PCM_F32, big_endian);
            dst[frame * 2] = value;
            dst[frame * 2 + 1] = value;
        }
        return;
    }
    for (int frame = 0; frame < frames; ++frame) {
        for (int channel = 0; channel < channels; ++channel) {
            dst[frame * 2 + channel] = load_sample(
                src + (static_cast<size_t>(frame) * channels + channel) * 4,
                NAR_PCM_F32,
                big_endian);
        }
    }
}

// Converts `frames` interleaved input frames into interleaved stereo float.
// The caller guarantees output capacity >= frames * 2.
void convert_to_stereo(
    const uint8_t* src,
    int frames,
    int channels,
    int format,
    bool big_endian,
    float* dst) {
    if (channels == 1 || channels == 2) {
        switch (format) {
            case NAR_PCM_U8:
                convert_u8(src, frames, channels, dst);
                return;
            case NAR_PCM_S16:
                convert_s16(src, frames, channels, big_endian, dst);
                return;
            case NAR_PCM_S32:
                convert_s32(src, frames, channels, big_endian, dst);
                return;
            case NAR_PCM_F32:
                convert_f32(src, frames, channels, big_endian, dst);
                return;
            default:
                break;
        }
    }

    if (channels <= 2) {
        // S24/F64 and big-endian paths. Convert to float first, then handle
        // mono duplication without a second temporary allocation.
        const int sample_bytes = bytes_per_sample(format);
        for (int frame = 0; frame < frames; ++frame) {
            const size_t base = static_cast<size_t>(frame) * channels;
            const float left = load_sample(src + base * sample_bytes, format, big_endian);
            dst[frame * 2] = left;
            dst[frame * 2 + 1] = channels == 2
                ? load_sample(src + (base + 1) * sample_bytes, format, big_endian)
                : left;
        }
        return;
    }

    // Surround downmix, matching PcmConversions.toStereo(): centre and
    // surrounds at -3 dB, LFE excluded, conservative fallback for unknown
    // layouts. Input samples are sanitised before summing.
    const int sample_bytes = bytes_per_sample(format);
    for (int frame = 0; frame < frames; ++frame) {
        const size_t base = static_cast<size_t>(frame) * channels;
        float left = 0.0f;
        float right = 0.0f;
        if (channels == 3) {
            const float centre =
                0.70710677f * load_sample(
                    src + (base + 2) * sample_bytes, format, big_endian);
            left = load_sample(src + base * sample_bytes, format, big_endian) + centre;
            right =
                load_sample(src + (base + 1) * sample_bytes, format, big_endian) +
                centre;
        } else if (channels == 4) {
            left = load_sample(src + base * sample_bytes, format, big_endian) +
                0.70710677f * load_sample(src + (base + 2) * sample_bytes, format, big_endian);
            right = load_sample(src + (base + 1) * sample_bytes, format, big_endian) +
                0.70710677f * load_sample(src + (base + 3) * sample_bytes, format, big_endian);
        } else if (channels == 6) {
            left = load_sample(src + base * sample_bytes, format, big_endian) +
                0.70710677f * (load_sample(src + (base + 2) * sample_bytes, format, big_endian) +
                                load_sample(src + (base + 4) * sample_bytes, format, big_endian));
            right = load_sample(src + (base + 1) * sample_bytes, format, big_endian) +
                0.70710677f * (load_sample(src + (base + 2) * sample_bytes, format, big_endian) +
                                load_sample(src + (base + 5) * sample_bytes, format, big_endian));
        } else if (channels == 8) {
            left = load_sample(src + base * sample_bytes, format, big_endian) +
                0.70710677f * (load_sample(src + (base + 2) * sample_bytes, format, big_endian) +
                                load_sample(src + (base + 4) * sample_bytes, format, big_endian) +
                                load_sample(src + (base + 6) * sample_bytes, format, big_endian));
            right = load_sample(src + (base + 1) * sample_bytes, format, big_endian) +
                0.70710677f * (load_sample(src + (base + 2) * sample_bytes, format, big_endian) +
                                load_sample(src + (base + 5) * sample_bytes, format, big_endian) +
                                load_sample(src + (base + 7) * sample_bytes, format, big_endian));
        } else {
            left = load_sample(src + base * sample_bytes, format, big_endian);
            right = load_sample(src + (base + 1) * sample_bytes, format, big_endian);
            float extra = 0.0f;
            for (int channel = 2; channel < channels; ++channel) {
                extra += load_sample(
                    src + (base + static_cast<size_t>(channel)) * sample_bytes,
                    format,
                    big_endian);
            }
            extra = extra / static_cast<float>(channels - 2) * 0.5f;
            left += extra;
            right += extra;
        }
        dst[frame * 2] = clamp_sample(left);
        dst[frame * 2 + 1] = clamp_sample(right);
    }
}

}  // namespace

struct NarDeckConverter {
    int input_rate = 0;
    int output_rate = 0;
    int taps = kDefaultTaps;
    int phases = kDefaultPhases;
    int half = kDefaultTaps / 2;
    bool bypass = true;
    double step = 1.0;
    double cutoff = 1.0;

    std::vector<float> coefficients;  // phases * taps
    std::vector<float> history;       // (taps - 1) * stereo
    std::vector<float> history_scratch;
    std::vector<float> input_stereo;  // current block, interleaved stereo

    int input_frames = 0;  // valid frames in input_stereo for this call
    int history_frames = 0;
    int64_t base_frame = 0;
    double position = 0.0;

    bool ensure_input_capacity(int frames) {
        const size_t needed = static_cast<size_t>(frames) * kBusChannels;
        if (input_stereo.size() < needed) {
            input_stereo.resize(needed);
        }
        return true;
    }

    void build_kernel() {
        if (bypass) return;
        coefficients.resize(static_cast<size_t>(phases) * taps);
        for (int phase = 0; phase < phases; ++phase) {
            const double fraction = static_cast<double>(phase) / phases;
            double sum = 0.0;
            for (int tap = 0; tap < taps; ++tap) {
                const double offset = static_cast<double>(tap - (half - 1)) - fraction;
                double window = 0.0;
                const double absolute = std::fabs(offset);
                if (absolute < half) {
                    window = 0.42 +
                             0.5 * std::cos(kPi * offset / half) +
                             0.08 * std::cos(2.0 * kPi * offset / half);
                }
                const double scaled = cutoff * offset;
                const double sinc = std::fabs(scaled) < 1e-9
                    ? 1.0
                    : std::sin(kPi * scaled) / (kPi * scaled);
                const double coefficient = cutoff * sinc * window;
                coefficients[static_cast<size_t>(phase) * taps + tap] =
                    static_cast<float>(coefficient);
                sum += coefficient;
            }
            if (std::fabs(sum) > 1e-12) {
                for (int tap = 0; tap < taps; ++tap) {
                    const size_t index = static_cast<size_t>(phase) * taps + tap;
                    coefficients[index] = static_cast<float>(
                        static_cast<double>(coefficients[index]) / sum);
                }
            }
        }
    }

    inline float sample_at(int64_t absolute_frame, int channel) const {
        if (absolute_frame < 0) return 0.0f;
        if (absolute_frame >= base_frame) {
            const int64_t index = absolute_frame - base_frame;
            // Bound by this block's valid frame count, not the retained vector
            // capacity, so a shorter block can never read stale samples.
            if (index >= input_frames) return 0.0f;
            return input_stereo[static_cast<size_t>(index) * kBusChannels + channel];
        }
        const int64_t history_index = absolute_frame - (base_frame - history_frames);
        if (history_index < 0 || history_index >= history_frames) return 0.0f;
        return history[static_cast<size_t>(history_index) * kBusChannels + channel];
    }

    void update_history(int64_t end_exclusive) {
        const int64_t history_start = std::max<int64_t>(0, end_exclusive - (taps - 1));
        const int count = static_cast<int>(end_exclusive - history_start);
        if (count <= 0) {
            history_frames = 0;
            base_frame = end_exclusive;
            return;
        }
        const size_t needed = static_cast<size_t>(count) * kBusChannels;
        if (history_scratch.size() < needed) history_scratch.resize(needed);
        for (int i = 0; i < count; ++i) {
            const int64_t absolute = history_start + i;
            history_scratch[static_cast<size_t>(i) * kBusChannels] =
                sample_at(absolute, 0);
            history_scratch[static_cast<size_t>(i) * kBusChannels + 1] =
                sample_at(absolute, 1);
        }
        if (history.size() < needed) history.resize(needed);
        std::memcpy(history.data(), history_scratch.data(), needed * sizeof(float));
        history_frames = count;
        base_frame = end_exclusive;
    }
};

struct NarStereoMixer {
    int max_frames = 0;
    float release_coefficient = 1.0f;
    float smoothing_coefficient = 1.0f;
    float limiter_gain[kBusChannels] = {1.0f, 1.0f};
};

extern "C" {

NarDeckConverter* nar_deck_converter_create(
    int input_rate,
    int output_rate,
    int taps,
    int phases) {
    if (input_rate <= 0 || output_rate <= 0) return nullptr;
    if (input_rate > 768000 || output_rate > 768000) return nullptr;
    if (taps < 2 || taps > 128 || phases < 1 || phases > 4096) return nullptr;
    try {
        auto* converter = new NarDeckConverter();
        converter->input_rate = input_rate;
        converter->output_rate = output_rate;
        converter->taps = taps;
        converter->phases = phases;
        converter->half = taps / 2;
        converter->bypass = input_rate == output_rate;
        converter->step = static_cast<double>(input_rate) / output_rate;
        converter->cutoff = converter->bypass
            ? 1.0
            : std::min(1.0, static_cast<double>(output_rate) / input_rate);
        converter->history.resize(static_cast<size_t>(std::max(0, taps - 1)) * kBusChannels);
        converter->history_scratch.resize(converter->history.size());
        converter->input_stereo.resize(
            static_cast<size_t>(kInitialInputFrames) * kBusChannels);
        converter->build_kernel();
        return converter;
    } catch (...) {
        return nullptr;
    }
}

void nar_deck_converter_destroy(NarDeckConverter* converter) {
    delete converter;
}

void nar_deck_converter_reset(NarDeckConverter* converter) {
    if (converter == nullptr) return;
    converter->input_frames = 0;
    converter->history_frames = 0;
    converter->base_frame = 0;
    converter->position = 0.0;
}

int nar_deck_converter_max_output_frames(
    const NarDeckConverter* converter,
    int input_frames) {
    if (converter == nullptr || input_frames <= 0) return 0;
    if (converter->bypass) return input_frames;
    const double ratio = static_cast<double>(converter->output_rate) /
                         converter->input_rate;
    const double frames =
        std::ceil(static_cast<double>(input_frames) * ratio) + 2.0;
    if (!(frames <= static_cast<double>(std::numeric_limits<int>::max()))) {
        return 0;
    }
    return static_cast<int>(frames);
}

int nar_deck_converter_process(
    NarDeckConverter* converter,
    const void* input,
    int input_frames,
    int channels,
    int format,
    int big_endian,
    float* output,
    int output_capacity_frames) {
    if (converter == nullptr || input == nullptr || output == nullptr) {
        return NAR_PCM_ERROR_ARGUMENT;
    }
    if (input_frames <= 0) return 0;
    if (channels <= 0 || channels > kMaxChannels) return NAR_PCM_ERROR_ARGUMENT;
    if (bytes_per_sample(format) == 0) return NAR_PCM_ERROR_ARGUMENT;
    if (output_capacity_frames <= 0) return 0;

    const int max_output_frames =
        nar_deck_converter_max_output_frames(converter, input_frames);
    if (max_output_frames <= 0 || output_capacity_frames < max_output_frames) {
        return NAR_PCM_ERROR_ARGUMENT;
    }

    try {
        if (!converter->ensure_input_capacity(input_frames)) {
            return NAR_PCM_ERROR_MEMORY;
        }
    } catch (...) {
        return NAR_PCM_ERROR_MEMORY;
    }

    converter->input_frames = input_frames;
    convert_to_stereo(
        static_cast<const uint8_t*>(input),
        input_frames,
        channels,
        format,
        big_endian != 0,
        converter->input_stereo.data());

    if (converter->bypass) {
        const int copied = std::min(input_frames, output_capacity_frames);
        std::memcpy(
            output,
            converter->input_stereo.data(),
            static_cast<size_t>(copied) * kBusChannels * sizeof(float));
        converter->base_frame += input_frames;
        return copied;
    }

    const int taps = converter->taps;
    const int half = converter->half;
    const int64_t end_exclusive = converter->base_frame + input_frames;
    int out_frames = 0;

    while (converter->position <
           static_cast<double>(end_exclusive - half)) {
        if (out_frames >= output_capacity_frames) break;
        const double position = converter->position;
        const int64_t index = static_cast<int64_t>(std::floor(position));
        const float fraction = static_cast<float>(position - static_cast<double>(index));
        const double row = static_cast<double>(fraction) * converter->phases;
        const int row0 = std::min(
            static_cast<int>(std::floor(row)), converter->phases - 1);
        const float blend = static_cast<float>(row - row0);
        const int row1 = (row0 + 1) % converter->phases;
        const float* table0 = converter->coefficients.data() +
                              static_cast<size_t>(row0) * taps;
        const float* table1 = converter->coefficients.data() +
                              static_cast<size_t>(row1) * taps;

        float left = 0.0f;
        float right = 0.0f;
        for (int tap = 0; tap < taps; ++tap) {
            const float coefficient = table0[tap] * (1.0f - blend) +
                                      table1[tap] * blend;
            const int64_t absolute = index + tap - (half - 1);
            left += coefficient * converter->sample_at(absolute, 0);
            right += coefficient * converter->sample_at(absolute, 1);
        }
        if (!is_finite(left)) left = 0.0f;
        if (!is_finite(right)) right = 0.0f;
        output[static_cast<size_t>(out_frames) * kBusChannels] = left;
        output[static_cast<size_t>(out_frames) * kBusChannels + 1] = right;

        out_frames++;
        converter->position += converter->step;
        if (!is_finite(static_cast<float>(converter->position))) break;
    }

    converter->update_history(end_exclusive);
    return out_frames;
}

NarStereoMixer* nar_stereo_mixer_create(int sample_rate, int max_frames) {
    if (sample_rate <= 0 || sample_rate > 768000 || max_frames <= 0) {
        return nullptr;
    }
    try {
        auto* mixer = new NarStereoMixer();
        mixer->max_frames = max_frames;
        const double release_frames = static_cast<double>(sample_rate) *
                                      (kLimiterReleaseMs / 1000.0);
        mixer->release_coefficient = release_frames > 0.0
            ? static_cast<float>(1.0 - std::exp(-1.0 / release_frames))
            : 1.0f;
        const double smoothing_frames = static_cast<double>(sample_rate) *
                                        (kGainSmoothingMs / 1000.0);
        mixer->smoothing_coefficient = smoothing_frames > 0.0
            ? static_cast<float>(1.0 - std::exp(-1.0 / smoothing_frames))
            : 1.0f;
        return mixer;
    } catch (...) {
        return nullptr;
    }
}

void nar_stereo_mixer_destroy(NarStereoMixer* mixer) {
    delete mixer;
}

void nar_stereo_mixer_reset(NarStereoMixer* mixer) {
    if (mixer == nullptr) return;
    mixer->limiter_gain[0] = 1.0f;
    mixer->limiter_gain[1] = 1.0f;
}

int nar_stereo_mixer_process(
    NarStereoMixer* mixer,
    const float* deck0,
    const float* deck1,
    unsigned int active_mask,
    int frames,
    float* gains,
    const float* targets,
    float* output) {
    if (mixer == nullptr || gains == nullptr || targets == nullptr ||
        output == nullptr || frames <= 0) {
        return 0;
    }
    // Reject an oversized block instead of mixing only part of it: the caller
    // writes `frames` samples downstream even if a smaller prefix was mixed.
    if (frames > mixer->max_frames) return 0;

    const bool use_deck0 = (active_mask & 1u) != 0 && deck0 != nullptr;
    const bool use_deck1 = (active_mask & 2u) != 0 && deck1 != nullptr;
    float gain0 = is_finite(gains[0]) ? gains[0] : 1.0f;
    float gain1 = is_finite(gains[1]) ? gains[1] : 1.0f;
    gain0 = std::min(1.0f, std::max(0.0f, gain0));
    gain1 = std::min(1.0f, std::max(0.0f, gain1));
    const float target0 = safe_target(targets[0]);
    const float target1 = safe_target(targets[1]);
    const float smoothing = mixer->smoothing_coefficient;

    if (!use_deck0 && !use_deck1) {
        std::memset(output, 0, static_cast<size_t>(frames) * kBusChannels * sizeof(float));
        gains[0] = gain0;
        gains[1] = gain1;
        return 1;
    }

#if defined(__aarch64__)
    int frame = 0;
    for (; frame + 2 <= frames; frame += 2) {
        if (use_deck0) {
            gain0 = gain_step(gain0, target0, smoothing);
        }
        const float gain0a = gain0;
        if (use_deck0) {
            gain0 = gain_step(gain0, target0, smoothing);
        }
        const float gain0b = gain0;
        if (use_deck1) {
            gain1 = gain_step(gain1, target1, smoothing);
        }
        const float gain1a = gain1;
        if (use_deck1) {
            gain1 = gain_step(gain1, target1, smoothing);
        }
        const float gain1b = gain1;

        float32x4_t accumulator = vdupq_n_f32(0.0f);
        if (use_deck0) {
            const float32x4_t samples = vld1q_f32(deck0 + static_cast<size_t>(frame) * 2);
            const float32x4_t gain_vector = vcombine_f32(
                vdup_n_f32(gain0a), vdup_n_f32(gain0b));
            accumulator = vmulq_f32(samples, gain_vector);
        }
        if (use_deck1) {
            const float32x4_t samples = vld1q_f32(deck1 + static_cast<size_t>(frame) * 2);
            const float32x4_t gain_vector = vcombine_f32(
                vdup_n_f32(gain1a), vdup_n_f32(gain1b));
            accumulator = vmlaq_f32(accumulator, samples, gain_vector);
        }
        vst1q_f32(output + static_cast<size_t>(frame) * 2, accumulator);
    }
    for (; frame < frames; ++frame) {
        const size_t base = static_cast<size_t>(frame) * kBusChannels;
        if (use_deck0) gain0 = gain_step(gain0, target0, smoothing);
        if (use_deck1) gain1 = gain_step(gain1, target1, smoothing);
        const float left = (use_deck0 ? deck0[base] * gain0 : 0.0f) +
                           (use_deck1 ? deck1[base] * gain1 : 0.0f);
        const float right = (use_deck0 ? deck0[base + 1] * gain0 : 0.0f) +
                            (use_deck1 ? deck1[base + 1] * gain1 : 0.0f);
        output[base] = left;
        output[base + 1] = right;
    }
#else
    for (int frame = 0; frame < frames; ++frame) {
        const size_t base = static_cast<size_t>(frame) * kBusChannels;
        if (use_deck0) gain0 = gain_step(gain0, target0, smoothing);
        if (use_deck1) gain1 = gain_step(gain1, target1, smoothing);
        const float left = (use_deck0 ? deck0[base] * gain0 : 0.0f) +
                           (use_deck1 ? deck1[base] * gain1 : 0.0f);
        const float right = (use_deck0 ? deck0[base + 1] * gain0 : 0.0f) +
                            (use_deck1 ? deck1[base + 1] * gain1 : 0.0f);
        output[base] = left;
        output[base + 1] = right;
    }
#endif

    gains[0] = gain0;
    gains[1] = gain1;

    // Final safety stage after both decks are summed. Keep the exact causal
    // limiter semantics of the Kotlin BusLimiter so the bus ceiling, release
    // and non-finite policy do not change when the native path is active.
    // A non-finite sample is replaced with silence without advancing the
    // release envelope, exactly like BusLimiter.process().
    const float release = mixer->release_coefficient;
    for (int frame = 0; frame < frames; ++frame) {
        const size_t base = static_cast<size_t>(frame) * kBusChannels;
        for (int channel = 0; channel < kBusChannels; ++channel) {
            const float sample = output[base + channel];
            if (!is_finite(sample)) {
                output[base + channel] = 0.0f;
                continue;
            }
            const float peak = std::fabs(sample);
            const float current = mixer->limiter_gain[channel];
            const float required = peak * current > kLimiterCeiling
                ? kLimiterCeiling / peak
                : 1.0f;
            const float next = std::min(
                required, current + (1.0f - current) * release);
            float limited = sample * next;
            if (limited > kLimiterCeiling) limited = kLimiterCeiling;
            if (limited < -kLimiterCeiling) limited = -kLimiterCeiling;
            mixer->limiter_gain[channel] = next;
            output[base + channel] = limited;
        }
    }

    return 1;
}

}  // extern "C"
