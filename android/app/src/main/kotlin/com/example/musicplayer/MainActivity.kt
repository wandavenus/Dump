package com.example.musicplayer

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
import android.media.audiofx.BassBoost
import android.media.audiofx.PresetReverb
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import java.io.File
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {

    private val mediaStoreChannel = "musicplayer/media_store"
    private val audioEffectsChannel = "musicplayer/audio_effects"

    // ── Audio effects ────────────────────────────────────────────────────────
    private var virtualizer: Virtualizer? = null
    private var bassBoost: BassBoost? = null
    private var presetReverb: PresetReverb? = null
    private var currentSessionId: Int = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupMediaStoreChannel(flutterEngine)
        setupAudioEffectsChannel(flutterEngine)
    }

    // ── MediaStore channel ───────────────────────────────────────────────────

    private fun setupMediaStoreChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaStoreChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSongs" -> result.success(getSongs())
                    "getArtwork" -> {
                        val songId = call.argument<Int>("songId")
                        result.success(getArtwork(songId ?: 0))
                    }
                    "getAudioMetadata" -> {
                        val path = call.argument<String>("path")
                        val songId = call.argument<Int>("songId")
                        result.success(getAudioMetadata(path, songId ?: 0))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Audio Effects channel ────────────────────────────────────────────────

    private fun setupAudioEffectsChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioEffectsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "attachEffects" -> {
                        val sessionId = call.argument<Int>("sessionId") ?: 0
                        attachEffects(sessionId)
                        result.success(null)
                    }
                    "setSpatialEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        setSpatialEnabled(enabled)
                        result.success(null)
                    }
                    "setBassBoost" -> {
                        val strength = call.argument<Int>("strength") ?: 0
                        setBassBoost(strength.toShort())
                        result.success(null)
                    }
                    "setReverb" -> {
                        val preset = call.argument<Int>("preset") ?: 0
                        setReverb(preset.toShort())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun attachEffects(sessionId: Int) {
        if (sessionId == 0 || sessionId == currentSessionId) return
        currentSessionId = sessionId

        releaseEffects()

        try {
            virtualizer = Virtualizer(0, sessionId).apply {
                enabled = false
            }
        } catch (_: Exception) {}

        try {
            bassBoost = BassBoost(0, sessionId).apply {
                setStrength(0)
                enabled = false
            }
        } catch (_: Exception) {}

        try {
            presetReverb = PresetReverb(0, sessionId).apply {
                preset = PresetReverb.PRESET_NONE
                enabled = false
            }
        } catch (_: Exception) {}
    }

    private fun setSpatialEnabled(enabled: Boolean) {
        try {
            virtualizer?.run {
                if (enabled) {
                    setStrength(1000)
                    this.enabled = true
                } else {
                    this.enabled = false
                }
            }
        } catch (_: Exception) {}
    }

    private fun setBassBoost(strength: Short) {
        try {
            bassBoost?.run {
                setStrength(strength)
                this.enabled = strength > 0
            }
        } catch (_: Exception) {}
    }

    private fun setReverb(preset: Short) {
        try {
            presetReverb?.run {
                val androidPreset = when (preset.toInt()) {
                    0 -> PresetReverb.PRESET_NONE
                    1 -> PresetReverb.PRESET_SMALLROOM
                    2 -> PresetReverb.PRESET_MEDIUMROOM
                    3 -> PresetReverb.PRESET_LARGEROOM
                    4 -> PresetReverb.PRESET_MEDIUMHALL
                    5 -> PresetReverb.PRESET_LARGEHALL
                    6 -> PresetReverb.PRESET_PLATE
                    else -> PresetReverb.PRESET_NONE
                }
                this.preset = androidPreset
                this.enabled = preset.toInt() > 0
            }
        } catch (_: Exception) {}
    }

    private fun releaseEffects() {
        try { virtualizer?.release() } catch (_: Exception) {}
        try { bassBoost?.release() } catch (_: Exception) {}
        try { presetReverb?.release() } catch (_: Exception) {}
        virtualizer = null
        bassBoost = null
        presetReverb = null
    }

    override fun onDestroy() {
        releaseEffects()
        super.onDestroy()
    }

    // ── MediaStore helpers ───────────────────────────────────────────────────

    private fun hasMediaPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_MEDIA_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun getArtwork(songId: Int): ByteArray? {
        return try {
            val uri = Uri.withAppendedPath(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                songId.toString()
            )
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(this, uri)
            val artwork = retriever.embeddedPicture
            retriever.release()
            artwork
        } catch (_: Exception) {
            null
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
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    songId.toString()
                )
                retriever.setDataSource(this, uri)
            }
            mapOf(
                "year"       to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR),
                "bitrate"    to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE),
                "sampleRate" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE),
                "fileSize"   to getFileSize(path)
            )
        } catch (_: Exception) {
            emptyMap()
        } finally {
            retriever.release()
        }
    }

    private fun getFileSize(path: String?): String? {
        if (path.isNullOrBlank()) return null
        return try {
            File(path).length().takeIf { it > 0 }?.toString()
        } catch (_: Exception) {
            null
        }
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
            MediaStore.Audio.Media.DURATION
        )

        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            MediaStore.Audio.Media.IS_MUSIC + "!= 0",
            null,
            MediaStore.Audio.Media.TITLE + " ASC"
        )?.use { cursor ->
            val idCol      = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol   = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol  = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol   = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val pathCol    = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val durCol     = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)

            while (cursor.moveToNext()) {
                val albumId = cursor.getInt(albumIdCol)
                songs.add(mapOf(
                    "id"         to cursor.getLong(idCol).toInt(),
                    "title"      to cursor.getString(titleCol),
                    "artist"     to (cursor.getString(artistCol) ?: "Unknown Artist"),
                    "album"      to (cursor.getString(albumCol)  ?: "Unknown Album"),
                    "albumId"    to albumId,
                    "artworkUri" to "content://media/external/audio/albumart/$albumId",
                    "path"       to cursor.getString(pathCol),
                    "duration"   to cursor.getLong(durCol).toInt()
                ))
            }
        }
        return songs
    }
}
