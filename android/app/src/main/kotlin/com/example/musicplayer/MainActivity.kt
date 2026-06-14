package com.example.musicplayer

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.PresetReverb
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import java.io.File
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {

    private val mediaStoreChannel   = "musicplayer/media_store"
    private val audioEffectsChannel = "musicplayer/audio_effects"

    // ── Audio effects ─────────────────────────────────────────────────────────
    private var virtualizer:  Virtualizer?   = null
    private var bassBoost:    BassBoost?     = null
    private var presetReverb: PresetReverb?  = null
    private var currentSessionId: Int = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupMediaStoreChannel(flutterEngine)
        setupAudioEffectsChannel(flutterEngine)
    }

    // ── MediaStore channel ────────────────────────────────────────────────────

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
                        val path   = call.argument<String>("path")
                        val songId = call.argument<Int>("songId")
                        result.success(getAudioMetadata(path, songId ?: 0))
                    }
                    "getEmbeddedLyrics" -> {
                        val path = call.argument<String>("path") ?: ""
                        result.success(getEmbeddedLyrics(path))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Audio Effects channel ─────────────────────────────────────────────────

    private fun setupAudioEffectsChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioEffectsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "attachEffects" -> {
                        val sessionId = call.argument<Int>("sessionId") ?: 0
                        result.success(attachEffects(sessionId))
                    }
                    "setSpatialEnabled" -> {
                        val enabled  = call.argument<Boolean>("enabled") ?: false
                        val strength = call.argument<Int>("strength") ?: 1000
                        setSpatialEnabled(enabled, strength.toShort())
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
                    "setAudioOutputMode" -> {
                        val mode = call.argument<Int>("mode") ?: 0
                        setAudioOutputMode(mode)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── attachEffects ─────────────────────────────────────────────────────────

    private fun attachEffects(sessionId: Int): Map<String, Boolean> {
        if (sessionId == 0) return emptyMap()
        if (sessionId == currentSessionId) {
            return mapOf(
                "virtualizerSupported" to (virtualizer  != null),
                "bassBoostSupported"   to (bassBoost    != null),
                "reverbSupported"      to (presetReverb != null),
            )
        }
        currentSessionId = sessionId
        releaseEffects()

        val virt   = tryCreateVirtualizer(sessionId)
        val bass   = tryCreateBassBoost(sessionId)
        val reverb = tryCreateReverb(sessionId)

        virtualizer  = virt
        bassBoost    = bass
        presetReverb = reverb

        return mapOf(
            "virtualizerSupported" to (virt   != null),
            "bassBoostSupported"   to (bass   != null),
            "reverbSupported"      to (reverb != null),
        )
    }

    private fun tryCreateVirtualizer(sessionId: Int): Virtualizer? {
        if (!isEffectTypeSupported(AudioEffect.EFFECT_TYPE_VIRTUALIZER)) return null
        return try {
            Virtualizer(0, sessionId).apply { enabled = false }
        } catch (_: Exception) { null }
    }

    private fun tryCreateBassBoost(sessionId: Int): BassBoost? {
        if (!isEffectTypeSupported(AudioEffect.EFFECT_TYPE_BASS_BOOST)) return null
        return try {
            BassBoost(0, sessionId).apply {
                setStrength(0); enabled = false
            }
        } catch (_: Exception) { null }
    }

    private fun tryCreateReverb(sessionId: Int): PresetReverb? {
        if (!isEffectTypeSupported(AudioEffect.EFFECT_TYPE_PRESET_REVERB)) return null
        return try {
            PresetReverb(0, sessionId).apply {
                preset = PresetReverb.PRESET_NONE; enabled = false
            }
        } catch (_: Exception) { null }
    }

    private fun isEffectTypeSupported(type: java.util.UUID): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return true
        return try {
            AudioEffect.queryEffects()?.any { it.type == type } ?: false
        } catch (_: Exception) { false }
    }

    // ── Spatial audio ─────────────────────────────────────────────────────────

    private fun setSpatialEnabled(enabled: Boolean, strength: Short) {
        try {
            virtualizer?.run {
                if (enabled && canVirtualize()) {
                    setStrength(strength.coerceIn(0, 1000))
                    this.enabled = true
                } else {
                    this.enabled = false
                }
            }
        } catch (_: Exception) {}
    }

    private fun canVirtualize(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                virtualizer?.canVirtualize(
                    Virtualizer.CHANNEL_LAYOUT_NATIVE,
                    Virtualizer.VIRTUALIZATION_MODE_AUTO
                ) ?: false
            } else true
        } catch (_: Exception) { true }
    }

    // ── Bass Boost ────────────────────────────────────────────────────────────

    private fun setBassBoost(strength: Short) {
        try {
            bassBoost?.run {
                setStrength(strength)
                this.enabled = strength > 0
            }
        } catch (_: Exception) {}
    }

    // ── Reverb ────────────────────────────────────────────────────────────────

    private fun setReverb(preset: Short) {
        try {
            presetReverb?.run {
                val androidPreset = when (preset.toInt()) {
                    1 -> PresetReverb.PRESET_SMALLROOM
                    2 -> PresetReverb.PRESET_MEDIUMROOM
                    3 -> PresetReverb.PRESET_LARGEROOM
                    4 -> PresetReverb.PRESET_MEDIUMHALL
                    5 -> PresetReverb.PRESET_LARGEHALL
                    6 -> PresetReverb.PRESET_PLATE
                    else -> PresetReverb.PRESET_NONE
                }
                this.preset  = androidPreset
                this.enabled = preset.toInt() > 0
            }
        } catch (_: Exception) {}
    }

    // ── Audio output mode ─────────────────────────────────────────────────────
    //
    //  0 = Auto / AAudio  — default ExoPlayer path (Android 8+)
    //  1 = OpenSL ES      — legacy path, all Android versions
    //  2 = Hi-Res Audio   — enable hardware Hi-Res / Hi-Fi DAC path
    //                       Tries: AudioManager.setParameters(), MIUI broadcast,
    //                       MIUI Settings.System write.

    private fun setAudioOutputMode(mode: Int) {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        when (mode) {
            2 -> enableHiRes(am, true)
            else -> enableHiRes(am, false)
        }
    }

    private fun enableHiRes(am: AudioManager, enable: Boolean) {
        val onOff = if (enable) "on" else "off"

        // 1. Standard Android AudioManager parameters (works on many OEM ROMs)
        try { am.setParameters("hifi_audio=$onOff") }        catch (_: Exception) {}
        try { am.setParameters("high_resolution_audio=$onOff") } catch (_: Exception) {}
        try { am.setParameters("hifi_enable=$onOff") }       catch (_: Exception) {}

        // 2. MIUI-specific broadcast intent (MIUI 12+ com.android.phone)
        try {
            val action = if (enable)
                "miui.intent.action.ACTION_HEADSET_HIFI_ENABLE"
            else
                "miui.intent.action.ACTION_HEADSET_HIFI_DISABLE"
            sendBroadcast(Intent(action).apply { setPackage("com.android.phone") })
        } catch (_: Exception) {}

        // 3. MIUI ContentResolver write (requires WRITE_SETTINGS — silently fails otherwise)
        try {
            val value = if (enable) "1" else "0"
            android.provider.Settings.System.putString(contentResolver, "hifi_audio", value)
        } catch (_: Exception) {}

        // 4. Sony / Qualcomm high-res parameter
        try { am.setParameters("audio_qoe_enable=$onOff") }   catch (_: Exception) {}
        try { am.setParameters("hi_res_audio_enabled=$onOff") } catch (_: Exception) {}
    }

    // ── Embedded lyrics ───────────────────────────────────────────────────────
    //
    //  Reads lyrics embedded in audio file tags using jaudiotagger.
    //  Supported formats: MP3 (ID3v2 USLT/SYLT), M4A (iTunes ©lyr),
    //  FLAC/OGG/OPUS (Vorbis LYRICS field), WAV (ID3).

    private fun getEmbeddedLyrics(path: String): String? {
        if (path.isBlank()) return null
        return try {
            val file = File(path)
            if (!file.exists()) return null

            val audioFile = org.jaudiotagger.audio.AudioFileIO.read(file)
            val tag = audioFile?.tag ?: return null

            // Standard LYRICS field (works for all formats jaudiotagger supports)
            val lyrics = tag.getFirst(org.jaudiotagger.tag.FieldKey.LYRICS)
            if (!lyrics.isNullOrBlank()) return lyrics.trim()

            // Fallback: try COMMENT field (some encoders store lyrics there)
            val comment = tag.getFirst(org.jaudiotagger.tag.FieldKey.COMMENT)
            if (!comment.isNullOrBlank() && comment.contains('\n')) return comment.trim()

            null
        } catch (_: Exception) { null }
    }

    // ── Release ───────────────────────────────────────────────────────────────

    private fun releaseEffects() {
        try { virtualizer?.release()  } catch (_: Exception) {}
        try { bassBoost?.release()    } catch (_: Exception) {}
        try { presetReverb?.release() } catch (_: Exception) {}
        virtualizer  = null
        bassBoost    = null
        presetReverb = null
    }

    override fun onDestroy() {
        releaseEffects()
        super.onDestroy()
    }

    // ── MediaStore helpers ────────────────────────────────────────────────────

    private fun hasMediaPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.READ_MEDIA_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun getArtwork(songId: Int): ByteArray? {
        return try {
            val uri = Uri.withAppendedPath(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString()
            )
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
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString()
                )
                retriever.setDataSource(this, uri)
            }
            mapOf(
                "year"       to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR),
                "bitrate"    to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE),
                "sampleRate" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE),
                "fileSize"   to getFileSize(path)
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
            MediaStore.Audio.Media.DURATION
        )
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            "${MediaStore.Audio.Media.TITLE} ASC"
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
