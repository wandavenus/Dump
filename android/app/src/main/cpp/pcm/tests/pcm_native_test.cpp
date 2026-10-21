// Host test harness for pcm_native.cpp. Built by run_host_tests.sh:
//   - x86-64 clang++ (scalar fallbacks)
//   - aarch64-linux-gnu-g++ (NEON paths), run under qemu-aarch64-static
//
// This file is intentionally standalone: it uses only the public C API in
// pcm_native.h, so it can also be wired into CI as a native host test.

#include "pcm_native.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <vector>

namespace {

int failures = 0;
int checks = 0;

#define EXPECT_TRUE(cond)                                                        \
    do {                                                                         \
        ++checks;                                                                \
        if (!(cond)) {                                                           \
            ++failures;                                                          \
            std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        }                                                                        \
    } while (0)

#define EXPECT_NEAR(actual, expected, tolerance)                                  \
    do {                                                                          \
        ++checks;                                                                 \
        const double a_ = static_cast<double>(actual);                            \
        const double e_ = static_cast<double>(expected);                          \
        if (!(std::fabs(a_ - e_) <= (tolerance))) {                               \
            ++failures;                                                           \
            std::fprintf(                                                         \
                stderr,                                                           \
                "FAIL %s:%d: %s = %.9f, expected %.9f (tol %.9g)\n",             \
                __FILE__,                                                         \
                __LINE__,                                                         \
                #actual,                                                          \
                a_,                                                               \
                e_,                                                               \
                static_cast<double>(tolerance));                                  \
        }                                                                         \
    } while (0)

void append_le16(std::vector<uint8_t>& out, int16_t value) {
    out.push_back(static_cast<uint8_t>(value & 0xFF));
    out.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
}

void append_be16(std::vector<uint8_t>& out, int16_t value) {
    out.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
    out.push_back(static_cast<uint8_t>(value & 0xFF));
}

void append_le24(std::vector<uint8_t>& out, int32_t value) {
    out.push_back(static_cast<uint8_t>(value & 0xFF));
    out.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
    out.push_back(static_cast<uint8_t>((value >> 16) & 0xFF));
}

void append_be24(std::vector<uint8_t>& out, int32_t value) {
    out.push_back(static_cast<uint8_t>((value >> 16) & 0xFF));
    out.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
    out.push_back(static_cast<uint8_t>(value & 0xFF));
}

void append_le32(std::vector<uint8_t>& out, int32_t value) {
    out.push_back(static_cast<uint8_t>(value & 0xFF));
    out.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
    out.push_back(static_cast<uint8_t>((value >> 16) & 0xFF));
    out.push_back(static_cast<uint8_t>((value >> 24) & 0xFF));
}

void append_be32(std::vector<uint8_t>& out, int32_t value) {
    out.push_back(static_cast<uint8_t>((value >> 24) & 0xFF));
    out.push_back(static_cast<uint8_t>((value >> 16) & 0xFF));
    out.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
    out.push_back(static_cast<uint8_t>(value & 0xFF));
}

struct ConversionResult {
    int status = 0;
    std::vector<float> output;
};

ConversionResult convert(
    const std::vector<uint8_t>& bytes,
    int frames,
    int channels,
    int format,
    bool bigEndian) {
    ConversionResult result;
    NarDeckConverter* converter = nar_deck_converter_create(48000, 48000, 32, 256);
    EXPECT_TRUE(converter != nullptr);
    if (converter == nullptr) return result;

    const int capacity = nar_deck_converter_max_output_frames(converter, frames);
    EXPECT_TRUE(capacity == frames);
    result.output.assign(static_cast<size_t>(capacity) * 2, -12345.0f);
    result.status = nar_deck_converter_process(
        converter,
        bytes.data(),
        frames,
        channels,
        format,
        bigEndian ? 1 : 0,
        result.output.data(),
        capacity);
    nar_deck_converter_destroy(converter);
    return result;
}

void test_u8() {
    // U8 is unsigned and centered at 128.
    std::vector<uint8_t> stereo = {0, 128, 255, 64};
    auto result = convert(stereo, 2, 2, NAR_PCM_U8, false);
    EXPECT_TRUE(result.status == 2);
    EXPECT_NEAR(result.output[0], -1.0f, 1e-6);
    EXPECT_NEAR(result.output[1], 0.0f, 1e-6);
    EXPECT_NEAR(result.output[2], 127.0f / 128.0f, 1e-6);
    EXPECT_NEAR(result.output[3], -0.5f, 1e-6);

    // Mono must be duplicated to both bus channels.
    std::vector<uint8_t> mono = {0, 192};
    result = convert(mono, 2, 1, NAR_PCM_U8, false);
    EXPECT_TRUE(result.status == 2);
    EXPECT_NEAR(result.output[0], -1.0f, 1e-6);
    EXPECT_NEAR(result.output[1], -1.0f, 1e-6);
    EXPECT_NEAR(result.output[2], 0.5f, 1e-6);
    EXPECT_NEAR(result.output[3], 0.5f, 1e-6);
}

void test_s16() {
    std::vector<uint8_t> stereo;
    append_le16(stereo, std::numeric_limits<int16_t>::min());
    append_le16(stereo, std::numeric_limits<int16_t>::max());
    append_le16(stereo, 0);
    append_le16(stereo, 16384);
    auto result = convert(stereo, 2, 2, NAR_PCM_S16, false);
    EXPECT_TRUE(result.status == 2);
    EXPECT_NEAR(result.output[0], -1.0f, 1e-7);
    EXPECT_NEAR(result.output[1], 32767.0f / 32768.0f, 1e-7);
    EXPECT_NEAR(result.output[2], 0.0f, 1e-7);
    EXPECT_NEAR(result.output[3], 0.5f, 1e-7);

    // Big-endian input must produce the same samples.
    std::vector<uint8_t> be;
    append_be16(be, -12345);
    append_be16(be, 23456);
    result = convert(be, 1, 2, NAR_PCM_S16, true);
    EXPECT_TRUE(result.status == 1);
    EXPECT_NEAR(result.output[0], -12345.0f / 32768.0f, 1e-7);
    EXPECT_NEAR(result.output[1], 23456.0f / 32768.0f, 1e-7);
}

void test_s24() {
    std::vector<uint8_t> stereo;
    append_le24(stereo, -8388608);
    append_le24(stereo, 8388607);
    append_le24(stereo, -1);
    append_le24(stereo, 4194304);
    auto result = convert(stereo, 2, 2, NAR_PCM_S24, false);
    EXPECT_TRUE(result.status == 2);
    EXPECT_NEAR(result.output[0], -1.0f, 1e-7);
    EXPECT_NEAR(result.output[1], 8388607.0f / 8388608.0f, 1e-7);
    EXPECT_NEAR(result.output[2], -1.0f / 8388608.0f, 1e-9);
    EXPECT_NEAR(result.output[3], 0.5f, 1e-7);

    std::vector<uint8_t> be;
    append_be24(be, -4194304);
    append_be24(be, 2097152);
    result = convert(be, 1, 2, NAR_PCM_S24, true);
    EXPECT_TRUE(result.status == 1);
    EXPECT_NEAR(result.output[0], -0.5f, 1e-7);
    EXPECT_NEAR(result.output[1], 0.25f, 1e-7);
}

void test_s32() {
    std::vector<uint8_t> stereo;
    append_le32(stereo, std::numeric_limits<int32_t>::min());
    append_le32(stereo, std::numeric_limits<int32_t>::max());
    append_le32(stereo, -1);
    append_le32(stereo, 1073741824);
    auto result = convert(stereo, 2, 2, NAR_PCM_S32, false);
    EXPECT_TRUE(result.status == 2);
    EXPECT_NEAR(result.output[0], -1.0f, 1e-7);
    EXPECT_NEAR(result.output[1], 2147483647.0f / 2147483648.0f, 1e-7);
    EXPECT_NEAR(result.output[2], -1.0f / 2147483648.0f, 1e-9);
    EXPECT_NEAR(result.output[3], 0.5f, 1e-7);

    std::vector<uint8_t> be;
    append_be32(be, -1073741824);
    append_be32(be, 536870912);
    result = convert(be, 1, 2, NAR_PCM_S32, true);
    EXPECT_TRUE(result.status == 1);
    EXPECT_NEAR(result.output[0], -0.5f, 1e-7);
    EXPECT_NEAR(result.output[1], 0.25f, 1e-7);
}

void test_f32_f64_and_non_finite() {
    std::vector<uint8_t> stereo;
    const float values[4] = {1.0f, -1.0f, std::numeric_limits<float>::quiet_NaN(), 0.25f};
    for (float value : values) {
        int32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        append_le32(stereo, bits);
    }
    auto result = convert(stereo, 2, 2, NAR_PCM_F32, false);
    EXPECT_TRUE(result.status == 2);
    EXPECT_NEAR(result.output[0], 1.0f, 1e-7);
    EXPECT_NEAR(result.output[1], -1.0f, 1e-7);
    EXPECT_TRUE(std::isfinite(result.output[2]));
    EXPECT_NEAR(result.output[2], 0.0f, 1e-7);
    EXPECT_NEAR(result.output[3], 0.25f, 1e-7);

    // F64 is converted to float; non-finite values are replaced by silence.
    std::vector<uint8_t> f64;
    const double dvalues[4] = {
        0.5,
        -0.25,
        std::numeric_limits<double>::infinity(),
        std::numeric_limits<double>::quiet_NaN(),
    };
    for (double value : dvalues) {
        int64_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        append_le32(f64, static_cast<int32_t>(bits & 0xFFFFFFFF));
        append_le32(f64, static_cast<int32_t>((bits >> 32) & 0xFFFFFFFF));
    }
    result = convert(f64, 2, 2, NAR_PCM_F64, false);
    EXPECT_TRUE(result.status == 2);
    EXPECT_NEAR(result.output[0], 0.5f, 1e-7);
    EXPECT_NEAR(result.output[1], -0.25f, 1e-7);
    EXPECT_NEAR(result.output[2], 0.0f, 1e-7);
    EXPECT_NEAR(result.output[3], 0.0f, 1e-7);
}

void test_downmix() {
    // 3ch: L, R, C -> C at -3 dB to both sides.
    std::vector<uint8_t> bytes;
    append_le16(bytes, 3277);   // 0.1
    append_le16(bytes, 6554);   // 0.2
    append_le16(bytes, 9830);   // 0.3
    auto result = convert(bytes, 1, 3, NAR_PCM_S16, false);
    EXPECT_TRUE(result.status == 1);
    EXPECT_NEAR(result.output[0], (0.1 + 0.70710677 * 0.3), 2e-4);
    EXPECT_NEAR(result.output[1], (0.2 + 0.70710677 * 0.3), 2e-4);

    // 6ch: L R C LFE LS RS - LFE must be ignored.
    bytes.clear();
    append_le16(bytes, 3277);    // L 0.1
    append_le16(bytes, 6554);    // R 0.2
    append_le16(bytes, 9830);    // C 0.3
    append_le16(bytes, 32767);   // LFE (ignored)
    append_le16(bytes, 16384);   // LS 0.5
    append_le16(bytes, -16384);  // RS -0.5
    result = convert(bytes, 1, 6, NAR_PCM_S16, false);
    EXPECT_TRUE(result.status == 1);
    EXPECT_NEAR(result.output[0], 0.1 + 0.70710677 * (0.3 + 0.5), 2e-4);
    EXPECT_NEAR(result.output[1], 0.2 + 0.70710677 * (0.3 - 0.5), 2e-4);

    // Unknown 5ch layout: first two channels plus spread of the rest.
    bytes.clear();
    for (int i = 0; i < 5; ++i) append_le16(bytes, static_cast<int16_t>(16384));
    result = convert(bytes, 1, 5, NAR_PCM_S16, false);
    EXPECT_TRUE(result.status == 1);
    EXPECT_NEAR(result.output[0], 0.5 + 0.25, 2e-4);
    EXPECT_NEAR(result.output[1], 0.5 + 0.25, 2e-4);

    // Downmix is clamped to +/-8 rather than wrapping.
    bytes.clear();
    append_le16(bytes, 32767);
    append_le16(bytes, 32767);
    append_le16(bytes, 32767);
    result = convert(bytes, 1, 3, NAR_PCM_S16, false);
    EXPECT_TRUE(result.status == 1);
    EXPECT_TRUE(result.output[0] <= 8.0f && result.output[0] >= -8.0f);
}

std::vector<float> run_resampler(
    int inputRate,
    int outputRate,
    const std::vector<float>& stereo,
    const std::vector<int>& blockSizes) {
    NarDeckConverter* converter =
        nar_deck_converter_create(inputRate, outputRate, 32, 256);
    if (converter == nullptr) {
        EXPECT_TRUE(false);
        return {};
    }

    std::vector<float> output;
    size_t offset = 0;
    size_t blockIndex = 0;
    while (offset < stereo.size() / 2) {
        int frames = blockSizes[blockIndex % blockSizes.size()];
        ++blockIndex;
        frames = std::min<int>(
            frames, static_cast<int>(stereo.size() / 2 - offset));
        if (frames <= 0) break;

        const int capacity = nar_deck_converter_max_output_frames(converter, frames);
        std::vector<float> block(static_cast<size_t>(capacity) * 2);
        const int produced = nar_deck_converter_process(
            converter,
            stereo.data() + offset * 2,
            frames,
            2,
            NAR_PCM_F32,
            0,
            block.data(),
            capacity);
        EXPECT_TRUE(produced >= 0);
        if (produced < 0) break;
        output.insert(output.end(), block.begin(), block.begin() + produced * 2);
        offset += frames;
    }
    nar_deck_converter_destroy(converter);
    return output;
}

void test_resampler_block_invariance() {
    const int inputRate = 44100;
    const int outputRate = 48000;
    const int frames = inputRate;  // one second
    std::vector<float> stereo(static_cast<size_t>(frames) * 2);
    for (int i = 0; i < frames; ++i) {
        const double sample = 0.7 * std::sin(2.0 * 3.14159265358979323846 * 440.0 * i / inputRate);
        stereo[static_cast<size_t>(i) * 2] = static_cast<float>(sample);
        stereo[static_cast<size_t>(i) * 2 + 1] = static_cast<float>(sample * 0.5);
    }

    const std::vector<float> reference = run_resampler(
        inputRate, outputRate, stereo, {1024});
    const std::vector<float> uneven = run_resampler(
        inputRate, outputRate, stereo, {37, 1, 333, 2048, 5});
    const std::vector<float> tiny = run_resampler(
        inputRate, outputRate, stereo, {1, 2, 3, 7, 11});

    EXPECT_TRUE(!reference.empty());
    EXPECT_TRUE(std::abs(static_cast<int>(reference.size()) -
                         static_cast<int>(outputRate * 2)) < 128);
    EXPECT_TRUE(reference.size() == uneven.size());
    EXPECT_TRUE(reference.size() == tiny.size());
    const size_t compared = std::min(reference.size(), uneven.size());
    double maxDifference = 0.0;
    for (size_t i = 0; i < compared; ++i) {
        maxDifference = std::max(
            maxDifference,
            std::fabs(static_cast<double>(reference[i]) - uneven[i]));
    }
    EXPECT_NEAR(maxDifference, 0.0, 1e-6);

    const size_t comparedTiny = std::min(reference.size(), tiny.size());
    maxDifference = 0.0;
    for (size_t i = 0; i < comparedTiny; ++i) {
        maxDifference = std::max(
            maxDifference,
            std::fabs(static_cast<double>(reference[i]) - tiny[i]));
    }
    EXPECT_NEAR(maxDifference, 0.0, 1e-6);

    // No clicks at block joins: the waveform derivative stays small.
    double maxStep = 0.0;
    for (size_t i = 1; i < reference.size() / 2; ++i) {
        maxStep = std::max(
            maxStep,
            std::fabs(static_cast<double>(reference[i * 2]) -
                      reference[(i - 1) * 2]));
    }
    EXPECT_TRUE(maxStep < 0.1);

    // Amplitude preserved away from the initial filter transient.
    double sumSquares = 0.0;
    size_t count = 0;
    for (size_t i = 256; i < reference.size() / 2 - 256; ++i) {
        const double value = reference[i * 2];
        sumSquares += value * value;
        ++count;
    }
    const double rms = std::sqrt(sumSquares / count);
    EXPECT_NEAR(rms, 0.7 / std::sqrt(2.0), 0.01);
    // Right channel was generated at half amplitude.
    sumSquares = 0.0;
    count = 0;
    for (size_t i = 256; i < reference.size() / 2 - 256; ++i) {
        const double value = reference[i * 2 + 1];
        sumSquares += value * value;
        ++count;
    }
    EXPECT_NEAR(rms * 0.5, std::sqrt(sumSquares / count), 0.01);
}

void test_resampler_downsample_and_bounds() {
    const int inputRate = 48000;
    const int outputRate = 44100;
    const int frames = 48000;
    std::vector<float> stereo(static_cast<size_t>(frames) * 2);
    for (int i = 0; i < frames; ++i) {
        const float sample =
            static_cast<float>(0.5 * std::sin(2.0 * 3.14159265358979323846 * 1000.0 * i / inputRate));
        stereo[static_cast<size_t>(i) * 2] = sample;
        stereo[static_cast<size_t>(i) * 2 + 1] = sample;
    }

    const std::vector<float> a =
        run_resampler(inputRate, outputRate, stereo, {1024});
    const std::vector<float> b =
        run_resampler(inputRate, outputRate, stereo, {13, 512, 1, 77});
    EXPECT_TRUE(!a.empty());
    EXPECT_TRUE(std::abs(static_cast<int>(a.size()) -
                         static_cast<int>(outputRate * 2)) < 128);
    EXPECT_TRUE(a.size() == b.size());
    double maxDifference = 0.0;
    for (size_t i = 0; i < std::min(a.size(), b.size()); ++i) {
        maxDifference = std::max(
            maxDifference,
            std::fabs(static_cast<double>(a[i]) - b[i]));
    }
    EXPECT_NEAR(maxDifference, 0.0, 1e-6);

    // A short output buffer is rejected instead of silently dropping frames.
    NarDeckConverter* converter =
        nar_deck_converter_create(44100, 48000, 32, 256);
    EXPECT_TRUE(converter != nullptr);
    const int inputFrames = 512;
    std::vector<float> block(static_cast<size_t>(inputFrames) * 2);
    const int capacity = nar_deck_converter_max_output_frames(converter, inputFrames);
    EXPECT_TRUE(capacity > inputFrames);
    const int rejected = nar_deck_converter_process(
        converter,
        block.data(),
        inputFrames,
        2,
        NAR_PCM_F32,
        0,
        block.data(),
        capacity - 1);
    EXPECT_TRUE(rejected == NAR_PCM_ERROR_ARGUMENT);

    std::vector<float> enough(static_cast<size_t>(capacity) * 2);
    const int accepted = nar_deck_converter_process(
        converter,
        block.data(),
        inputFrames,
        2,
        NAR_PCM_F32,
        0,
        enough.data(),
        capacity);
    EXPECT_TRUE(accepted > 0);
    nar_deck_converter_destroy(converter);
}

float smoothing_coefficient(int sampleRate, float ms) {
    return static_cast<float>(
        1.0 - std::exp(-1.0 / (static_cast<double>(ms) / 1000.0 * sampleRate)));
}

float release_coefficient(int sampleRate, float ms) {
    return static_cast<float>(
        1.0 - std::exp(-1.0 / (static_cast<double>(ms) / 1000.0 * sampleRate)));
}

void test_gain_ramp() {
    const int sampleRate = 48000;
    const int frames = 512;
    NarStereoMixer* mixer = nar_stereo_mixer_create(sampleRate, frames);
    EXPECT_TRUE(mixer != nullptr);

    std::vector<float> deck0(static_cast<size_t>(frames) * 2, 1.0f);
    std::vector<float> deck1(static_cast<size_t>(frames) * 2, 2.0f);
    std::vector<float> output(static_cast<size_t>(frames) * 2, 0.0f);
    float gains[2] = {0.0f, 0.25f};
    float targets[2] = {1.0f, 1.0f};

    const float coefficient = smoothing_coefficient(sampleRate, 12.0f);
    float expectedGain = 1.0f - std::pow(1.0f - coefficient, frames);

    // Only deck 0 is active: its gain ramps, deck 1's gain must not move.
    EXPECT_TRUE(nar_stereo_mixer_process(
        mixer, deck0.data(), deck1.data(), 1u, frames, gains, targets, output.data()));
    EXPECT_NEAR(gains[0], expectedGain, 2e-5);
    EXPECT_NEAR(gains[1], 0.25f, 1e-7);
    EXPECT_NEAR(output[0], coefficient, 2e-6);
    EXPECT_NEAR(output[static_cast<size_t>(frames - 1) * 2], expectedGain, 2e-5);
    for (int frame = 1; frame < frames; ++frame) {
        EXPECT_TRUE(output[static_cast<size_t>(frame) * 2] >=
                    output[static_cast<size_t>(frame - 1) * 2] - 1e-7);
    }

    // Both decks active: the same per-frame gain is applied before summing.
    std::fill(output.begin(), output.end(), 0.0f);
    float bothGains[2] = {0.0f, 0.0f};
    EXPECT_TRUE(nar_stereo_mixer_process(
        mixer, deck0.data(), deck1.data(), 3u, frames, bothGains, targets, output.data()));
    const int checkFrame = 100;
    const float expectedAtCheck =
        1.0f - std::pow(1.0f - coefficient, checkFrame + 1);
    EXPECT_NEAR(
        output[static_cast<size_t>(checkFrame) * 2],
        expectedAtCheck * 1.0f + expectedAtCheck * 2.0f,
        1e-4);
    EXPECT_NEAR(bothGains[0], expectedGain, 2e-5);
    EXPECT_NEAR(bothGains[1], expectedGain, 2e-5);

    // Invalid/oversized blocks are rejected without touching output.
    std::vector<float> untouched(8, 42.0f);
    EXPECT_TRUE(nar_stereo_mixer_process(
        mixer, deck0.data(), nullptr, 1u, frames + 1, gains, targets, untouched.data()) == 0);
    for (float value : untouched) EXPECT_NEAR(value, 42.0f, 0.0f);

    nar_stereo_mixer_destroy(mixer);
}

void test_limiter() {
    const int sampleRate = 48000;
    const int frames = 8;
    NarStereoMixer* mixer = nar_stereo_mixer_create(sampleRate, frames);
    EXPECT_TRUE(mixer != nullptr);

    std::vector<float> loud(static_cast<size_t>(frames) * 2, 2.0f);
    std::vector<float> output(static_cast<size_t>(frames) * 2, 0.0f);
    float gains[2] = {1.0f, 1.0f};
    float targets[2] = {1.0f, 1.0f};

    EXPECT_TRUE(nar_stereo_mixer_process(
        mixer, loud.data(), nullptr, 1u, frames, gains, targets, output.data()));
    EXPECT_NEAR(output[0], 0.98f, 1e-6);
    for (float value : output) EXPECT_TRUE(std::fabs(value) <= 0.98f + 1e-7);

    // Limiter is stateful: one loud sample reduces gain, then a quiet sample is
    // attenuated by that gain and released only slightly.
    const float release = release_coefficient(sampleRate, 50.0f);
    std::vector<float> step(8);
    step[0] = 2.0f;
    step[1] = 2.0f;
    step[2] = 0.5f;
    step[3] = 0.5f;
    step[4] = std::numeric_limits<float>::quiet_NaN();
    step[5] = std::numeric_limits<float>::quiet_NaN();
    step[6] = 1.0f;
    step[7] = 1.0f;

    NarStereoMixer* fresh = nar_stereo_mixer_create(sampleRate, 4);
    float freshGains[2] = {1.0f, 1.0f};
    float freshTargets[2] = {1.0f, 1.0f};
    std::vector<float> freshOutput(8, -1.0f);
    EXPECT_TRUE(nar_stereo_mixer_process(
        fresh, step.data(), nullptr, 1u, 4, freshGains, freshTargets, freshOutput.data()));
    EXPECT_NEAR(freshOutput[0], 0.98f, 1e-6);

    float gainAfterLoud = 0.98f / 2.0f;
    // Sample 1 (0.5): peak * gain = 0.245 <= ceiling, so required=1.
    float gainAfterQuiet = gainAfterLoud + (1.0f - gainAfterLoud) * release;
    EXPECT_NEAR(freshOutput[2], 0.5f * gainAfterQuiet, 2e-6);
    // Sample 2 is NaN: output must be silence and the envelope must not move.
    EXPECT_NEAR(freshOutput[4], 0.0f, 1e-7);
    float gainAfterNaN = gainAfterQuiet + (1.0f - gainAfterQuiet) * release;
    EXPECT_NEAR(freshOutput[6], 1.0f * gainAfterNaN, 2e-6);

    // Reset restores unity gain.
    nar_stereo_mixer_reset(fresh);
    freshGains[0] = 1.0f;
    freshGains[1] = 1.0f;
    std::vector<float> quiet(8, 0.5f);
    EXPECT_TRUE(nar_stereo_mixer_process(
        fresh, quiet.data(), nullptr, 1u, 4, freshGains, freshTargets, freshOutput.data()));
    EXPECT_NEAR(freshOutput[0], 0.5f, 1e-7);

    nar_stereo_mixer_destroy(fresh);
    nar_stereo_mixer_destroy(mixer);
}

void test_mixer_sum_and_channels() {
    const int frames = 4;
    NarStereoMixer* mixer = nar_stereo_mixer_create(48000, frames);
    EXPECT_TRUE(mixer != nullptr);
    std::vector<float> deck0 = {0.25f, -0.25f, 0.25f, -0.25f, 0.25f, -0.25f, 0.25f, -0.25f};
    std::vector<float> deck1 = {0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f};
    std::vector<float> output(8, 0.0f);
    float gains[2] = {1.0f, 1.0f};
    float targets[2] = {1.0f, 1.0f};
    EXPECT_TRUE(nar_stereo_mixer_process(
        mixer, deck0.data(), deck1.data(), 3u, frames, gains, targets, output.data()));
    // With gain smoothing, gains fall slightly below 1, but both channels must
    // sum the two decks (not replace one another).
    EXPECT_NEAR(output[0], 0.75f, 1e-6);
    EXPECT_NEAR(output[1], 0.25f, 1e-6);

    // Neither deck active -> silence and unchanged gains.
    float heldGains[2] = {0.3f, 0.7f};
    std::fill(output.begin(), output.end(), 9.0f);
    EXPECT_TRUE(nar_stereo_mixer_process(
        mixer, nullptr, nullptr, 0u, frames, heldGains, targets, output.data()));
    for (float value : output) EXPECT_NEAR(value, 0.0f, 0.0f);
    EXPECT_NEAR(heldGains[0], 0.3f, 0.0f);
    EXPECT_NEAR(heldGains[1], 0.7f, 0.0f);

    nar_stereo_mixer_destroy(mixer);
}

}  // namespace

int main() {
    test_u8();
    test_s16();
    test_s24();
    test_s32();
    test_f32_f64_and_non_finite();
    test_downmix();
    test_resampler_block_invariance();
    test_resampler_downsample_and_bounds();
    test_gain_ramp();
    test_limiter();
    test_mixer_sum_and_channels();

    if (failures == 0) {
        std::printf("PASS: %d checks\n", checks);
        return 0;
    }
    std::fprintf(stderr, "FAILED: %d/%d checks\n", failures, checks);
    return 1;
}
