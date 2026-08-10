package dev.wndavenz.music.notification

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.SystemClock
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaStyleNotificationHelper
import dev.wndavenz.music.ArtworkCacheManager
import dev.wndavenz.music.Media3PlaybackService
import dev.wndavenz.music.R
import dev.wndavenz.music.events.NativeLogger
import java.util.concurrent.Executors

@UnstableApi
class PlaybackNotificationManager(
    private val service: Service,
    private val handler: Handler,
    private val getSession: () -> MediaSession?,
    private val getIsPlaying: () -> Boolean,
    private val getCurrentTrack: () -> Map<String, Any?>?,
    private val serviceClass: Class<*> = Media3PlaybackService::class.java,
    private val artworkCacheManager: ArtworkCacheManager? = null,
) {
    var isForeground = false
        private set

    private val notificationManager: NotificationManager by lazy {
        service.getSystemService(NotificationManager::class.java)
    }

    private val launchPendingIntent: PendingIntent? by lazy {
        service.packageManager.getLaunchIntentForPackage(service.packageName)?.let { intent ->
            PendingIntent.getActivity(
                service,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
    }

    private val bitmapCache = android.util.LruCache<String, Bitmap>(10)
    private val noArtworkTimestamps = HashMap<String, Long>(64)
    private var artworkLoadGeneration = 0L
    private var pendingAsyncCacheKey: String? = null
    private val artworkExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "artwork-loader").also { it.isDaemon = true }
    }

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (notificationManager.getNotificationChannel(CHANNEL_ID) != null) return
        notificationManager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Music Playback", NotificationManager.IMPORTANCE_LOW).apply {
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            },
        )
    }

    fun buildTransportPendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(service, serviceClass).setAction(action)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(
                service,
                requestCode,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        } else {
            PendingIntent.getService(
                service,
                requestCode,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
    }

    fun ensureMediaForeground() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (isForeground) return
        ensureChannel()

        val session = getSession()
        val track = getCurrentTrack()
        val notification = buildNotification(
            session = session,
            track = track,
            isPlaying = getIsPlaying(),
            bitmap = null,
        )
        startForegroundWith(notification)
        refreshAsync()
    }

    fun refresh() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val sess = getSession() ?: return
        ensureChannel()

        val track = getCurrentTrack()
        val isPlaying = getIsPlaying()

        // Always render our own normalized bitmap via setLargeIcon. An explicit
        // largeIcon overrides MediaStyleNotificationHelper's auto-rendered session
        // artwork, which would otherwise decode the low-res MediaStore album-art
        // thumbnail (≤512 px, non-square) → SystemUI center-crop = zoom + pixelation.
        val artUri = track?.get("artworkUri") as? String
        val songId = (track?.get("id") as? Number)?.toInt() ?: 0
        val cacheKey = artUri ?: if (songId > 0) "song:$songId" else null
        val cached = cacheKey?.let { bitmapCache.get(it) }
        val hasCached = cacheKey == null || bitmapCache.get(cacheKey) != null || isInNoArtworkCache(cacheKey)
        postNotification(buildNotification(sess, track, isPlaying, cached))

        if (!hasCached && cacheKey != null) {
            refreshAsync(artUri, songId, track, isPlaying)
        }
    }

    fun stopForeground() {
        service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
        isForeground = false
        notificationManager.cancel(NOTIFICATION_ID)
    }

    fun prewarmArtwork(nextSongId: Int, nextArtUri: String?) {
        val cacheKey = nextArtUri ?: if (nextSongId > 0) "song:$nextSongId" else null
        if (cacheKey == null) return
        if (bitmapCache.get(cacheKey) != null || isInNoArtworkCache(cacheKey)) return
        if (cacheKey == pendingAsyncCacheKey) return

        pendingAsyncCacheKey = cacheKey
        val generation = ++artworkLoadGeneration
        artworkExecutor.execute {
            val bmp = loadBitmap(nextArtUri, nextSongId)?.let(::normalizeNotificationArtwork)
            handler.post {
                pendingAsyncCacheKey = null
                if (generation != artworkLoadGeneration) return@post
                if (bmp != null) bitmapCache.put(cacheKey, bmp) else markNoArtwork(cacheKey)
                NativeLogger.emit("debug", "Notification", "prewarmArtwork done: cacheKey=$cacheKey bmp=${bmp != null}")
            }
        }
    }

    private fun refreshAsync(
        artUri: String? = getCurrentTrack()?.get("artworkUri") as? String,
        songId: Int = (getCurrentTrack()?.get("id") as? Number)?.toInt() ?: 0,
        track: Map<String, Any?>? = getCurrentTrack(),
        isPlaying: Boolean = getIsPlaying(),
    ) {
        val cacheKey = artUri ?: if (songId > 0) "song:$songId" else null
        if (cacheKey == null) return
        if (cacheKey == pendingAsyncCacheKey) return
        pendingAsyncCacheKey = cacheKey

        val generation = ++artworkLoadGeneration
        artworkExecutor.execute {
            val bmp = loadBitmap(artUri, songId)?.let(::normalizeNotificationArtwork)
            handler.post {
                pendingAsyncCacheKey = null
                if (generation != artworkLoadGeneration) return@post
                if (bmp != null) bitmapCache.put(cacheKey, bmp) else markNoArtwork(cacheKey)
                val sess = getSession() ?: return@post
                try {
                    postNotification(buildNotification(sess, track, isPlaying, bmp))
                } catch (e: Exception) {
                    NativeLogger.emit("warn", "Notification", "async refresh failed: ${e.message}")
                }
            }
        }
    }

    private fun postNotification(notification: android.app.Notification) {
        try {
            if (!isForeground) startForegroundWith(notification) else notificationManager.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            NativeLogger.emit("warn", "Notification", "postNotification failed: ${e.message}")
        }
    }

    private fun startForegroundWith(notification: android.app.Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            service.startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            service.startForeground(NOTIFICATION_ID, notification)
        }
        isForeground = true
    }

    private fun buildNotification(
        session: MediaSession?,
        track: Map<String, Any?>?,
        isPlaying: Boolean,
        bitmap: Bitmap?,
    ): android.app.Notification {
        val title = track?.get("title") as? String ?: "Music Player"
        val artist = track?.get("artist") as? String ?: ""

        val builder = NotificationCompat.Builder(service, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_overlay_music_note)
            .setColor(notificationIconColor())
            .setContentTitle(title)
            .setContentText(artist)
            .setOngoing(isPlaying)
            .setAutoCancel(!isPlaying)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        }

        launchPendingIntent?.let { builder.setContentIntent(it) }
        bitmap?.let { builder.setLargeIcon(it) }

        if (session != null) {
            builder
                .addAction(NotificationCompat.Action(R.drawable.ic_prev, "Previous", buildTransportPendingIntent(ACTION_SKIP_PREV, 1)))
                .addAction(NotificationCompat.Action(if (isPlaying) R.drawable.ic_pause else R.drawable.ic_play, if (isPlaying) "Pause" else "Play", buildTransportPendingIntent(ACTION_PLAY_PAUSE, 2)))
                .addAction(NotificationCompat.Action(R.drawable.ic_next, "Next", buildTransportPendingIntent(ACTION_SKIP_NEXT, 3)))
                .addAction(NotificationCompat.Action(R.drawable.ic_stop, "Stop", buildTransportPendingIntent(ACTION_STOP, 4)))
                .setStyle(MediaStyleNotificationHelper.MediaStyle(session).setShowActionsInCompactView(0, 1, 2))
        }
        return builder.build()
    }

    private fun notificationIconColor(): Int {
        val nightMode = service.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return if (nightMode == Configuration.UI_MODE_NIGHT_YES) Color.WHITE else Color.BLACK
    }

    private fun loadBitmap(artUri: String?, songId: Int): Bitmap? {
        // 1) Full-resolution embedded artwork decoded straight from the file.
        if (songId > 0) {
            val original = loadOriginalEmbeddedBitmap(songId)
            if (original != null) return original
        }

        // 2) App's persistent artwork cache (extracted embedded art, ≤1000 px).
        //    Higher quality than the MediaStore album-art thumbnail, so prefer
        //    it over the URI below.
        if (artworkCacheManager != null && songId > 0) {
            try {
                val path = artworkCacheManager.getOrExtract(songId)
                if (path != null) {
                    val bmp = BitmapFactory.decodeFile(path)
                    if (bmp != null) {
                        NativeLogger.emit("debug", "Notification", "artwork loaded via cache for songId=$songId")
                        return bmp
                    }
                }
            } catch (e: Exception) {
                NativeLogger.emit("warn", "Notification", "ArtworkCacheManager fallback failed for songId=$songId: ${e.message}")
            }
        }

        // 3) MediaStore album-art thumbnail URI — lowest resolution, last resort.
        return tryUri(artUri)
    }

    private fun loadOriginalEmbeddedBitmap(songId: Int): Bitmap? {
        val mmr = MediaMetadataRetriever()
        return try {
            val uri = Uri.withAppendedPath(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString())
            mmr.setDataSource(service, uri)
            val raw = mmr.embeddedPicture ?: return null
            decodeCapped(raw, NOTIF_ART_PX)
        } catch (_: Exception) {
            null
        } finally {
            try {
                mmr.release()
            } catch (_: Exception) {
                // ignore
            }
        }
    }

    private fun tryUri(artUri: String?): Bitmap? {
        if (artUri.isNullOrBlank()) return null
        return try {
            val uri = Uri.parse(artUri)
            if (uri.toString().contains("/albumart/-") || uri.toString().endsWith("/0")) return null

            val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            service.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, boundsOpts)
            }
            if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) return null

            val sample = computeSampleSize(boundsOpts.outWidth, boundsOpts.outHeight, NOTIF_ART_PX)
            val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
            service.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, decodeOpts)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun decodeCapped(bytes: ByteArray, maxPx: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val sample = computeSampleSize(bounds.outWidth, bounds.outHeight, maxPx)
        return BitmapFactory.decodeByteArray(
            bytes,
            0,
            bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sample },
        )
    }

    private fun normalizeNotificationArtwork(source: Bitmap): Bitmap {
        if (source.width <= 0 || source.height <= 0) return source
        if (source.width == NOTIF_ART_PX && source.height == NOTIF_ART_PX && source.config == Bitmap.Config.ARGB_8888) {
            return source
        }

        val out = Bitmap.createBitmap(NOTIF_ART_PX, NOTIF_ART_PX, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.BLACK)

        val scale = minOf(
            NOTIF_ART_PX.toFloat() / source.width.toFloat(),
            NOTIF_ART_PX.toFloat() / source.height.toFloat(),
        )
        val drawnW = source.width * scale
        val drawnH = source.height * scale
        val left = (NOTIF_ART_PX - drawnW) / 2f
        val top = (NOTIF_ART_PX - drawnH) / 2f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG)
        canvas.drawBitmap(source, null, RectF(left, top, left + drawnW, top + drawnH), paint)
        return out
    }

    private fun isInNoArtworkCache(key: String): Boolean {
        val ts = noArtworkTimestamps[key] ?: return false
        if (SystemClock.elapsedRealtime() - ts > NO_ARTWORK_TTL_MS) {
            noArtworkTimestamps.remove(key)
            return false
        }
        return true
    }

    private fun markNoArtwork(key: String) {
        if (noArtworkTimestamps.size >= 64) {
            noArtworkTimestamps.keys.firstOrNull()?.let { noArtworkTimestamps.remove(it) }
        }
        noArtworkTimestamps[key] = SystemClock.elapsedRealtime()
    }

    private fun computeSampleSize(w: Int, h: Int, maxPx: Int): Int {
        var s = 1
        while ((w / s) > maxPx || (h / s) > maxPx) s *= 2
        return s
    }

    companion object {
        const val CHANNEL_ID = "media3_playback_silent_v3"
        const val NOTIFICATION_ID = 1001
        const val ACTION_PLAY_PAUSE = "dev.wndavenz.music.ACTION_PLAY_PAUSE"
        const val ACTION_SKIP_NEXT = "dev.wndavenz.music.ACTION_SKIP_NEXT"
        const val ACTION_SKIP_PREV = "dev.wndavenz.music.ACTION_SKIP_PREV"
        const val ACTION_STOP = "dev.wndavenz.music.ACTION_STOP"
        private const val NOTIF_ART_PX = 1024
        private const val NO_ARTWORK_TTL_MS = 30_000L
    }
}
