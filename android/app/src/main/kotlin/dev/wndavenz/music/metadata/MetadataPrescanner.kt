package dev.wndavenz.music.metadata

import android.content.Context
import android.os.Process
import android.util.Log
import java.util.concurrent.atomic.AtomicLong

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
 *
 * K1 fix: cancellation/supersession uses a monotonic generation counter
 * instead of a boolean flag. The old `cancelled` flag raced: `start()` reset
 * it while the previous worker thread was still alive, so that thread could
 * read `cancelled == false`, keep scanning (two scans at once), and clear
 * `running` out from under the replacement scan — which in turn made a later
 * `cancel()` a silent no-op. Each worker captures the generation it started
 * with and stops as soon as it no longer matches the current generation.
 * [start] claims its generation atomically, so two concurrent `start()` calls
 * can never produce two workers with the same generation either.
 */
object MetadataPrescanner {

    private const val TAG                = "MetadataPrescanner"
    private const val INTER_FILE_DELAY_MS = 40L   // yield between files

    data class SongRef(val id: Int, val path: String)

    /**
     * Monotonic generation counter. Both [start] and [cancel] bump it; a
     * worker thread treats `generation != myGeneration` as "I was superseded
     * or cancelled — stop". AtomicLong makes the claim in [start] atomic, so
     * concurrent starts get distinct generations.
     */
    private val generation = AtomicLong(0L)
    @Volatile private var running = false

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
        // Claim a fresh generation: any previously running worker sees the
        // mismatch at its next loop check and stops, even if it was still
        // alive when this call ran (K1 race fix).
        val myGeneration = generation.incrementAndGet()

        if (songs.isEmpty()) {
            // Still bumped the generation so a stale scan is cancelled, matching
            // the old `cancel()`-first semantics; nothing new to run.
            if (running) running = false
            return
        }

        running = true

        val appContext = context.applicationContext

        Thread {
            // Lowest priority: won't starve audio threads or the UI
            Process.setThreadPriority(Process.THREAD_PRIORITY_LOWEST)

            var scanned = 0
            var skipped = 0
            var errors  = 0

            Log.d(TAG, "Pre-scan started — ${songs.size} songs to check")

            for (song in songs) {
                if (generation.get() != myGeneration) break
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
                    if (generation.get() == myGeneration) Thread.sleep(INTER_FILE_DELAY_MS)

                } catch (e: InterruptedException) {
                    break
                } catch (e: Exception) {
                    errors++
                    Log.w(TAG, "Pre-scan error for ${song.path}: ${e.message}")
                }
            }

            // Only the worker that still owns the current generation clears
            // `running` — a superseded worker must not reset it while the
            // replacement scan is still in progress.
            if (generation.get() == myGeneration) running = false
            Log.d(TAG, "Pre-scan finished — " +
                "scanned=$scanned skipped=$skipped errors=$errors cancelled=${generation.get() != myGeneration}")

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
        // Bump the generation unconditionally: even if `running` was left stale
        // by a racing superseded worker, the live scan (if any) still observes
        // the mismatch and stops. A scan started concurrently right after this
        // call is a fresh scan and is not affected.
        generation.incrementAndGet()
        if (running) {
            Log.d(TAG, "Pre-scan cancelled")
        }
    }
}
