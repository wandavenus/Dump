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
import android.provider.MediaStore
import android.util.Log
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
 * first, then sampled) AND is letterboxed onto a MAX_PX×MAX_PX square with a black
 * background.  SystemUI / MIUI media templates center-crop non-square bitmaps to
 * fill the artwork area — that crop is exactly what makes album art look "zoomed".
 * Pre-letterboxing to a square keeps the full image visible and sharp.
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

        /**
         * Session-lifetime negative cache: albumIds confirmed to have NO resolvable
         * artwork (neither MediaStore-indexed nor embedded in the file). Populated
         * only after both [tryUri] and [tryEmbedded] fail for a given albumId.
         *
         * Why: MediaSessionLegacyStub calls loadBitmap(artworkUri) again on every
         * metadata/queue update, not just once per track — without this cache, a
         * song confirmed to have zero artwork pays a full ContentResolver open +
         * MediaStore query + artwork extraction attempt every single time.
         *
         * Safe because: cache lives only for the process lifetime (cleared on app
         * restart), so if MediaStore later indexes new artwork for an albumId
         * (e.g. after a rescan), the worst case is it stays "no artwork" until the
         * next cold start — never a permanent or persisted false negative.
         */
        private val noArtworkCache = java.util.concurrent.ConcurrentHashMap.newKeySet<Long>()
    }

    /**
     * Single daemon thread — keeps I/O off the main thread and does not prevent
     * process exit when the MediaSession is released.
     */
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "fallback-bitmap-loader").also { it.isDaemon = true }
    }

    // ── BitmapLoader ──────────────────────────────────────────────────────────

    override fun supportsMimeType(mimeType: String): Boolean {
        // Accept all MIME types — artwork can be JPEG, PNG, WebP, etc.
        return true
    }

    override fun decodeBitmap(data: ByteArray): ListenableFuture<Bitmap> {
        val future = SettableFuture.create<Bitmap>()
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
        val albumId = parseAlbumId(uri)

        // Short-circuit: this albumId was already confirmed to have no artwork
        // (neither MediaStore-indexed nor embedded) earlier this session — skip
        // the ContentResolver + MediaStore query + artwork extraction work
        // entirely instead of repeating a known-failed lookup.
        if (albumId != null && noArtworkCache.contains(albumId)) {
            future.setException(Exception("No artwork resolved for: $uri (cached)"))
            return future
        }

        executor.execute {
            try {
                // Embedded first: sharpest source (full-res embedded picture).
                // MediaStore albumart URI second: low-res thumbnail fallback.
                val bmp = tryEmbedded(uri) ?: tryUri(uri)
                if (bmp != null) {
                    future.set(bmp)
                } else {
                    if (albumId != null) noArtworkCache.add(albumId)
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

    // ── Private helpers ───────────────────────────────────────────────────────

    /**
     * Fallback path (now primary): parse albumId from [uri], find a matching
     * MediaStore track, and decode that song's FULL-RESOLUTION embedded artwork
     * straight from the audio file.  Falls back to the shared persistent cache
     * (≤1000 px copies) if the direct decode fails.
     *
     * Expected URI format: content://media/external/audio/albumart/{albumId}
     */
    private fun tryEmbedded(uri: Uri): Bitmap? {
        val albumId = parseAlbumId(uri) ?: run {
            Log.d(TAG, "Cannot parse albumId from $uri")
            return null
        }
        val songUri = songUriForAlbumId(albumId) ?: run {
            Log.d(TAG, "No MediaStore track found for albumId=$albumId")
            return null
        }
        val songId = songUri.lastPathSegment?.toLongOrNull()?.toInt() ?: run {
            Log.d(TAG, "Cannot parse songId from $songUri")
            return null
        }

        // 1) Full-resolution embedded picture — no cache round-trip, no ≤1000 px
        //    cap, no WebP re-encode. This is the sharpest artwork the file has.
        val fullRes = embeddedRawBytes(songId)
        if (fullRes != null) {
            val bmp = decodeCapped(fullRes)
            if (bmp != null) return bmp
        }

        // 2) Persistent cache fallback (raw-copied JPEG for ≤1000 px art, WebP 85
        //    re-encode beyond that) — same pipeline as the in-app player.
        val cachedPath = artworkCache.getOrExtract(songId) ?: run {
            Log.d(TAG, "No artwork cached/extracted for albumId=$albumId")
            return null
        }
        return try {
            val bytes = File(cachedPath).readBytes()
            decodeCapped(bytes)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read cached artwork for albumId=$albumId: ${e.message}")
            null
        }
    }

    /**
     * Returns the content URI of the first MediaStore track that belongs to
     * [albumId], or null if not found.  The numeric id in the returned URI is
     * the songId used to look up the shared artwork cache.
     *
     * Uses the track's _ID (not the deprecated DATA column) so the result URI
     * respects scoped storage and maps directly to an ArtworkCacheManager entry.
     */
    private fun songUriForAlbumId(albumId: Long): Uri? {
        val projection = arrayOf(MediaStore.Audio.Media._ID)
        val selection  = "${MediaStore.Audio.Media.ALBUM_ID} = ?"
        val args       = arrayOf(albumId.toString())
        return try {
            context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection, selection, args,
                /* sortOrder = */ null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID))
                Uri.withAppendedPath(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id.toString())
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

            // Pass 2: decode at reduced size.
            val sample = computeSampleSize(boundsOpts.outWidth, boundsOpts.outHeight, MAX_PX)
            val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
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
            BitmapFactory.Options().apply { inSampleSize = sample },
        ) ?: return null
        return normalizeSquare(decoded, MAX_PX)
    }

    /**
     * Letterboxes [source] onto a [maxPx]×[maxPx] square with a black background.
     * SystemUI / MIUI media templates fill the artwork area by center-cropping
     * non-square bitmaps — pre-letterboxing keeps the full image visible instead
     * of zoomed. Mirrors PlaybackNotificationManager.normalizeNotificationArtwork.
     */
    private fun normalizeSquare(source: Bitmap, maxPx: Int): Bitmap {
        if (source.width <= 0 || source.height <= 0) return source
        if (source.width == maxPx && source.height == maxPx && source.config == Bitmap.Config.ARGB_8888) {
            return source
        }

        val out = Bitmap.createBitmap(maxPx, maxPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.BLACK)

        val scale = minOf(
            maxPx.toFloat() / source.width.toFloat(),
            maxPx.toFloat() / source.height.toFloat(),
        )
        val drawnW = source.width * scale
        val drawnH = source.height * scale
        val left = (maxPx - drawnW) / 2f
        val top = (maxPx - drawnH) / 2f
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
}
