package dev.wndavenz.music

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.SystemClock
import android.provider.MediaStore
import android.util.Log
import android.util.LruCache
import androidx.media3.common.util.BitmapLoader
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import java.io.File
import java.util.concurrent.Executors

/**
 * BitmapLoader for Media3's MediaSession that falls back to embedded file artwork
 * when the standard MediaStore album-art URI cannot be resolved.
 *
 * Problem this solves:
 *   MediaSessionLegacyStub (Media3's Bluetooth / lock-screen compatibility layer)
 *   calls loadBitmap(artworkUri) on every track change.  For songs stored outside
 *   standard music directories (e.g. Telegram downloads) MediaStore may not have
 *   indexed the embedded artwork, so the URI
 *       content://media/external/audio/albumart/{albumId}
 *   throws FileNotFoundException — logged as:
 *       W/MediaSessionLegacyStub: Failed to load bitmap: FileNotFoundException:
 *           No media for album content://media/external/audio/albums/{id}
 *   This prevents album art from appearing on Bluetooth devices and the lock screen.
 *
 * Strategy (two-pass, fully off-main-thread):
 *   1. Embedded first — parse albumId from the URI, find the MediaStore track, then
 *      decode the FULL-RESOLUTION embedded picture straight from the audio file via
 *      MediaMetadataRetriever (sharpest possible source; the persistent cache only
 *      stores ≤1000 px copies).  MediaStore's own albumart URI is NOT preferred:
 *      it is a low-res thumbnail (often ≤512 px) that SystemUI upscales → blurry.
 *   2. Fallback    — the shared persistent cache (ArtworkCacheManager.getOrExtract),
 *      then the original artworkUri via ContentResolver (for songs whose art
 *      MediaStore has already indexed).  A cache hit returns the stored bytes
 *      immediately — raw-copied JPEG for most songs since 1.5.19 — and a cache miss
 *      runs the same extract-and-persist pipeline as the full player.  No deprecated
 *      DATA column is read — the song is identified by its MediaStore content URI so
 *      scoped-storage rules are respected.
 *
 * Bitmap size & shape: every decode path (URI stream, cached bytes, byte-array API)
 * uses a two-pass BitmapFactory decode capped at MAX_PX on the longest side (bounds
 * first, then sampled) AND is letterboxed onto a square with a black background
 * (never larger than MAX_PX, never upscaled).  SystemUI / MIUI media templates
 * center-crop non-square bitmaps to fill the artwork area — that crop is exactly
 * what makes album art look "zoomed".  Pre-letterboxing to a square keeps the full
 * image visible and sharp.
 *
 * Thread-safety: all work is executed on a single daemon thread; the SettableFuture
 * is always resolved (set or setException) before the thread task ends.
 */
class FallbackBitmapLoader(
    private val context: Context,
    private val artworkCache: ArtworkCacheManager,
) : BitmapLoader {

    companion object {
        private const val TAG    = "FallbackBitmapLoader"
        /** Max longest side for decoded bitmaps — matches PlaybackNotificationManager. */
        private const val MAX_PX = 1024

        /** How many album tracks to probe for embedded art (compilation albums). */
        private const val MAX_ALBUM_PROBE = 3

        /** Albums kept in the positive in-memory artwork cache (~4 MB each). */
        private const val POSITIVE_CACHE_ALBUMS = 4

        /**
         * TTL-based negative cache: albumIds confirmed to have NO resolvable
         * artwork (neither MediaStore-indexed nor embedded in the file). Populated
         * only after both [tryUri] and [tryEmbedded] fail for a given albumId.
         *
         * Why: MediaSessionLegacyStub calls loadBitmap(artworkUri) again on every
         * metadata/queue update, not just once per track — without this cache, a
         * song confirmed to have zero artwork pays a full ContentResolver open +
         * MediaStore query + artwork extraction attempt every single time.
         *
         * Safe because: entries expire after [NO_ARTWORK_TTL_MS], so if MediaStore
         * later indexes new artwork for an albumId (e.g. after a rescan), the
         * loader retries without requiring an app restart.
         */
        private val noArtworkCache = java.util.concurrent.ConcurrentHashMap<Long, Long>()
        private const val NO_ARTWORK_TTL_MS = 30_000L
    }

    /**
     * Single daemon thread — keeps I/O off the main thread and does not prevent
     * process exit when the MediaSession is released.
     */
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "fallback-bitmap-loader").also { it.isDaemon = true }
    }

    /**
     * Positive per-album cache: albumId → resolved, normalized artwork bitmap.
     * MediaSessionLegacyStub calls loadBitmap(artworkUri) again on every metadata
     * / queue update — this skips the MediaStore query + MediaMetadataRetriever
     * extraction entirely for albums already resolved this session. Bounded to
     * [POSITIVE_CACHE_ALBUMS] entries (~4 MB each). Only touched from the single
     * executor thread, so no synchronization needed.
     */
    private val albumArtworkCache = LruCache<Long, Bitmap>(POSITIVE_CACHE_ALBUMS)

    // ── BitmapLoader ──────────────────────────────────────────────────────────

    override fun supportsMimeType(mimeType: String): Boolean {
        // Accept all MIME types — artwork can be JPEG, PNG, WebP, etc.
        return true
    }

    override fun decodeBitmap(data: ByteArray): ListenableFuture<Bitmap> {
        val future = SettableFuture.create<Bitmap>()
        if (executor.isShutdown) {
            future.setException(IllegalStateException("FallbackBitmapLoader is closed"))
            return future
        }
        executor.execute {
            try {
                // E-A: cap at MAX_PX like every other path — never allocate a
                // full-size bitmap for a small notification/lock-screen image.
                val bmp = decodeCapped(data)
                    ?: throw IllegalArgumentException("BitmapFactory returned null for byte array")
                future.set(bmp)
            } catch (e: Exception) {
                future.setException(e)
            }
        }
        return future
    }

    override fun loadBitmap(uri: Uri): ListenableFuture<Bitmap> {
        val future = SettableFuture.create<Bitmap>()
        if (executor.isShutdown) {
            future.setException(IllegalStateException("FallbackBitmapLoader is closed"))
            return future
        }
        val albumId = parseAlbumId(uri)

        // Short-circuit: this albumId was already confirmed to have no artwork
        // (neither MediaStore-indexed nor embedded) within the negative-cache TTL —
        // skip
        // the ContentResolver + MediaStore query + artwork extraction work
        // entirely instead of repeating a known-failed lookup.
        if (albumId != null && isNoArtworkCached(albumId)) {
            future.setException(Exception("No artwork resolved for: $uri (cached)"))
            return future
        }

        executor.execute {
            try {
                // Per-album positive cache: skips the MediaStore query +
                // MediaMetadataRetriever extraction for albums already resolved
                // this session.
                val cached = albumId?.let { albumArtworkCache.get(it) }
                val bmp = cached
                    ?: tryEmbedded(uri) ?: tryUri(uri)
                if (bmp != null) {
                    if (cached == null && albumId != null) albumArtworkCache.put(albumId, bmp)
                    future.set(bmp)
                } else {
                    if (albumId != null) {
                        noArtworkCache[albumId] = SystemClock.elapsedRealtime()
                    }
                    // setException so Media3 knows there is no artwork — it will not
                    // retry, and MediaSessionLegacyStub will simply show no art rather
                    // than logging a fresh warning on every tick.
                    future.setException(Exception("No artwork resolved for: $uri"))
                }
            } catch (e: Exception) {
                future.setException(e)
            }
        }
        return future
    }

    private fun isNoArtworkCached(albumId: Long): Boolean {
        val failedAt = noArtworkCache[albumId] ?: return false
        if (SystemClock.elapsedRealtime() - failedAt > NO_ARTWORK_TTL_MS) {
            noArtworkCache.remove(albumId, failedAt)
            return false
        }
        return true
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /**
     * Primary path: parse albumId from [uri], find MediaStore tracks of that
     * album, and decode the FULL-RESOLUTION embedded picture from the first
     * track that carries one.  Falls back to the shared persistent cache
     * (≤1000 px copies) if every probe fails.
     *
     * Probing up to [MAX_ALBUM_PROBE] tracks (instead of only the first) covers
     * compilation albums whose tracks embed different artwork — the first track
     * with art is the best available representative for the album-art URI.
     *
     * Expected URI format: content://media/external/audio/albumart/{albumId}
     */
    private fun tryEmbedded(uri: Uri): Bitmap? {
        val albumId = parseAlbumId(uri) ?: run {
            Log.d(TAG, "Cannot parse albumId from $uri")
            return null
        }
        val songIds = songIdsForAlbum(albumId) ?: run {
            Log.d(TAG, "No MediaStore track found for albumId=$albumId")
            return null
        }

        // 1) Full-resolution embedded picture — no cache round-trip, no ≤1000 px
        //    cap, no WebP re-encode. This is the sharpest artwork the file has.
        for (songId in songIds) {
            val fullRes = embeddedRawBytes(songId)
            if (fullRes != null) {
                val bmp = decodeCapped(fullRes)
                if (bmp != null) return bmp
            }
        }

        // 2) Persistent cache fallback (raw-copied JPEG for ≤1000 px art, WebP 85
        //    re-encode beyond that) — same pipeline as the in-app player. Iterate
        //    every probed songId (not just the first) so a compilation album whose
        //    only cached art belongs to track 2/3 still resolves instead of being
        //    reported as no-artwork.
        for (songId in songIds) {
            val cachedPath = artworkCache.getOrExtract(songId) ?: continue
            try {
                val bytes = File(cachedPath).readBytes()
                val bmp = decodeCapped(bytes)
                if (bmp != null) return bmp
            } catch (e: Exception) {
                Log.w(TAG, "Failed to read cached artwork for albumId=$albumId songId=$songId: ${e.message}")
            }
        }
        Log.d(TAG, "No artwork cached/extracted for albumId=$albumId")
        return null
    }

    /**
     * Returns up to [MAX_ALBUM_PROBE] MediaStore track _IDs that belong to
     * [albumId], or null if none are found.  The ids are used for embedded-art
     * extraction and the shared artwork cache lookup.
     *
     * Uses the track's _ID (not the deprecated DATA column) so scoped-storage
     * rules are respected and the ids map directly to ArtworkCacheManager entries.
     */
    private fun songIdsForAlbum(albumId: Long): List<Int>? {
        val projection = arrayOf(MediaStore.Audio.Media._ID)
        val selection  = "${MediaStore.Audio.Media.ALBUM_ID} = ?"
        val args       = arrayOf(albumId.toString())
        return try {
            context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection, selection, args,
                /* sortOrder = */ null,
            )?.use { cursor ->
                val ids = mutableListOf<Int>()
                while (cursor.moveToNext() && ids.size < MAX_ALBUM_PROBE) {
                    ids.add(cursor.getInt(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)))
                }
                ids.ifEmpty { null }
            }
        } catch (e: Exception) {
            Log.w(TAG, "MediaStore query failed for albumId=$albumId: ${e.message}")
            null
        }
    }

    /** Reads the embedded picture bytes directly from the audio file (full-res). */
    private fun embeddedRawBytes(songId: Int): ByteArray? {
        val mmr = MediaMetadataRetriever()
        return try {
            val uri = Uri.withAppendedPath(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString()
            )
            mmr.setDataSource(context, uri)
            mmr.embeddedPicture
        } catch (e: Exception) {
            Log.d(TAG, "Embedded extraction failed for songId=$songId: ${e.message}")
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

    /**
     * Fast path: open [uri] via ContentResolver and decode with size capping.
     * Returns null on any failure (URI not found, IO error, decode failure).
     * The MediaStore albumart URI is the low-res thumbnail — used only as the
     * last resort after [tryEmbedded] fails.
     */
    private fun tryUri(uri: Uri): Bitmap? {
        return try {
            // Pass 1: read bounds only (zero pixel allocation).
            val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, boundsOpts)
            }
            // If bounds are invalid the URI content was not a decodable image.
            if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) return null

            // Pass 2: decode at reduced size. ARGB_8888 so already-square art can
            // skip the letterbox copy in normalizeSquare().
            val sample = computeSampleSize(boundsOpts.outWidth, boundsOpts.outHeight, MAX_PX)
            val decodeOpts = BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            val decoded = context.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, decodeOpts)
            } ?: return null
            normalizeSquare(decoded, MAX_PX)
        } catch (e: Exception) {
            Log.d(TAG, "URI load failed ($uri): ${e.message} — trying embedded fallback")
            null
        }
    }

    /**
     * Two-pass decode capped at [MAX_PX] on the longest side — bounds pass first
     * (zero pixel allocation), then a sampled decode — then letterboxed onto a
     * [MAX_PX]×[MAX_PX] square so SystemUI never center-crops non-square art.
     */
    private fun decodeCapped(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val sample = computeSampleSize(bounds.outWidth, bounds.outHeight, MAX_PX)
        val decoded = BitmapFactory.decodeByteArray(
            bytes, 0, bytes.size,
            BitmapFactory.Options().apply {
                inSampleSize = sample
                // ARGB_8888 so already-square art hits the fast path in
                // normalizeSquare() instead of being re-letterboxed.
                inPreferredConfig = Bitmap.Config.ARGB_8888
            },
        ) ?: return null
        return normalizeSquare(decoded, MAX_PX)
    }

    /**
     * Letterboxes [source] onto a square with a black background, capped at
     * [maxPx]×[maxPx]. SystemUI / MIUI media templates fill the artwork area by
     * center-cropping non-square bitmaps — pre-letterboxing keeps the full image
     * visible instead of zoomed. Mirrors
     * PlaybackNotificationManager.normalizeNotificationArtwork.
     *
     * Never upscales: the canvas is no larger than the source's longest side
     * (capped at [maxPx]), so small art stays at native resolution and the
     * system does the final scaling instead of us adding an upscale pass.
     */
    private fun normalizeSquare(source: Bitmap, maxPx: Int): Bitmap {
        if (source.width <= 0 || source.height <= 0) return source
        val target = minOf(maxPx, maxOf(source.width, source.height))
        if (source.width == target && source.height == target) return source

        val out = Bitmap.createBitmap(target, target, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.BLACK)

        val scale = minOf(
            target.toFloat() / source.width.toFloat(),
            target.toFloat() / source.height.toFloat(),
        )
        val drawnW = source.width * scale
        val drawnH = source.height * scale
        val left = (target - drawnW) / 2f
        val top = (target - drawnH) / 2f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG)
        canvas.drawBitmap(source, null, RectF(left, top, left + drawnW, top + drawnH), paint)
        return out
    }

    /** Smallest power-of-two sample size so neither dimension exceeds [maxPx]. */
    private fun computeSampleSize(w: Int, h: Int, maxPx: Int): Int {
        var s = 1
        while ((w / s) > maxPx || (h / s) > maxPx) s = s shl 1
        return s
    }

    /**
     * Parses the albumId from an expected `content://media/external/audio/albumart/{albumId}`
     * URI. Returns null if the last path segment is not numeric (unexpected URI shape).
     */
    private fun parseAlbumId(uri: Uri): Long? = uri.lastPathSegment?.toLongOrNull()

    /**
     * Shuts down the executor and rejects new loads. Idempotent; called from the
     * service's onDestroy so queued I/O cannot outlive service teardown.
     */
    fun close() {
        executor.shutdown()
    }
}
