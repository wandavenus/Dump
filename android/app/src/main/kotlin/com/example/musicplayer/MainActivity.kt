package com.example.musicplayer

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.PresetReverb
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import java.io.File
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.log10

// ─────────────────────────────────────────────────────────────────────────────
//  Dual-player: maintain per-session-ID effect instances so that both Player A
//  and Player B have independent native effect chains.
// ─────────────────────────────────────────────────────────────────────────────

data class SessionEffects(
    var virtualizer:  Virtualizer?  = null,
    var bassBoost:    BassBoost?    = null,
    var presetReverb: PresetReverb? = null,
)

class MainActivity : AudioServiceActivity() {

    private val mediaStoreChannel   = "musicplayer/media_store"
    private val audioEffectsChannel = "musicplayer/audio_effects"
    private val loudnessChannel     = "musicplayer/loudness"

    // ── Per-session native effects ─────────────────────────────────────────────
    private val effectsBySession = HashMap<Int, SessionEffects>()

    // Last-applied values so new sessions inherit the current state
    private var lastBassStrength:    Short   = 0
    private var lastReverbPreset:    Short   = 0
    private var lastSpatialEnabled:  Boolean = false
    private var lastSpatialStrength: Short   = 1000

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupMediaStoreChannel(flutterEngine)
        setupAudioEffectsChannel(flutterEngine)
        setupLoudnessChannel(flutterEngine)
    }

    // ── MediaStore channel ────────────────────────────────────────────────────

    private fun setupMediaStoreChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaStoreChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSongs"       -> result.success(getSongs())
                    "getArtwork"     -> result.success(getArtwork(call.argument<Int>("songId") ?: 0))
                    "getAudioMetadata" -> result.success(
                        getAudioMetadata(call.argument("path"), call.argument<Int>("songId") ?: 0)
                    )
                    "getEmbeddedLyrics" -> result.success(
                        getEmbeddedLyrics(call.argument<String>("path") ?: "")
                    )
                    else -> result.notImplemented()
                }
            }
    }

    // ── Audio effects channel ─────────────────────────────────────────────────

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
                        val strength = (call.argument<Int>("strength") ?: 1000).toShort()
                        lastSpatialEnabled  = enabled
                        lastSpatialStrength = strength
                        effectsBySession.values.forEach { setSpatialForEffects(it, enabled, strength) }
                        result.success(null)
                    }
                    "setBassBoost" -> {
                        val strength = (call.argument<Int>("strength") ?: 0).toShort()
                        lastBassStrength = strength
                        effectsBySession.values.forEach { setBassBoostForEffects(it, strength) }
                        result.success(null)
                    }
                    "setReverb" -> {
                        val preset = (call.argument<Int>("preset") ?: 0).toShort()
                        lastReverbPreset = preset
                        effectsBySession.values.forEach { setReverbForEffects(it, preset) }
                        result.success(null)
                    }
                    "setAudioOutputMode" -> {
                        setAudioOutputMode(call.argument<Int>("mode") ?: 0)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Loudness channel ──────────────────────────────────────────────────────

    private fun setupLoudnessChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, loudnessChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "analyzeLoudness" -> {
                        val path = call.argument<String>("path") ?: ""
                        // Run on a background thread to avoid blocking the UI
                        Thread {
                            val analysisResult = try {
                                analyzeLoudness(path)
                            } catch (_: Exception) {
                                null
                            }
                            runOnUiThread {
                                if (analysisResult != null) {
                                    result.success(analysisResult)
                                } else {
                                    result.success(null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── attachEffects (per-session) ───────────────────────────────────────────

    private fun attachEffects(sessionId: Int): Map<String, Boolean> {
        if (sessionId == 0) return emptyMap()

        // Release old effects for this session if they exist
        effectsBySession[sessionId]?.let { releaseSessionEffects(it) }

        val effects = SessionEffects(
            virtualizer  = tryCreateVirtualizer(sessionId),
            bassBoost    = tryCreateBassBoost(sessionId),
            presetReverb = tryCreateReverb(sessionId),
        )
        effectsBySession[sessionId] = effects

        // Apply current settings so new session matches
        setBassBoostForEffects(effects, lastBassStrength)
        setReverbForEffects(effects, lastReverbPreset)
        setSpatialForEffects(effects, lastSpatialEnabled, lastSpatialStrength)

        return mapOf(
            "virtualizerSupported" to (effects.virtualizer  != null),
            "bassBoostSupported"   to (effects.bassBoost    != null),
            "reverbSupported"      to (effects.presetReverb != null),
        )
    }

    private fun tryCreateVirtualizer(sessionId: Int): Virtualizer? {
        if (!isEffectTypeSupported(AudioEffect.EFFECT_TYPE_VIRTUALIZER)) return null
        return try { Virtualizer(0, sessionId).apply { enabled = false } }
        catch (_: Exception) { null }
    }

    private fun tryCreateBassBoost(sessionId: Int): BassBoost? {
        if (!isEffectTypeSupported(AudioEffect.EFFECT_TYPE_BASS_BOOST)) return null
        return try { BassBoost(0, sessionId).apply { setStrength(0); enabled = false } }
        catch (_: Exception) { null }
    }

    private fun tryCreateReverb(sessionId: Int): PresetReverb? {
        if (!isEffectTypeSupported(AudioEffect.EFFECT_TYPE_PRESET_REVERB)) return null
        return try { PresetReverb(0, sessionId).apply { preset = PresetReverb.PRESET_NONE; enabled = false } }
        catch (_: Exception) { null }
    }

    private fun isEffectTypeSupported(type: java.util.UUID): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return true
        return try { AudioEffect.queryEffects()?.any { it.type == type } ?: false }
        catch (_: Exception) { false }
    }

    private fun releaseSessionEffects(effects: SessionEffects) {
        try { effects.virtualizer?.release()  } catch (_: Exception) {}
        try { effects.bassBoost?.release()    } catch (_: Exception) {}
        try { effects.presetReverb?.release() } catch (_: Exception) {}
    }

    // ── Per-effect helpers ────────────────────────────────────────────────────

    private fun setBassBoostForEffects(effects: SessionEffects, strength: Short) {
        try { effects.bassBoost?.run { setStrength(strength); enabled = strength > 0 } }
        catch (_: Exception) {}
    }

    private fun setReverbForEffects(effects: SessionEffects, preset: Short) {
        try {
            effects.presetReverb?.run {
                this.preset = when (preset.toInt()) {
                    1 -> PresetReverb.PRESET_SMALLROOM
                    2 -> PresetReverb.PRESET_MEDIUMROOM
                    3 -> PresetReverb.PRESET_LARGEROOM
                    4 -> PresetReverb.PRESET_MEDIUMHALL
                    5 -> PresetReverb.PRESET_LARGEHALL
                    6 -> PresetReverb.PRESET_PLATE
                    else -> PresetReverb.PRESET_NONE
                }
                enabled = preset.toInt() > 0
            }
        } catch (_: Exception) {}
    }

    private fun setSpatialForEffects(effects: SessionEffects, enabled: Boolean, strength: Short) {
        try {
            effects.virtualizer?.run {
                if (enabled) {
                    setStrength(strength.toInt().coerceIn(0, 1000).toShort())
                    this.enabled = true
                } else {
                    this.enabled = false
                }
            }
        } catch (_: Exception) {}
    }

    // ── Audio output mode ─────────────────────────────────────────────────────

    private fun setAudioOutputMode(mode: Int) {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        enableHiRes(am, mode == 2)
    }

    private fun enableHiRes(am: AudioManager, enable: Boolean) {
        val onOff = if (enable) "on" else "off"
        try { am.setParameters("hifi_audio=$onOff") }             catch (_: Exception) {}
        try { am.setParameters("high_resolution_audio=$onOff") }  catch (_: Exception) {}
        try { am.setParameters("hifi_enable=$onOff") }            catch (_: Exception) {}
        try {
            val action = if (enable) "miui.intent.action.ACTION_HEADSET_HIFI_ENABLE"
                         else        "miui.intent.action.ACTION_HEADSET_HIFI_DISABLE"
            sendBroadcast(Intent(action).apply { setPackage("com.android.phone") })
        } catch (_: Exception) {}
        try {
            android.provider.Settings.System.putString(
                contentResolver, "hifi_audio", if (enable) "1" else "0"
            )
        } catch (_: Exception) {}
        try { am.setParameters("audio_qoe_enable=$onOff") }       catch (_: Exception) {}
        try { am.setParameters("hi_res_audio_enabled=$onOff") }   catch (_: Exception) {}
    }

    // ── LUFS / RMS loudness analysis (MediaCodec) ─────────────────────────────
    //
    //  Decodes the audio file to PCM using MediaCodec, then applies a
    //  K-weighting biquad filter (ITU-R BS.1770) and computes:
    //    • Integrated loudness (LUFS ≈ −0.691 + 10·log₁₀(K-weighted mean square))
    //    • RMS (dBFS)
    //    • True peak (dBFS)
    //
    //  Analysis is limited to the first 60 seconds to keep latency acceptable.

        private fun analyzeLoudness(path: String): Map<String, Any?>? {
        if (path.isBlank() || !File(path).exists()) return null

        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        return try {
            extractor.setDataSource(path)

            // Find the first audio track
            var audioTrackIndex = -1
            var audioFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val fmt  = extractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    audioFormat     = fmt
                    break
                }
            }
            if (audioTrackIndex < 0 || audioFormat == null) return null

            val mime       = audioFormat.getString(MediaFormat.KEY_MIME) ?: return null
            val sampleRate = if (audioFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE))
                                 audioFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 44100

            extractor.selectTrack(audioTrackIndex)

            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(audioFormat, null, null, 0)
            codec.start()

            // K-weighting biquad coefficients for ~48 kHz (reasonable for 44.1–48 kHz)
            // Stage 1: pre-filter (high-shelf)
            val b1 = doubleArrayOf(1.53512485958697, -2.69169618940638, 1.19839281085285)
            val a1 = doubleArrayOf(1.0, -1.69065929318241, 0.73248077421585)
            // Stage 2: RLB weighting (high-pass)
            val b2 = doubleArrayOf(1.0, -2.0, 1.0)
            val a2 = doubleArrayOf(1.0, -1.99004745483398, 0.99007225036498)

            // Filter state for one channel (left / mono)
            var s1x1 = 0.0; var s1x2 = 0.0; var s1y1 = 0.0; var s1y2 = 0.0
            var s2x1 = 0.0; var s2x2 = 0.0; var s2y1 = 0.0; var s2y2 = 0.0

            var kSumSq     = 0.0
            var rawSumSq   = 0.0
            var sampleCount = 0L
            var maxPeak    = 0.0

            val maxDurationUs = 60_000_000L  // 60 seconds
            val bufInfo = MediaCodec.BufferInfo()
            var eos = false

            while (!eos) {
                // Feed input
                val inIdx = codec.dequeueInputBuffer(10_000)
                if (inIdx >= 0) {
                    val inBuf    = codec.getInputBuffer(inIdx)!!
                    val readSize = extractor.readSampleData(inBuf, 0)
                    val pts      = extractor.sampleTime
                    if (readSize < 0 || pts > maxDurationUs) {
                        codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        eos = true
                    } else {
                        codec.queueInputBuffer(inIdx, 0, readSize, pts, 0)
                        extractor.advance()
                    }
                }

                // Drain output
                val outIdx = codec.dequeueOutputBuffer(bufInfo, 10_000)
                if (outIdx >= 0) {
                    val outBuf = codec.getOutputBuffer(outIdx)
                    if (outBuf != null && bufInfo.size > 0) {
                        outBuf.order(ByteOrder.nativeOrder())
                        val shortBuf = outBuf.asShortBuffer()
                        while (shortBuf.hasRemaining()) {
                            val raw = shortBuf.get().toInt()
                            val s   = raw / 32768.0

                            // K-weight stage 1
                            val ky1 = b1[0]*s + b1[1]*s1x1 + b1[2]*s1x2 - a1[1]*s1y1 - a1[2]*s1y2
                            s1x2 = s1x1; s1x1 = s; s1y2 = s1y1; s1y1 = ky1

                            // K-weight stage 2
                            val ky2 = b2[0]*ky1 + b2[1]*s2x1 + b2[2]*s2x2 - a2[1]*s2y1 - a2[2]*s2y2
                            s2x2 = s2x1; s2x1 = ky1; s2y2 = s2y1; s2y1 = ky2

                            kSumSq   += ky2 * ky2
                            rawSumSq += s * s
                            sampleCount++

                            val a = abs(s)
                            if (a > maxPeak) maxPeak = a
                        }
                    }
                    if (bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) eos = true
                    codec.releaseOutputBuffer(outIdx, false)
                }
            }

            if (sampleCount == 0L) return null

            val kMeanSq = kSumSq / sampleCount
            val lufs    = -0.691 + 10.0 * log10(kMeanSq)
            val rms     = 10.0 * log10(rawSumSq / sampleCount)
            val peak    = if (maxPeak > 0.0) 20.0 * log10(maxPeak) else -96.0

            mapOf(
                "lufs"        to lufs,
                "rms"         to rms,
                "truePeak"    to peak,
                "isEstimated" to false,
                "sampleRate"  to sampleRate,
            )
        } catch (e: Exception) {
    return null
} finally {
            try {
                codec?.stop()
            } catch (_: Exception) {}
            try {
                codec?.release()
            } catch (_: Exception) {}
            try {
                extractor.release()
            } catch (_: Exception) {}
        }
    }
    // ── Embedded lyrics ───────────────────────────────────────────────────────

    private fun getEmbeddedLyrics(path: String): String? {
        if (path.isBlank()) return null
        return try {
            val file = File(path)
            if (!file.exists()) return null
            val audioFile = org.jaudiotagger.audio.AudioFileIO.read(file)
            val tag       = audioFile?.tag ?: return null
            val lyrics    = tag.getFirst(org.jaudiotagger.tag.FieldKey.LYRICS)
            if (!lyrics.isNullOrBlank()) return lyrics.trim()
            val comment   = tag.getFirst(org.jaudiotagger.tag.FieldKey.COMMENT)
            if (!comment.isNullOrBlank() && comment.contains('\n')) return comment.trim()
            null
        } catch (_: Exception) { null }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onDestroy() {
        effectsBySession.values.forEach { releaseSessionEffects(it) }
        effectsBySession.clear()
        super.onDestroy()
    }

    // ── MediaStore helpers ────────────────────────────────────────────────────

    private fun hasMediaPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private fun getArtwork(songId: Int): ByteArray? {
        return try {
            val uri      = Uri.withAppendedPath(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString())
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(this, uri)
            val artwork  = retriever.embeddedPicture
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

    private fun getSongs(): List<Map<String, Any?>> {
        if (!hasMediaPermission()) return emptyList()
        val songs      = mutableListOf<Map<String, Any?>>()
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
                    "duration"   to cursor.getLong(durCol).toInt(),
                ))
            }
        }
        return songs
    }
}
