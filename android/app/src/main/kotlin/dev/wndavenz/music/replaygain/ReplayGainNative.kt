package dev.wndavenz.music.replaygain

/**
 * Raw JNI surface for `libreplaygain_native.so` (libebur128 + TagLib).
 *
 * See `src/main/cpp/replaygain/replaygain_jni.cpp` for the native
 * implementation. This object owns nothing except the `System.loadLibrary`
 * call — all state (analyzer handles, file I/O) lives on the native side or
 * is orchestrated by [ReplayGainService] / [EburTrackSession].
 *
 * IMPORTANT: every `nativeCreateAnalyzer` handle returned must be released
 * exactly once via `nativeDestroyAnalyzer`, even on the error path — use
 * [EburTrackSession] rather than calling these methods directly to get that
 * for free via `use { }`.
 */
object ReplayGainNative {

    @Volatile
    private var loaded = false
    @Volatile
    private var failed = false
    @Volatile
    private var loadError: Throwable? = null

    /**
     * Loads the native library once. Safe to call repeatedly. Returns true
     * if the library is available. All callers MUST check this before
     * invoking any other method here — every JNI call below will crash the
     * process (UnsatisfiedLinkError) if the library failed to load, so
     * [ReplayGainService] fails open (falls back to "no native ReplayGain
     * available") instead of calling into this class when [isAvailable]
     * is false.
     */
    fun ensureLoaded(): Boolean {
        if (loaded) return true
        if (failed) return false   // permanent failure — skip re-attempt
        synchronized(this) {
            if (loaded) return true
            if (failed) return false
            try {
                System.loadLibrary("replaygain_native")
                loaded = true
            } catch (t: Throwable) {
                loadError = t
                failed = true      // don't retry on every call
            }
        }
        return loaded
    }

    val isAvailable: Boolean get() = loaded
    val lastLoadError: Throwable? get() = loadError

    // ── Analyzer lifecycle ──────────────────────────────────────────────────

    /** Returns 0 on failure (invalid sample rate/channel count). */
    external fun nativeCreateAnalyzer(sampleRate: Int, channels: Int): Long

    /** Returns false if libebur128 reported an internal error for this chunk. */
    external fun nativeAddFramesShort(handle: Long, buf: ShortArray, frameCount: Int): Boolean

    /**
     * Returns a double[6]:
     * [integratedLufs, lra, truePeakDbtp, samplePeakDbfs, recommendedGainDb, validFlag]
     * or null if the handle is invalid / measurement failed entirely.
     */
    external fun nativeFinishAnalyzer(handle: Long): DoubleArray?

    /** Must be called exactly once per handle returned by nativeCreateAnalyzer. */
    external fun nativeDestroyAnalyzer(handle: Long)

    // ── Album aggregation ───────────────────────────────────────────────────

    /**
     * Computes album-integrated loudness (EBU Tech 3341 album mode) across
     * every still-alive analyzer handle in [handles]. Returns
     * Double.NEGATIVE_INFINITY on failure or if all handles are invalid.
     * Handles remain valid after this call — destroy them separately.
     */
    external fun nativeComputeAlbumLoudness(handles: LongArray): Double

    /** Converts LUFS (relative to -23 LUFS reference) to Opus R128 Q7.8 fixed point. */
    external fun nativeLufsToR128Q7x8(integratedLufs: Double): Int

    // ── Scoped-storage-safe fd-based tag writing ───────────────────────────────
    // `fd` must come from ParcelFileDescriptor.detachFd() — ownership passes
    // to native for the duration of the call; TagLib closes the underlying
    // fd internally (fdopen/fclose), so callers must NOT also close a
    // ParcelFileDescriptor they've detached and passed here.
    //
    // Each write/remove call returns Object[3] = [Int resultCode,
    // String[9]? priorSnapshot, ByteArray? regionBackup] — see
    // PackWriteEnvelope in replaygain_jni.cpp. Payload is only present when
    // resultCode == ReplayGainError.NONE's native ordinal (0).

    external fun nativeWriteReplayGainTagsFd(
        fd: Int,
        format: Int,
        trackGainDb: Double,
        trackPeakLinear: Double,
        hasAlbum: Boolean,
        albumGainDb: Double,
        albumPeakLinear: Double,
        r128TrackQ7x8: Int,
        hasR128Album: Boolean,
        r128AlbumQ7x8: Int,
    ): Array<Any?>

    external fun nativeRemoveReplayGainTagsFd(fd: Int, format: Int): Array<Any?>

    /** Returns a [ReplayGainError] ordinal. */
    external fun nativeVerifyReplayGainTagsFd(
        fd: Int,
        format: Int,
        trackGainDb: Double,
        trackPeakLinear: Double,
        hasAlbum: Boolean,
        albumGainDb: Double,
        albumPeakLinear: Double,
        r128TrackQ7x8: Int,
        hasR128Album: Boolean,
        r128AlbumQ7x8: Int,
        priorSnapshot: Array<String?>,
    ): Int

    /** Returns a [ReplayGainError] ordinal. */
    external fun nativeVerifyReplayGainRemovedFd(
        fd: Int,
        format: Int,
        priorSnapshot: Array<String?>,
    ): Int

    /** Returns a [ReplayGainError] ordinal. */
    external fun nativeRestoreMetadataRegionFd(fd: Int, format: Int, regionBytes: ByteArray): Int
}

/**
 * RAII-style wrapper around a single native analyzer handle so callers can't
 * forget to call `nativeDestroyAnalyzer`. Use with Kotlin's `use { }`:
 *
 * ```
 * EburTrackSession.create(sampleRate, channels)?.use { session ->
 *     session.addFramesShort(pcmChunk, frameCount)
 *     val result = session.finish()
 * }
 * ```
 *
 * For album scans, do NOT wrap in `use{}` immediately — hold the session
 * open (call [finish] to get the per-track result, but delay [close] until
 * after album aggregation), then pass [handle] into
 * [ReplayGainNative.nativeComputeAlbumLoudness] for every track in the
 * album, and only then close every session.
 */
class EburTrackSession private constructor(val handle: Long) : AutoCloseable {

    private var closed = false

    fun addFramesShort(buf: ShortArray, frameCount: Int): Boolean =
        ReplayGainNative.nativeAddFramesShort(handle, buf, frameCount)

    fun finish(): LoudnessResult? {
        val raw = ReplayGainNative.nativeFinishAnalyzer(handle) ?: return null
        if (raw.size < 6) return null
        return LoudnessResult(
            integratedLufs = raw[0],
            loudnessRangeLu = raw[1],
            truePeakDbtp = raw[2],
            samplePeakDbfs = raw[3],
            recommendedGainDb = raw[4],
            valid = raw[5] >= 0.5,
        )
    }

    override fun close() {
        if (closed) return
        closed = true
        ReplayGainNative.nativeDestroyAnalyzer(handle)
    }

    companion object {
        /** Returns null if the native library isn't loaded or params are invalid. */
        fun create(sampleRate: Int, channels: Int): EburTrackSession? {
            if (!ReplayGainNative.ensureLoaded()) return null
            val handle = ReplayGainNative.nativeCreateAnalyzer(sampleRate, channels)
            if (handle == 0L) return null
            return EburTrackSession(handle)
        }
    }
}
