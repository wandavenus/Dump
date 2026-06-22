package com.example.musicplayer

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Persistent WebP artwork cache stored in `{cacheDir}/artwork/{songId}.webp`.
 *
 * Design goals:
 *  - Zero MediaStore I/O on subsequent app launches (cache hit returns path immediately).
 *  - Atomic writes: artwork is saved to `{id}.webp.tmp` then renamed so a partial write
 *    is never visible as a valid cache entry.
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
        private const val MAX_ARTWORK_SIZE = 1024
    

    // Lazily create the cache directory on first access.
    private val cacheDir: File by lazy {
    File(context.cacheDir, CACHE_SUBDIR).also { dir ->
        dir.mkdirs()

        dir.listFiles { file ->
            file.name.endsWith(".tmp")
        }?.forEach {
            try {
                it.delete()
            } catch (_: Exception) {}
        }
    }
}

    // Global lock guards the per-songId lock map to prevent map corruption.
    private val globalLock  = ReentrantLock()
    // Per-songId locks prevent double-extraction of the same song under concurrency.
    private val songLocks   = HashMap<Int, ReentrantLock>()

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
     * Slow path (cache miss): extract via MediaMetadataRetriever → encode WebP 85 →
     *   write atomically → return path.
     * Returns null only when artwork cannot be extracted (song has no embedded art).
     *
     * Thread-safety note: the per-songId lock is acquired before extraction and
     * released (by withLock) before cleanupSongLock removes it from the map.
     * This ensures no concurrent thread ever holds two locks for the same songId.
     */
    fun getOrExtract(songId: Int): String? {
        if (songId <= 0) return null

        val target = File(cacheDir, "$songId.webp")

        // Fast path — file already cached.
        if (target.exists() && target.length() > 0L) {
            touch(target)           // update mtime for LRU ordering
            return target.absolutePath
        }

        // Acquire a per-songId lock to serialise concurrent requests for the same song.
        val lock = globalLock.withLock {
            songLocks.getOrPut(songId) { ReentrantLock() }
        }

        // NOTE: cleanupSongLock is called in the finally block, AFTER withLock has
        // fully released the lock.  Calling it inside withLock would allow a
        // concurrent thread to create a new lock and start extraction before the
        // current thread's withLock lambda finishes — a subtle but real race.
        val result: String? = try {
            lock.withLock {
                // Re-check after acquiring the lock (another thread may have written it).
                if (target.exists() && target.length() > 0L) {
                    touch(target)
                    return@withLock target.absolutePath
                }

                val raw = extractRawBytes(songId) ?: return@withLock null

                val ok = saveAsWebP(raw, target)

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
        // This runs outside the per-songId lock — cleanup is idempotent and only
        // does real work when total cache size exceeds MAX_BYTES.
        if (result != null) cleanupIfNeeded(activeQueueIds)

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

    // ── Diagnostics ────────────────────────────────────────────────────────────

    fun cacheCount(): Int =
        cacheDir.listFiles { f -> f.extension == "webp" }?.size ?: 0

    fun cacheSizeBytes(): Long =
        cacheDir.listFiles { f -> f.extension == "webp" }?.sumOf { it.length() } ?: 0L

    // ── Private helpers ────────────────────────────────────────────────────────

    private fun extractRawBytes(songId: Int): ByteArray? {
        return try {
            val uri = Uri.withAppendedPath(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString()
            )
            val mmr = MediaMetadataRetriever()
            mmr.setDataSource(context, uri)
            val bytes = mmr.embeddedPicture
            mmr.release()
            bytes
        } catch (e: Exception) {
            Log.w(TAG, "Cannot extract artwork songId=$songId: ${e.message}")
            null
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
        val tmp = File(target.parent, "${target.name}.tmp")
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

                bitmap.compress(fmt, WEBP_QUALITY, out)
                out.flush()
            }

            ok = tmp.renameTo(target)
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

    /** Update lastModified so LRU order reflects access time. */
    private fun touch(file: File) {
        try { file.setLastModified(System.currentTimeMillis()) } catch (_: Exception) {}
    }

    private fun cleanupSongLock(songId: Int) {
        globalLock.withLock { songLocks.remove(songId) }
    }
}
