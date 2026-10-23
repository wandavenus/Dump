package dev.wndavenz.music.automix

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.math.sqrt
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Offline audio render regression for the crossfade envelope.
 *
 * Renders the production [AutomixGainEnvelope] over synthetic (or FFmpeg-
 * generated) source signals at a realistic 48 kHz / 16 ms tick cadence, writes
 * 32-bit float WAVs, and checks for sample discontinuities. The companion
 * `tools/automix_ffmpeg_regression.sh` analyzes the same WAVs with FFmpeg
 * `astats` so the result is independently measured by a second tool.
 *
 * The legacy renders are deliberate fault models:
 *  - mid-fade cancel: outgoing deck stops and the promoted deck jumps to the
 *    pre-duck volume (the old `setCrossfadeDuration` path);
 *  - volume copy: the promoted deck is audible at full volume for one tick
 *    before the first equal-power update (the old `ActivePlayerProxy` path).
 * They prove that the metric used below is sensitive to both regressions.
 */
class AutomixFadeRenderTest {

    private companion object {
        const val SAMPLE_RATE = 48_000
        const val PRE_ROLL_MS = 500
        const val FADE_MS = 3_000
        const val POST_ROLL_MS = 500
        const val TICK_MS = 16
        const val TARGET_VOLUME = 1f
        const val PRE_ROLL_FRAMES = PRE_ROLL_MS * SAMPLE_RATE / 1_000
        const val FADE_FRAMES = FADE_MS * SAMPLE_RATE / 1_000
        const val TICK_FRAMES = TICK_MS * SAMPLE_RATE / 1_000
        const val TOTAL_FRAMES =
            (PRE_ROLL_MS + FADE_MS + POST_ROLL_MS) * SAMPLE_RATE / 1_000

        // The source phase is chosen so the sample at 40% into the fade is
        // A=-0.5 and B=+0.4. That makes the legacy cancel discontinuity
        // deterministic instead of depending on accidental phase alignment.
        const val CANCEL_PROGRESS = 0.4f
        const val CANCEL_TIME_SECONDS =
            (PRE_ROLL_MS + FADE_MS * CANCEL_PROGRESS) / 1_000.0
        const val A_FREQUENCY = 220.0
        const val B_FREQUENCY = 330.0
        const val A_AMPLITUDE = 0.5f
        const val B_AMPLITUDE = 0.4f
        const val A_PHASE =
            -PI / 2.0 - 2.0 * PI * A_FREQUENCY * CANCEL_TIME_SECONDS
        const val B_PHASE =
            PI / 2.0 - 2.0 * PI * B_FREQUENCY * CANCEL_TIME_SECONDS
    }

    @Test
    fun `current envelope stays continuous while legacy fault models expose hard cuts`() {
        val (sourceA, sourceB) = loadOrSynthesizeSources()
        val outputDir = audioOutputDir().also { it.mkdirs() }

        val current = renderCurrent(sourceA, sourceB, gamma = 1f, 1f, 1f)
        val currentQuick = renderCurrent(
            sourceA,
            sourceB,
            gamma = 1.35f,
            outgoingTrim = 0.7f,
            incomingTrim = 0.8f,
        )
        val legacyCancel = renderLegacyMidFadeCancel(sourceA, sourceB)
        val legacyCopy = renderLegacyVolumeCopy(sourceA, sourceB)

        writeWav(File(outputDir, "current_envelope_gamma1.wav"), current)
        writeWav(File(outputDir, "current_envelope_gamma135_trims.wav"), currentQuick)
        writeWav(File(outputDir, "legacy_midfade_cancel.wav"), legacyCancel)
        writeWav(File(outputDir, "legacy_volume_copy.wav"), legacyCopy)

        val currentJump = maxAbsDifference(current)
        val currentQuickJump = maxAbsDifference(currentQuick)
        val cancelJump = maxAbsDifference(legacyCancel)
        val copyJump = maxAbsDifference(legacyCopy)

        // The current envelope is stepped at 16 ms, so small gain steps are
        // expected. The source tones themselves are < 0.02 per sample here.
        assertTrue(
            "current envelope jump $currentJump must stay below a click-sized step",
            currentJump < 0.05f,
        )
        assertTrue(
            "current envelope with trims jump $currentQuickJump must stay below a click-sized step",
            currentQuickJump < 0.05f,
        )
        assertTrue(
            "current envelope must not clip: peak ${maxAbs(current)}",
            maxAbs(current) <= 1.0f + 0.0001f,
        )
        assertTrue(
            "current envelope must not collapse to silence: rms ${rms(current)}",
            rms(current) > 0.01f,
        )

        // Sensitivity of the metric: both legacy paths must be detected as a
        // hard cut, otherwise this test could pass while the bug returns.
        assertTrue(
            "legacy mid-fade cancel must produce a hard cut, got $cancelJump",
            cancelJump > 0.25f,
        )
        assertTrue(
            "legacy volume copy must produce an audible pre-fade step, got $copyJump",
            copyJump > 0.20f,
        )

        val normalLeakPeak = leakWindowPeak(current)
        val legacyLeakPeak = leakWindowPeak(legacyCopy)
        assertTrue(
            "legacy copy must leak the incoming deck above the current envelope " +
                "(current=$normalLeakPeak legacy=$legacyLeakPeak)",
            legacyLeakPeak > normalLeakPeak + 0.20f,
        )

        println(
            "AUTOMIX_AUDIO_RENDER dir=${outputDir.absolutePath} " +
                "currentJump=$currentJump currentQuickJump=$currentQuickJump " +
                "cancelJump=$cancelJump copyJump=$copyJump " +
                "normalLeakPeak=$normalLeakPeak legacyLeakPeak=$legacyLeakPeak",
        )
    }

    private fun renderCurrent(
        sourceA: FloatArray,
        sourceB: FloatArray,
        gamma: Float,
        outgoingTrim: Float,
        incomingTrim: Float,
    ): FloatArray {
        val out = FloatArray(TOTAL_FRAMES)
        var outgoingGain = 1f
        var incomingGain = 0f
        for (frame in 0 until TOTAL_FRAMES) {
            val relative = frame - PRE_ROLL_FRAMES
            if (relative in 0 until FADE_FRAMES) {
                if (relative % TICK_FRAMES == 0) {
                    val gains = AutomixGainEnvelope.gains(
                        progress = relative.toFloat() / FADE_FRAMES,
                        targetVolume = TARGET_VOLUME,
                        curveGamma = gamma,
                        outgoingTrim = outgoingTrim,
                        incomingTrim = incomingTrim,
                    )
                    outgoingGain = gains.outgoing
                    incomingGain = gains.incoming
                }
            } else if (relative < 0) {
                outgoingGain = 1f
                incomingGain = 0f
            } else {
                outgoingGain = 0f
                incomingGain = 1f
            }
            out[frame] = sourceA[frame] * outgoingGain + sourceB[frame] * incomingGain
        }
        return out
    }

    private fun renderLegacyMidFadeCancel(
        sourceA: FloatArray,
        sourceB: FloatArray,
    ): FloatArray {
        val out = FloatArray(TOTAL_FRAMES)
        val cancelFrame = PRE_ROLL_FRAMES + (FADE_FRAMES * CANCEL_PROGRESS).toInt()
        var outgoingGain = 1f
        var incomingGain = 0f
        for (frame in 0 until TOTAL_FRAMES) {
            val relative = frame - PRE_ROLL_FRAMES
            if (relative >= cancelFrame - PRE_ROLL_FRAMES) {
                // Old cancel path: outgoing deck stopped, promoted deck restored
                // to volumeBeforeDuck (1.0 here) immediately.
                out[frame] = sourceB[frame] * TARGET_VOLUME
                continue
            }
            if (relative in 0 until FADE_FRAMES && relative % TICK_FRAMES == 0) {
                val gains = AutomixGainEnvelope.gains(
                    progress = relative.toFloat() / FADE_FRAMES,
                    targetVolume = TARGET_VOLUME,
                    curveGamma = 1f,
                    outgoingTrim = 1f,
                    incomingTrim = 1f,
                )
                outgoingGain = gains.outgoing
                incomingGain = gains.incoming
            }
            out[frame] = sourceA[frame] * outgoingGain + sourceB[frame] * incomingGain
        }
        return out
    }

    private fun renderLegacyVolumeCopy(
        sourceA: FloatArray,
        sourceB: FloatArray,
    ): FloatArray {
        val out = FloatArray(TOTAL_FRAMES)
        var outgoingGain = 1f
        var incomingGain = 0f
        for (frame in 0 until TOTAL_FRAMES) {
            val relative = frame - PRE_ROLL_FRAMES
            if (relative in 0 until FADE_FRAMES) {
                if (relative % TICK_FRAMES == 0) {
                    val gains = AutomixGainEnvelope.gains(
                        progress = relative.toFloat() / FADE_FRAMES,
                        targetVolume = TARGET_VOLUME,
                        curveGamma = 1f,
                        outgoingTrim = 1f,
                        incomingTrim = 1f,
                    )
                    outgoingGain = gains.outgoing
                    incomingGain = gains.incoming
                }
                // One tick of main-thread delay before the first envelope
                // update. The old proxy copied A's volume (1.0) onto B.
                val leaking = relative < TICK_FRAMES
                out[frame] = sourceA[frame] * (if (leaking) 1f else outgoingGain) +
                    sourceB[frame] * (if (leaking) 1f else incomingGain)
            } else if (relative < 0) {
                out[frame] = sourceA[frame]
            } else {
                out[frame] = sourceB[frame]
            }
        }
        return out
    }

    private fun loadOrSynthesizeSources(): Pair<FloatArray, FloatArray> {
        val sourceDir = System.getenv("AUTOMIX_AUDIO_SOURCE_DIR")
        val requireSources = System.getenv("AUTOMIX_AUDIO_REQUIRE_SOURCES") == "1"
        if (!sourceDir.isNullOrBlank()) {
            val a = File(sourceDir, "source_a.wav")
            val b = File(sourceDir, "source_b.wav")
            if (requireSources) {
                check(a.isFile && b.isFile) {
                    "FFmpeg source WAVs are required but missing in $sourceDir"
                }
            }
            if (a.isFile && b.isFile) {
                return readPcmFloatWav(a) to readPcmFloatWav(b)
            }
        }
        return synthesize(amplitude = A_AMPLITUDE, frequency = A_FREQUENCY, phase = A_PHASE) to
            synthesize(amplitude = B_AMPLITUDE, frequency = B_FREQUENCY, phase = B_PHASE)
    }

    private fun synthesize(amplitude: Float, frequency: Double, phase: Double): FloatArray =
        FloatArray(TOTAL_FRAMES) { frame ->
            (amplitude * sin(2.0 * PI * frequency * frame / SAMPLE_RATE + phase)).toFloat()
        }

    private fun readPcmFloatWav(file: File): FloatArray {
        val bytes = file.readBytes()
        require(bytes.size >= 44) { "${file.name} is too short to be a WAV file" }
        require(String(bytes, 0, 4, Charsets.US_ASCII) == "RIFF") {
            "${file.name} is not a RIFF file"
        }
        require(String(bytes, 8, 4, Charsets.US_ASCII) == "WAVE") {
            "${file.name} is not a WAVE file"
        }
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        var offset = 12
        var format = -1
        var channels = -1
        var sampleRate = -1
        var bitsPerSample = -1
        var dataOffset = -1
        var dataSize = -1
        while (offset + 8 <= bytes.size) {
            val id = String(bytes, offset, 4, Charsets.US_ASCII)
            val size = buffer.getInt(offset + 4)
            require(size >= 0) { "negative WAV chunk size ${file.name}" }
            if (id == "fmt ") {
                // FFmpeg >= 6.1 writes 32-bit float mono as
                // WAVE_FORMAT_EXTENSIBLE (0xFFFE) with the IEEE-float GUID
                // (0x0003) in the SubFormat field instead of the legacy
                // plain WAVE_FORMAT_IEEE_FLOAT tag. Accept both encodings
                // while still requiring the effective format to be float.
                val declaredFormat = buffer.getShort(offset + 8).toInt() and 0xFFFF
                format = if (declaredFormat == 0xFFFE) {
                    buffer.getShort(offset + 8 + 24).toInt() and 0xFFFF
                } else {
                    declaredFormat
                }
                channels = buffer.getShort(offset + 10).toInt()
                sampleRate = buffer.getInt(offset + 12)
                bitsPerSample = buffer.getShort(offset + 22).toInt()
            } else if (id == "data") {
                dataOffset = offset + 8
                dataSize = minOf(size, bytes.size - dataOffset)
            }
            offset += 8 + size + (size and 1)
        }
        require(format == 3) { "${file.name} must be IEEE float PCM" }
        require(channels == 1) { "${file.name} must be mono" }
        require(sampleRate == SAMPLE_RATE) { "${file.name} must be $SAMPLE_RATE Hz" }
        require(bitsPerSample == 32) { "${file.name} must be 32-bit float" }
        require(dataOffset >= 0 && dataSize >= 0) { "${file.name} has no data chunk" }
        val frames = dataSize / 4
        require(frames >= TOTAL_FRAMES) {
            "${file.name} has $frames frames, need $TOTAL_FRAMES"
        }
        val data = ByteBuffer.wrap(bytes, dataOffset, TOTAL_FRAMES * 4)
            .order(ByteOrder.LITTLE_ENDIAN)
        return FloatArray(TOTAL_FRAMES) { data.float }
    }

    private fun writeWav(file: File, samples: FloatArray) {
        val dataSize = samples.size * 4
        val buffer = ByteBuffer.allocate(44 + dataSize).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put("RIFF".toByteArray(Charsets.US_ASCII))
        buffer.putInt(36 + dataSize)
        buffer.put("WAVE".toByteArray(Charsets.US_ASCII))
        buffer.put("fmt ".toByteArray(Charsets.US_ASCII))
        buffer.putInt(16) // PCM fmt chunk size
        buffer.putShort(3) // IEEE float
        buffer.putShort(1) // mono
        buffer.putInt(SAMPLE_RATE)
        buffer.putInt(SAMPLE_RATE * 4) // byte rate
        buffer.putShort(4) // block align
        buffer.putShort(32) // bits per sample
        buffer.put("data".toByteArray(Charsets.US_ASCII))
        buffer.putInt(dataSize)
        for (sample in samples) buffer.putFloat(sample)
        file.parentFile?.mkdirs()
        file.writeBytes(buffer.array())
    }

    private fun audioOutputDir(): File =
        System.getenv("AUTOMIX_AUDIO_OUTPUT_DIR")
            ?.takeIf { it.isNotBlank() }
            ?.let(::File)
            ?: File("build/automix-audio-regression")

    private fun maxAbs(samples: FloatArray): Float {
        var max = 0f
        for (sample in samples) max = maxOf(max, abs(sample))
        return max
    }

    private fun maxAbsDifference(samples: FloatArray): Float {
        var max = 0f
        for (index in 1 until samples.size) {
            max = maxOf(max, abs(samples[index] - samples[index - 1]))
        }
        return max
    }

    private fun rms(samples: FloatArray): Float {
        var sum = 0.0
        for (sample in samples) sum += sample.toDouble() * sample
        return sqrt(sum / samples.size).toFloat()
    }

    private fun leakWindowPeak(samples: FloatArray): Float {
        // First fade tick: the window where a copied volume could be audible
        // before the equal-power envelope takes ownership of the incoming deck.
        val start = PRE_ROLL_FRAMES
        val end = minOf(start + TICK_FRAMES, samples.size)
        var max = 0f
        for (index in start until end) max = maxOf(max, abs(samples[index]))
        return max
    }
}
