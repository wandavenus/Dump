package com.example.musicplayer.metadata

import android.content.Context
import android.os.Process
import android.util.Log

/**
 * Background metadata pre-scanner.
 *
 * After [getSongs()] returns the full library, this object scans every song
 * that is not yet in [MetadataCacheDb] at the lowest OS thread priority so it
 * never interferes with audio playback or UI.
 *
 * Strategy:
 *  1. Build a work-list of (songId, path) pairs.
 *  2. For each pair, check the cache first (mtime match = skip).
 *  3. On a cache miss, call [ExoMetadataReader.read] and store the result.
 *  4. Sleep [INTER_FILE_DELAY_MS] between files to avoid saturating I/O.
 *  5. Stop immediately when [cancel] is called or the work-list is exhausted.
 *
 * Only one scan may run at a time; calling [start] while a scan is running
 * cancels the previous scan and starts a new one.
 *
 * Thread-safety: [start] and [cancel] may be called from any thread.
 */
object MetadataPrescanner {

    private const val TAG                = "MetadataPrescanner"
    private const val INTER_FILE_DELAY_MS = 40L   // yield between files

    data class SongRef(val id: Int, val path: String)

    @Volatile private var cancelled = false
    @Volatile private var running   = false

    /** True while a scan is in progress. */
    val isRunning: Boolean get() = running

    /**
     * Starts a new background pre-scan for [songs].
     * Any currently-running scan is cancelled first.
     *
     * @param context  Used by [ExoMetadataReader].
     * @param songs    Full library list — entries already in cache are skipped cheaply.
     * @param cache    The shared [MetadataCacheDb] instance.
     */
    fun start(context: Context, songs: List<SongRef>, cache: MetadataCacheDb) {
        cancel()   // stop any previous scan

        if (songs.isEmpty()) return

        cancelled = false
        running   = true

        val appContext = context.applicationContext

        Thread {
            // Lowest priority: won't starve audio threads or the UI
            Process.setThreadPriority(Process.THREAD_PRIORITY_LOWEST)

            var scanned = 0
            var skipped = 0
            var errors  = 0

            Log.d(TAG, "Pre-scan started — ${songs.size} songs to check")

            for (song in songs) {
                if (cancelled) break
                if (song.path.isBlank()) continue

                try {
                    val mtime = MetadataCacheDb.mtime(song.path)
                    if (mtime == 0L) continue   // file doesn't exist

                    // Cache hit: already fresh, skip expensive ExoPlayer parse
                    val cached = cache.get(song.id, mtime)
                    if (cached != null) {
                        skipped++
                        continue
                    }

                    // Cache miss: read tags + lyrics in one ExoPlayer pass
                    val tags = ExoMetadataReader.read(appContext, song.path)
                    cache.put(
                        songId = song.id,
                        path   = song.path,
                        mtime  = mtime,
                        entry  = MetadataCacheDb.CachedEntry(
                            rgTrackGain = tags.rgTrackGain,
                            rgTrackPeak = tags.rgTrackPeak,
                            rgAlbumGain = tags.rgAlbumGain,
                            rgAlbumPeak = tags.rgAlbumPeak,
                            r128Track   = tags.r128Track,
                            r128Album   = tags.r128Album,
                            iTunNorm    = tags.iTunNorm,
                            lyrics      = tags.lyrics ?: MetadataCacheDb.LYRICS_NONE,
                        )
                    )
                    scanned++

                    // Brief yield so we don't dominate I/O bandwidth
                    if (!cancelled) Thread.sleep(INTER_FILE_DELAY_MS)

                } catch (e: InterruptedException) {
                    break
                } catch (e: Exception) {
                    errors++
                    Log.w(TAG, "Pre-scan error for ${song.path}: ${e.message}")
                }
            }

            running = false
            Log.d(TAG, "Pre-scan finished — " +
                "scanned=$scanned skipped=$skipped errors=$errors cancelled=$cancelled")

        }.apply {
            name     = "metadata-prescanner"
            isDaemon = true   // doesn't block app shutdown
            start()
        }
    }

    /**
     * Cancels the currently running scan.
     * Returns immediately; the background thread stops at the next file boundary.
     */
    fun cancel() {
        if (running) {
            cancelled = true
            Log.d(TAG, "Pre-scan cancelled")
        }
    }
}
