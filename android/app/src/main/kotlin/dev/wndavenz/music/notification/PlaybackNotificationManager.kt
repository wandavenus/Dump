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
import android.graphics.Color
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
import dev.wndavenz.music.BitmapUtils
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
    /**
     * Latest load generation per cache key. Generation is scoped per key so a
     * prewarm of the NEXT track cannot discard the CURRENT track's in-flight
     * async result — the crossfade prewarm and the transition-time prewarm run
     * back to back with different keys. Entries are removed when a load finishes;
     * all access happens on the main thread.
     */
    private val artworkLoadGenerations = HashMap<String, Long>()
    /**
     * Cache keys with an in-flight async load (prewarm or refresh). Unlike the
     * old single `pendingAsyncCacheKey` slot, one entry per key means a finished
     * request for key A can never clear the in-flight marker of key B, so the
     * same key can never be loaded twice concurrently.
     */
    private val inFlightLoads = HashSet<String>()
    /** Set by [close]; rejects new async work after service teardown. */
    @Volatile
    private var closed = false
    /**
     * K3 fix: while suppressed (file-manager preview mode), the manager never
     * CREATES a foreground notification. Updates to an already-showing
     * notification are still allowed, so a preview that overrides active
     * playback does not leave a stale track on screen.
     */
    @Volatile
    private var suppressed = false

    /**
     * K3 fix: enable/disable notification suppression. The service wires this
     * to preview mode (IS_OVERLAY_PREVIEW) and clears it as soon as the
     * Flutter app starts driving playback through the MethodChannel.
     */
    fun setSuppressed(value: Boolean) {
        suppressed = value
    }
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
        // K3 fix: never start a foreground notification while suppressed.
        if (suppressed) return
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
        val artUri = track?.get("artworkUri") as? String
        val songId = (track?.get("id") as? Number)?.toInt() ?: 0
        // K10: pass the current track's DATA path so the persistent cache can
        // validate its entry against the file identity (MediaStore _ID reuse).
        refreshAsync(artUri, songId, track?.get("path") as? String)
    }

    fun refresh() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        // K3 fix: never start a foreground notification while suppressed; an
        // already-showing notification keeps updating.
        if (suppressed && !isForeground) return
        val sess = getSession() ?: return
        ensureChannel()

        val track = getCurrentTrack()
        val isPlaying = getIsPlaying()

        // Always render our own normalized (square letterboxed) bitmap via
        // setLargeIcon. An explicit
        // largeIcon overrides MediaStyleNotificationHelper's auto-rendered session
        // artwork, which would otherwise decode the low-res MediaStore album-art
        // thumbnail (≤512 px, non-square) → SystemUI center-crop = zoom + pixelation.
        val artUri = track?.get("artworkUri") as? String
        val songId = (track?.get("id") as? Number)?.toInt() ?: 0
        val cacheKey = artUri ?: if (songId > 0) "song:$songId" else null
        val cached = cacheKey?.let { bitmapCache.get(it) }
        val hasCached = cacheKey == null || cached != null || isInNoArtworkCache(cacheKey)
        postNotification(buildNotification(sess, track, isPlaying, cached))

        if (!hasCached) {
            // K10: pass the current track's DATA path (see ensureMediaForeground).
            refreshAsync(artUri, songId, track?.get("path") as? String)
        }
    }

    fun stopForeground() {
        service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
        isForeground = false
        notificationManager.cancel(NOTIFICATION_ID)
    }

    fun prewarmArtwork(nextSongId: Int, nextArtUri: String?) {
        if (closed) return
        val cacheKey = nextArtUri ?: if (nextSongId > 0) "song:$nextSongId" else null
        if (cacheKey == null) return
        if (bitmapCache.get(cacheKey) != null || isInNoArtworkCache(cacheKey)) return
        if (!inFlightLoads.add(cacheKey)) return

        val generation = (artworkLoadGenerations[cacheKey] ?: 0L) + 1L
        artworkLoadGenerations[cacheKey] = generation
        artworkExecutor.execute {
            val bmp = loadBitmap(nextArtUri, nextSongId)?.let { BitmapUtils.normalizeSquare(it, NOTIF_ART_PX) }
            handler.post {
                inFlightLoads.remove(cacheKey)
                if (closed || generation != artworkLoadGenerations[cacheKey]) return@post
                artworkLoadGenerations.remove(cacheKey)
                if (bmp != null) bitmapCache.put(cacheKey, bmp) else markNoArtwork(cacheKey)
                NativeLogger.emit("debug", "Notification", "prewarmArtwork done: cacheKey=$cacheKey bmp=${bmp != null}")
                // If the prewarmed track became the current track while loading
                // (e.g. user hit next), refresh() saw our in-flight key and
                // skipped its own async load — repost so the artwork appears
                // immediately instead of waiting for the next refresh cycle.
                if (cacheKey == currentTrackCacheKey()) {
                    val sess = getSession() ?: return@post
                    postNotification(buildNotification(sess, getCurrentTrack(), getIsPlaying(), bmp))
                }
            }
        }
    }

    /** Cache key of the current track (artworkUri, else "song:$id"). */
    private fun currentTrackCacheKey(): String? {
        val track = getCurrentTrack()
        (track?.get("artworkUri") as? String)?.let { return it }
        val id = (track?.get("id") as? Number)?.toInt() ?: 0
        return if (id > 0) "song:$id" else null
    }

    private fun refreshAsync(artUri: String?, songId: Int, filePath: String? = null) {
        if (closed) return
        val cacheKey = artUri ?: if (songId > 0) "song:$songId" else null
        if (cacheKey == null) return
        if (!inFlightLoads.add(cacheKey)) return

        val generation = (artworkLoadGenerations[cacheKey] ?: 0L) + 1L
        artworkLoadGenerations[cacheKey] = generation
        artworkExecutor.execute {
            val bmp = loadBitmap(artUri, songId, filePath)?.let { BitmapUtils.normalizeSquare(it, NOTIF_ART_PX) }
            handler.post {
                inFlightLoads.remove(cacheKey)
                if (closed || generation != artworkLoadGenerations[cacheKey]) return@post
                artworkLoadGenerations.remove(cacheKey)
                if (bmp != null) bitmapCache.put(cacheKey, bmp) else markNoArtwork(cacheKey)
                val sess = getSession() ?: return@post
                // Never post a stale result: a load for a track the user already
                // skipped away from must not overwrite the current notification
                // with old title/artist/art (rapid-skip flicker). The bitmap was
                // cached above under its own key, so the next play of this track
                // still gets an instant cache hit — and prewarmArtwork() handles
                // the "became current while loading" repost case.
                if (cacheKey != currentTrackCacheKey()) return@post
                try {
                    postNotification(buildNotification(sess, getCurrentTrack(), getIsPlaying(), bmp))
                } catch (e: Exception) {
                    NativeLogger.emit("warn", "Notification", "async refresh failed: ${e.message}")
                }
            }
        }
    }

    /**
     * Shuts down the artwork executor and rejects new loads. Idempotent; safe
     * to call from the service's onDestroy during teardown.
     */
    fun close() {
        closed = true
        artworkExecutor.shutdown()
    }

    private fun postNotification(notification: android.app.Notification) {
        // K3 fix: belt-and-suspenders for async refresh()/prewarm completions
        // that resolve after suppression was enabled — never create a
        // foreground from an async callback either.
        if (suppressed && !isForeground) return
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

    private fun loadBitmap(artUri: String?, songId: Int, filePath: String? = null): Bitmap? {
        // 1) Full-resolution embedded artwork decoded straight from the file.
        if (songId > 0) {
            val original = loadOriginalEmbeddedBitmap(songId)
            if (original != null) return original
        } else {
            // A1 fix: external files (overlay / ACTION_PLAY_URI) have songId = 0
            // but carry the audio URI in artUri — read the embedded picture from
            // that URI so the notification gets artwork for them too.
            val original = loadOriginalEmbeddedFromUri(artUri)
            if (original != null) return original
        }

        // 2) App's persistent artwork cache (extracted embedded art, ≤1000 px).
        //    Higher quality than the MediaStore album-art thumbnail, so prefer
        //    it over the URI below.
        // K10: [filePath] lets the cache validate its entry against the source
        // file's current size+mtime (stale entry → re-extract instead of showing
        // the previous song's art after a MediaStore _ID reuse).
        if (artworkCacheManager != null && songId > 0) {
            try {
                val path = artworkCacheManager.getOrExtract(songId, filePath)
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
            BitmapUtils.decodeCapped(raw, NOTIF_ART_PX)
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

    /**
     * A1 fix: reads the embedded picture from an arbitrary audio URI
     * (content:// or file://) for files that have no MediaStore song ID.
     */
    private fun loadOriginalEmbeddedFromUri(artUri: String?): Bitmap? {
        if (artUri.isNullOrBlank()) return null
        val mmr = MediaMetadataRetriever()
        return try {
            mmr.setDataSource(service, Uri.parse(artUri))
            val raw = mmr.embeddedPicture ?: return null
            BitmapUtils.decodeCapped(raw, NOTIF_ART_PX)
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

            val sample = BitmapUtils.computeSampleSize(boundsOpts.outWidth, boundsOpts.outHeight, NOTIF_ART_PX)
            val decodeOpts = BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            service.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, decodeOpts)
            }
        } catch (_: Exception) {
            null
        }
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
