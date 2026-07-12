package dev.wndavenz.music.ffmpeg

import dev.wndavenz.music.events.NativeLogger

/**
 * Phase 9 — FFmpeg decoder capability probe.
 *
 * ## Why reflection
 *
 * `androidx.media3:media3-decoder-ffmpeg` is **not** on any public Maven
 * repository. The AAR (including the native `libffmpegJNI.so`) must be built
 * from the androidx/media source tree using `android/build-ffmpeg-jni.sh`
 * (requires Android NDK) and dropped as a local Gradle module at
 * `android/decoder-ffmpeg/`. Until that module is present, the class is not on
 * the classpath at all and this probe returns `available = false`.
 *
 * Reflection is kept so that this file compiles and runs cleanly whether or not
 * the module is present: `Class.forName` returning null and `isAvailable()`
 * returning false both collapse to `available = false` — callers get a single
 * yes/no answer and ExoPlayer falls back to the platform MediaCodec ALAC
 * decoder automatically with zero code changes needed.
 *
 * ## What "available" means
 *
 * `FfmpegLibrary.isAvailable()` returns true only if the class exists AND the
 * native `libffmpegJNI.so` was successfully `System.loadLibrary`'d. A missing
 * class (module not vendored) and a present-but-unloadable native lib both
 * collapse to `available = false` here — callers only need "can I use it or
 * not", not the specific reason.
 */
object FfmpegCapabilityProbe {

    private const val LIBRARY_CLASS = "androidx.media3.decoder.ffmpeg.FfmpegLibrary"

    // MIME type constants, duplicated from androidx.media3.common.MimeTypes so
    // this file has zero compile-time dependency on the ffmpeg module or on
    // any media3-common symbol that could shift between versions.
    // Official-path scope only (Phase 9): formats Media3 can already demux
    // (container/extractor support exists) but has no on-device MediaCodec
    // decoder for. APE/WavPack/TAK are explicitly out of scope — see the
    // Phase 9 doc's "Deferred" section.
    private val PROBE_MIME_TYPES = linkedMapOf(
        "audio/alac" to "ALAC",
        "audio/vnd.dts" to "DTS",
        "audio/vnd.dts.hd" to "DTS-HD",
        "audio/true-hd" to "TrueHD",
        "audio/vorbis" to "Vorbis",
        "audio/opus" to "Opus",
    )

    data class Status(
        val available: Boolean,
        val version: String?,
        val supportedCodecs: List<String>,
        /** True only if the ffmpeg module class was found on the classpath at all. */
        val moduleLinked: Boolean,
    )

    private var cached: Status? = null

    /** Cheap after the first call — the underlying reflective lookups are cached. */
    fun queryStatus(): Status {
        cached?.let { return it }

        val libraryClass = try {
            Class.forName(LIBRARY_CLASS)
        } catch (_: ClassNotFoundException) {
            null
        } catch (t: Throwable) {
            // Defensive: any other classloading failure (e.g. LinkageError from a
            // half-vendored module) must not crash playback.
            NativeLogger.emit("warn", "Ffmpeg", "FfmpegLibrary classload failed: $t")
            null
        }

        if (libraryClass == null) {
            val result = Status(
                available = false,
                version = null,
                supportedCodecs = emptyList(),
                moduleLinked = false,
            )
            cached = result
            return result
        }

        val result = try {
            val isAvailableMethod = libraryClass.getMethod("isAvailable")
            val available = isAvailableMethod.invoke(null) as? Boolean ?: false

            if (!available) {
                Status(available = false, version = null, supportedCodecs = emptyList(), moduleLinked = true)
            } else {
                val version = try {
                    libraryClass.getMethod("getVersion").invoke(null) as? String
                } catch (_: Throwable) {
                    null
                }

                val supportsFormatMethod = libraryClass.getMethod("supportsFormat", String::class.java)
                val supported = PROBE_MIME_TYPES.entries
                    .filter { (mime, _) ->
                        try {
                            supportsFormatMethod.invoke(null, mime) as? Boolean ?: false
                        } catch (_: Throwable) {
                            false
                        }
                    }
                    .map { it.value }

                Status(available = true, version = version, supportedCodecs = supported, moduleLinked = true)
            }
        } catch (t: Throwable) {
            NativeLogger.emit("warn", "Ffmpeg", "FfmpegLibrary reflective query failed: $t")
            Status(available = false, version = null, supportedCodecs = emptyList(), moduleLinked = true)
        }

        cached = result
        return result
    }

    /**
     * ExoPlayer's `DecoderAudioRenderer` reports `decoder.getName()` as the
     * `decoderName` argument of `AnalyticsListener.onAudioDecoderInitialized`.
     * `FfmpegAudioDecoder.getName()` returns `"ffmpeg" + version + "-" + codecName`
     * (see androidx/media FfmpegAudioDecoder.java) — no other Media3 decoder
     * name starts with "ffmpeg", so this prefix check is a reliable signal.
     */
    fun isFfmpegDecoderName(decoderName: String): Boolean = decoderName.startsWith("ffmpeg")

    /** Human-readable diagnostic string for the decoderInfo event payload. */
    fun describeSelection(decoderName: String, mimeType: String?): String {
        return if (isFfmpegDecoderName(decoderName)) {
            "No on-device MediaCodec decoder for ${mimeType ?: "this format"}; " +
                "used bundled FFmpeg software decoder ($decoderName)."
        } else {
            "Decoded by platform MediaCodec ($decoderName)."
        }
    }
}
