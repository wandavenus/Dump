package dev.wndavenz.music.audio.mixer

import java.nio.ByteBuffer

/**
 * JNI surface for `libpcm_mixer_native.so` — the C++/NEON implementation of
 * the single-AudioTrack PCM path.
 *
 * The native library owns:
 *  - decoder byte → stereo float conversion for every supported PCM layout;
 *  - windowed-sinc sample-rate conversion onto the shared bus rate;
 *  - per-frame deck gain ramps, two-deck summation and the post-sum limiter.
 *
 * Kotlin keeps the ring buffers, source-timeline mappings and Media3 sink
 * contract. Those are metadata/state machines, not sample math; keeping them
 * on the Kotlin side is what makes seeking/EOS/position deterministic.
 *
 * The library is optional. If it is missing (JVM unit tests, a build without
 * the native target, or an unsupported ABI), [isAvailable] is false and the
 * mixer falls back to the Kotlin reference implementation. No caller may throw
 * from the audio thread because the native library is unavailable.
 */
object NativePcmBridge {

    /** Native `NarPcmFormat` ordinals — keep in sync with pcm_native.h. */
    private const val FORMAT_U8 = 0
    private const val FORMAT_S16 = 1
    private const val FORMAT_S24 = 2
    private const val FORMAT_S32 = 3
    private const val FORMAT_F32 = 4
    private const val FORMAT_F64 = 5

    /** Whether `libpcm_mixer_native.so` was loaded. Evaluated once. */
    val isAvailable: Boolean = runCatching {
        System.loadLibrary("pcm_mixer_native")
        true
    }.getOrDefault(false)

    fun nativeFormat(format: PcmSampleFormat): Int = when (format) {
        PcmSampleFormat.UNSIGNED_8 -> FORMAT_U8
        PcmSampleFormat.SIGNED_16 -> FORMAT_S16
        PcmSampleFormat.SIGNED_24 -> FORMAT_S24
        PcmSampleFormat.SIGNED_32 -> FORMAT_S32
        PcmSampleFormat.FLOAT_32 -> FORMAT_F32
        PcmSampleFormat.FLOAT_64 -> FORMAT_F64
    }

    /** Returns a non-zero converter handle, or 0 when native is unavailable. */
    fun createDeckConverter(inputRate: Int, outputRate: Int): Long {
        if (!isAvailable || inputRate <= 0 || outputRate <= 0) return 0L
        return try {
            nativeCreateDeckConverter(inputRate, outputRate)
        } catch (_: LinkageError) {
            0L
        }
    }

    fun destroyDeckConverter(handle: Long) {
        if (!isAvailable || handle == 0L) return
        try {
            nativeDestroyDeckConverter(handle)
        } catch (_: LinkageError) {
            // The handle is already unusable if the library disappeared.
        }
    }

    fun resetDeckConverter(handle: Long) {
        if (!isAvailable || handle == 0L) return
        try {
            nativeResetDeckConverter(handle)
        } catch (_: LinkageError) {
            // Best-effort state reset.
        }
    }

    fun deckOutputFramesUpperBound(handle: Long, inputFrames: Int): Int {
        if (!isAvailable || handle == 0L || inputFrames <= 0) return 0
        return try {
            nativeDeckOutputFramesUpperBound(handle, inputFrames)
        } catch (_: LinkageError) {
            0
        }
    }

    /**
     * Converts [inputFrames] interleaved frames from [input] into [output].
     *
     * [offsetBytes] is relative to the start of the direct buffer (not its
     * current position). [output] must hold at least
     * [deckOutputFramesUpperBound] stereo frames.
     *
     * Returns the number of frames written, or a negative status. Callers must
     * fall back to the Kotlin converter on any negative result.
     */
    fun processDeck(
        handle: Long,
        input: ByteBuffer,
        offsetBytes: Int,
        inputFrames: Int,
        channels: Int,
        format: PcmSampleFormat,
        bigEndian: Boolean,
        output: FloatArray,
    ): Int {
        if (!isAvailable || handle == 0L || !input.isDirect) return -1
        return try {
            nativeProcessDeck(
                handle,
                input,
                offsetBytes,
                inputFrames,
                channels,
                nativeFormat(format),
                bigEndian,
                output,
            )
        } catch (_: LinkageError) {
            -1
        }
    }

    /** Returns a non-zero mixer handle, or 0 when native is unavailable. */
    fun createMixer(sampleRate: Int, maxBlockFrames: Int): Long {
        if (!isAvailable || sampleRate <= 0 || maxBlockFrames <= 0) return 0L
        return try {
            nativeCreateMixer(sampleRate, maxBlockFrames)
        } catch (_: LinkageError) {
            0L
        }
    }

    fun destroyMixer(handle: Long) {
        if (!isAvailable || handle == 0L) return
        try {
            nativeDestroyMixer(handle)
        } catch (_: LinkageError) {
            // Teardown is best-effort.
        }
    }

    fun resetMixer(handle: Long) {
        if (!isAvailable || handle == 0L) return
        try {
            nativeResetMixer(handle)
        } catch (_: LinkageError) {
            // Best-effort state reset.
        }
    }

    /**
     * Mixes the active decks into [output] and applies the bus limiter.
     *
     * [gains] is updated in place with the smoothed gain after this block.
     * Returns false if the native library rejected the call; the engine then
     * falls back to its Kotlin path for this block.
     */
    fun mix(
        handle: Long,
        activeMask: Int,
        deck0: FloatArray,
        deck1: FloatArray,
        gains: FloatArray,
        targets: FloatArray,
        output: FloatArray,
        frames: Int,
    ): Boolean {
        if (!isAvailable || handle == 0L || frames <= 0) return false
        return try {
            nativeMix(handle, activeMask, deck0, deck1, gains, targets, output, frames)
        } catch (_: LinkageError) {
            false
        }
    }

    @JvmStatic
    private external fun nativeCreateDeckConverter(inputRate: Int, outputRate: Int): Long

    @JvmStatic
    private external fun nativeDestroyDeckConverter(handle: Long)

    @JvmStatic
    private external fun nativeResetDeckConverter(handle: Long)

    @JvmStatic
    private external fun nativeDeckOutputFramesUpperBound(handle: Long, inputFrames: Int): Int

    @JvmStatic
    private external fun nativeProcessDeck(
        handle: Long,
        input: ByteBuffer,
        offsetBytes: Int,
        inputFrames: Int,
        channels: Int,
        format: Int,
        bigEndian: Boolean,
        output: FloatArray,
    ): Int

    @JvmStatic
    private external fun nativeCreateMixer(sampleRate: Int, maxBlockFrames: Int): Long

    @JvmStatic
    private external fun nativeDestroyMixer(handle: Long)

    @JvmStatic
    private external fun nativeResetMixer(handle: Long)

    @JvmStatic
    private external fun nativeMix(
        handle: Long,
        activeMask: Int,
        deck0: FloatArray,
        deck1: FloatArray,
        gains: FloatArray,
        targets: FloatArray,
        output: FloatArray,
        frames: Int,
    ): Boolean
}
