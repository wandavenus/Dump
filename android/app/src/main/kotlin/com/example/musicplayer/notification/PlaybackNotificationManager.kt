package com.example.musicplayer.notification

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import android.net.Uri
import android.os.Build
import android.os.Handler
import androidx.core.app.NotificationCompat
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.MediaStyleNotificationHelper
import com.example.musicplayer.Media3PlaybackService
import com.example.musicplayer.R
import com.example.musicplayer.events.NativeLogger
import java.util.concurrent.Executors

/**
 * Manages the media playback notification.
 *
 * Fixes applied:
 * NS-01: Unified notification building — single buildNotification() shared by both
 *        ensureMediaForeground() and refresh(), eliminating subtle inconsistencies.
 * NS-03: Artwork bitmap loading is moved to a background thread; notifications post
 *        first without artwork, then update once the bitmap is ready. A generation
 *        counter prevents stale async results from overwriting a newer notification.
 * NS-04: launchPendingIntent is cached as a lazy val — no rebuild on every refresh.
 */
@UnstableApi
class PlaybackNotificationManager(
    private val service: MediaSessionService,
    private val handler: Handler,
    private val getSession: () -> MediaSession?,
    private val getPlayer: () -> ExoPlayer?,
    private val getCurrentTrack: () -> Map<String, Any?>?,
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
    // LruCache does not accept null values, so we track "tried but no artwork" URIs separately.
    // LOW-02 fix: noArtworkUris is now a bounded LinkedHashSet (max 64 entries) that evicts
    // the oldest entry when full, preventing unbounded growth during long listening sessions.
    private val artworkCache  = LruCache<String, Bitmap>(10)
    private val noArtworkUris: MutableSet<String> = object : java.util.LinkedHashSet<String>(64) {
        override fun add(element: String): Boolean {
            if (size >= 64) remove(iterator().next())
            return super.add(element)
        }
    }
    private var artworkLoadGeneration = 0L

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
        val intent = Intent(service, Media3PlaybackService::class.java).setAction(action)
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
        val p = getPlayer() ?: return
        ensureChannel()
        val track = getCurrentTrack()
        val notification = buildNotification(getSession(), track, p.isPlaying, bitmap = null)
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
        val p    = getPlayer()   ?: return
        ensureChannel()
        val track     = getCurrentTrack()
        val isPlaying = p.isPlaying
        val artUri    = track?.get("artworkUri") as? String

        // Post immediately with cached artwork (null if not yet loaded)
        val cached   = artUri?.let { artworkCache.get(it) }
        val hasCached = artUri == null || artworkCache.get(artUri) != null || artUri in noArtworkUris
        postNotification(buildNotification(sess, track, isPlaying, cached))

        // If not cached yet, load async and update
        if (!hasCached && artUri != null) {
            refreshAsync(artUri, track, isPlaying)
        }
    }

    fun stopForeground() {
        service.stopForeground(MediaSessionService.STOP_FOREGROUND_REMOVE)
        isForeground = false
        notificationManager.cancel(NOTIFICATION_ID)
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private fun refreshAsync(
        artUri: String? = getCurrentTrack()?.get("artworkUri") as? String,
        track: Map<String, Any?>? = getCurrentTrack(),
        isPlaying: Boolean = getPlayer()?.isPlaying ?: false,
    ) {
        if (artUri == null) return
        val generation = ++artworkLoadGeneration
        artworkExecutor.execute {
            val bmp = loadBitmap(artUri)
            handler.post {
                if (generation != artworkLoadGeneration) return@post  // superseded
                if (bmp != null) artworkCache.put(artUri, bmp) else noArtworkUris.add(artUri)
                val sess = getSession() ?: return@post
                val p2   = getPlayer()   ?: return@post
                try {
                    postNotification(buildNotification(sess, getCurrentTrack(), p2.isPlaying, bmp))
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
     * Loads and scales album artwork for use in the notification.
     *
     * Two-pass decode: first read bounds only (no pixel allocation), compute
     * the power-of-two inSampleSize that fits within NOTIF_ART_PX, then decode
     * at the reduced size. Content URIs (MediaStore) can be opened twice — each
     * openInputStream call returns an independent stream.
     *
     * Before: large album art (3000×3000 JPEG) → ~34 MB Bitmap for a 128dp slot.
     * After:  same art decoded at 512×512 → ~1 MB Bitmap.
     */
    private fun loadBitmap(artUri: String?): Bitmap? {
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

            // Pass 2: scaled decode
            val sample = computeSampleSize(boundsOpts.outWidth, boundsOpts.outHeight, NOTIF_ART_PX)
            val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
            service.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, decodeOpts)
            }
        } catch (_: Exception) { null }
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
        const val ACTION_PLAY_PAUSE = "com.example.musicplayer.ACTION_PLAY_PAUSE"
        const val ACTION_SKIP_NEXT  = "com.example.musicplayer.ACTION_SKIP_NEXT"
        const val ACTION_SKIP_PREV  = "com.example.musicplayer.ACTION_SKIP_PREV"
        const val ACTION_STOP       = "com.example.musicplayer.ACTION_STOP"

        /** Target long edge for notification artwork in pixels. 512 px is crisp at 3× density. */
        private const val NOTIF_ART_PX = 512
    }
}
