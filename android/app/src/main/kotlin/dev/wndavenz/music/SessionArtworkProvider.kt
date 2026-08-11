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
import android.util.LruCache
import dev.wndavenz.music.events.NativeLogger
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * Produces the high-resolution, square, letterboxed artwork BYTES that get
 * published as MediaSession metadata (`MediaMetadata.artworkData`).
 *
 * Why this exists — the actual root cause of the "zoom + pecah" notification
 * artwork bug:
 *
 *   SystemUI / MIUI media surfaces (notification shade media card, lock screen
 *   media controls) do NOT render `Notification.Builder.setLargeIcon()`. They
 *   connect to the MediaSession and decode `METADATA_KEY_ART` (artworkData)
 *   or `METADATA_KEY_ART_URI` themselves. MediaItemFactory only sets
 *   artworkUri = `content://media/external/audio/albumart/{albumId}` — the
 *   low-res MediaStore thumbnail (often ≤512 px, non-square). SystemUI then
 *   upscales + center-crops it to fill the large media-artwork slot →
 *   the zoomed & pixelated art the user sees. Large-icon letterboxing can
 *   never fix that path because it is bypassed entirely.
 *
 * Fix: publish `artworkData` = the full-resolution embedded picture,
 * letterboxed onto a square (so no renderer ever center-crops it) and capped
 * at [TARGET_PX]. Every consumer that prefers ART bytes over ART_URI
 * (MediaStyleNotificationHelper, SystemUI, MIUI, MediaSessionLegacyStub /
 * Bluetooth AVRCP) then renders the same sharp square image.
 *
 * Zero-cost fast path: when the source picture is already square and no larger
 * than [TARGET_PX], the original encoded bytes are passed through untouched
 * (no decode / re-encode round trip).
 *
 * Source priority (mirrors the notification pipeline):
 *   1. Full-res embedded picture read straight from the audio file
 *      (MediaMetadataRetriever) — sharpest possible source.
 *   2. The app's persistent artwork cache (ArtworkCacheManager, ≤1000 px).
 *   3. The MediaStore album-art thumbnail URI — last resort.
 *
 * Threading: all work runs on a single daemon thread; the result callback is
 * always invoked (with null on failure) on the provider thread — callers post
 * it to the main looper before touching ExoPlayer.
 */
class SessionArtworkProvider(
    private val context: Context,
    private val artworkCache: ArtworkCacheManager,
) {

    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "session-artwork-provider").also { it.isDaemon = true }
    }

    /**
     * In-memory square-bytes cache per songId. Repeated skips / replays of the
     * same track hit this instead of re-decoding + re-encoding.
     */
    private val bytesCache = LruCache<Int, ByteArray>(MAX_CACHED_TRACKS)

    /**
     * LruCache is not thread-safe. Calls to [provide] normally originate on the
     * service handler while the actual extraction runs on [executor], so both
     * cache access and the in-flight registry use this lock.
     */
    private val cacheLock = Any()

    /**
     * Requests currently being resolved, keyed by songId (or the artwork URI
     * when no songId is available). Multiple refresh callbacks for the same
     * artwork share one extraction and all receive the same result.
     */
    private val inFlight = mutableMapOf<String, MutableList<(ByteArray?) -> Unit>>()

    /**
     * Resolves square artwork bytes for [songId] / [artUri] and invokes
     * [onResult] (possibly synchronously on a cache hit). [onResult] is always
     * called exactly once; null means no artwork could be resolved.
     */
    fun provide(songId: Int, artUri: String?, onResult: (ByteArray?) -> Unit) {
        val requestKey = requestKey(songId, artUri)
        var cached: ByteArray? = null
        var shouldStart = false
        synchronized(cacheLock) {
            if (songId > 0) {
                cached = bytesCache.get(songId)
            }
            if (cached == null) {
                val waiters = inFlight[requestKey]
                if (waiters != null) {
                    waiters += onResult
                } else {
                    inFlight[requestKey] = mutableListOf(onResult)
                    shouldStart = true
                }
            }
        }

        cached?.let {
            onResult(it)
            return
        }
        if (!shouldStart) return

        executor.execute {
            val bytes = try {
                val existing = if (songId > 0) {
                    synchronized(cacheLock) { bytesCache.get(songId) }
                } else {
                    null
                }
                existing ?: buildBytes(songId, artUri).also { hit ->
                    if (hit != null && songId > 0) {
                        synchronized(cacheLock) { bytesCache.put(songId, hit) }
                    }
                }
            } catch (e: Exception) {
                NativeLogger.emit(
                    "debug",
                    "SessionArt",
                    "artwork request failed songId=$songId: ${e.message}",
                )
                null
            }

            val waiters = synchronized(cacheLock) {
                inFlight.remove(requestKey).orEmpty().toList()
            }
            waiters.forEach { waiter ->
                runCatching { waiter(bytes) }
            }
        }
    }

    private fun requestKey(songId: Int, artUri: String?): String =
        if (songId > 0) "song:$songId" else "uri:${artUri.orEmpty()}"

    // ── Private helpers ───────────────────────────────────────────────────────

    private fun buildBytes(songId: Int, artUri: String?): ByteArray? {
        val raw = (if (songId > 0) rawEmbedded(songId) else null)
            ?: rawFromCache(songId)
            ?: rawFromUri(artUri)
            ?: return null

        // Fast path: already-square art at/under target size passes through
        // untouched — no decode/re-encode cost for well-tagged albums.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(raw, 0, raw.size, bounds)
        if (bounds.outWidth == bounds.outHeight &&
            bounds.outWidth in 1..TARGET_PX &&
            bounds.outWidth > 0) {
            return raw
        }

        val decoded = decodeCapped(raw) ?: return null
        return encodeJpeg(letterboxSquare(decoded, TARGET_PX))
    }

    /** Reads the full-resolution embedded picture directly from the audio file. */
    private fun rawEmbedded(songId: Int): ByteArray? {
        val mmr = MediaMetadataRetriever()
        return try {
            val uri = Uri.withAppendedPath(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString()
            )
            mmr.setDataSource(context, uri)
            mmr.embeddedPicture
        } catch (e: Exception) {
            NativeLogger.emit("debug", "SessionArt", "embedded extraction failed songId=$songId: ${e.message}")
            null
        } finally {
            try {
                mmr.release()
            } catch (_: Exception) {
                // Cleanup must not mask the original result/error.
            }
        }
    }

    /** Reads the app's persistent artwork cache file (≤1000 px copy). */
    private fun rawFromCache(songId: Int): ByteArray? {
        if (songId <= 0) return null
        return try {
            val path = artworkCache.getOrExtract(songId) ?: return null
            File(path).readBytes()
        } catch (e: Exception) {
            NativeLogger.emit("debug", "SessionArt", "cache read failed songId=$songId: ${e.message}")
            null
        }
    }

    /** Reads the MediaStore album-art thumbnail URI — lowest-res, last resort. */
    private fun rawFromUri(artUri: String?): ByteArray? {
        if (artUri.isNullOrBlank()) return null
        return try {
            context.contentResolver.openInputStream(Uri.parse(artUri))?.use { it.readBytes() }
        } catch (e: Exception) {
            NativeLogger.emit("debug", "SessionArt", "URI read failed ($artUri): ${e.message}")
            null
        }
    }

    /** Two-pass decode capped at [TARGET_PX] on the longest side. */
    private fun decodeCapped(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while ((bounds.outWidth / sample) > TARGET_PX ||
               (bounds.outHeight / sample) > TARGET_PX) {
            sample *= 2
        }
        return BitmapFactory.decodeByteArray(
            bytes, 0, bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sample },
        )
    }

    /**
     * Letterboxes [source] onto a [maxPx]×[maxPx] square with a black
     * background so SystemUI / MIUI never center-crops the art. Mirrors
     * PlaybackNotificationManager.normalizeNotificationArtwork so every
     * surface renders the same shape.
     */
    private fun letterboxSquare(source: Bitmap, maxPx: Int): Bitmap {
        if (source.width <= 0 || source.height <= 0) return source
        // Never upscale a low-resolution URI fallback. SystemUI performs the
        // final display scaling; enlarging a small MediaStore thumbnail here
        // only preserves its pixelation in a larger payload.
        val target = minOf(maxPx, maxOf(source.width, source.height))
        if (source.width == target && source.height == target) {
            return source
        }

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

    private fun encodeJpeg(bmp: Bitmap): ByteArray? {
        val out = ByteArrayOutputStream()
        return try {
            if (bmp.compress(Bitmap.CompressFormat.JPEG, 90, out)) out.toByteArray() else null
        } catch (e: Exception) {
            NativeLogger.emit("debug", "SessionArt", "JPEG encode failed: ${e.message}")
            null
        }
    }

    companion object {
        /**
         * Square target for the letterboxed session artwork — sharp on the Mi 9T's
         * 1080p media card and consistent with the notification largeIcon pipeline.
         */
        private const val TARGET_PX = 1024

        /** Keep the 12 most recent tracks in memory (~2–4 MB). */
        private const val MAX_CACHED_TRACKS = 12
    }
}
