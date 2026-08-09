package dev.wndavenz.music

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
 *   1. Fast path  — open the artworkUri via ContentResolver (works for songs whose
 *      art MediaStore has already indexed).
 *   2. Fallback   — parse albumId from the URI, query MediaStore for any track with
 *      that albumId, then serve that song's artwork from the shared persistent cache
 *      (ArtworkCacheManager.getOrExtract): a cache hit returns the stored bytes
 *      immediately — raw-copied JPEG for most songs since 1.5.19 — and a cache miss
 *      runs the exact same extract-and-persist pipeline as the full player.  No
 *      MediaMetadataRetriever is used here, and no deprecated DATA column is read —
 *      the song is identified by its MediaStore content URI so scoped-storage rules
 *      are respected.
 *
 * Bitmap size: every decode path (URI stream, cached bytes, byte-array API) uses a
 * two-pass BitmapFactory decode capped at MAX_PX on the longest side (bounds first,
 * then sampled), keeping memory usage bounded instead of allocating full-size art.
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
        private const val MAX_PX = 512

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
                val bmp = tryUri(uri) ?: tryEmbedded(uri)
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
     * Fast path: open [uri] via ContentResolver and decode with size capping.
     * Returns null on any failure (URI not found, IO error, decode failure).
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
            context.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, decodeOpts)
            }
        } catch (e: Exception) {
            Log.d(TAG, "URI load failed ($uri): ${e.message} — trying embedded fallback")
            null
        }
    }

    /**
     * Fallback path: parse albumId from [uri], find a matching MediaStore track,
     * and serve that song's artwork from the shared persistent cache.
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
        // Same pipeline as the in-app artwork: cache hit serves the stored bytes
        // immediately (raw-copied JPEG for most songs since 1.5.19 E-A); cache miss
        // extracts + persists here.  No MediaMetadataRetriever round-trip and never
        // a full-size decode — [decodeCapped] caps at MAX_PX below.
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

    /**
     * Two-pass decode capped at [MAX_PX] on the longest side — bounds pass first
     * (zero pixel allocation), then a sampled decode.  The E-A equivalent for the
     * BitmapLoader contract (which must return a Bitmap): decode only what the
     * notification/lock-screen actually renders, never a full-size embedded image.
     */
    private fun decodeCapped(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val sample = computeSampleSize(bounds.outWidth, bounds.outHeight, MAX_PX)
        return BitmapFactory.decodeByteArray(
            bytes, 0, bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sample },
        )
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
