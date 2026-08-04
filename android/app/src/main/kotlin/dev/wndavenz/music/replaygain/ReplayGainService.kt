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
            if (ok) {
                val finished = s.finish()
                // Reject invalid measurements (e.g. silence-only tracks that
                // never cross libebur128's absolute gate) instead of letting
                // them fall through as a bogus "+0.00 dB" result — scanAlbum
                // already enforces this same check per-track; scanTrack must
                // match it so a failed measurement is never mistaken for a
                // real 0 dB gain and (if writeTags is on) permanently burned
                // into the file's tags.
                if (finished != null && finished.valid) {
                    result = finished
                }
            }
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

    // ── Scoped-storage-safe fd-based tag writing ────────────────────────────────
    //
    // These operate on a single already-open fd and do not know about
    // MediaStore/permissions/reopening at all — see MediaStoreWriteGate for
    // the permission dance and ReplayGainBridge for the
    // write→close→reopen→verify→(restore) orchestration that ties this
    // together. Kept separate so this class never needs a Context.

    /** [fd] must come from `ParcelFileDescriptor.detachFd()` — see ReplayGainNative. */
    fun writeReplayGainFd(
        fd: Int,
        format: TagFormat,
        trackGainDb: Double,
        trackPeakLinear: Double,
        trackIntegratedLufs: Double,
        albumGainDb: Double? = null,
        albumPeakLinear: Double? = null,
        albumIntegratedLufs: Double? = null,
    ): FdWriteOutcome {
        if (!nativeAvailable) return FdWriteOutcome(ReplayGainError.UNKNOWN, emptySnapshot(), null)
        val r128Track = ReplayGainNative.nativeLufsToR128Q7x8(trackIntegratedLufs)
        val hasR128Album = albumIntegratedLufs != null
        val r128Album = albumIntegratedLufs?.let { ReplayGainNative.nativeLufsToR128Q7x8(it) } ?: 0

        val raw = ReplayGainNative.nativeWriteReplayGainTagsFd(
            fd,
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
        return unpackWriteEnvelope(raw)
    }

    /** [fd] must come from `ParcelFileDescriptor.detachFd()`. */
    fun removeReplayGainFd(fd: Int, format: TagFormat): FdWriteOutcome {
        if (!nativeAvailable) return FdWriteOutcome(ReplayGainError.UNKNOWN, emptySnapshot(), null)
        val raw = ReplayGainNative.nativeRemoveReplayGainTagsFd(fd, format.nativeValue)
        return unpackWriteEnvelope(raw)
    }

    /**
     * Re-reads [fd] (a freshly (re)opened fd is fine — read-only access is
     * enough) and confirms the values just written via [writeReplayGainFd]
     * actually persisted, and that [prior]'s title/artist/album sentinel is
     * unchanged. [fd] must come from `ParcelFileDescriptor.detachFd()`.
     */
    fun verifyWriteFd(
        fd: Int,
        format: TagFormat,
        trackGainDb: Double,
        trackPeakLinear: Double,
        trackIntegratedLufs: Double,
        albumGainDb: Double?,
        albumPeakLinear: Double?,
        albumIntegratedLufs: Double?,
        prior: TagSnapshot,
    ): ReplayGainError {
        if (!nativeAvailable) return ReplayGainError.UNKNOWN
        val r128Track = ReplayGainNative.nativeLufsToR128Q7x8(trackIntegratedLufs)
        val hasR128Album = albumIntegratedLufs != null
        val r128Album = albumIntegratedLufs?.let { ReplayGainNative.nativeLufsToR128Q7x8(it) } ?: 0
        val code = ReplayGainNative.nativeVerifyReplayGainTagsFd(
            fd,
            format.nativeValue,
            trackGainDb,
            trackPeakLinear,
            albumGainDb != null,
            albumGainDb ?: 0.0,
            albumPeakLinear ?: 0.0,
            r128Track,
            hasR128Album,
            r128Album,
            prior.toArray(),
        )
        return ReplayGainError.fromNative(code)
    }

    /** Re-reads [fd] and confirms [removeReplayGainFd]'s removal persisted. */
    fun verifyRemovedFd(fd: Int, format: TagFormat, prior: TagSnapshot): ReplayGainError {
        if (!nativeAvailable) return ReplayGainError.UNKNOWN
        val code = ReplayGainNative.nativeVerifyReplayGainRemovedFd(fd, format.nativeValue, prior.toArray())
        return ReplayGainError.fromNative(code)
    }

    /** Re-reads [fd] and confirms the pre-mutation tag snapshot was restored. */
    fun verifyRestoredFd(fd: Int, format: TagFormat, prior: TagSnapshot): ReplayGainError {
        if (!nativeAvailable) return ReplayGainError.UNKNOWN
        val code = ReplayGainNative.nativeVerifyReplayGainRestoredFd(
            fd,
            format.nativeValue,
            prior.toArray(),
        )
        return ReplayGainError.fromNative(code)
    }

    /**
     * Byte-exact rollback after a verification failure: [fd] must be open
     * for writing (a fresh open after the write fd was closed is fine).
     * Restores exactly the metadata region [region] backed up before the
     * mutation — see RestoreMetadataRegionFd in tag_writer.h for why this
     * is correct regardless of how the failed write resized the region.
     */
    fun restoreRegionFd(fd: Int, format: TagFormat, region: ByteArray): ReplayGainError {
        if (!nativeAvailable) return ReplayGainError.UNKNOWN
        val code = ReplayGainNative.nativeRestoreMetadataRegionFd(fd, format.nativeValue, region)
        return ReplayGainError.fromNative(code)
    }

    private fun emptySnapshot(): TagSnapshot = TagSnapshot.fromArray(null)

    private fun unpackWriteEnvelope(raw: Array<Any?>): FdWriteOutcome {
        val code = (raw.getOrNull(0) as? Int) ?: ReplayGainError.UNKNOWN.ordinal
        @Suppress("UNCHECKED_CAST")
        val snapshotArr = raw.getOrNull(1) as? Array<String?>
        val region = raw.getOrNull(2) as? ByteArray
        return FdWriteOutcome(ReplayGainError.fromNative(code), TagSnapshot.fromArray(snapshotArr), region)
    }

    private fun dbToLinear(db: Double): Double =
        if (db.isFinite()) Math.pow(10.0, db / 20.0) else 0.0
}
