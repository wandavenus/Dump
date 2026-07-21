package dev.wndavenz.music.notification

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaStyleNotificationHelper
import dev.wndavenz.music.ArtworkCacheManager
import dev.wndavenz.music.Media3PlaybackService
import dev.wndavenz.music.R
import dev.wndavenz.music.events.NativeLogger
import java.util.concurrent.Executors

/**
 * Media playback notification manager for [Media3PlaybackService].
 *
 * Accepts any [android.app.Service] as host and manages the foreground
 * media notification lifecycle.
 *
 * The [serviceClass] parameter determines the PendingIntent target for
 * transport action buttons (Play/Pause, Next, Previous, Stop).
 *
 * Fixes applied:
 * NS-01: Unified notification building — single buildNotification() shared by both
 *        ensureMediaForeground() and refresh(), eliminating subtle inconsistencies.
 * NS-03: Artwork bitmap loading is moved to a background thread; notifications post
 *        first without artwork, then update once the bitmap is ready. A generation
 *        counter prevents stale async results from overwriting a newer notification.
 * NS-04: launchPendingIntent is cached as a lazy val — no rebuild on every refresh.
 * ART-01: loadBitmap() now has a two-stage fallback pipeline:
 *         1. ContentResolver (MediaStore album art URI)
 *         2. ArtworkCacheManager.getOrExtract(songId) — same pipeline as Full Player
 *        This ensures Notification, Lock Screen, Bluetooth, and Android Auto all draw
 *        artwork from the same source as the in-app Full Player and Mini Player.
 * ART-02: noArtworkUris replaced with a TTL-based map (30 s). Transient failures
 *         (e.g. MediaStore not yet ready on cold start) are retried after expiry
 *         instead of being permanently blocked until app restart.
 * ART-03: songId (existing "id" field) used for fallback — no new fields added.
 */
@UnstableApi
class PlaybackNotificationManager(
    private val service: Service,
    private val handler: Handler,
    private val getSession: () -> MediaSession?,
    private val getIsPlaying: () -> Boolean,
    private val getCurrentTrack: () -> Map<String, Any?>?,
    private val serviceClass: Class<*> = Media3PlaybackService::class.java,
    /** Same ArtworkCacheManager instance used by the Full Player (passed from the service).
     *  Provides embedded-art extraction + persistent WebP disk cache as a fallback when
     *  the MediaStore album-art URI cannot be resolved. */
    private val artworkCacheManager: ArtworkCacheManager? = null,
) {
    var isForeground = false
        private set

    private val notificationManager: NotificationManager by lazy {
        service.getSystemService(NotificationManager::class.java)
    }

    // NS-04 fix: cached once, not rebuilt on every refresh call.
    private val launchPendingIntent: PendingIntent? by lazy {
        service.packageManager.getLaunchIntentForPackage(service.packageName)?.let { intent ->
            PendingIntent.getActivity(
                service, 0, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }
    }

    // LRU bitmap cache (max 10 entries) — evicts least-recently-used album art automatically.
    // Key is artUri when available, or "song:{songId}" for embedded-only tracks.
    private val bitmapCache = android.util.LruCache<String, Bitmap>(10)

    // ART-02 fix: TTL-based no-artwork map. Entries expire after NO_ARTWORK_TTL_MS so
    // transient failures (MediaStore not ready on cold start) can be retried automatically.
    // Bounded to 64 entries to prevent unbounded growth during long sessions.
    private val noArtworkTimestamps = HashMap<String, Long>(64)

    private var artworkLoadGeneration = 0L

    // Patch A (RC-2 fix): tracks the cacheKey of the currently-enqueued async load.
    // refreshAsync() bails out early if the same key is already pending — prevents the
    // 3 redundant loadBitmap() calls that fire within ~1 ms at crossfade start
    // (onIsPlayingChanged + onPlaybackStateChanged + refreshNotification all trigger
    // refresh() in quick succession for the same incoming track).
    // Accessed only on the main/Handler thread — no synchronisation needed.
    private var pendingAsyncCacheKey: String? = null

    // LOW-04 fix: single daemon thread reused for all artwork loads instead of spawning
    // a new thread per refresh() call. Prevents thread explosion during rapid track changes.
    private val artworkExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "artwork-loader").also { it.isDaemon = true }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (notificationManager.getNotificationChannel(CHANNEL_ID) == null) {
            notificationManager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Music Playback",
                    NotificationManager.IMPORTANCE_LOW).apply {
                    setSound(null, null)
                    enableVibration(false)
                }
            )
        }
    }

    fun buildTransportPendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(service, serviceClass).setAction(action)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(
                service, requestCode, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        } else {
            PendingIntent.getService(
                service, requestCode, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }
    }

    /**
     * Called once per service lifecycle to enter foreground.
     * Android 11 / MIUI 12: startForeground() must be called within 5s of service start.
     * Posts immediately without artwork (fast path), then loads artwork async.
     */
    fun ensureMediaForeground() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (isForeground) return
        ensureChannel()
        val track = getCurrentTrack()
        val notification = buildNotification(getSession(), track, getIsPlaying(), bitmap = null)
        startForegroundWith(notification)
        // Load artwork async and refresh after
        refreshAsync()
    }

    /**
     * Updates the notification with the latest playback state.
     * Posts immediately with cached artwork (if available), then loads async if needed.
     */
    fun refresh() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val sess = getSession() ?: return
        ensureChannel()
        val track     = getCurrentTrack()
        val isPlaying = getIsPlaying()
        val artUri    = track?.get("artworkUri") as? String
        val songId    = (track?.get("id") as? Number)?.toInt() ?: 0

        // Combined cache key: prefer artUri; fall back to song-id key for embedded-only tracks.
        val cacheKey  = artUri ?: if (songId > 0) "song:$songId" else null

        // Post immediately with cached artwork (null if not yet loaded)
        val cached    = cacheKey?.let { bitmapCache.get(it) }
        val hasCached = cacheKey == null
                || bitmapCache.get(cacheKey) != null
                || isInNoArtworkCache(cacheKey)
        postNotification(buildNotification(sess, track, isPlaying, cached))

        // If not cached yet, load async and update
        if (!hasCached && cacheKey != null) {
            refreshAsync(artUri, songId, track, isPlaying)
        }
    }

    fun stopForeground() {
        service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
        isForeground = false
        notificationManager.cancel(NOTIFICATION_ID)
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    /**
     * Pre-loads artwork for the next track into [bitmapCache] during Phase 1 prewarm
     * (~1500 ms before crossfade starts), so [refresh] at Phase 2 finds a cache hit
     * and posts the notification synchronously with artwork — no blank-artwork window.
     *
     * RC-3 fix: previously the 1500 ms prewarm window only warmed the audio pipeline;
     * [artworkExecutor] was idle the whole time.  This call starts the artwork load
     * during that idle window so it's ready (or nearly ready) by the time
     * [beginCrossfade] triggers [refresh].
     *
     * Callers: [CrossfadeController.maybeCrossfadeOut] Phase 1 block.
     */
    fun prewarmArtwork(nextSongId: Int, nextArtUri: String?) {
        val cacheKey = nextArtUri ?: if (nextSongId > 0) "song:$nextSongId" else null
        if (cacheKey == null) return
        // Already in bitmapCache or confirmed no-artwork — nothing to do
        if (bitmapCache.get(cacheKey) != null || isInNoArtworkCache(cacheKey)) return
        // Same key already loading — don't double-enqueue
        if (cacheKey == pendingAsyncCacheKey) return

        pendingAsyncCacheKey = cacheKey
        val generation = ++artworkLoadGeneration
        artworkExecutor.execute {
            val bmp = loadBitmap(nextArtUri, nextSongId)
            handler.post {
                pendingAsyncCacheKey = null
                if (generation != artworkLoadGeneration) return@post
                // Populate cache only — do NOT post a notification here.
                // The refresh() that fires at crossfade start will find the hit and post.
                if (bmp != null) bitmapCache.put(cacheKey, bmp)
                else markNoArtwork(cacheKey)
                NativeLogger.emit("debug", "Notification",
                    "prewarmArtwork done: cacheKey=$cacheKey bmp=${bmp != null}")
            }
        }
    }

    private fun refreshAsync(
        artUri: String?       = getCurrentTrack()?.get("artworkUri") as? String,
        songId: Int           = (getCurrentTrack()?.get("id") as? Number)?.toInt() ?: 0,
        track: Map<String, Any?>? = getCurrentTrack(),
        isPlaying: Boolean    = getIsPlaying(),
    ) {
        val cacheKey = artUri ?: if (songId > 0) "song:$songId" else null
        if (cacheKey == null) return

        // Patch A (RC-2 fix): if the same cacheKey is already loading, skip enqueue.
        // This collapses the 3 back-to-back refreshAsync() calls that happen within ~1 ms
        // at crossfade start (onIsPlayingChanged + onPlaybackStateChanged + refreshNotification)
        // into a single loadBitmap() call, reducing worst-case artwork latency by ~3×.
        if (cacheKey == pendingAsyncCacheKey) return
        pendingAsyncCacheKey = cacheKey

        val generation = ++artworkLoadGeneration
        artworkExecutor.execute {
            val bmp = loadBitmap(artUri, songId)
            handler.post {
                pendingAsyncCacheKey = null  // reset: this key's load is complete
                if (generation != artworkLoadGeneration) return@post  // superseded
                if (bmp != null) bitmapCache.put(cacheKey, bmp) else markNoArtwork(cacheKey)
                val sess = getSession() ?: return@post
                try {
                    postNotification(buildNotification(sess, getCurrentTrack(), getIsPlaying(), bmp))
                } catch (e: Exception) {
                    NativeLogger.emit("warn", "Notification", "async refresh failed: ${e.message}")
                }
            }
        }
    }

    private fun postNotification(notification: android.app.Notification) {
        try {
            if (!isForeground) {
                startForegroundWith(notification)
            } else {
                notificationManager.notify(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            NativeLogger.emit("warn", "Notification", "postNotification failed: ${e.message}")
        }
    }

    private fun startForegroundWith(notification: android.app.Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            service.startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            service.startForeground(NOTIFICATION_ID, notification)
        }
        isForeground = true
    }

    /**
     * NS-01 fix: single canonical notification builder used by both ensureMediaForeground
     * and refresh, eliminating the previous subtle differences between the two.
     */
    private fun buildNotification(
        session: MediaSession?,
        track: Map<String, Any?>?,
        isPlaying: Boolean,
        bitmap: Bitmap?,
    ): android.app.Notification {
        val title  = track?.get("title")  as? String ?: "Music Player"
        val artist = track?.get("artist") as? String ?: ""

        val builder = NotificationCompat.Builder(service, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(artist)
            .setOngoing(isPlaying)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        launchPendingIntent?.let { builder.setContentIntent(it) }
        bitmap?.let { builder.setLargeIcon(it) }

        if (session != null) {
            builder
                .addAction(NotificationCompat.Action(R.drawable.ic_prev, "Previous",
                    buildTransportPendingIntent(ACTION_SKIP_PREV, 1)))
                .addAction(NotificationCompat.Action(
                    if (isPlaying) R.drawable.ic_pause else R.drawable.ic_play,
                    if (isPlaying) "Pause" else "Play",
                    buildTransportPendingIntent(ACTION_PLAY_PAUSE, 2)))
                .addAction(NotificationCompat.Action(R.drawable.ic_next, "Next",
                    buildTransportPendingIntent(ACTION_SKIP_NEXT, 3)))
                .addAction(NotificationCompat.Action(R.drawable.ic_stop, "Stop",
                    buildTransportPendingIntent(ACTION_STOP, 4)))
                .setStyle(
                    MediaStyleNotificationHelper.MediaStyle(session)
                        .setShowActionsInCompactView(0, 1, 2)
                )
        }
        return builder.build()
    }

    /**
     * ART-01: Two-stage artwork loading pipeline — mirrors the Full Player's artwork strategy.
     *
     * Stage 1 — ContentResolver (fast path):
     *   Opens the MediaStore album-art URI directly via ContentResolver with a two-pass
     *   BitmapFactory decode (bounds first, then scaled to NOTIF_ART_PX). Works for songs
     *   whose artwork MediaStore has already indexed.
     *
     * Stage 2 — ArtworkCacheManager (fallback):
     *   Delegates to the same ArtworkCacheManager used by the Full Player.
     *   It first checks a persistent WebP disk cache ({filesDir}/artwork/{songId}.webp),
     *   then extracts embedded artwork via MediaMetadataRetriever as a last resort.
     *   This covers songs in non-standard directories and cold-start scenarios where
     *   MediaStore hasn't indexed artwork yet.
     *
     * Returns null only after both stages have been exhausted.
     */
    private fun loadBitmap(artUri: String?, songId: Int): Bitmap? {
        // Stage 1: ContentResolver
        val fromUri = tryUri(artUri)
        if (fromUri != null) return fromUri

        // Stage 2: ArtworkCacheManager — same pipeline as Full Player / Mini Player
        if (artworkCacheManager != null && songId > 0) {
            try {
                val path = artworkCacheManager.getOrExtract(songId)
                if (path != null) {
                    val bmp = BitmapFactory.decodeFile(path)
                    if (bmp != null) {
                        NativeLogger.emit("debug", "Notification",
                            "artwork loaded via cache fallback for songId=$songId")
                        return bmp
                    }
                }
            } catch (e: Exception) {
                NativeLogger.emit("warn", "Notification",
                    "ArtworkCacheManager fallback failed for songId=$songId: ${e.message}")
            }
        }

        return null
    }

    /**
     * Stage 1 of loadBitmap: tries the MediaStore album-art URI via ContentResolver.
     *
     * Two-pass decode: first read bounds only (no pixel allocation), compute
     * the power-of-two inSampleSize that fits within NOTIF_ART_PX, then decode
     * at the reduced size.
     *
     * Before: large album art (3000×3000 JPEG) → ~34 MB Bitmap for a 128dp slot.
     * After:  same art decoded at 512×512 → ~1 MB Bitmap.
     */
    private fun tryUri(artUri: String?): Bitmap? {
        if (artUri.isNullOrBlank()) return null
        return try {
            val uri = Uri.parse(artUri)
            // Skip known-invalid album art URIs (negative / zero album IDs)
            if (uri.toString().contains("/albumart/-") || uri.toString().endsWith("/0")) return null

            // Pass 1: bounds only (no pixel allocation)
            val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            service.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, boundsOpts)
            }
            // URI content was not a decodable image (e.g. MediaStore not yet indexed)
            if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) return null

            // Pass 2: scaled decode
            val sample = computeSampleSize(boundsOpts.outWidth, boundsOpts.outHeight, NOTIF_ART_PX)
            val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
            service.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, decodeOpts)
            }
        } catch (_: Exception) { null }
    }

    // ── noArtwork TTL helpers ─────────────────────────────────────────────────

    /**
     * ART-02: Returns true if [key] is in the no-artwork cache AND the entry hasn't
     * expired yet. Expired entries are removed so the next lookup triggers a fresh attempt.
     *
     * All accesses are on the main/Handler thread (refreshAsync posts back via handler.post),
     * so no additional synchronization is needed.
     */
    private fun isInNoArtworkCache(key: String): Boolean {
        val ts = noArtworkTimestamps[key] ?: return false
        if (SystemClock.elapsedRealtime() - ts > NO_ARTWORK_TTL_MS) {
            noArtworkTimestamps.remove(key)
            return false
        }
        return true
    }

    /**
     * Records [key] as confirmed-no-artwork with the current elapsed-realtime timestamp.
     * Evicts the oldest entry when the map reaches 64 entries to keep memory bounded.
     */
    private fun markNoArtwork(key: String) {
        if (noArtworkTimestamps.size >= 64) {
            // Remove one arbitrary entry (oldest in insertion order via LinkedHashMap would be
            // ideal, but HashMap.keys.first() is O(bucket scan) and acceptable at 64 entries).
            noArtworkTimestamps.keys.firstOrNull()?.let { noArtworkTimestamps.remove(it) }
        }
        noArtworkTimestamps[key] = SystemClock.elapsedRealtime()
    }

    /** Smallest power-of-two sample size so that neither dimension exceeds [maxPx]. */
    private fun computeSampleSize(w: Int, h: Int, maxPx: Int): Int {
        var s = 1
        while ((w / s) > maxPx || (h / s) > maxPx) s *= 2
        return s
    }

    companion object {
        const val CHANNEL_ID        = "media3_playback"
        const val NOTIFICATION_ID   = 1001
        const val ACTION_PLAY_PAUSE = "dev.wndavenz.music.ACTION_PLAY_PAUSE"
        const val ACTION_SKIP_NEXT  = "dev.wndavenz.music.ACTION_SKIP_NEXT"
        const val ACTION_SKIP_PREV  = "dev.wndavenz.music.ACTION_SKIP_PREV"
        const val ACTION_STOP       = "dev.wndavenz.music.ACTION_STOP"

        /** Target long edge for notification artwork in pixels. 512 px is crisp at 3× density. */
        private const val NOTIF_ART_PX = 512

        /**
         * ART-02: TTL for the no-artwork cache. Entries older than this are retried.
         * 30 seconds covers typical MediaStore indexing delays on cold start while
         * still preventing tight retry loops during a playback session.
         */
        private const val NO_ARTWORK_TTL_MS = 30_000L
    }
}
