package dev.wndavenz.music.replaygain

import android.os.ParcelFileDescriptor
import android.util.Log
import dev.wndavenz.music.metadata.MetadataCacheDb

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
) {

    companion object {
        private const val TAG = "ReplayGainBridge"
    }

    /** Handles `scanTrack` (also backs the legacy `scanReplayGain` case name). */
    fun scanTrack(path: String): Map<String, Any?> {
        val result = ReplayGainService.scanTrack(path)
            ?: return mapOf("success" to false, "error" to "scan_failed")

        // Update SQLite cache immediately so getReplayGainTags() reflects the
        // fresh measurement even before/without writing tags to the file.
        val mtime = MetadataCacheDb.mtime(path)
        val existing = metadataCacheDb.getByPath(path, mtime)
        val gainStr = "%+.2f dB".format(result.recommendedGainDb)
        val peakStr = "%.6f".format(dbToLinear(result.samplePeakDbfs))
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
        val albumResult = ReplayGainService.scanAlbum(paths)

        // Cache each successfully-scanned track with both its own track gain
        // AND the shared album gain, so getReplayGainTags() returns complete
        // data for every song in the album without a second native round-trip.
        albumResult.trackResults.forEach { (path, trackLoudness) ->
            val mtime = MetadataCacheDb.mtime(path)
            val existing = metadataCacheDb.getByPath(path, mtime)
            metadataCacheDb.putByPath(
                path, mtime,
                MetadataCacheDb.CachedEntry(
                    rgTrackGain = "%+.2f dB".format(trackLoudness.recommendedGainDb),
                    rgTrackPeak = "%.6f".format(dbToLinear(trackLoudness.samplePeakDbfs)),
                    rgAlbumGain = "%+.2f dB".format(albumResult.albumGainDb),
                    rgAlbumPeak = "%.6f".format(albumResult.albumPeakLinear),
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

        if (path.isBlank() || songId == null || trackGainDb == null || trackPeak == null ||
            trackIntegratedLufs == null
        ) {
            return mapOf("success" to false, "error" to "INVALID_ARGUMENT")
        }
        val format = TagFormat.fromPath(path)
            ?: return mapOf("success" to false, "error" to "UNSUPPORTED_FORMAT")

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

    /** Handles `removeReplayGain`. Requires `songId` — see [writeReplayGain]. */
    fun removeReplayGain(path: String, songId: Int?): Map<String, Any?> {
        if (songId == null) return mapOf("success" to false, "error" to "INVALID_ARGUMENT")
        val format = TagFormat.fromPath(path)
            ?: return mapOf("success" to false, "error" to "UNSUPPORTED_FORMAT")

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

        if (outcome.error != ReplayGainError.NONE) return outcome.error

        val verifyPfd = openFd(songId)
            ?: return ReplayGainError.WRITE_ACCESS_DENIED  // wrote fine, but can't confirm — treat as unverified failure
        val verifyFd = verifyPfd.detachFd()
        val verifyResult = verify(verifyFd, outcome.priorSnapshot)
        // Read-only-intent stream, but TagLib still opens with fdopen();
        // same detach/no-close rule applies — see nativeVerifyReplayGainTagsFd doc.

        if (verifyResult == ReplayGainError.NONE) return ReplayGainError.NONE

        // Verification failed — attempt byte-exact rollback using the
        // region backed up before the mutation.
        val region = outcome.regionBackup
        if (region == null) {
            Log.e(TAG, "songId=$songId verification failed with no region backup to restore")
            return ReplayGainError.VERIFICATION_FAILED
        }
        val restorePfd = openFd(songId)
        if (restorePfd == null) {
            Log.e(TAG, "songId=$songId verification failed AND could not reopen for restore")
            return ReplayGainError.VERIFICATION_FAILED
        }
        val restoreFd = restorePfd.detachFd()
        val restoreError = ReplayGainService.restoreRegionFd(restoreFd, format, region)
        if (restoreError != ReplayGainError.NONE) {
            Log.e(TAG, "songId=$songId verification failed AND restore also failed: $restoreError")
        }
        return ReplayGainError.VERIFICATION_FAILED
    }

    private fun dbToLinear(db: Double): Double =
        if (db.isFinite()) Math.pow(10.0, db / 20.0) else 0.0
}
