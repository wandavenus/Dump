package dev.wndavenz.music.replaygain

import android.os.ParcelFileDescriptor
import android.util.Log
import dev.wndavenz.music.events.NativeLogger
import dev.wndavenz.music.metadata.MetadataCacheDb
import java.io.File
import java.util.Locale

/**
 * Thin glue between MainActivity's MethodChannel switch and
 * [ReplayGainService]. Kept separate from MainActivity so the (fairly
 * involved) result-map shaping for each call lives in one place and can be
 * unit-tested independently of Flutter plugin wiring.
 *
 * MainActivity is still responsible for: choosing which executor to run on,
 * posting results back to the UI thread, resolving the MediaStore write
 * grant via [MediaStoreWriteGate] BEFORE calling [writeReplayGainFd] /
 * [removeReplayGainFd] here, and catching/mapping exceptions to
 * `MethodChannel.Result.error(...)` — this class only computes plain Kotlin
 * result values (maps/lists), matching the pattern already used by
 * `getReplayGainTags` / `getEmbeddedLyrics` in MainActivity.
 *
 * [openFd] opens a fresh read/write `content://` fd for a given path/uri
 * pair, returning null on failure. Passed in (rather than holding a
 * ContentResolver directly) so this class stays easy to construct in
 * isolation; MainActivity wires it to
 * `contentResolver.openFileDescriptor(uri, "rw")`.
 */
class ReplayGainBridge(
    private val metadataCacheDb: MetadataCacheDb,
    private val openFd: (songId: Int) -> ParcelFileDescriptor?,
    private val pathForSongId: (songId: Int) -> String?,
) {

    companion object {
        private const val TAG = "ReplayGainBridge"
    }

    /** Handles `scanTrack` (also backs the legacy `scanReplayGain` case name). */
    fun scanTrack(path: String): Map<String, Any?> {
        // F3 (RG-01): snapshot the file identity BEFORE decoding. If the file
        // is replaced/edited while the scan runs, the measurement describes the
        // OLD content — caching it under the new mtime would poison the SQLite
        // cache (getReplayGainTags would serve the stale measurement until the
        // file changes again). The Dart caller independently discards the
        // result via its own before/after identity check, but the cache write
        // here must be guarded on its own too.
        val mtimeBefore = MetadataCacheDb.mtime(path)
        val result = ReplayGainService.scanTrack(path)
            ?: return mapOf("success" to false, "error" to "scan_failed")

        val mtime = MetadataCacheDb.mtime(path)
        if (mtimeBefore != 0L && mtimeBefore == mtime) {
            // File unchanged across the scan — safe to cache. Update SQLite
            // cache immediately so getReplayGainTags() reflects the fresh
            // measurement even before/without writing tags to the file.
            val existing = metadataCacheDb.getByPath(path, mtime)
            val gainStr = formatGain(result.recommendedGainDb)
            val peakStr = formatPeak(dbToLinear(result.samplePeakDbfs))
            metadataCacheDb.putByPath(
                path, mtime,
                MetadataCacheDb.CachedEntry(
                    rgTrackGain = gainStr,
                    rgTrackPeak = peakStr,
                    rgAlbumGain = existing?.rgAlbumGain,
                    rgAlbumPeak = existing?.rgAlbumPeak,
                    r128Track = existing?.r128Track,
                    r128Album = existing?.r128Album,
                    iTunNorm = existing?.iTunNorm,
                    lyrics = existing?.lyrics,
                ),
            )
        } else {
            // F3: file changed (or vanished) mid-scan — do not cache the stale
            // measurement. Result is still returned; the Dart identity guard
            // decides whether to discard it.
            Log.w(TAG, "scanTrack: file changed during scan, not caching: $path")
        }

        return mapOf(
            "success" to true,
            "integratedLufs" to result.integratedLufs,
            "loudnessRangeLu" to result.loudnessRangeLu,
            "truePeakDbtp" to result.truePeakDbtp,
            "samplePeakDbfs" to result.samplePeakDbfs,
            "trackGainDb" to result.recommendedGainDb,
            "trackPeak" to dbToLinear(result.samplePeakDbfs),
        )
    }

    /** Handles `scanAlbum`. [paths] must all belong to the same album. */
    fun scanAlbum(paths: List<String>): Map<String, Any?> {
        // F3 (RG-01): snapshot every file's identity BEFORE the album decode,
        // then only cache tracks whose file survived the scan unchanged.
        val mtimeBefore = paths.associateWith { MetadataCacheDb.mtime(it) }
        val albumResult = ReplayGainService.scanAlbum(paths)

        // Cache each successfully-scanned track with both its own track gain
        // AND the shared album gain, so getReplayGainTags() returns complete
        // data for every song in the album without a second native round-trip.
        albumResult.trackResults.forEach { (path, trackLoudness) ->
            val mtime = MetadataCacheDb.mtime(path)
            val before = mtimeBefore[path]
            if (before == null || before == 0L || before != mtime) {
                Log.w(TAG, "scanAlbum: file changed during scan, not caching: $path")
                return@forEach
            }
            val existing = metadataCacheDb.getByPath(path, mtime)
            metadataCacheDb.putByPath(
                path, mtime,
                MetadataCacheDb.CachedEntry(
                    rgTrackGain = formatGain(trackLoudness.recommendedGainDb),
                    rgTrackPeak = formatPeak(dbToLinear(trackLoudness.samplePeakDbfs)),
                    rgAlbumGain = formatGain(albumResult.albumGainDb),
                    rgAlbumPeak = formatPeak(albumResult.albumPeakLinear),
                    r128Track = existing?.r128Track,
                    r128Album = existing?.r128Album,
                    iTunNorm = existing?.iTunNorm,
                    lyrics = existing?.lyrics,
                ),
            )
        }

        return mapOf(
            "success" to albumResult.trackResults.isNotEmpty(),
            "albumGainDb" to albumResult.albumGainDb,
            "albumPeak" to albumResult.albumPeakLinear,
            "albumIntegratedLufs" to albumResult.albumIntegratedLufs,
            "scannedCount" to albumResult.trackResults.size,
            "failedPaths" to albumResult.failedPaths,
            "tracks" to albumResult.trackResults.mapValues { (_, r) ->
                mapOf(
                    "trackGainDb" to r.recommendedGainDb,
                    "trackPeak" to dbToLinear(r.samplePeakDbfs),
                    "integratedLufs" to r.integratedLufs,
                )
            },
        )
    }

    /**
     * Handles `writeReplayGain`. Expects the caller to have already scanned
     * (via `scanTrack`/`scanAlbum`) and pass the measured values in —
     * writing never re-runs analysis itself, so callers can review/tweak a
     * measurement before committing it to disk.
     *
     * Requires `songId` (int) in [args] in addition to `path`, so this can
     * resolve a fresh MediaStore fd for the write→verify→(restore) sequence
     * — the caller (MainActivity) must already have confirmed write access
     * via [MediaStoreWriteGate] before invoking this.
     *
     * Follows the protocol documented on tag_writer.h's fd-based API: write
     * (with an exact-region backup taken first) → close → reopen fresh →
     * verify what was actually persisted → on any mismatch, reopen for
     * write and restore the backed-up region → report
     * `WRITE_VERIFICATION_FAILED` rather than a false success.
     */
    fun writeReplayGain(args: Map<String, Any?>): Map<String, Any?> {
        val path = args["path"] as? String ?: ""
        val songId = (args["songId"] as? Number)?.toInt()
        val trackGainDb = (args["trackGainDb"] as? Number)?.toDouble()
        val trackPeak = (args["trackPeak"] as? Number)?.toDouble()
        val trackIntegratedLufs = (args["integratedLufs"] as? Number)?.toDouble()
        val albumGainDb = (args["albumGainDb"] as? Number)?.toDouble()
        val albumPeak = (args["albumPeak"] as? Number)?.toDouble()
        val albumIntegratedLufs = (args["albumIntegratedLufs"] as? Number)?.toDouble()
        val expectedFileSize = (args["fileSize"] as? Number)?.toLong()
        val expectedFileMtimeMs = (args["fileMtimeMs"] as? Number)?.toLong()

        if (path.isBlank() || songId == null || trackGainDb == null || trackPeak == null ||
            trackIntegratedLufs == null || !trackGainDb.isFinite() || !trackPeak.isFinite() ||
            trackPeak < 0.0 || !trackIntegratedLufs.isFinite()
        ) {
            return mapOf("success" to false, "error" to "INVALID_ARGUMENT")
        }
        val albumValues = listOf(albumGainDb, albumPeak, albumIntegratedLufs)
        if (albumValues.any { it != null } &&
            albumValues.any { it == null || !it.isFinite() } ||
            albumPeak != null && albumPeak < 0.0
        ) {
            return mapOf("success" to false, "error" to "INVALID_ARGUMENT")
        }
        val format = TagFormat.fromPath(path)
            ?: return mapOf("success" to false, "error" to "UNSUPPORTED_FORMAT")
        if (!sameFile(path, songId)) {
            return mapOf("success" to false, "error" to "STALE_SCAN")
        }
        if ((expectedFileSize == null) != (expectedFileMtimeMs == null) ||
            expectedFileSize != null && !matchesIdentity(path, expectedFileSize, expectedFileMtimeMs!!)
        ) {
            return mapOf("success" to false, "error" to "STALE_SCAN")
        }

        val error = runFdMutation(
            songId = songId,
            format = format,
            mutate = { fd ->
                ReplayGainService.writeReplayGainFd(
                    fd, format, trackGainDb, trackPeak, trackIntegratedLufs,
                    albumGainDb, albumPeak, albumIntegratedLufs,
                )
            },
            verify = { fd, prior ->
                ReplayGainService.verifyWriteFd(
                    fd, format, trackGainDb, trackPeak, trackIntegratedLufs,
                    albumGainDb, albumPeak, albumIntegratedLufs, prior,
                )
            },
        )

        if (error == ReplayGainError.NONE) {
            // File tags changed — mtime changed too, so invalidate the SQLite
            // cache entry keyed on the OLD mtime; next getReplayGainTags()
            // read will re-parse via ExoMetadataReader and re-cache under the
            // new mtime, picking up exactly what TagLib just wrote.
            metadataCacheDb.invalidateByPath(path)
        }

        return mapOf("success" to (error == ReplayGainError.NONE), "error" to error.name)
    }

    /**
     * Handles `writeReplayGainBatch` — the batch counterpart of
     * [writeReplayGain] (R-B, 1.5.21). Every element must be a valid
     * single-song write args map with the exact same contract as
     * [writeReplayGain]; each element is processed through that same
     * write→close→reopen→verify→(restore) protocol, so per-song
     * success/error semantics are preserved and one bad file never fails the
     * whole batch. Each result map additionally carries its `songId` so the
     * Dart caller can invalidate exactly the songs that were written.
     *
     * Callers must have pre-authorized write access for every songId via
     * MainActivity's `requestReplayGainWriteAccessBatch` first — songs that
     * were not granted simply resolve `WRITE_ACCESS_DENIED` in their own slot
     * (openFd fails) without any per-file dialog.
     */
    fun writeReplayGainBatch(requests: List<Map<String, Any?>>): List<Map<String, Any?>> =
        requests.map { request ->
            val songId = (request["songId"] as? Number)?.toInt()
            mapOf("songId" to songId) + writeReplayGain(request)
        }

    /** Handles `removeReplayGain`. Requires `songId` — see [writeReplayGain]. */
    fun removeReplayGain(path: String, songId: Int?): Map<String, Any?> {
        if (songId == null) return mapOf("success" to false, "error" to "INVALID_ARGUMENT")
        val format = TagFormat.fromPath(path)
            ?: return mapOf("success" to false, "error" to "UNSUPPORTED_FORMAT")
        if (!sameFile(path, songId)) {
            return mapOf("success" to false, "error" to "STALE_SCAN")
        }

        val error = runFdMutation(
            songId = songId,
            format = format,
            mutate = { fd -> ReplayGainService.removeReplayGainFd(fd, format) },
            verify = { fd, prior -> ReplayGainService.verifyRemovedFd(fd, format, prior) },
        )

        if (error == ReplayGainError.NONE) {
            metadataCacheDb.invalidateByPath(path)
        }
        return mapOf("success" to (error == ReplayGainError.NONE), "error" to error.name)
    }

    /**
     * Shared write→close→reopen→verify→(restore) orchestration for both
     * [writeReplayGain] and [removeReplayGain]. [mutate] performs the
     * actual TagLib mutation on a fresh write fd (capturing the pre-
     * mutation snapshot + region backup); [verify] re-checks a fresh
     * read-back fd against that snapshot.
     */
    private fun runFdMutation(
        songId: Int,
        format: TagFormat,
        mutate: (fd: Int) -> FdWriteOutcome,
        verify: (fd: Int, prior: TagSnapshot) -> ReplayGainError,
    ): ReplayGainError {
        val writePfd = openFd(songId) ?: return ReplayGainError.WRITE_ACCESS_DENIED
        val writeFd = writePfd.detachFd()  // ownership passes to native — do NOT close writePfd after this
        val outcome = mutate(writeFd)
        // TagLib::FileStream's destructor already fclose()'d the underlying
        // fd inside the native call above — nothing left to close here.

        if (outcome.error != ReplayGainError.NONE) {
            // A native save can fail after TagLib has already resized or
            // partially rewritten the metadata region. If a backup exists,
            // restore it before returning the original error.
            return if (outcome.regionBackup != null) {
                val rollback = rollback(
                    songId,
                    format,
                    outcome.regionBackup,
                    outcome.priorSnapshot,
                )
                if (rollback == ReplayGainError.NONE) outcome.error else rollback
            } else {
                outcome.error
            }
        }

        val verifyPfd = openFd(songId)
            ?: run {
                val rollback = rollback(
                    songId,
                    format,
                    outcome.regionBackup,
                    outcome.priorSnapshot,
                )
                return if (rollback == ReplayGainError.NONE) {
                    ReplayGainError.VERIFICATION_FAILED
                } else {
                    rollback
                }
            }
        val verifyFd = verifyPfd.detachFd()
        val verifyResult = verify(verifyFd, outcome.priorSnapshot)
        // Read-only-intent stream, but TagLib still opens with fdopen();
        // same detach/no-close rule applies — see nativeVerifyReplayGainTagsFd doc.

        if (verifyResult == ReplayGainError.NONE) return ReplayGainError.NONE

        // Verification failed — attempt byte-exact rollback using the
        // region backed up before the mutation and verify the restored state.
        val rollback = rollback(
            songId,
            format,
            outcome.regionBackup,
            outcome.priorSnapshot,
        )
        return if (rollback == ReplayGainError.NONE) {
            ReplayGainError.VERIFICATION_FAILED
        } else {
            rollback
        }
    }

    private fun rollback(
        songId: Int,
        format: TagFormat,
        region: ByteArray?,
        prior: TagSnapshot?,
    ): ReplayGainError {
        // L-3 fix: these data-integrity failures used to be logcat-only, so the
        // in-app Log Viewer (Settings → Log Aktivitas) never showed them. Emit
        // every one through NativeLogger too so a failed write→verify→rollback
        // cycle is visible to the user/dev without adb. Log.e is kept so logcat
        // behaviour is unchanged.
        if (region == null) {
            logError("songId=$songId mutation failed without a metadata backup")
            return ReplayGainError.ROLLBACK_FAILED
        }
        val restorePfd = openFd(songId)
            ?: return ReplayGainError.ROLLBACK_FAILED.also {
                logError("songId=$songId could not reopen for rollback")
            }
        val restoreFd = restorePfd.detachFd()
        val restoreError = ReplayGainService.restoreRegionFd(restoreFd, format, region)
        if (restoreError != ReplayGainError.NONE) {
            logError("songId=$songId rollback failed: $restoreError")
            return ReplayGainError.ROLLBACK_FAILED
        }
        if (prior == null) return ReplayGainError.NONE

        val verifyPfd = openFd(songId)
            ?: return ReplayGainError.ROLLBACK_FAILED.also {
                logError("songId=$songId rollback completed but could not verify it")
            }
        val verifyFd = verifyPfd.detachFd()
        val verifyError = ReplayGainService.verifyRestoredFd(verifyFd, format, prior)
        if (verifyError != ReplayGainError.NONE) {
            logError("songId=$songId rollback verification failed: $verifyError")
            return ReplayGainError.ROLLBACK_FAILED
        }
        return ReplayGainError.NONE
    }

    private fun logError(msg: String) {
        Log.e(TAG, msg)
        NativeLogger.emit("error", "ReplayGain", msg)
    }

    private fun dbToLinear(db: Double): Double =
        if (db.isFinite()) Math.pow(10.0, db / 20.0) else 0.0

    private fun formatGain(value: Double): String =
        String.format(Locale.ROOT, "%+.2f dB", value)

    private fun formatPeak(value: Double): String =
        String.format(Locale.ROOT, "%.6f", value)

    private fun sameFile(path: String, songId: Int): Boolean {
        val mediaStorePath = pathForSongId(songId) ?: return false
        return runCatching {
            File(path).canonicalFile == File(mediaStorePath).canonicalFile
        }.getOrDefault(false)
    }

    private fun matchesIdentity(path: String, expectedSize: Long, expectedMtimeMs: Long): Boolean =
        runCatching {
            val file = File(path)
            file.isFile && file.length() == expectedSize && file.lastModified() == expectedMtimeMs
        }.getOrDefault(false)
}
