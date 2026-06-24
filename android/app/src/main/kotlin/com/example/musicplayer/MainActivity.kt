package com.example.musicplayer

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import androidx.media3.common.util.UnstableApi
import com.example.musicplayer.metadata.ExoMetadataReader
import com.example.musicplayer.metadata.MetadataCacheDb
import com.example.musicplayer.metadata.MetadataPrescanner
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val mediaStoreChannel     = "musicplayer/media_store"
    private val audioEffectsChannel   = "musicplayer/audio_effects"
    private val media3PlaybackChannel = "musicplayer/media3_playback"

    private lateinit var artworkCacheManager: ArtworkCacheManager
    private lateinit var metadataCacheDb: MetadataCacheDb

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        artworkCacheManager = ArtworkCacheManager(this)
        metadataCacheDb     = MetadataCacheDb.getInstance(this)

        // Prune stale cache entries older than 90 days on a background thread
        Thread {
            metadataCacheDb.pruneOld()
        }.apply { name = "metadata-cache-prune"; isDaemon = true; start() }

        setupMediaStoreChannel(flutterEngine)
        setupAudioEffectsChannel(flutterEngine)
        setupMedia3PlaybackChannels(flutterEngine)
    }

    // ── Media3 playback channels ───────────────────────────────────────────────

    @OptIn(UnstableApi::class)
    private fun setupMedia3PlaybackChannels(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, media3PlaybackChannel).setMethodCallHandler { call, result ->
            val needsService = call.method in setOf(
                "play", "pause", "stop", "seek",
                "setQueue", "setTrack", "skipNext", "skipPrevious"
            )

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
        ).forEach { name ->
            EventChannel(messenger, "musicplayer/media3_$name")
                .setStreamHandler(Media3PlaybackService.Events.handler(name))
        }

        EventChannel(messenger, "musicplayer/native_logs")
            .setStreamHandler(Media3PlaybackService.NativeLogs.handler())
    }

    // ── MediaStore channel ─────────────────────────────────────────────────────

    private fun setupMediaStoreChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaStoreChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "getSongs" -> result.success(getSongs())

                    "getArtwork" -> {
                        val songId = call.argument<Int>("songId")
                        result.success(getArtwork(songId ?: 0))
                    }

                    "getArtworkPath" -> {
                        val songId = call.argument<Int>("songId") ?: 0
                        Thread {
                            try {
                                val path = artworkCacheManager.getOrExtract(songId)
                                runOnUiThread { result.success(path) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("artwork_cache_error", e.message, null)
                                }
                            }
                        }.apply { name = "artwork-cache-$songId"; start() }
                    }

                    "setActiveQueueIds" -> {
                        val ids = call.argument<List<Int>>("ids")?.toSet() ?: emptySet()
                        artworkCacheManager.setActiveQueueIds(ids)
                        result.success(null)
                    }

                    "cleanupArtworkCache" -> {
                        val activeIds = call.argument<List<Int>>("activeIds")
                            ?.toSet() ?: emptySet()
                        Thread {
                            artworkCacheManager.cleanupIfNeeded(activeIds)
                            val data = mapOf(
                                "count"     to artworkCacheManager.cacheCount(),
                                "sizeBytes" to artworkCacheManager.cacheSizeBytes(),
                            )
                            runOnUiThread { result.success(data) }
                        }.apply { name = "artwork-cleanup"; start() }
                    }

                    "getAudioMetadata" -> {
                        val path   = call.argument<String>("path")
                        val songId = call.argument<Int>("songId") ?: 0
                        result.success(getAudioMetadata(path, songId))
                    }

                    // ── Embedded lyrics ─────────────────────────────────────
                    // Reads via ExoPlayer MetadataRetriever + SQLite cache.
                    // Runs on a background thread; result returned via runOnUiThread.
                    "getEmbeddedLyrics" -> {
                        val path = call.argument<String>("path") ?: ""
                        Thread {
                            val lyrics = getEmbeddedLyrics(path)
                            runOnUiThread { result.success(lyrics) }
                        }.apply { name = "lyrics-reader"; start() }
                    }

                    // ── ReplayGain tag read ─────────────────────────────────
                    // Reads via ExoPlayer MetadataRetriever + SQLite cache.
                    // Runs on a background thread; result returned via runOnUiThread.
                    "getReplayGainTags" -> {
                        val path = call.argument<String>("path") ?: ""
                        Thread {
                            val tags = getReplayGainTags(path)
                            runOnUiThread { result.success(tags) }
                        }.apply { name = "rg-tags-reader"; start() }
                    }

                    // ── ReplayGain scan ─────────────────────────────────────
                    // Scan uses native MediaCodec (no jaudiotagger).
                    // Results are stored in MetadataCacheDb (not written to file).
                    // This is reliable on Android 10+ / MIUI 11+ where scoped
                    // storage prevents arbitrary audio-file tag writes.
                    "scanReplayGain" -> {
                        val path = call.argument<String>("path") ?: ""
                        Thread {
                            try {
                                val scanResult = com.example.musicplayer.replay_gain
                                    .ReplayGainScanner.scan(path) { _ -> }
                                if (scanResult != null) {
                                    val gainStr  = "%+.2f dB".format(scanResult.trackGainDb)
                                    val peakStr  = "%.6f".format(scanResult.trackPeak.coerceAtMost(1.0))
                                    val mtime    = MetadataCacheDb.mtime(path)
                                    val existing = metadataCacheDb.getByPath(path, mtime)
                                    metadataCacheDb.putByPath(path, mtime,
                                        MetadataCacheDb.CachedEntry(
                                            rgTrackGain = gainStr,
                                            rgTrackPeak = peakStr,
                                            rgAlbumGain = existing?.rgAlbumGain,
                                            rgAlbumPeak = existing?.rgAlbumPeak,
                                            r128Track   = existing?.r128Track,
                                            r128Album   = existing?.r128Album,
                                            iTunNorm    = existing?.iTunNorm,
                                            lyrics      = existing?.lyrics,
                                        )
                                    )
                                    runOnUiThread {
                                        result.success(mapOf(
                                            "integratedLufs" to scanResult.integratedLufs,
                                            "trackGainDb"    to scanResult.trackGainDb,
                                            "trackPeak"      to scanResult.trackPeak,
                                            "tagsWritten"    to true,
                                        ))
                                    }
                                } else {
                                    runOnUiThread {
                                        result.error("scan_failed",
                                            "Could not decode audio", null)
                                    }
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("scan_error", e.message, null)
                                }
                            }
                        }.apply { name = "rg-scanner"; start() }
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
                    // Dart can cancel it (e.g. when the user starts playback
                    // and we want all I/O budget for the player) and check
                    // its status via getMetadataCacheInfo.
                    "cancelMetadataPrescanner" -> {
                        MetadataPrescanner.cancel()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
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
                            "virtualizerSupported" to true,
                            "bassBoostSupported"   to true,
                            "reverbSupported"      to true
                        ))
                    }
                    "setSpatialEnabled" -> {
                        val enabled  = call.argument<Boolean>("enabled") ?: false
                        val strength = call.argument<Int>("strength") ?: 1000
                        val args1 = mutableMapOf<String, Any?>("enabled" to enabled)
                        service.handle(MethodCall("setVirtualizerEnabled", args1), result)
                        if (enabled) {
                            val args2 = mutableMapOf<String, Any?>("strength" to strength)
                            service.handle(MethodCall("setVirtualizerStrength", args2), result)
                        }
                    }
                    "setBassBoost" -> {
                        val strength = call.argument<Int>("strength") ?: 0
                        service.handle(MethodCall("setBassBoostEnabled",
                            mutableMapOf<String, Any?>("enabled" to (strength > 0))), result)
                        service.handle(MethodCall("setBassBoostStrength",
                            mutableMapOf<String, Any?>("strength" to strength)), result)
                    }
                    "setReverb" -> {
                        val preset = call.argument<Int>("preset") ?: 0
                        service.handle(MethodCall("setReverbPreset",
                            mutableMapOf<String, Any?>("preset" to preset)), result)
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
        return try {
            val uri = Uri.withAppendedPath(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString())
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(this, uri)
            val artwork = retriever.embeddedPicture
            retriever.release()
            artwork
        } catch (_: Exception) { null }
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
        MetadataPrescanner.start(this, songRefs, metadataCacheDb)

        return songs
    }

    override fun onDestroy() {
        MetadataPrescanner.cancel()
        super.onDestroy()
    }
}
