package com.example.musicplayer

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.MediaStore
import android.util.Log
import androidx.media3.session.BitmapLoader
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
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
 *      that albumId, then extract the embedded picture from the audio file directly
 *      via MediaMetadataRetriever.  No deprecated DATA column is used — the song is
 *      identified by its MediaStore content URI so scoped-storage rules are respected.
 *
 * Bitmap size: artwork is decoded at up to MAX_PX on the longest side via a two-pass
 * BitmapFactory decode (bounds first, then scaled), keeping memory usage bounded.
 *
 * Thread-safety: all work is executed on a single daemon thread; the SettableFuture
 * is always resolved (set or setException) before the thread task ends.
 */
class FallbackBitmapLoader(private val context: Context) : BitmapLoader {

    companion object {
        private const val TAG    = "FallbackBitmapLoader"
        /** Max longest side for decoded bitmaps — matches PlaybackNotificationManager. */
        private const val MAX_PX = 512
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
                val bmp = BitmapFactory.decodeByteArray(data, 0, data.size)
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
        executor.execute {
            try {
                val bmp = tryUri(uri) ?: tryEmbedded(uri)
                if (bmp != null) {
                    future.set(bmp)
                } else {
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
     * and extract its embedded picture via MediaMetadataRetriever.
     *
     * Expected URI format: content://media/external/audio/albumart/{albumId}
     */
    private fun tryEmbedded(uri: Uri): Bitmap? {
        val albumId = uri.lastPathSegment?.toLongOrNull() ?: run {
            Log.d(TAG, "Cannot parse albumId from $uri")
            return null
        }
        val songUri = songUriForAlbumId(albumId) ?: run {
            Log.d(TAG, "No MediaStore track found for albumId=$albumId")
            return null
        }
        return try {
            // MediaMetadataRetriever implements AutoCloseable since API 29 (Android 10).
            // setDataSource(Context, Uri) respects scoped storage on Android 10+.
            MediaMetadataRetriever().use { mmr ->
                mmr.setDataSource(context, songUri)
                val bytes = mmr.embeddedPicture
                if (bytes != null) {
                    Log.d(TAG, "Embedded artwork extracted for albumId=$albumId")
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                } else {
                    Log.d(TAG, "No embedded artwork for albumId=$albumId")
                    null
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Embedded extraction failed for albumId=$albumId: ${e.message}")
            null
        }
    }

    /**
     * Returns the content URI of the first MediaStore track that belongs to
     * [albumId], or null if not found.
     *
     * Uses the track's _ID (not the deprecated DATA column) so the result URI
     * is safe to pass to MediaMetadataRetriever.setDataSource(Context, Uri).
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

    /** Smallest power-of-two sample size so neither dimension exceeds [maxPx]. */
    private fun computeSampleSize(w: Int, h: Int, maxPx: Int): Int {
        var s = 1
        while ((w / s) > maxPx || (h / s) > maxPx) s = s shl 1
        return s
    }
}
