package dev.wndavenz.music.audio.mixer

import java.nio.ByteBuffer

/**
 * Linear PCM sample layouts the deck pipeline can convert. Kept free of Media3
 * so the mixer core stays JVM-testable; `DeckAudioSink` maps
 * `C.ENCODING_PCM_*` onto these values.
 */
enum class PcmSampleFormat(val bytesPerSample: Int) {
    UNSIGNED_8(1),
    SIGNED_16(2),
    SIGNED_24(3),
    SIGNED_32(4),
    FLOAT_32(4),
    FLOAT_64(8),
}

/**
 * Byte-level conversion helpers shared by [DeckAudioPipeline] and the JVM
 * tests.
 *
 * Decoder output is treated as little-endian unless the caller says otherwise;
 * Media3 decoders emit native-endian PCM, which is little-endian on every
 * Android ABI this app ships (arm64-v8a).
 */
object PcmConversions {

    /** Reads [frames] interleaved frames from [src] and returns float samples. */
    fun readFloats(
        src: ByteBuffer,
        offsetBytes: Int,
        frames: Int,
        channelCount: Int,
        format: PcmSampleFormat,
        bigEndian: Boolean,
    ): FloatArray {
        require(frames >= 0 && channelCount > 0)
        val samples = frames * channelCount
        val out = FloatArray(samples)
        val frameSize = format.bytesPerSample * channelCount
        val base = src.position() + offsetBytes
        for (i in 0 until samples) {
            val byteIndex = base + (i / channelCount) * frameSize +
                (i % channelCount) * format.bytesPerSample
            out[i] = readSample(src, byteIndex, format, bigEndian)
        }
        return out
    }

    /** Reads [frames] interleaved frames from a heap array. */
    fun readFloats(
        src: ByteArray,
        offsetBytes: Int,
        frames: Int,
        channelCount: Int,
        format: PcmSampleFormat,
        bigEndian: Boolean,
    ): FloatArray {
        require(frames >= 0 && channelCount > 0)
        val samples = frames * channelCount
        val out = FloatArray(samples)
        val frameSize = format.bytesPerSample * channelCount
        for (i in 0 until samples) {
            val byteIndex = offsetBytes + (i / channelCount) * frameSize +
                (i % channelCount) * format.bytesPerSample
            out[i] = readSample(src, byteIndex, format, bigEndian)
        }
        return out
    }

    /**
     * Folds [channelCount] interleaved channels down to stereo.
     *
     * Mono is duplicated, stereo is copied unchanged, and common surround
     * layouts are folded with 0.707 (-3 dB) side/centre coefficients. Unknown
     * layouts keep the first two channels and add the remaining channels at a
     * conservative level. This is a bus normalisation fallback, not a
     * bit-exact surround downmix.
     */
    fun toStereo(
        src: FloatArray,
        frames: Int,
        channelCount: Int,
        dst: FloatArray = FloatArray(frames * PcmRingBuffer.CHANNELS),
    ): FloatArray {
        require(src.size >= frames * channelCount)
        require(dst.size >= frames * PcmRingBuffer.CHANNELS)
        when (channelCount) {
            1 -> {
                for (frame in 0 until frames) {
                    val sample = src[frame]
                    dst[frame * 2] = sample
                    dst[frame * 2 + 1] = sample
                }
            }
            2 -> {
                System.arraycopy(src, 0, dst, 0, frames * 2)
            }
            else -> {
                for (frame in 0 until frames) {
                    val base = frame * channelCount
                    var left = src[base]
                    var right = src[base + 1]
                    when (channelCount) {
                        3 -> {
                            left += 0.70710677f * src[base + 2]
                            right += 0.70710677f * src[base + 2]
                        }
                        4 -> {
                            left += 0.70710677f * src[base + 2]
                            right += 0.70710677f * src[base + 3]
                        }
                        6 -> {
                            left += 0.70710677f * (src[base + 2] + src[base + 4])
                            right += 0.70710677f * (src[base + 2] + src[base + 5])
                        }
                        8 -> {
                            left += 0.70710677f * (src[base + 2] + src[base + 4] + src[base + 6])
                            right += 0.70710677f * (src[base + 2] + src[base + 5] + src[base + 7])
                        }
                        else -> {
                            var extra = 0f
                            for (channel in 2 until channelCount) extra += src[base + channel]
                            extra = extra / (channelCount - 2) * 0.5f
                            left += extra
                            right += extra
                        }
                    }
                    dst[frame * 2] = left.coerceIn(-8f, 8f)
                    dst[frame * 2 + 1] = right.coerceIn(-8f, 8f)
                }
            }
        }
        return dst
    }

    private fun readSample(
        src: ByteBuffer,
        byteIndex: Int,
        format: PcmSampleFormat,
        bigEndian: Boolean,
    ): Float {
        return when (format) {
            PcmSampleFormat.UNSIGNED_8 -> ((src.get(byteIndex).toInt() and 0xFF) - 128) / 128f
            PcmSampleFormat.SIGNED_16 -> {
                val raw = if (bigEndian) {
                    ((src.get(byteIndex).toInt() and 0xFF) shl 8) or
                        (src.get(byteIndex + 1).toInt() and 0xFF)
                } else {
                    ((src.get(byteIndex + 1).toInt() and 0xFF) shl 8) or
                        (src.get(byteIndex).toInt() and 0xFF)
                }
                raw.toShort() / 32768f
            }
            PcmSampleFormat.SIGNED_24 -> {
                val b0 = src.get(byteIndex).toInt() and 0xFF
                val b1 = src.get(byteIndex + 1).toInt() and 0xFF
                val b2 = src.get(byteIndex + 2).toInt() and 0xFF
                val raw = if (bigEndian) {
                    (b0 shl 16) or (b1 shl 8) or b2
                } else {
                    (b2 shl 16) or (b1 shl 8) or b0
                }
                val signed = if ((raw and 0x800000) != 0) raw or 0xFF000000.toInt() else raw
                signed / 8388608f
            }
            PcmSampleFormat.SIGNED_32 -> {
                val raw = readInt(src, byteIndex, bigEndian)
                raw / 2147483648f
            }
            PcmSampleFormat.FLOAT_32 -> Float.fromBits(readInt(src, byteIndex, bigEndian))
            PcmSampleFormat.FLOAT_64 -> {
                val high = readInt(src, byteIndex + 4, bigEndian).toLong() and 0xFFFFFFFFL
                val low = readInt(src, byteIndex, bigEndian).toLong() and 0xFFFFFFFFL
                Double.fromBits((high shl 32) or low).toFloat()
            }
        }
    }

    private fun readSample(
        src: ByteArray,
        byteIndex: Int,
        format: PcmSampleFormat,
        bigEndian: Boolean,
    ): Float {
        return when (format) {
            PcmSampleFormat.UNSIGNED_8 -> ((src[byteIndex].toInt() and 0xFF) - 128) / 128f
            PcmSampleFormat.SIGNED_16 -> {
                val b0 = src[byteIndex].toInt() and 0xFF
                val b1 = src[byteIndex + 1].toInt() and 0xFF
                val raw = if (bigEndian) (b0 shl 8) or b1 else (b1 shl 8) or b0
                raw.toShort() / 32768f
            }
            PcmSampleFormat.SIGNED_24 -> {
                val b0 = src[byteIndex].toInt() and 0xFF
                val b1 = src[byteIndex + 1].toInt() and 0xFF
                val b2 = src[byteIndex + 2].toInt() and 0xFF
                val raw = if (bigEndian) {
                    (b0 shl 16) or (b1 shl 8) or b2
                } else {
                    (b2 shl 16) or (b1 shl 8) or b0
                }
                val signed = if ((raw and 0x800000) != 0) raw or 0xFF000000.toInt() else raw
                signed / 8388608f
            }
            PcmSampleFormat.SIGNED_32 -> {
                val raw = readInt(src, byteIndex, bigEndian)
                raw / 2147483648f
            }
            PcmSampleFormat.FLOAT_32 -> Float.fromBits(readInt(src, byteIndex, bigEndian))
            PcmSampleFormat.FLOAT_64 -> {
                val high = readInt(src, byteIndex + 4, bigEndian).toLong() and 0xFFFFFFFFL
                val low = readInt(src, byteIndex, bigEndian).toLong() and 0xFFFFFFFFL
                Double.fromBits((high shl 32) or low).toFloat()
            }
        }
    }

    private fun readInt(src: ByteBuffer, index: Int, bigEndian: Boolean): Int {
        return if (bigEndian) {
            ((src.get(index).toInt() and 0xFF) shl 24) or
                ((src.get(index + 1).toInt() and 0xFF) shl 16) or
                ((src.get(index + 2).toInt() and 0xFF) shl 8) or
                (src.get(index + 3).toInt() and 0xFF)
        } else {
            ((src.get(index + 3).toInt() and 0xFF) shl 24) or
                ((src.get(index + 2).toInt() and 0xFF) shl 16) or
                ((src.get(index + 1).toInt() and 0xFF) shl 8) or
                (src.get(index).toInt() and 0xFF)
        }
    }

    private fun readInt(src: ByteArray, index: Int, bigEndian: Boolean): Int {
        return if (bigEndian) {
            ((src[index].toInt() and 0xFF) shl 24) or
                ((src[index + 1].toInt() and 0xFF) shl 16) or
                ((src[index + 2].toInt() and 0xFF) shl 8) or
                (src[index + 3].toInt() and 0xFF)
        } else {
            ((src[index + 3].toInt() and 0xFF) shl 24) or
                ((src[index + 2].toInt() and 0xFF) shl 16) or
                ((src[index + 1].toInt() and 0xFF) shl 8) or
                (src[index].toInt() and 0xFF)
        }
    }
}
