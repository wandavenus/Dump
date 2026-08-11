package dev.wndavenz.music

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.MediaStore
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Persistent WebP artwork cache stored in `{filesDir}/artwork/{songId}.webp`.
 *
 * Stored in [Context.filesDir] (app support directory) rather than [Context.cacheDir]
 * so files are never cleared by MIUI or Android's automatic storage-free mechanisms.
 *
 * Design goals:
 *  - Zero MediaStore I/O on subsequent app launches (cache hit returns path immediately).
 *  - Atomic writes: artwork is saved to `{id}.webp.tmp` then renamed so a partial write
 *    is never visible as a valid cache entry.
 *  - Zero re-encode fast path: embedded JPEG art already ≤ MAX_ARTWORK_SIZE is copied to
 *    cache byte-for-byte (no decode/re-encode), so cache-miss extraction is near-instant.
 *  - Thread-safe: [getOrExtract] may be called from any thread (used from a background
 *    thread in the MethodChannel handler to avoid blocking the Flutter UI thread).
 *  - LRU eviction via [cleanupIfNeeded]: when cache > 500 MB, deletes oldest files
 *    (by lastModified) while preserving songs currently in the active queue.
 */
class ArtworkCacheManager(private val context: Context) {

    companion object {
        private const val TAG           = "ArtworkCache"
        private const val CACHE_SUBDIR  = "artwork"
        private const val MAX_BYTES     = 500L * 1024 * 1024   // 500 MB hard cap
        private const val TARGET_BYTES  = 400L * 1024 * 1024   // shrink to 400 MB
        private const val WEBP_QUALITY  = 85
        private const val MAX_ARTWORK_SIZE = 1000
        // A3 (1.5.21): raw-copy fast path extended beyond JPEG — any decodable
        // artwork up to this size (and ≤ MAX_ARTWORK_SIZE on both sides) is
        // byte-copied into the cache instead of paying the 50–150 ms
        // decode → scale → re-encode WebP round-trip.
        private const val MAX_RAW_COPY_BYTES = 400 * 1024
        // A1 (1.5.21): LRU bookkeeping (listFiles + size sum over the whole
        // cache dir) runs at most once per this window instead of after every
        // single extraction.
        private const val CLEANUP_THROTTLE_MS = 15_000L

        // MainActivity and Media3PlaybackService intentionally share the same
        // on-disk cache, so their extraction locks must also be process-wide.
        private val processGlobalLock = ReentrantLock()
        private val processSongLocks = HashMap<Int, ReentrantLock>()
        private val processInFlightSongIds = HashSet<Int>()
    }

    // A1 (1.5.21): monotonic timestamp of the last LRU eviction pass.
    @Volatile
    private var lastCleanupAtMs = 0L

    // Lazily create the persistent cache directory on first access.
    // Uses filesDir (app support directory) so files survive MIUI/system cleanup.
    private val cacheDir: File by lazy {
    File(context.filesDir, CACHE_SUBDIR).also { dir ->
        dir.mkdirs()

        // Do not eagerly delete temp files here. Multiple cache-manager
        // instances (Activity + playback service) share this directory and a
        // second instance may otherwise delete an active writer's temp file.
    }
}

    // Active-queue song IDs: never evicted during LRU cleanup.
    // Written by Flutter via setActiveQueueIds(); read during cleanupIfNeeded().
    @Volatile
    private var activeQueueIds: Set<Int> = emptySet()

    // ── Public API ─────────────────────────────────────────────────────────────

    /**
     * Update the set of song IDs that are currently queued for playback.
     * These songs will never be evicted during LRU cleanup.
     * Call this from the Flutter side whenever the playback queue changes.
     */
    fun setActiveQueueIds(ids: Set<Int>) {
        activeQueueIds = ids
    }

    /**
     * Returns the absolute path to `{cacheDir}/artwork/{songId}.webp`.
     *
     * Fast path (cache hit): file exists → return path immediately.
     * Slow path (cache miss): extract via MediaMetadataRetriever → write atomically →
     *   return path. Small JPEG art is raw-copied without decode/re-encode; larger or
     *   non-JPEG art is scaled to MAX_ARTWORK_SIZE and encoded WebP 85.
     * Returns null only when artwork cannot be extracted (song has no embedded art).
     *
     * Thread-safety note: the per-songId lock registry is process-wide because
     * Activity and playback service instances share this directory.
     */
    fun getOrExtract(songId: Int): String? {
        if (songId <= 0) return null

        val target = File(cacheDir, "$songId.webp")

        // Fast path — file already cached.
        if (isUsableCacheFile(target)) {
            touch(target)           // update mtime for LRU ordering
            return target.absolutePath
        }
        if (target.exists()) {
            try { target.delete() } catch (_: Exception) {}
        }

        // Acquire a per-songId lock to serialise concurrent requests for the same song.
        val lock = processGlobalLock.withLock {
            processSongLocks.getOrPut(songId) { ReentrantLock() }
        }
        processGlobalLock.withLock { processInFlightSongIds.add(songId) }

        // NOTE: cleanupSongLock is called in the finally block, AFTER withLock has
        // fully released the lock.  Calling it inside withLock would allow a
        // concurrent thread to create a new lock and start extraction before the
        // current thread's withLock lambda finishes — a subtle but real race.
        val result: String? = try {
            lock.withLock {
                // Re-check after acquiring the lock (another thread may have written it).
                if (isUsableCacheFile(target)) {
                    touch(target)
                    return@withLock target.absolutePath
                }
                if (target.exists()) {
                    try { target.delete() } catch (_: Exception) {}
                }

                val raw = extractRawBytes(songId) ?: return@withLock null

                // E-A fast path (extended in 1.5.21 to PNG/WebP): small decodable
                // artwork ≤ MAX_ARTWORK_SIZE and ≤ MAX_RAW_COPY_BYTES is written to
                // cache byte-for-byte — no 50–150 ms decode → re-encode WebP round-trip
                // and no quality loss from double compression. Larger or non-
                // raw-copyable art still goes through the two-pass scaled WebP encode.
                val ok = if (isRawCopyCandidate(raw)) {
                    saveRaw(raw, target)
                } else {
                    saveAsWebP(raw, target)
                }

                if (ok) {
                    touch(target)
                    target.absolutePath
                } else {
                    null
                }
            }
        } finally {
            // Remove from map only after the lock is fully released by withLock,
            // so no concurrent thread can ever observe the lock while it is held.
            cleanupSongLock(songId)
        }

        // Run LRU cleanup after a successful save, protecting the active queue.
        // Also protect any songId that currently holds a per-songId lock
        // (i.e. being extracted by another thread) to prevent a TOCTOU where
        // cleanup deletes a file between the fast-path exists() check and the
        // caller consuming the returned path.
        if (result != null) {
            val lockedIds = processGlobalLock.withLock { processInFlightSongIds.toSet() }
            // A1 (1.5.21): throttle the LRU eviction pass to at most once per
            // CLEANUP_THROTTLE_MS. The previous code scanned the whole cache
            // directory (listFiles + size sum) after EVERY successful extraction
            // — with 3 concurrent extraction threads, a large batch/prefetch
            // turned that into repeated O(n) directory scans dozens of times per
            // second. The 500 MB cap is a soft ceiling; evicting a few seconds
            // later changes nothing user-visible.
            val now = SystemClock.elapsedRealtime()
            if (now - lastCleanupAtMs >= CLEANUP_THROTTLE_MS) {
                lastCleanupAtMs = now
                cleanupIfNeeded(activeQueueIds + lockedIds)
            }
        }

        return result
    }

    /**
     * Evicts LRU cache files when total size exceeds [MAX_BYTES].
     * Files whose songId appears in [activeQueueIds] are never deleted.
     * Call after a batch of extractions.
     */
    fun cleanupIfNeeded(activeQueueIds: Set<Int> = emptySet()) {
        val files = cacheDir.listFiles { f -> f.extension == "webp" } ?: return
        val total = files.sumOf { it.length() }
        if (total <= MAX_BYTES) return

        val candidates = files
            .filter { f ->
                val id = f.nameWithoutExtension.toIntOrNull()
                id != null && id !in activeQueueIds
            }
            .sortedBy { it.lastModified() }   // oldest first

        var remaining = total
        for (f in candidates) {
            if (remaining <= TARGET_BYTES) break
            val sz = f.length()
            if (f.delete()) {
                remaining -= sz
                Log.d(TAG, "Evicted ${f.name} (${sz / 1024} KB)")
            }
        }
    }

    /**
     * Deletes the persistent cache entry for [songId] (e.g. after the song is
     * removed from the library). The file is re-extracted on the next
     * [getOrExtract] call. Safe to call concurrently with extraction: worst
     * case a concurrent writer recreates the file, which is correct for a
     * song that still exists. A2 fix — previously the on-disk entry could
     * only ever leave via LRU eviction, so a deleted/replaced song's old
     * artwork could linger indefinitely.
     */
    fun delete(songId: Int) {
        if (songId <= 0) return
        try {
            val target = File(cacheDir, "$songId.webp")
            if (target.exists()) target.delete()
        } catch (_: Exception) {
            // Best-effort: a failed delete only costs a stale file that LRU
            // cleanup will eventually evict.
        }
    }

    // ── Diagnostics ────────────────────────────────────────────────────────────

    fun cacheCount(): Int =
        cacheDir.listFiles { f -> f.extension == "webp" }?.size ?: 0

    fun cacheSizeBytes(): Long =
        cacheDir.listFiles { f -> f.extension == "webp" }?.sumOf { it.length() } ?: 0L

    // ── Private helpers ────────────────────────────────────────────────────────

    private fun extractRawBytes(songId: Int): ByteArray? {
        val mmr = MediaMetadataRetriever()
        return try {
            val uri = Uri.withAppendedPath(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString()
            )
            mmr.setDataSource(context, uri)
            mmr.embeddedPicture
        } catch (e: Exception) {
            Log.w(TAG, "Cannot extract artwork songId=$songId: ${e.message}")
            null
        } finally {
            // Always release, even if setDataSource()/embeddedPicture throws.
            // Relying on the finalizer here is known to cause
            // MediaMetadataRetriever.finalize() TimeoutException crashes in
            // apps that load artwork inside a scrolling grid/RecyclerView.
            try {
                mmr.release()
            } catch (_: Exception) {
                // Cleanup must not mask the original extraction result/error.
            }
        }
    }

    private fun decodeScaledBitmap(raw: ByteArray): Bitmap? {
    val bounds = BitmapFactory.Options().apply {
        inJustDecodeBounds = true
    }

    BitmapFactory.decodeByteArray(
        raw,
        0,
        raw.size,
        bounds
    )

    var sampleSize = 1

    while (
        bounds.outWidth / sampleSize > MAX_ARTWORK_SIZE ||
        bounds.outHeight / sampleSize > MAX_ARTWORK_SIZE
    ) {
        sampleSize *= 2
    }

    return BitmapFactory.decodeByteArray(
        raw,
        0,
        raw.size,
        BitmapFactory.Options().apply {
            inSampleSize = sampleSize
        }
    )
    }

    
    /**
     * Decode [raw] → Bitmap → compress to WebP → write atomically to [target].
     * Uses WEBP_LOSSY on API 30+ (Android 11) and the legacy WEBP format below.
     */
    private fun saveAsWebP(raw: ByteArray, target: File): Boolean {
        var bitmap: Bitmap? = null
        val tmp = uniqueTempFile(target)
        var ok = false

        return try {
            bitmap = decodeScaledBitmap(raw) ?: return false

            FileOutputStream(tmp).use { out ->
                val fmt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    Bitmap.CompressFormat.WEBP_LOSSY
                } else {
                    @Suppress("DEPRECATION")
                    Bitmap.CompressFormat.WEBP
                }

                if (!bitmap.compress(fmt, WEBP_QUALITY, out)) return false
                out.flush()
            }

            ok = tmp.length() > 0L && tmp.renameTo(target)
            ok
        } catch (e: Exception) {
            Log.w(TAG, "Failed to save WebP for ${target.name}: ${e.message}")
            false
        } finally {
            bitmap?.recycle()
            if (!ok) {
                try {
                    tmp.delete()
                } catch (_: Exception) {}
            }
        }
    }

    /**
     * True when [raw] starts with a JPEG SOI marker (FF D8 FF) — the embedded
     * art format used by the vast majority of real-world music files.
     */
    private fun isJpeg(raw: ByteArray): Boolean =
        raw.size >= 3 &&
            raw[0] == 0xFF.toByte() &&
            raw[1] == 0xD8.toByte() &&
            raw[2] == 0xFF.toByte()

    /** True when [raw] starts with the PNG signature (89 50 4E 47). */
    private fun isPng(raw: ByteArray): Boolean =
        raw.size >= 8 &&
            raw[0] == 0x89.toByte() &&
            raw[1] == 0x50.toByte() &&
            raw[2] == 0x4E.toByte() &&
            raw[3] == 0x47.toByte()

    /** True when [raw] is a RIFF container holding a WEBP payload. */
    private fun isWebp(raw: ByteArray): Boolean =
        raw.size >= 12 &&
            raw[0] == 'R'.code.toByte() &&
            raw[1] == 'I'.code.toByte() &&
            raw[2] == 'F'.code.toByte() &&
            raw[3] == 'F'.code.toByte() &&
            raw[8] == 'W'.code.toByte() &&
            raw[9] == 'E'.code.toByte() &&
            raw[10] == 'B'.code.toByte() &&
            raw[11] == 'P'.code.toByte()

    /**
     * True when [raw] is a raw-copy candidate: decodable JPEG/PNG/WebP, no
     * larger than [MAX_ARTWORK_SIZE] on either side, and small enough that
     * byte-copying beats a decode → scale → re-encode WebP round-trip (which
     * costs 50–150 ms per song on mid-range devices and degrades quality via
     * double compression).
     *
     * The bounds-only decode (zero pixel allocation) also guards the raw-copy
     * path: a corrupt payload (valid magic bytes, broken image data) must never
     * be committed to cache as-is, so anything that fails here falls back to
     * the WebP path, which reports failure cleanly.
     */
    private fun isRawCopyCandidate(raw: ByteArray): Boolean {
        if (raw.size > MAX_RAW_COPY_BYTES) return false
        if (!isJpeg(raw) && !isPng(raw) && !isWebp(raw)) return false
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(raw, 0, raw.size, bounds)
        return bounds.outWidth in 1..MAX_ARTWORK_SIZE &&
            bounds.outHeight in 1..MAX_ARTWORK_SIZE
    }

    /**
     * Raw-copy fast path: writes the original embedded bytes to [target]
     * atomically (tmp + rename) without the decode → scale → re-encode WebP
     * round-trip, which costs 100–300 ms per song on mid-range devices and
     * degrades quality via double compression.
     *
     * The file keeps its `.webp` extension for cache bookkeeping (LRU cleanup
     * filters on it); every reader — Flutter's FileImage and BitmapFactory —
     * sniffs content magic bytes, not extensions, so a JPEG payload decodes
     * correctly end-to-end.
     */
    private fun saveRaw(raw: ByteArray, target: File): Boolean {
        val tmp = uniqueTempFile(target)
        var ok = false
        return try {
            FileOutputStream(tmp).use { out ->
                out.write(raw)
                out.flush()
            }
            ok = tmp.renameTo(target)
            ok
        } catch (e: Exception) {
            Log.w(TAG, "Failed to save raw artwork for ${target.name}: ${e.message}")
            false
        } finally {
            if (!ok) {
                try {
                    tmp.delete()
                } catch (_: Exception) {}
            }
        }
    }

    /** Update lastModified so LRU order reflects access time. */
    private fun touch(file: File) {
        try { file.setLastModified(System.currentTimeMillis()) } catch (_: Exception) {}
    }

    private fun uniqueTempFile(target: File): File {
        val threadId = Thread.currentThread().id
        return File(
            target.parent,
            "${target.name}.${android.os.Process.myPid()}.$threadId.tmp",
        )
    }

    private fun cleanupSongLock(songId: Int) {
        // Keep the process-wide lock object for the lifetime of the process.
        // Removing it after unlock races with another ArtworkCacheManager
        // instance acquiring the same song ID and can create two locks.
        processGlobalLock.withLock { processInFlightSongIds.remove(songId) }
    }

    private fun isUsableCacheFile(file: File): Boolean {
        if (!file.exists() || file.length() <= 0L) return false
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, bounds)
            bounds.outWidth > 0 && bounds.outHeight > 0
        } catch (_: Exception) {
            false
        }
    }
}
