// Deterministic fuzz/invariant test for pcm_native. Run under ASan/UBSan.
#include "pcm_native.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <random>
#include <vector>

namespace {

int failures = 0;
int checks = 0;

void check(bool condition, const char* what, int iteration) {
    ++checks;
    if (!condition) {
        ++failures;
        std::fprintf(stderr, "FAIL iteration %d: %s\n", iteration, what);
    }
}

int bytesPerSample(int format) {
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

void fuzzConverters(std::mt19937& rng) {
    const int rates[] = {8000, 11025, 16000, 22050, 32000, 44100, 48000, 88200, 96000, 192000};
    for (int iteration = 0; iteration < 4000; ++iteration) {
        const int inputRate = rates[rng() % (sizeof(rates) / sizeof(rates[0]))];
        const int outputRate = rates[rng() % (sizeof(rates) / sizeof(rates[0]))];
        const int channels = 1 + static_cast<int>(rng() % 8);
        const int format = static_cast<int>(rng() % 6);
        const bool bigEndian = (rng() & 1u) != 0;
        const int frames = 1 + static_cast<int>(rng() % 4096);
        const int sampleBytes = bytesPerSample(format);
        if (sampleBytes == 0) {
            check(false, "invalid fuzz format", iteration);
            continue;
        }

        std::vector<uint8_t> input(
            static_cast<size_t>(frames) * channels * sampleBytes);
        for (uint8_t& byte : input) byte = static_cast<uint8_t>(rng());

        NarDeckConverter* converter =
            nar_deck_converter_create(inputRate, outputRate, 32, 256);
        check(converter != nullptr, "create converter", iteration);
        if (converter == nullptr) continue;

        const int capacity =
            nar_deck_converter_max_output_frames(converter, frames);
        check(capacity > 0, "positive capacity", iteration);
        if (capacity <= 0) {
            nar_deck_converter_destroy(converter);
            continue;
        }
        const int capLimit = 1'000'000;
        if (capacity > capLimit) {
            // Pathological rate ratio, but the API must still reject a small
            // buffer rather than write out of bounds.
            std::vector<float> small(8);
            const int rejected = nar_deck_converter_process(
                converter, input.data(), frames, channels, format,
                bigEndian ? 1 : 0, small.data(), 4);
            check(rejected == NAR_PCM_ERROR_ARGUMENT,
                  "pathological short buffer rejected", iteration);
            nar_deck_converter_destroy(converter);
            continue;
        }

        std::vector<float> output(static_cast<size_t>(capacity) * 2, -777.0f);
        const int produced = nar_deck_converter_process(
            converter,
            input.data(),
            frames,
            channels,
            format,
            bigEndian ? 1 : 0,
            output.data(),
            capacity);
        check(produced >= 0 && produced <= capacity,
              "produced within capacity", iteration);
        if (produced > 0) {
            const bool floatFormat = format == NAR_PCM_F32 || format == NAR_PCM_F64;
            for (int i = 0; i < produced * 2; ++i) {
                check(std::isfinite(output[i]), "finite converted sample", iteration);
                if (!floatFormat) {
                    // Resampler ringing can slightly overshoot full scale;
                    // downmixed surround is explicitly clamped to +/-8.
                    check(output[i] >= -16.0f && output[i] <= 16.0f,
                          "converted sample in range", iteration);
                }
            }
        }

        if (inputRate == outputRate) {
            check(produced == frames, "bypass frame count", iteration);
        }

        // A second block must work after the first, including a short block
        // after a longer one (history/input capacity retention).
        const int secondFrames = 1 + static_cast<int>(rng() % 512);
        std::vector<uint8_t> second(
            static_cast<size_t>(secondFrames) * channels * sampleBytes);
        const int secondCapacity =
            nar_deck_converter_max_output_frames(converter, secondFrames);
        if (secondCapacity <= 0 || secondCapacity > capLimit) {
            nar_deck_converter_destroy(converter);
            continue;
        }
        std::vector<float> secondOutput(
            static_cast<size_t>(std::max(secondCapacity, 1)) * 2, -888.0f);
        const int secondProduced = nar_deck_converter_process(
            converter,
            second.data(),
            secondFrames,
            channels,
            format,
            bigEndian ? 1 : 0,
            secondOutput.data(),
            std::max(secondCapacity, 1));
        check(secondProduced >= 0 && secondProduced <= std::max(secondCapacity, 1),
              "second block produced within capacity", iteration);

        nar_deck_converter_destroy(converter);
    }
}

void fuzzMixers(std::mt19937& rng) {
    for (int iteration = 0; iteration < 4000; ++iteration) {
        const int maxFrames = 1 + static_cast<int>(rng() % 1024);
        NarStereoMixer* mixer = nar_stereo_mixer_create(48000, maxFrames);
        check(mixer != nullptr, "create mixer", iteration);
        if (mixer == nullptr) continue;

        for (int block = 0; block < 8; ++block) {
            const int frames = 1 + static_cast<int>(rng() % maxFrames);
            std::vector<float> deck0(static_cast<size_t>(frames) * 2);
            std::vector<float> deck1(static_cast<size_t>(frames) * 2);
            for (float& value : deck0) {
                value = static_cast<float>(static_cast<int>(rng() % 4001) - 2000) / 1000.0f;
            }
            for (float& value : deck1) {
                value = static_cast<float>(static_cast<int>(rng() % 4001) - 2000) / 1000.0f;
            }
            if ((rng() & 15u) == 0) deck0[rng() % deck0.size()] =
                std::numeric_limits<float>::quiet_NaN();
            if ((rng() & 31u) == 0) deck1[rng() % deck1.size()] =
                (rng() & 1u) ? std::numeric_limits<float>::infinity()
                             : -std::numeric_limits<float>::infinity();

            std::vector<float> output(static_cast<size_t>(frames) * 2, -999.0f);
            float gains[2] = {
                (rng() & 1u) ? 1.0f : static_cast<float>(rng() % 1001) / 1000.0f,
                (rng() & 1u) ? 1.0f : static_cast<float>(rng() % 1001) / 1000.0f,
            };
            float targets[2] = {
                static_cast<float>(rng() % 1001) / 1000.0f,
                static_cast<float>(rng() % 1001) / 1000.0f,
            };
            const unsigned int mask = static_cast<unsigned int>(rng() % 4);
            const int result = nar_stereo_mixer_process(
                mixer,
                deck0.data(),
                deck1.data(),
                mask,
                frames,
                gains,
                targets,
                output.data());
            check(result == 1, "mixer result", iteration);
            for (int i = 0; i < frames * 2; ++i) {
                check(std::isfinite(output[i]), "finite mixed sample", iteration);
                check(std::fabs(output[i]) <= 0.9800001f,
                      "limited mixed sample", iteration);
            }
            check(std::isfinite(gains[0]) && gains[0] >= 0.0f && gains[0] <= 1.0f,
                  "finite gain 0", iteration);
            check(std::isfinite(gains[1]) && gains[1] >= 0.0f && gains[1] <= 1.0f,
                  "finite gain 1", iteration);

            if (mask == 0) {
                for (float value : output) check(value == 0.0f, "mask zero silence", iteration);
            }
        }

        nar_stereo_mixer_destroy(mixer);
    }
}

}  // namespace

int main() {
    std::mt19937 rng(0xC0FFEEu);
    fuzzConverters(rng);
    fuzzMixers(rng);
    if (failures == 0) {
        std::printf("PASS: %d fuzz checks\n", checks);
        return 0;
    }
    std::fprintf(stderr, "FAILED: %d/%d fuzz checks\n", failures, checks);
    return 1;
}
