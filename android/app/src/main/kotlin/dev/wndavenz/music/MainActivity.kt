package dev.wndavenz.music

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import androidx.media3.common.util.UnstableApi
import dev.wndavenz.music.events.ServiceReadyGate
import dev.wndavenz.music.metadata.ExoMetadataReader
import dev.wndavenz.music.metadata.MetadataCacheDb
import dev.wndavenz.music.metadata.MetadataPrescanner
import dev.wndavenz.music.replaygain.ReplayGainBridge
import dev.wndavenz.music.replaygain.MediaStoreWriteGate
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {

    private val mediaStoreChannel     = "musicplayer/media_store"
    private val audioEffectsChannel   = "musicplayer/audio_effects"
    private val media3PlaybackChannel = "musicplayer/media3_playback"
    private val ffmpegDecoderChannel  = "musicplayer/ffmpeg_decoder"

    private lateinit var artworkCacheManager: ArtworkCacheManager
    private lateinit var metadataCacheDb: MetadataCacheDb
    private lateinit var replayGainBridge: ReplayGainBridge

    // Snapdragon 730 / 6 GB RAM friendly pools: bounded queues avoid unbounded
    // thread creation and keep artwork/metadata scans from competing with audio
    // decoding or UI work on MIUI 12.
    private val artworkExecutor: ExecutorService = boundedExecutor(
        name = "artwork-cache",
        threads = 2,
        queueCapacity = 48,
    )
    private val metadataExecutor: ExecutorService = boundedExecutor(
        name = "metadata-io",
        threads = 2,
        queueCapacity = 32,
    )
    private val replayGainScanExecutor: ExecutorService = boundedExecutor(
        name = "rg-scan",
        threads = 2,   // 2 concurrent scans — Snapdragon 730 hardware MediaCodec
                       // supports multiple concurrent audio decoders without
                       // significant CPU contention.  Queue increased in proportion.
        queueCapacity = 8,
    )

    @Volatile private var shuttingDown = false

    // Stored after every getSongs() call so startMetadataPrescanner can
    // restart without a second MediaStore round-trip.
    @Volatile private var lastSongRefs: List<MetadataPrescanner.SongRef> = emptyList()

    // ── Delete song activity-result plumbing ────────────────────────────────
    // Android 11+ needs a system dialog (createDeleteRequest) that returns via
    // onActivityResult. We park the MethodChannel result here and resolve it
    // when the user dismisses the dialog.
    private var pendingDeleteResult: MethodChannel.Result? = null
    private val DELETE_REQUEST_CODE = 0x4445 // 'DE' — arbitrary unique code

    // Requests a MediaStore write grant (system dialog) before a ReplayGain
    // tag write/removal touches a file the app doesn't already own — see
    // MediaStoreWriteGate for the full API-level matrix. Its own pending
    // callback is resolved from onActivityResult below.
    private val replayGainWriteGate = MediaStoreWriteGate()

    // ── Open-file intent plumbing ────────────────────────────────────────────
    // Stores the URI from ACTION_VIEW intents that arrive before Dart is ready.
    @Volatile private var pendingOpenFileUri: String? = null
    private var openFileChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        artworkCacheManager = ArtworkCacheManager(this)
        metadataCacheDb     = MetadataCacheDb.getInstance(this)
        replayGainBridge    = ReplayGainBridge(metadataCacheDb) { songId ->
            openReplayGainWriteFd(songId)
        }

        // Prune stale cache entries older than 90 days on a bounded background
        // queue instead of spawning an extra ad-hoc thread during startup.
        submitBackground(metadataExecutor) { metadataCacheDb.pruneOld() }

        // Capture URI from the intent that cold-started the app.
        pendingOpenFileUri = extractAudioUri(intent)

        setupMediaStoreChannel(flutterEngine)
        setupAudioEffectsChannel(flutterEngine)
        setupMedia3PlaybackChannels(flutterEngine)
        setupFfmpegDecoderChannel(flutterEngine)
        setupOpenFileChannel(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val uri = extractAudioUri(intent) ?: return
        // Always write to pendingOpenFileUri so getInitialUri() can drain it.
        // Also invoke the Dart handler if it is already registered (best-effort
        // for warm starts); Dart will call getInitialUri() on resume as a safety
        // net if the invoke arrives before the handler is ready.
        pendingOpenFileUri = uri
        openFileChannel?.let { ch ->
            runOnUiThread { ch.invokeMethod("openUri", uri) }
        }
    }

    // Known audio file extensions for file:// URIs that omit a MIME type.
    private val AUDIO_EXTENSIONS = setOf(
        "mp3", "flac", "m4a", "aac", "ogg", "opus", "wav", "aiff",
        "aif", "wma", "alac", "ape", "dsf", "dff", "mka", "webm"
    )

    /** Returns a URI string if the intent is an audio ACTION_VIEW, else null. */
    private fun extractAudioUri(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri: Uri = intent.data ?: return null
        val scheme = uri.scheme ?: ""
        val mimeType = intent.type ?: contentResolver.getType(uri) ?: ""

        return when {
            // Explicit audio MIME — always accept.
            mimeType.startsWith("audio/") -> uri.toString()
            // No MIME from content resolver; reject non-audio content:// URIs
            // because we can't safely determine their type.
            scheme == "content" -> null
            // file:// URI: accept only known audio extensions.
            scheme == "file" || scheme.isEmpty() -> {
                val ext = uri.lastPathSegment?.substringAfterLast('.')
                    ?.lowercase() ?: ""
                if (ext in AUDIO_EXTENSIONS) uri.toString() else null
            }
            else -> null
        }
    }

    private fun setupOpenFileChannel(flutterEngine: FlutterEngine) {
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "musicplayer/open_file")
        openFileChannel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialUri" -> {
                    result.success(pendingOpenFileUri)
                    pendingOpenFileUri = null
                }
                else -> result.notImplemented()
            }
        }
    }


    private fun boundedExecutor(
        name: String,
        threads: Int,
        queueCapacity: Int,
    ): ExecutorService {
        val index = AtomicInteger(1)
        return ThreadPoolExecutor(
            threads,
            threads,
            30L,
            TimeUnit.SECONDS,
            LinkedBlockingQueue(queueCapacity),
            { runnable ->
                Thread({
                    android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
                    runnable.run()
                }, "$name-${index.getAndIncrement()}").apply { isDaemon = true }
            },
            ThreadPoolExecutor.AbortPolicy(),
        ).apply { allowCoreThreadTimeOut(true) }
    }

    private fun submitBackground(
        executor: ExecutorService,
        onRejected: (() -> Unit)? = null,
        block: () -> Unit,
    ) {
        try {
            executor.execute {
                if (!shuttingDown) block()
            }
        } catch (_: RejectedExecutionException) {
            onRejected?.invoke()
        }
    }

    private fun postToFlutter(block: () -> Unit) {
        if (shuttingDown) return
        runOnUiThread {
            if (!shuttingDown) block()
        }
    }

    // ── Media3 playback channels ───────────────────────────────────────────────

    @OptIn(UnstableApi::class)
    private fun setupMedia3PlaybackChannels(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, media3PlaybackChannel).setMethodCallHandler { call, result ->
            // Only "play" (resume from a persisted queue) and "setQueue" (start a
            // new queue) are legitimate reasons to spin up a stopped service.
            // pause/stop/seek/setTrack/skipNext/skipPrevious have nothing to act on
            // when no instance exists — starting the service for them leaves it
            // alive with an empty queue and no path to startForeground(), which
            // guarantees RemoteServiceException("did not then call
            // Service.startForeground()"). See MediaKit channel below, which never
            // included these methods in its own needsService set for the same reason.
            val needsService = call.method in setOf("play", "setQueue")

            if (Media3PlaybackService.instance == null && needsService) {
                val intent = Intent(this, Media3PlaybackService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ContextCompat.startForegroundService(this, intent)
                } else {
                    startService(intent)
                }
                result.error("not_ready", "Media3 service is starting", null)
                return@setMethodCallHandler
            }

            Media3PlaybackService.instance?.handle(call, result)
                ?: result.error("not_ready", "Media3 service is starting", null)
        }

        listOf(
            "playbackState", "position", "duration", "currentTrack",
            "queue", "bufferingState", "audioSessionId"
        ).forEach { name ->
            EventChannel(messenger, "musicplayer/media3_$name")
                .setStreamHandler(Media3PlaybackService.Events.handler(name))
        }

        listOf(
            "shuffleMode", "repeatMode", "sleepTimer", "offloadState",
            "audioFormat", "skipSilence",
            // Item 8: stereo widening state — emitted when setStereoWidening() is called
            // Map payload: { enabled: Boolean, strength: Double }
            "stereoWidening",
        ).forEach { name ->
            EventChannel(messenger, "musicplayer/media3_$name")
                .setStreamHandler(Media3PlaybackService.Events.handler(name))
        }

        EventChannel(messenger, "musicplayer/native_logs")
            .setStreamHandler(Media3PlaybackService.NativeLogs.handler())

        // Cold-start race fix: Dart awaits this before its first push into
        // media3PlaybackChannel (see ServiceReadyGate doc comment). Replays
        // "ready" immediately to a listener attaching after onCreate() already
        // finished (service alive from a previous launch in this process).
        EventChannel(messenger, "musicplayer/media3_serviceReady")
            .setStreamHandler(ServiceReadyGate.handler())
    }

    // ── FFmpeg decoder channel (Phase 9) ────────────────────────────────────
    //
    // Dedicated channel pair, owned exclusively by `FfmpegDecoderBridge` on the
    // Dart side (see lib/services/native/bridges/ffmpeg_decoder_bridge.dart).
    // `PlaybackManager` never talks to this channel directly — it goes through
    // that bridge, matching every other NativeModule in this codebase.
    //
    // - MethodChannel "queryStatus": one-shot capability probe, called once at
    //   startup by FfmpegDecoderBridge.initialize().
    // - EventChannel: per-track decoder selection info, emitted from
    //   Media3PlaybackService's AnalyticsListener (onAudioDecoderInitialized).
    private fun setupFfmpegDecoderChannel(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, ffmpegDecoderChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "queryStatus" -> {
                    val status = dev.wndavenz.music.ffmpeg.FfmpegCapabilityProbe.queryStatus()
                    result.success(mapOf(
                        "available"       to status.available,
                        "moduleLinked"    to status.moduleLinked,
                        "version"         to status.version,
                        "supportedCodecs" to status.supportedCodecs,
                    ))
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "musicplayer/ffmpeg_decoder_events")
            .setStreamHandler(Media3PlaybackService.Events.handler("ffmpegDecoderInfo"))
    }

    // ── MediaStore channel ─────────────────────────────────────────────────────

    private fun setupMediaStoreChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaStoreChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "getSongs" -> {
                        submitBackground(
                            metadataExecutor,
                            onRejected = {
                                postToFlutter {
                                    result.error("metadata_busy", "Metadata queue is busy", null)
                                }
                            },
                        ) {
                            try {
                                val songs = getSongs()
                                postToFlutter { result.success(songs) }
                            } catch (e: Exception) {
                                postToFlutter {
                                    result.error("songs_query_error", e.message, null)
                                }
                            }
                        }
                    }

                    "getArtwork" -> {
                        val songId = call.argument<Int>("songId") ?: 0
                        submitBackground(
                            artworkExecutor,
                            onRejected = {
                                postToFlutter {
                                    result.error("artwork_cache_busy", "Artwork queue is busy", null)
                                }
                            },
                        ) {
                            val artwork = getArtwork(songId)
                            postToFlutter { result.success(artwork) }
                        }
                    }

                    "getArtworkPath" -> {
                        val songId = call.argument<Int>("songId") ?: 0
                        submitBackground(
                            artworkExecutor,
                            onRejected = {
                                postToFlutter {
                                    result.error("artwork_cache_busy", "Artwork queue is busy", null)
                                }
                            },
                        ) {
                            try {
                                val path = artworkCacheManager.getOrExtract(songId)
                                postToFlutter { result.success(path) }
                            } catch (e: Exception) {
                                postToFlutter {
                                    result.error("artwork_cache_error", e.message, null)
                                }
                            }
                        }
                    }

                    "setActiveQueueIds" -> {
                        val ids = call.argument<List<Int>>("ids")?.toSet() ?: emptySet()
                        artworkCacheManager.setActiveQueueIds(ids)
                        result.success(null)
                    }

                    "cleanupArtworkCache" -> {
                        val activeIds = call.argument<List<Int>>("activeIds")
                            ?.toSet() ?: emptySet()
                        submitBackground(
                            metadataExecutor,
                            onRejected = {
                                postToFlutter {
                                    result.error("metadata_busy", "Metadata queue is busy", null)
                                }
                            },
                        ) {
                            try {
                                artworkCacheManager.cleanupIfNeeded(activeIds)
                                val data = mapOf(
                                    "count"     to artworkCacheManager.cacheCount(),
                                    "sizeBytes" to artworkCacheManager.cacheSizeBytes(),
                                )
                                postToFlutter { result.success(data) }
                            } catch (e: Exception) {
                                postToFlutter {
                                    result.error("artwork_cleanup_error", e.message, null)
                                }
                            }
                        }
                    }

                    "getAudioMetadata" -> {
                        val path   = call.argument<String>("path")
                        val songId = call.argument<Int>("songId") ?: 0
                        submitBackground(
                            metadataExecutor,
                            onRejected = {
                                postToFlutter {
                                    result.error("metadata_busy", "Metadata queue is busy", null)
                                }
                            },
                        ) {
                            try {
                                val metadata = getAudioMetadata(path, songId)
                                postToFlutter { result.success(metadata) }
                            } catch (e: Exception) {
                                postToFlutter {
                                    result.error("metadata_error", e.message, null)
                                }
                            }
                        }
                    }

                    // ── Embedded lyrics ─────────────────────────────────────
                    // Reads via ExoPlayer MetadataRetriever + SQLite cache.
                    // Runs on bounded background IO; result returned on UI thread.
                    "getEmbeddedLyrics" -> {
                        val path = call.argument<String>("path") ?: ""
                        submitBackground(
                            metadataExecutor,
                            onRejected = {
                                postToFlutter {
                                    result.error("metadata_busy", "Metadata queue is busy", null)
                                }
                            },
                        ) {
                            try {
                                val lyrics = getEmbeddedLyrics(path)
                                postToFlutter { result.success(lyrics) }
                            } catch (e: Exception) {
                                postToFlutter {
                                    result.error("lyrics_error", e.message, null)
                                }
                            }
                        }
                    }

                    // ── ReplayGain tag read ─────────────────────────────────
                    // Reads via ExoPlayer MetadataRetriever + SQLite cache.
                    // Runs on bounded background IO; result returned on UI thread.
                    "getReplayGainTags" -> {
                        val path = call.argument<String>("path") ?: ""
                        submitBackground(
                            metadataExecutor,
                            onRejected = {
                                postToFlutter {
                                    result.error("metadata_busy", "Metadata queue is busy", null)
                                }
                            },
                        ) {
                            try {
                                val tags = getReplayGainTags(path)
                                postToFlutter { result.success(tags) }
                            } catch (e: Exception) {
                                postToFlutter {
                                    result.error("rg_tags_error", e.message, null)
                                }
                            }
                        }
                    }

                    // ── ReplayGain scan (single track) ──────────────────────
                    // Native EBU R128 analysis via libebur128 (JNI). "scanReplayGain"
                    // is kept as an alias of "scanTrack" for backward compatibility
                    // with the existing Dart batch-scan call sites.
                    "scanReplayGain", "scanTrack" -> {
                        val path = call.argument<String>("path") ?: ""
                        submitBackground(
                            replayGainScanExecutor,
                            onRejected = {
                                postToFlutter {
                                    result.error("scan_busy", "ReplayGain scan queue is busy", null)
                                }
                            },
                        ) {
                            try {
                                val map = replayGainBridge.scanTrack(path)
                                postToFlutter {
                                    if (map["success"] == true) {
                                        result.success(map)
                                    } else {
                                        result.error("scan_failed", "Could not decode audio", null)
                                    }
                                }
                            } catch (e: Exception) {
                                postToFlutter {
                                    result.error("scan_error", e.message, null)
                                }
                            }
                        }
                    }

                    // ── ReplayGain scan (whole album) ───────────────────────
                    // Computes per-track loudness AND the shared album gain
                    // (EBU Tech 3341 album mode) across every path passed in.
                    "scanAlbum" -> {
                        @Suppress("UNCHECKED_CAST")
                        val paths = (call.argument<List<String>>("paths")) ?: emptyList()
                        submitBackground(
                            replayGainScanExecutor,
                            onRejected = {
                                postToFlutter {
                                    result.error("scan_busy", "ReplayGain scan queue is busy", null)
                                }
                            },
                        ) {
                            try {
                                val map = replayGainBridge.scanAlbum(paths)
                                postToFlutter { result.success(map) }
                            } catch (e: Exception) {
                                postToFlutter {
                                    result.error("scan_error", e.message, null)
                                }
                            }
                        }
                    }

                    // ── ReplayGain batch write-access pre-authorization ─────
                    // Requests write access for every songId in `songIds` up
                    // front, with at most ONE system confirmation dialog for
                    // the whole batch (Android 11+, via a single
                    // MediaStore.createWriteRequest grant) — see
                    // MediaStoreWriteGate.ensureWriteAccessBatch. Callers
                    // (e.g. the batch "write tags" library/album scan) should
                    // invoke this once with every songId they intend to write
                    // before making any individual `writeReplayGain` calls;
                    // those per-song calls will then find access already
                    // granted and proceed with no further dialogs.
                    //
                    // Returns a map of songId (as String, since Flutter's
                    // MethodChannel map keys round-trip cleanly as strings) to
                    // whether that song is now writable.
                    "requestReplayGainWriteAccessBatch" -> {
                        @Suppress("UNCHECKED_CAST")
                        val songIds = (call.argument<List<Any?>>("songIds"))
                            ?.mapNotNull { (it as? Number)?.toInt() }
                            ?: emptyList()
                        if (songIds.isEmpty()) {
                            result.success(emptyMap<String, Boolean>())
                        } else {
                            requestReplayGainWriteAccessBatch(songIds) { grantedById ->
                                result.success(grantedById.mapKeys { (id, _) -> id.toString() })
                            }
                        }
                    }

                    // ── ReplayGain tag write ─────────────────────────────────
                    // Writes measured gain/peak (from a prior scanTrack/scanAlbum
                    // call) permanently into the file's own tags via TagLib:
                    // REPLAYGAIN_*_GAIN/_PEAK (MP3/FLAC/Ogg Vorbis) or
                    // R128_TRACK_GAIN/R128_ALBUM_GAIN (Ogg Opus). All other
                    // metadata (art, lyrics, ISRC, etc.) is preserved untouched.
                    //
                    // Scoped-storage safe: requires `songId` in `args` so a
                    // MediaStore write grant can be requested first (a system
                    // dialog on Android 10+, once per file the app doesn't
                    // already own) before any native write is attempted.
                    "writeReplayGain" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                        val songId = (args["songId"] as? Number)?.toInt()
                        if (songId == null) {
                            result.error("invalid_args", "songId required", null)
                        } else {
                            requestReplayGainWriteAccess(songId) { granted ->
                                if (!granted) {
                                    result.success(mapOf("success" to false, "error" to "WRITE_ACCESS_DENIED"))
                                    return@requestReplayGainWriteAccess
                                }
                                submitBackground(
                                    metadataExecutor,
                                    onRejected = {
                                        postToFlutter {
                                            result.error("metadata_busy", "Metadata queue is busy", null)
                                        }
                                    },
                                ) {
                                    try {
                                        val map = replayGainBridge.writeReplayGain(args)
                                        postToFlutter { result.success(map) }
                                    } catch (e: Exception) {
                                        postToFlutter {
                                            result.error("write_error", e.message, null)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── ReplayGain tag removal ───────────────────────────────
                    // Same scoped-storage-grant requirement as writeReplayGain.
                    "removeReplayGain" -> {
                        val path = call.argument<String>("path") ?: ""
                        val songId = call.argument<Int>("songId")
                        if (songId == null) {
                            result.error("invalid_args", "songId required", null)
                        } else {
                            requestReplayGainWriteAccess(songId) { granted ->
                                if (!granted) {
                                    result.success(mapOf("success" to false, "error" to "WRITE_ACCESS_DENIED"))
                                    return@requestReplayGainWriteAccess
                                }
                                submitBackground(
                                    metadataExecutor,
                                    onRejected = {
                                        postToFlutter {
                                            result.error("metadata_busy", "Metadata queue is busy", null)
                                        }
                                    },
                                ) {
                                    try {
                                        val map = replayGainBridge.removeReplayGain(path, songId)
                                        postToFlutter { result.success(map) }
                                    } catch (e: Exception) {
                                        postToFlutter {
                                            result.error("remove_error", e.message, null)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Metadata cache diagnostics ──────────────────────────
                    "getMetadataCacheInfo" -> {
                        result.success(mapOf(
                            "entryCount"        to metadataCacheDb.count(),
                            "prescannerRunning" to MetadataPrescanner.isRunning,
                        ))
                    }

                    "invalidateMetadataCache" -> {
                        val songId = call.argument<Int>("songId")
                        if (songId != null) metadataCacheDb.invalidate(songId)
                        result.success(null)
                    }

                    // ── Background pre-scanner control ──────────────────────
                    // The prescanner is started automatically by getSongs().
                    // Dart cancels it when playback starts (I/O priority),
                    // and restarts it when the queue ends (idle window).
                    "cancelMetadataPrescanner" -> {
                        MetadataPrescanner.cancel()
                        result.success(null)
                    }

                    // Restart the prescanner using the cached song list from
                    // the last getSongs() call — no extra MediaStore query.
                    "startMetadataPrescanner" -> {
                        val refs = lastSongRefs
                        if (refs.isNotEmpty()) {
                            MetadataPrescanner.start(this, refs, metadataCacheDb)
                        }
                        result.success(null)
                    }

                    // ── Hapus lagu dari perangkat ───────────────────────────
                    // Android 11+ (API 30+): createDeleteRequest → dialog sistem
                    //   → hasil dikembalikan lewat onActivityResult.
                    // Android 10  (API 29):  coba delete langsung; tangkap
                    //   RecoverableSecurityException jika file bukan milik app.
                    // Android < 10 (API < 29): delete file + ContentResolver.
                    "deleteSong" -> {
                        val songId = call.argument<Int>("songId")
                        if (songId == null) {
                            result.error("invalid_args", "songId required", null)
                        } else {
                            val contentUri = android.content.ContentUris.withAppendedId(
                                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                                songId.toLong(),
                            )
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                // Android 11+: sistem menampilkan dialog konfirmasi.
                                try {
                                    val pi = MediaStore.createDeleteRequest(
                                        contentResolver, listOf(contentUri),
                                    )
                                    pendingDeleteResult = result
                                    startIntentSenderForResult(
                                        pi.intentSender,
                                        DELETE_REQUEST_CODE,
                                        null, 0, 0, 0,
                                    )
                                } catch (e: Exception) {
                                    result.error("delete_error", e.message, null)
                                }
                            } else {
                                // Android < 11: coba hapus langsung di background.
                                submitBackground(
                                    metadataExecutor,
                                    onRejected = {
                                        postToFlutter {
                                            result.error("metadata_busy", "Metadata queue is busy", null)
                                        }
                                    },
                                ) {
                                    val deleted = try {
                                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                            // Android 10: scoped storage — file milik app lain
                                            // bisa lempar RecoverableSecurityException.
                                            try {
                                                contentResolver.delete(contentUri, null, null) > 0
                                            } catch (e: android.app.RecoverableSecurityException) {
                                                false
                                            }
                                        } else {
                                            // Android < 10: hapus file fisik dulu, lalu update DB.
                                            val path = getPathFromUri(contentUri)
                                            val fileOk = if (path != null) File(path).delete() else false
                                            val rows = try {
                                                contentResolver.delete(contentUri, null, null)
                                            } catch (_: Exception) { 0 }
                                            fileOk || rows > 0
                                        }
                                    } catch (e: Exception) {
                                        false
                                    }
                                    postToFlutter { result.success(deleted) }
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ── Activity result — untuk deleteSong di Android 11+ dan ReplayGain
    //    write-grant requests ────────────────────────────────────────────────
    @Suppress("OVERRIDE_DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == DELETE_REQUEST_CODE) {
            val deleted = resultCode == android.app.Activity.RESULT_OK
            pendingDeleteResult?.success(deleted)
            pendingDeleteResult = null
            return
        }
        if (replayGainWriteGate.handleActivityResult(requestCode, resultCode)) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    // ── ReplayGain write-grant helpers ───────────────────────────────────────

    /**
     * Requests (if not already held) write access to the audio file
     * identified by [songId], invoking [onResult] on the main thread with
     * true once an actual write-fd open has succeeded, false on decline or
     * failure. See [MediaStoreWriteGate] for the full API-level matrix.
     */
    private fun requestReplayGainWriteAccess(songId: Int, onResult: (Boolean) -> Unit) {
        val contentUri = android.content.ContentUris.withAppendedId(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toLong(),
        )
        replayGainWriteGate.ensureWriteAccess(this, contentUri, onResult)
    }

    /**
     * Batch variant of [requestReplayGainWriteAccess] — pre-authorizes every
     * songId in [songIds] with at most one system dialog for the whole
     * batch (Android 11+). [onResult] receives a map from songId to whether
     * that song is now writable. See [MediaStoreWriteGate.ensureWriteAccessBatch].
     */
    private fun requestReplayGainWriteAccessBatch(
        songIds: List<Int>,
        onResult: (Map<Int, Boolean>) -> Unit,
    ) {
        val uriToSongId = songIds.associateBy { songId ->
            android.content.ContentUris.withAppendedId(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toLong(),
            )
        }
        replayGainWriteGate.ensureWriteAccessBatch(this, uriToSongId.keys.toList()) { grantedByUri ->
            onResult(grantedByUri.mapKeys { (uri, _) -> uriToSongId.getValue(uri) })
        }
    }

    /**
     * Opens a fresh read/write fd for [songId]'s underlying MediaStore
     * entry. Used by [ReplayGainBridge] for every step of its
     * write→close→reopen→verify→(restore) sequence — a distinct
     * ParcelFileDescriptor is opened each time since the native side closes
     * the fd it's given internally (TagLib::FileStream fdopen()s it and
     * fclose()s it on destruction). Assumes [requestReplayGainWriteAccess]
     * already succeeded for this songId in the current call chain.
     */
    private fun openReplayGainWriteFd(songId: Int): ParcelFileDescriptor? {
        val contentUri = android.content.ContentUris.withAppendedId(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toLong(),
        )
        return try {
            contentResolver.openFileDescriptor(contentUri, "rw")
        } catch (e: Exception) {
            null
        }
    }

    // ── Helper: ambil path file dari content URI ─────────────────────────────
    private fun getPathFromUri(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(MediaStore.Audio.Media.DATA),
                null, null, null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA))
                } else null
            }
        } catch (_: Exception) { null }
    }


    // ── Audio effects channel ──────────────────────────────────────────────────

    private fun setupAudioEffectsChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioEffectsChannel)
            .setMethodCallHandler { call, result ->
                val service = Media3PlaybackService.instance
                if (service == null) {
                    result.error("not_ready", "Media3 service is not ready", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "attachEffects" -> {
                        result.success(mapOf(
                            "bassBoostSupported" to true
                        ))
                    }
                    "setBassBoost" -> {
                        val strength = call.argument<Int>("strength") ?: 0
                        service.handle(MethodCall("setBassBoostEnabled",
                            mutableMapOf<String, Any?>("enabled" to (strength > 0))), result)
                        service.handle(MethodCall("setBassBoostStrength",
                            mutableMapOf<String, Any?>("strength" to strength)), result)
                    }
                    "setAudioOutputMode" -> result.success(null)
                    else               -> result.notImplemented()
                }
            }
    }

    // ── ReplayGain tag reader ──────────────────────────────────────────────────
    //
    // Layer 1: SQLite MetadataCacheDb (mtime-keyed, near-zero latency on hit)
    // Layer 2: ExoPlayer MetadataRetriever (MP3 TXXX, Vorbis, M4A atoms)
    //
    // On the first call for a given file, ExoPlayer reads BOTH loudness tags
    // and lyrics in one pass and caches everything.  Subsequent calls for
    // either tags or lyrics return from SQLite.

    private fun getReplayGainTags(path: String): Map<String, String?> {
        if (path.isBlank()) return emptyMap()
        val file = File(path)
        if (!file.exists()) return emptyMap()

        val mtime   = MetadataCacheDb.mtime(path)
        val cached  = metadataCacheDb.getByPath(path, mtime)

        // Cache hit — return immediately
        if (cached != null) {
            return buildRgMap(cached)
        }

        // Cache miss — read via ExoPlayer and populate full cache entry
        val tags = ExoMetadataReader.read(this, path)
        metadataCacheDb.putByPath(path, mtime,
            MetadataCacheDb.CachedEntry(
                rgTrackGain = tags.rgTrackGain,
                rgTrackPeak = tags.rgTrackPeak,
                rgAlbumGain = tags.rgAlbumGain,
                rgAlbumPeak = tags.rgAlbumPeak,
                r128Track   = tags.r128Track,
                r128Album   = tags.r128Album,
                iTunNorm    = tags.iTunNorm,
                // Also cache lyrics in the same pass — avoids a second ExoPlayer read
                // when LyricsService later calls getEmbeddedLyrics for the same file.
                lyrics      = tags.lyrics ?: MetadataCacheDb.LYRICS_NONE,
            )
        )

        return mapOf(
            "replayGainTrackGain" to tags.rgTrackGain,
            "replayGainTrackPeak" to tags.rgTrackPeak,
            "replayGainAlbumGain" to tags.rgAlbumGain,
            "replayGainAlbumPeak" to tags.rgAlbumPeak,
            "r128TrackGain"       to tags.r128Track,
            "r128AlbumGain"       to tags.r128Album,
            "iTunNORM"            to tags.iTunNorm,
        )
    }

    private fun buildRgMap(e: MetadataCacheDb.CachedEntry): Map<String, String?> = mapOf(
        "replayGainTrackGain" to e.rgTrackGain,
        "replayGainTrackPeak" to e.rgTrackPeak,
        "replayGainAlbumGain" to e.rgAlbumGain,
        "replayGainAlbumPeak" to e.rgAlbumPeak,
        "r128TrackGain"       to e.r128Track,
        "r128AlbumGain"       to e.r128Album,
        "iTunNORM"            to e.iTunNorm,
    )

    // ── Embedded lyrics reader ─────────────────────────────────────────────────
    //
    // Supports:
    //   MP3   → ID3v2 USLT (all frames, prefers blank/eng language)
    //   M4A   → ©lyr atom
    //   FLAC  → Vorbis LYRICS / UNSYNCEDLYRICS / UNSYNCED LYRICS
    //   OGG   → same as FLAC
    //   OPUS  → same as FLAC
    //
    // Cache sentinel: LYRICS_NONE = file was parsed, confirmed no lyrics present.
    // This avoids re-parsing on every LyricsService call for songs without lyrics.

    private fun getEmbeddedLyrics(path: String): String? {
        if (path.isBlank()) return null
        val file = File(path)
        if (!file.exists()) return null

        val mtime  = MetadataCacheDb.mtime(path)
        val cached = metadataCacheDb.getByPath(path, mtime)

        // Cache hit
        if (cached != null) {
            return when (cached.lyrics) {
                MetadataCacheDb.LYRICS_NONE -> null   // confirmed absent
                null -> {
                    // Row exists (from prior RG read) but lyrics not yet read.
                    // Read now and update the lyrics column.
                    val tags = ExoMetadataReader.read(this, path)
                    val toStore = tags.lyrics ?: MetadataCacheDb.LYRICS_NONE
                    metadataCacheDb.updateLyrics(path, toStore)
                    tags.lyrics
                }
                else -> cached.lyrics   // cached lyrics text
            }
        }

        // Cache miss — read via ExoPlayer and populate full cache entry
        val tags = ExoMetadataReader.read(this, path)
        metadataCacheDb.putByPath(path, mtime,
            MetadataCacheDb.CachedEntry(
                rgTrackGain = tags.rgTrackGain,
                rgTrackPeak = tags.rgTrackPeak,
                rgAlbumGain = tags.rgAlbumGain,
                rgAlbumPeak = tags.rgAlbumPeak,
                r128Track   = tags.r128Track,
                r128Album   = tags.r128Album,
                iTunNorm    = tags.iTunNorm,
                lyrics      = tags.lyrics ?: MetadataCacheDb.LYRICS_NONE,
            )
        )
        return tags.lyrics
    }

    // ── MediaStore helpers ─────────────────────────────────────────────────────

    private fun hasMediaPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this,
                Manifest.permission.READ_MEDIA_AUDIO) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this,
                Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }

    private fun getArtwork(songId: Int): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            val uri = Uri.withAppendedPath(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString())
            retriever.setDataSource(this, uri)
            retriever.embeddedPicture
        } catch (_: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    private fun getAudioMetadata(path: String?, songId: Int): Map<String, String?> {
        val retriever = MediaMetadataRetriever()
        return try {
            try {
                if (path.isNullOrBlank()) throw IllegalArgumentException("Missing path")
                retriever.setDataSource(path)
            } catch (_: Exception) {
                val uri = Uri.withAppendedPath(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString())
                retriever.setDataSource(this, uri)
            }
            mapOf(
                "year"       to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR),
                "bitrate"    to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE),
                "sampleRate" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE),
                "fileSize"   to getFileSize(path),
            )
        } catch (_: Exception) { emptyMap() } finally { retriever.release() }
    }

    private fun getFileSize(path: String?): String? {
        if (path.isNullOrBlank()) return null
        return try { File(path).length().takeIf { it > 0 }?.toString() }
        catch (_: Exception) { null }
    }

    // ── getSongs — expanded MediaStore projection ─────────────────────────────
    //
    // Phase 1: expose additional metadata fields that are already indexed in the
    // MediaStore database, avoiding per-song MediaMetadataRetriever calls for
    // technical info on API 31+ devices.
    //
    // Field availability:
    //   year, track (incl. disc)  → all API levels (minSdk 29)
    //   album_artist, genre       → all API levels via string literal (column exists)
    //   bitrate, samplerate       → API 31+ (Android 12); null on older devices
    //
    // Track/disc encoding: MediaStore stores track as (disc * 1000) + track on
    // older Android versions.  We detect this by checking if the raw value > 1000
    // and unpack accordingly.  On API 30+ devices the disc may also be in a
    // separate DISC_NUMBER column — we prefer it when present.

    private fun getSongs(): List<Map<String, Any?>> {
        if (!hasMediaPermission()) return emptyList()

        // Build projection dynamically based on API level.
        // Columns must be guarded carefully — including a non-existent column
        // in the projection may cause ContentResolver.query() to throw on some
        // Android/MIUI versions rather than silently returning null.
        val projection = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.YEAR,     // API 1+, always safe
            MediaStore.Audio.Media.TRACK,    // API 1+, encodes disc*1000+track
            "album_artist",                  // column exists in MediaStore DB since API 16+
        )

        // API 30 (Android 11): genre added to the audio tracks table directly
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            projection.add("genre")
        }

        // API 31 (Android 12): technical audio fields (bits/s and Hz)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            projection.add("bitrate")
            projection.add("samplerate")
        }

        val songs = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection.toTypedArray(),
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            "${MediaStore.Audio.Media.TITLE} ASC",
        )?.use { cursor ->
            val idCol      = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol   = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol  = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol   = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val pathCol    = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val durCol     = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val yearCol    = cursor.getColumnIndex(MediaStore.Audio.Media.YEAR)
            val trackCol   = cursor.getColumnIndex(MediaStore.Audio.Media.TRACK)
            val albumArtistCol = cursor.getColumnIndex("album_artist")
            val genreCol       = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                cursor.getColumnIndex("genre") else -1
            val bitrateCol     = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                cursor.getColumnIndex("bitrate") else -1
            val sampleRateCol  = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                cursor.getColumnIndex("samplerate") else -1

            while (cursor.moveToNext()) {
                val map = mutableMapOf<String, Any?>(
                    "id"       to cursor.getLong(idCol).toInt(),
                    "title"    to cursor.getString(titleCol),
                    "artist"   to (cursor.getString(artistCol) ?: "Unknown Artist"),
                    "album"    to (cursor.getString(albumCol)  ?: "Unknown Album"),
                    "albumId"  to cursor.getInt(albumIdCol),
                    "path"     to cursor.getString(pathCol),
                    "duration" to cursor.getLong(durCol),
                )

                // Year
                if (yearCol >= 0) {
                    val y = cursor.getInt(yearCol)
                    if (y > 0) map["year"] = y
                }

                // Track number + disc number
                // MediaStore packs both as: raw = disc*1000 + track (older convention).
                // Values <= 1000 are pure track numbers without disc info.
                if (trackCol >= 0) {
                    val raw = cursor.getInt(trackCol)
                    if (raw > 0) {
                        if (raw > 1000) {
                            map["trackNumber"] = raw % 1000
                            map["discNumber"]  = raw / 1000
                        } else {
                            map["trackNumber"] = raw
                        }
                    }
                }

                // Album artist
                if (albumArtistCol >= 0) {
                    val aa = cursor.getString(albumArtistCol)
                    if (!aa.isNullOrBlank()) map["albumArtist"] = aa
                }

                // Genre
                if (genreCol >= 0) {
                    val g = cursor.getString(genreCol)
                    if (!g.isNullOrBlank()) map["genre"] = g
                }

                // Bitrate (API 31+) — stored in bits/s by MediaStore
                if (bitrateCol >= 0) {
                    val br = cursor.getLong(bitrateCol)
                    if (br > 0L) map["bitrate"] = br.toInt()
                }

                // Sample rate (API 31+) — stored in Hz
                if (sampleRateCol >= 0) {
                    val sr = cursor.getInt(sampleRateCol)
                    if (sr > 0) map["sampleRate"] = sr
                }

                songs.add(map)
            }
        }

        // Kick off background pre-scan so RG tags + lyrics are already in
        // cache by the time the user taps play or opens a lyrics view.
        // Runs at THREAD_PRIORITY_LOWEST — no impact on UI or audio decode.
        val songRefs = songs.mapNotNull { m ->
            val id   = m["id"]   as? Int    ?: return@mapNotNull null
            val path = m["path"] as? String ?: return@mapNotNull null
            if (path.isBlank()) null else MetadataPrescanner.SongRef(id, path)
        }
        lastSongRefs = songRefs
        MetadataPrescanner.start(this, songRefs, metadataCacheDb)

        return songs
    }

    override fun onDestroy() {
        shuttingDown = true
        MetadataPrescanner.cancel()
        artworkExecutor.shutdownNow()
        metadataExecutor.shutdownNow()
        replayGainScanExecutor.shutdownNow()
        super.onDestroy()
    }
}
