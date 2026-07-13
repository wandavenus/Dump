package dev.wndavenz.music.replaygain

import android.util.Log

/**
 * Orchestrates native EBU R128 loudness analysis and TagLib metadata writes.
 *
 * Replaces the old `dev.wndavenz.music.replay_gain.ReplayGainScanner`
 * (hand-rolled Kotlin K-weighting math, read-only/cache-only results). This
 * version:
 *   1. Decodes via [PcmDecoder] (same MediaExtractor/MediaCodec approach).
 *   2. Feeds PCM into libebur128 via [EburTrackSession] (JNI → C++).
 *   3. Can now WRITE the measured gain back into the file's own tags via
 *      TagLib (`writeReplayGain`), in addition to just returning the result
 *      for SQLite caching (`scanTrack`/`scanAlbum` alone don't write files —
 *      callers decide whether to persist to file, cache, or both).
 *
 * All methods are blocking/synchronous — callers (MainActivity's bridge)
 * must dispatch onto a background executor themselves, matching the
 * existing `replayGainScanExecutor` pattern.
 */
object ReplayGainService {

    private const val TAG = "ReplayGainService"

    /** True if the native module loaded successfully on this device/build. */
    val nativeAvailable: Boolean get() = ReplayGainNative.ensureLoaded()

    // ── Single-track scan ─────────────────────────────────────────────────────

    /**
     * Measures integrated loudness for a single file. Returns null if the
     * file can't be decoded or the native library isn't available.
     */
    fun scanTrack(path: String, onProgress: (Float) -> Unit = {}): LoudnessResult? {
        if (!nativeAvailable) {
            Log.w(TAG, "Native ReplayGain unavailable: ${ReplayGainNative.lastLoadError}")
            return null
        }

        var session: EburTrackSession? = null
        var result: LoudnessResult? = null

        val ok = PcmDecoder.decode(
            path,
            onFormat = { fmt ->
                session = EburTrackSession.create(fmt.sampleRate, fmt.channels)
            },
            feed = { buf, frameCount ->
                session?.addFramesShort(buf, frameCount) ?: false
            },
            onProgress = onProgress,
        )

        session?.use { s ->
            if (ok) result = s.finish()
        }

        return result
    }

    // ── Album scan ─────────────────────────────────────────────────────────────

    /**
     * Measures per-track loudness for every path in [paths], then computes
     * album-integrated loudness across all of them (EBU Tech 3341 album
     * mode — not a simple average of track LUFS values).
     *
     * Sessions for every track are kept alive until album aggregation
     * completes, then released together. [onTrackProgress] reports
     * (index, fraction) for UI progress across the whole album.
     */
    fun scanAlbum(
        paths: List<String>,
        onTrackProgress: (index: Int, fraction: Float) -> Unit = { _, _ -> },
    ): AlbumScanResult {
        if (!nativeAvailable || paths.isEmpty()) {
            return AlbumScanResult(emptyMap(), 0.0, 0.0, Double.NEGATIVE_INFINITY, paths)
        }

        val sessions = mutableListOf<EburTrackSession>()
        val trackResults = mutableMapOf<String, LoudnessResult>()
        val failed = mutableListOf<String>()
        var maxPeak = 0.0

        try {
            paths.forEachIndexed { index, path ->
                var session: EburTrackSession? = null
                val ok = PcmDecoder.decode(
                    path,
                    onFormat = { fmt -> session = EburTrackSession.create(fmt.sampleRate, fmt.channels) },
                    feed = { buf, frameCount -> session?.addFramesShort(buf, frameCount) ?: false },
                    onProgress = { f -> onTrackProgress(index, f) },
                )
                val s = session
                if (!ok || s == null) {
                    failed.add(path)
                    s?.close()
                    return@forEachIndexed
                }
                val result = s.finish()
                if (result == null || !result.valid) {
                    failed.add(path)
                    s.close()
                    return@forEachIndexed
                }
                trackResults[path] = result
                if (result.samplePeakDbfs.isFinite()) {
                    maxPeak = maxOf(maxPeak, dbToLinear(result.samplePeakDbfs))
                }
                sessions.add(s)  // keep alive for album aggregation
            }

            val albumLufs = if (sessions.isNotEmpty()) {
                ReplayGainNative.nativeComputeAlbumLoudness(sessions.map { it.handle }.toLongArray())
            } else {
                Double.NEGATIVE_INFINITY
            }
            val albumGainDb = if (albumLufs.isFinite()) -18.0 - albumLufs else 0.0

            return AlbumScanResult(
                trackResults = trackResults,
                albumGainDb = albumGainDb,
                albumPeakLinear = maxPeak,
                albumIntegratedLufs = albumLufs,
                failedPaths = failed,
            )
        } finally {
            sessions.forEach { it.close() }
        }
    }

    // ── Tag writing ────────────────────────────────────────────────────────────

    /**
     * Writes REPLAYGAIN_TRACK_* (and, for Opus, R128_TRACK_GAIN) tags into
     * the file at [path], preserving all other metadata. Pass [albumGainDb]
     * / [albumPeakLinear] together when writing as part of an album batch
     * so REPLAYGAIN_ALBUM_* / R128_ALBUM_GAIN are written too.
     *
     * Returns [ReplayGainError.NONE] on success, or a specific error
     * otherwise. [ReplayGainError.UNSUPPORTED_FORMAT] is returned for
     * formats with no registered tag writer (e.g. M4A/AAC — read-only via
     * ExoMetadataReader, see [TagFormat.fromPath]).
     */
    fun writeReplayGain(
        path: String,
        trackGainDb: Double,
        trackPeakLinear: Double,
        trackIntegratedLufs: Double,
        albumGainDb: Double? = null,
        albumPeakLinear: Double? = null,
        albumIntegratedLufs: Double? = null,
    ): ReplayGainError {
        if (!nativeAvailable) return ReplayGainError.UNKNOWN
        val format = TagFormat.fromPath(path) ?: return ReplayGainError.UNSUPPORTED_FORMAT

        val r128Track = ReplayGainNative.nativeLufsToR128Q7x8(trackIntegratedLufs)
        val hasR128Album = albumIntegratedLufs != null
        val r128Album = if (albumIntegratedLufs != null) {
            ReplayGainNative.nativeLufsToR128Q7x8(albumIntegratedLufs)
        } else 0

        val code = ReplayGainNative.nativeWriteReplayGainTags(
            path,
            format.nativeValue,
            trackGainDb,
            trackPeakLinear,
            albumGainDb != null,
            albumGainDb ?: 0.0,
            albumPeakLinear ?: 0.0,
            r128Track,
            hasR128Album,
            r128Album,
        )
        return ReplayGainError.fromNative(code)
    }

    /**
 * Strips REPLAYGAIN_* and R128_* tags from [path],
 * leaving all other metadata intact.
 */
    fun removeReplayGain(path: String): ReplayGainError {
        if (!nativeAvailable) return ReplayGainError.UNKNOWN
        if (TagFormat.fromPath(path) == null) return ReplayGainError.UNSUPPORTED_FORMAT
        val code = ReplayGainNative.nativeRemoveReplayGainTags(path)
        return ReplayGainError.fromNative(code)
    }

    private fun dbToLinear(db: Double): Double =
        if (db.isFinite()) Math.pow(10.0, db / 20.0) else 0.0
}
