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

    // Persistent artwork cache — initialised once in configureFlutterEngine.
    private lateinit var artworkCacheManager: ArtworkCacheManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        artworkCacheManager = ArtworkCacheManager(this)
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
                "play",
                "pause",
                "stop",
                "seek",
                "setQueue",
                "setTrack",
                "skipNext",
                "skipPrevious"
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
            "playbackState",
            "position",
            "duration",
            "currentTrack",
            "queue",
            "bufferingState",
            "audioSessionId"
        ).forEach { name ->
            EventChannel(messenger, "musicplayer/media3_$name")
                .setStreamHandler(Media3PlaybackService.Events.handler(name))
        }

        listOf("shuffleMode", "repeatMode", "sleepTimer", "offloadState").forEach { name ->
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
                        // Runs on a background thread so MediaStore I/O never blocks
                        // the Flutter UI thread.  Returns the cached file path (String?)
                        // so Flutter can use FileImage for zero-copy rendering.
                        val songId = call.argument<Int>("songId") ?: 0
                        Thread {
                                try {
                                val path = artworkCacheManager.getOrExtract(songId)

                                runOnUiThread {
                                    result.success(path)
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error(
                                        "artwork_cache_error",
                                        e.message,
                                        null
                                    )
                                }
                            }
                        }.apply {
                            name = "artwork-cache-$songId"
                            start()
                        }
                    }
                    "setActiveQueueIds" -> {
                        // Inform the cache manager which song IDs are in the active
                        // playback queue.  These songs are never evicted during LRU
                        // cleanup.  Call this whenever the queue changes.
                        val ids = call.argument<List<Int>>("ids")
                            ?.toSet() ?: emptySet()
                        artworkCacheManager.setActiveQueueIds(ids)
                        result.success(null)
                    }
                    "cleanupArtworkCache" -> {
                        // Optional manual cleanup.  Flutter may pass active-queue song
                        // IDs to protect them; the automatic cleanup inside
                        // getOrExtract already uses the stored activeQueueIds.
                        val activeIds = call.argument<List<Int>>("activeIds")
                            ?.toSet() ?: emptySet()
                        Thread {
                            artworkCacheManager.cleanupIfNeeded(activeIds)

                            val data = mapOf(
                                "count" to artworkCacheManager.cacheCount(),
                                "sizeBytes" to artworkCacheManager.cacheSizeBytes(),
                            )

                            runOnUiThread {
                                result.success(data)
                            }
                        }.apply {
                            name = "artwork-cleanup"
                            start()
                        }
                    }
                    "getAudioMetadata" -> {
                        val path = call.argument<String>("path")
                        val songId = call.argument<Int>("songId")
                        result.success(getAudioMetadata(path, songId ?: 0))
                    }
                    "getEmbeddedLyrics" -> {
                        val path = call.argument<String>("path") ?: ""
                        result.success(getEmbeddedLyrics(path))
                    }
                    "getReplayGainTags" -> {
                        val path = call.argument<String>("path") ?: ""
                        result.success(getReplayGainTags(path))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Audio effects channel (Activity-context operations only) ───────────────

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
                    result.success(
                        mapOf(
                            "virtualizerSupported" to true,
                            "bassBoostSupported" to true,
                            "reverbSupported" to true
                        )
                    )
                }
                "setSpatialEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val strength = call.argument<Int>("strength") ?: 1000
                    val args1 = mutableMapOf<String, Any?>()
                    args1["enabled"] = enabled
                    service.handle(MethodCall("setVirtualizerEnabled", args1), result)
                    if (enabled) {
                        val args2 = mutableMapOf<String, Any?>()
                        args2["strength"] = strength
                        service.handle(MethodCall("setVirtualizerStrength", args2), result)
                    }
                }
                "setBassBoost" -> {
                    val strength = call.argument<Int>("strength") ?: 0
                    val args1 = mutableMapOf<String, Any?>()
                    args1["enabled"] = strength > 0
                    service.handle(MethodCall("setBassBoostEnabled", args1), result)
                    val args2 = mutableMapOf<String, Any?>()
                    args2["strength"] = strength
                    service.handle(MethodCall("setBassBoostStrength", args2), result)
                }
                "setReverb" -> {
                    val preset = call.argument<Int>("preset") ?: 0
                    val args = mutableMapOf<String, Any?>()
                    args["preset"] = preset
                    service.handle(MethodCall("setReverbPreset", args), result)
                }
                "setAudioOutputMode" -> {
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
}

    // ── ReplayGain tag reader ──────────────────────────────────────────────────

    private fun getReplayGainTags(path: String): Map<String, String?> {
        if (path.isBlank()) return emptyMap()
        val file = File(path)
        if (!file.exists()) return emptyMap()

        try {
            val af = org.jaudiotagger.audio.AudioFileIO.read(file)
            val tag = af?.tag
            if (tag != null) {
                val result = mutableMapOf<String, String?>()
                result["replayGainTrackGain"] = readCustomTag(tag, "REPLAYGAIN_TRACK_GAIN")
                result["replayGainTrackPeak"] = readCustomTag(tag, "REPLAYGAIN_TRACK_PEAK")
                result["replayGainAlbumGain"] = readCustomTag(tag, "REPLAYGAIN_ALBUM_GAIN")
                result["replayGainAlbumPeak"] = readCustomTag(tag, "REPLAYGAIN_ALBUM_PEAK")
                result["r128TrackGain"] = readCustomTag(tag, "R128_TRACK_GAIN")
                    ?: readCustomTag(tag, "r128_track_gain")
                result["r128AlbumGain"] = readCustomTag(tag, "R128_ALBUM_GAIN")
                    ?: readCustomTag(tag, "r128_album_gain")
                result["iTunNORM"] = readCustomTag(tag, "iTunNORM")

                if (result.values.any { it != null }) return result
            }
        } catch (_: Exception) {
            // fallback ke default
        }

        return mapOf(
            "replayGainTrackGain" to "0.0 dB",
            "replayGainTrackPeak" to "1.0",
            "replayGainAlbumGain" to "0.0 dB",
            "replayGainAlbumPeak" to "1.0",
            "r128TrackGain" to "0.0",
            "r128AlbumGain" to "0.0",
            "iTunNORM" to "0.0"
        )
    }

    private fun readCustomTag(tag: org.jaudiotagger.tag.Tag, key: String): String? {
        return try {
            tag.getFirst(org.jaudiotagger.tag.FieldKey.valueOf(key.uppercase()))
                .takeIf { it.isNotBlank() }?.trim()
        } catch (_: Exception) {
            try {
                (tag as? org.jaudiotagger.tag.vorbiscomment.VorbisCommentTag)
                    ?.getFirst(key)?.takeIf { it.isNotBlank() }?.trim()
                    ?: (tag as? org.jaudiotagger.tag.id3.AbstractID3v2Tag)
                        ?.let { getID3TXXXValue(it, key) }
            } catch (_: Exception) { null }
        }
    }

    private fun getID3TXXXValue(
        tag: org.jaudiotagger.tag.id3.AbstractID3v2Tag,
        description: String,
    ): String? {
        return try {
            val frames = tag.getFrame("TXXX") ?: return null
            val list = if (frames is List<*>) frames else listOf(frames)
            for (frame in list) {
                val f = frame as? org.jaudiotagger.tag.id3.framebody.FrameBodyTXXX ?: continue
                if (f.description.equals(description, ignoreCase = true)) {
                    return f.userFriendlyValue.takeIf { it.isNotBlank() }?.trim()
                }
            }
            null
        } catch (_: Exception) { null }
    }

    // ── Embedded lyrics ────────────────────────────────────────────────────────
    //
    // Priority per format:
    //   MP3  : USLT (all frames, prefer English) → LYRICS field → multi-line COMMENT
    //   M4A  : ©lyr atom via FieldKey.LYRICS → multi-line COMMENT
    //   FLAC : LYRICS Vorbis comment → UNSYNCEDLYRICS → multi-line COMMENT
    //   OGG  : same as FLAC
    //   OPUS : same as FLAC (Vorbis comment container)

    private fun getEmbeddedLyrics(path: String): String? {
        if (path.isBlank()) return null
        val file = File(path)
        if (!file.exists()) return null

        return try {
            val audioFile = org.jaudiotagger.audio.AudioFileIO.read(file)
            val tag       = audioFile?.tag ?: return null

            // ── 1. Standard FieldKey.LYRICS
            //    Maps to: ID3v2 USLT (first frame only), M4A ©lyr, Vorbis LYRICS.
            val fromField = tag.getFirst(org.jaudiotagger.tag.FieldKey.LYRICS)?.trim()
            if (!fromField.isNullOrBlank()) return fromField

            // ── 2. ID3v2: scan ALL USLT frames (some MP3s have multiple language frames;
            //    jaudiotagger's getFirst() may return an empty-text frame first).
            if (tag is org.jaudiotagger.tag.id3.AbstractID3v2Tag) {
                val uslt = extractAllUsltFrames(tag)
                if (!uslt.isNullOrBlank()) return uslt
            }

            // ── 3. Vorbis comment explicit keys (OGG / FLAC / OPUS).
            //    Vorbis spec allows both LYRICS and UNSYNCEDLYRICS.
            if (tag is org.jaudiotagger.tag.vorbiscomment.VorbisCommentTag) {
                for (key in listOf("LYRICS", "UNSYNCEDLYRICS", "UNSYNCED LYRICS")) {
                    val v = tag.getFirst(key)?.trim()
                    if (!v.isNullOrBlank()) return v
                }
            }

            // ── 4. COMMENT fallback — only when the comment looks like lyrics:
            //    at least 3 newlines (≥4 non-empty lines), avoid fetching short comments.
            val comment = tag.getFirst(org.jaudiotagger.tag.FieldKey.COMMENT)?.trim()
            if (!comment.isNullOrBlank() && comment.count { it == '\n' } >= 3) {
                return comment
            }

            null
        } catch (_: Exception) { null }
    }

    /**
     * Iterates every USLT frame in an ID3v2 tag and returns the first non-empty lyric text.
     * Prefers frames with language "eng" or blank (unspecified) over other languages,
     * since those are the most common sources of plain/synced LRC lyrics in music files.
     */
    private fun extractAllUsltFrames(
        tag: org.jaudiotagger.tag.id3.AbstractID3v2Tag,
    ): String? {
        return try {
            val raw = tag.getFrame("USLT") ?: return null
            val frames = if (raw is List<*>) raw else listOf(raw)

            // Collect (lang, text) pairs; skip frames with empty lyric text.
            // Using Pair<String,String> avoids a local data class (Kotlin <1.9 compat).
            val entries: List<Pair<String, String>> = frames.mapNotNull { frame ->
    try {
        val body = frame as? org.jaudiotagger.tag.id3.framebody.FrameBodyUSLT
            ?: return@mapNotNull null

        val text = body.lyric?.trim().orEmpty()

        if (text.isEmpty()) null
        else Pair(body.language?.trim()?.lowercase().orEmpty(), text)
    } catch (_: Exception) {
        null
    }
}

            if (entries.isEmpty()) return null

            // Prefer blank language or "eng"; fall back to the first non-empty entry.
            (entries.firstOrNull { it.first.isBlank() || it.first == "eng" }
                ?: entries.first()).second
        } catch (_: Exception) { null }
    }

    override fun onDestroy() {
        super.onDestroy()
    }

    // ── MediaStore helpers ─────────────────────────────────────────────────────

    private fun hasMediaPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    private fun getArtwork(songId: Int): ByteArray? {
        return try {
            val uri = Uri.withAppendedPath(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString())
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
                val uri = Uri.withAppendedPath(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString())
                retriever.setDataSource(this, uri)
            }
            mapOf(
                "year" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR),
                "bitrate" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE),
                "sampleRate" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE),
                "fileSize" to getFileSize(path),
            )
        } catch (_: Exception) { emptyMap() } finally { retriever.release() }
    }

    private fun getFileSize(path: String?): String? {
        if (path.isNullOrBlank()) return null
        return try { File(path).length().takeIf { it > 0 }?.toString() }
        catch (_: Exception) { null }
    }

    private fun getSongs(): List<Map<String, Any?>> {
        if (!hasMediaPermission()) return emptyList()
        val songs = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DURATION,
        )
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            "${MediaStore.Audio.Media.TITLE} ASC",
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val pathCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val durCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            while (cursor.moveToNext()) {
                val albumId = cursor.getInt(albumIdCol)
                songs.add(
                    mapOf(
                        "id" to cursor.getLong(idCol).toInt(),
                        "title" to cursor.getString(titleCol),
                        "artist" to (cursor.getString(artistCol) ?: "Unknown Artist"),
                        "album" to (cursor.getString(albumCol) ?: "Unknown Album"),
                        "albumId" to albumId,
                        "path" to cursor.getString(pathCol),
                        "duration" to cursor.getLong(durCol),
                    )
                )
            }
        }
        return songs
    }
}
